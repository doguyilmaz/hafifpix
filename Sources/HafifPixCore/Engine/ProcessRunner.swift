import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum ProcessError: Error, LocalizedError {
    case toolNotFound(String)
    case timeout(tool: String)
    case failed(tool: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            LC("\(name) is not available")
        case .timeout(let tool):
            LC("\(tool) timed out")
        case .failed(let tool, let code, let stderr):
            LC("\(tool) failed (exit \(code)): \(String(stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)))")
        }
    }
}

/// Process isn't Sendable; the box lets cancellation/timeout handlers reach it.
private final class ProcessBox: @unchecked Sendable {
    let process = Process()
    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

/// Accumulates pipe output and fires exactly once when both streams hit EOF
/// and the process has exited.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var stdoutDone = false
    private var stderrDone = false
    private var exitCode: Int32?
    private var completion: ((ProcessResult) -> Void)?

    func onComplete(_ handler: @escaping (ProcessResult) -> Void) {
        lock.lock(); completion = handler; lock.unlock()
        fireIfReady()
    }

    func appendStdout(_ d: Data) { lock.lock(); stdout.append(d); lock.unlock() }
    func appendStderr(_ d: Data) { lock.lock(); stderr.append(d); lock.unlock() }
    func finishStdout() { lock.lock(); stdoutDone = true; lock.unlock(); fireIfReady() }
    func finishStderr() { lock.lock(); stderrDone = true; lock.unlock(); fireIfReady() }
    func exited(_ code: Int32) { lock.lock(); exitCode = code; lock.unlock(); fireIfReady() }

    private func fireIfReady() {
        lock.lock()
        guard stdoutDone, stderrDone, let code = exitCode, let handler = completion else {
            lock.unlock()
            return
        }
        completion = nil
        let result = ProcessResult(exitCode: code, stdout: stdout, stderr: stderr)
        lock.unlock()
        handler(result)
    }
}

public enum ProcessRunner {
    /// Runs an external tool to completion. Cancelling the surrounding task
    /// terminates the process; a timeout does the same and throws.
    public static func run(
        _ executable: URL,
        arguments: [String],
        stdin: Data? = nil,
        timeout: Duration = .seconds(600)
    ) async throws -> ProcessResult {
        let toolName = executable.lastPathComponent
        let box = ProcessBox()

        return try await withThrowingTaskGroup(of: ProcessResult?.self) { group in
            group.addTask {
                try await execute(box: box, executable: executable, arguments: arguments, stdin: stdin)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }

            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw ProcessError.timeout(tool: toolName)
            }
            guard let result = first else {
                box.terminate()
                throw ProcessError.timeout(tool: toolName)
            }
            return result
        }
    }

    private static func execute(
        box: ProcessBox,
        executable: URL,
        arguments: [String],
        stdin: Data?
    ) async throws -> ProcessResult {
        let process = box.process
        process.executableURL = executable
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let inPipe: Pipe? = stdin != nil ? Pipe() : nil
        process.standardInput = inPipe ?? Pipe() // empty stdin, immediately closed below

        let collector = OutputCollector()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                collector.finishStdout()
            } else {
                collector.appendStdout(data)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                collector.finishStderr()
            } else {
                collector.appendStderr(data)
            }
        }
        process.terminationHandler = { collector.exited($0.terminationStatus) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }

                if let stdin, let inPipe {
                    inPipe.fileHandleForWriting.writeabilityHandler = { handle in
                        handle.writeabilityHandler = nil
                        try? handle.write(contentsOf: stdin)
                        try? handle.close()
                    }
                } else if let standardInput = process.standardInput as? Pipe {
                    try? standardInput.fileHandleForWriting.close()
                }

                collector.onComplete { result in
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}
