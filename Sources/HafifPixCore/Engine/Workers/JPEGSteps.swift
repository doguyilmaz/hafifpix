import Foundation

/// Modern lossy JPEG re-encoding via Google's jpegli — noticeably better
/// quality-per-byte than classic libjpeg at web quality levels.
public struct CjpegliStep: OptimizationStep {
    public let name = "jpegli"

    public init() {}

    public func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool {
        let tool = try ToolRegistry.require(.cjpegli)
        let args = [input.path, output.path, "-q", String(context.settings.jpegQuality)]
        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: name, exitCode: result.exitCode, stderr: result.stderrText)
        }
        return FileManager.default.fileExists(atPath: output.path)
    }
}

/// JPEG recompression + metadata stripping (in place on a copy). Runs in
/// lossless mode when jpegli already did the lossy pass, to avoid stacking
/// two generations of quality loss on the same image.
public struct JpegoptimStep: OptimizationStep {
    public let name = "jpegoptim"
    let lossyAllowed: Bool

    public init(lossyAllowed: Bool) {
        self.lossyAllowed = lossyAllowed
    }

    public func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool {
        let tool = try ToolRegistry.require(.jpegoptim)

        // jpegoptim works in place; operate on a copy at the output path.
        let fm = FileManager.default
        if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
        try fm.copyItem(at: input, to: output)

        var args = ["--quiet", "--force"]
        if lossyAllowed && context.settings.lossyEnabled {
            args.append("-m\(context.settings.jpegQuality)")
        }
        args.append(context.settings.stripJPEGMetadata ? "--strip-all" : "--strip-none")
        args.append(output.path)

        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: name, exitCode: result.exitCode, stderr: result.stderrText)
        }
        return true
    }
}

/// Lossless entropy-coding optimization via MozJPEG's jpegtran
/// (optimized Huffman tables + progressive scan search).
public struct JpegtranStep: OptimizationStep {
    public let name = "jpegtran"

    public init() {}

    public func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool {
        let tool = try ToolRegistry.require(.jpegtran)

        let copyMode = context.settings.stripJPEGMetadata ? "none" : "all"
        let args = [
            "-copy", copyMode,
            "-optimize",
            "-progressive",
            "-outfile", output.path,
            input.path,
        ]

        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: name, exitCode: result.exitCode, stderr: result.stderrText)
        }
        return FileManager.default.fileExists(atPath: output.path)
    }
}
