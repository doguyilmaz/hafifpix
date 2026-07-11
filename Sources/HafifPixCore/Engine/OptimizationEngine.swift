import Foundation

/// Job queue with bounded parallelism. Owns the revert cache; publishes
/// progress through a Sendable event handler (the app hops to the main actor,
/// the CLI prints directly).
public actor OptimizationEngine {
    public typealias EventHandler = @Sendable (JobEvent) -> Void

    private struct QueuedJob {
        let request: JobRequest
        let settings: OptimizationSettings
    }

    private var pending: [QueuedJob] = []
    private var running: [JobID: Task<Void, Never>] = [:]
    private var concurrencyLimit = ProcessInfo.processInfo.activeProcessorCount
    private let revertCache = RevertCache()
    private let emit: EventHandler

    public init(onEvent: @escaping EventHandler) {
        emit = onEvent
    }

    public var isBusy: Bool {
        !pending.isEmpty || !running.isEmpty
    }

    public func enqueue(_ requests: [JobRequest], settings: OptimizationSettings) {
        concurrencyLimit = settings.effectiveConcurrency
        for request in requests {
            pending.append(QueuedJob(request: request, settings: settings))
            emit(JobEvent(id: request.id, status: .pending))
        }
        pump()
    }

    private func pump() {
        while running.count < concurrencyLimit, !pending.isEmpty {
            let job = pending.removeFirst()
            let cache = revertCache
            let emit = emit
            // Detached: chain work does CPU-bound ImageIO decoding that must
            // not serialize on this actor's executor.
            running[job.request.id] = Task.detached(priority: .userInitiated) { [weak self] in
                await JobExecutor.execute(
                    request: job.request,
                    settings: job.settings,
                    revertCache: cache,
                    emit: emit
                )
                await self?.finished(job.request.id)
            }
        }
    }

    private func finished(_ id: JobID) {
        running[id] = nil
        pump()
    }

    public func cancelAll() {
        for job in pending {
            emit(JobEvent(id: job.request.id, status: .failed(message: LC("Cancelled"))))
        }
        pending.removeAll()
        for task in running.values {
            task.cancel()
        }
    }

    public func canRevert(_ url: URL) async -> Bool {
        await revertCache.canRevert(url)
    }

    public func revert(id: JobID, url: URL) async {
        do {
            let bytes = try await revertCache.revert(url)
            emit(JobEvent(id: id, status: .reverted(bytes: bytes)))
        } catch {
            emit(JobEvent(id: id, status: .failed(message: error.localizedDescription)))
        }
    }

    public func shutdown() async {
        cancelAll()
        await revertCache.cleanup()
    }
}

enum JobExecutor {
    static func execute(
        request: JobRequest,
        settings: OptimizationSettings,
        revertCache: RevertCache,
        emit: @escaping @Sendable (JobEvent) -> Void
    ) async {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("hafifpix-job-\(request.id.raw.uuidString)")
        defer { try? fm.removeItem(at: tempDir) }

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let context = WorkContext(settings: settings, tempDir: tempDir, format: request.format)

            // SVG never converts; converting WebP to WebP is just optimization.
            let wantsConvert = settings.convertTarget != .none
                && request.format != .svg
                && !(request.format == .webp && settings.convertTarget == .webp)

            if wantsConvert {
                emit(JobEvent(id: request.id, status: .running(step: LC("Converting to \(settings.convertTarget.displayName)"))))
                let result = try await ConvertPipeline.convert(original: request.url, format: request.format, context: context)
                if settings.convertRemovesOriginal, result.newBytes < result.originalBytes {
                    try? fm.trashItem(at: request.url, resultingItemURL: nil)
                }
                emit(JobEvent(id: request.id, status: .converted(
                    originalBytes: result.originalBytes,
                    newBytes: result.newBytes,
                    outputURL: result.outputURL
                )))
                return
            }

            let outcome = try await ChainRunner.run(
                original: request.url,
                format: request.format,
                context: context
            ) { step in
                emit(JobEvent(id: request.id, status: .running(step: step)))
            }

            if let best = outcome.bestURL {
                try await revertCache.stash(original: request.url)
                try FileReplacer.replace(original: request.url, with: best, settings: settings)
                emit(JobEvent(id: request.id, status: .optimized(
                    originalBytes: outcome.originalBytes,
                    newBytes: outcome.bestBytes
                )))
            } else {
                emit(JobEvent(id: request.id, status: .alreadyOptimal(bytes: outcome.originalBytes)))
            }
        } catch is CancellationError {
            emit(JobEvent(id: request.id, status: .failed(message: LC("Cancelled"))))
        } catch {
            emit(JobEvent(id: request.id, status: .failed(message: error.localizedDescription)))
        }
    }
}
