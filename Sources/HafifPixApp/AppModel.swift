import Foundation
import Observation
import HafifPixCore

@MainActor
@Observable
final class AppModel {
    struct Entry: Identifiable {
        enum DisplayStatus: Equatable {
            case pending
            case running(String)
            case optimized
            case converted(URL)
            case alreadyOptimal
            case reverted
            case failed(String)
        }

        let id = UUID()
        let url: URL
        let format: ImageFormat
        let originalBytes: Int64
        var currentBytes: Int64
        var status: DisplayStatus = .pending
        var jobID: JobID?

        var name: String { url.lastPathComponent }

        var savedBytes: Int64 {
            max(0, originalBytes - currentBytes)
        }

        var statusText: String {
            switch status {
            case .pending: L("Waiting")
            case .running(let step): step
            case .optimized: L("Saved \(Formatting.bytes(savedBytes))")
            case .converted(let out): "→ \(out.lastPathComponent)"
            case .alreadyOptimal: L("Already optimized")
            case .reverted: L("Reverted to original")
            case .failed(let message): message
            }
        }

        // Sort keys for the table columns.
        var statusRank: Int {
            switch status {
            case .pending: 0
            case .running: 1
            case .optimized: 2
            case .converted: 3
            case .alreadyOptimal: 4
            case .reverted: 5
            case .failed: 6
            }
        }

        var savingsFraction: Double {
            originalBytes > 0 ? Double(savedBytes) / Double(originalBytes) : 0
        }
    }

    private(set) var entries: [Entry] = []
    var settings: OptimizationSettings {
        didSet { SettingsStorage.save(settings) }
    }

    private var jobToEntry: [JobID: UUID] = [:]
    private var engine: OptimizationEngine!
    private(set) var activeJobs = 0

    init() {
        settings = SettingsStorage.load()
        engine = OptimizationEngine { [weak self] event in
            Task { @MainActor in
                self?.apply(event)
            }
        }
    }

    var isBusy: Bool { activeJobs > 0 }

    var totals: (original: Int64, saved: Int64)? {
        let finished = entries.filter {
            if case .optimized = $0.status { return true }
            if case .converted = $0.status { return true }
            return false
        }
        guard !finished.isEmpty else { return nil }
        let original = finished.reduce(0) { $0 + $1.originalBytes }
        let saved = finished.reduce(0) { $0 + $1.savedBytes }
        return (original, saved)
    }

    // MARK: - Intake

    func add(urls: [URL]) {
        let snapshot = settings
        Task.detached(priority: .userInitiated) {
            // Collection sniffs file contents; keep that off the main thread.
            let requests = FileCollector.collect(from: urls)
            await self.enqueue(requests: requests, settings: snapshot)
        }
    }

    private func enqueue(requests: [JobRequest], settings: OptimizationSettings) async {
        var accepted: [JobRequest] = []
        for request in requests {
            if let index = entries.firstIndex(where: { $0.url == request.url }) {
                // Re-dropped file: reuse its row instead of duplicating.
                guard entries[index].status != .pending, !isRunning(entries[index]) else { continue }
                entries[index].jobID = request.id
                entries[index].status = .pending
                jobToEntry[request.id] = entries[index].id
                accepted.append(request)
            } else {
                var entry = Entry(
                    url: request.url,
                    format: request.format,
                    originalBytes: request.url.fileSize,
                    currentBytes: request.url.fileSize
                )
                entry.jobID = request.id
                entries.append(entry)
                jobToEntry[request.id] = entry.id
                accepted.append(request)
            }
        }
        guard !accepted.isEmpty else { return }
        activeJobs += accepted.count
        await engine.enqueue(accepted, settings: settings)
    }

    private func isRunning(_ entry: Entry) -> Bool {
        if case .running = entry.status { return true }
        return false
    }

    // MARK: - Actions

    func again() {
        let snapshot = settings
        var requests: [JobRequest] = []
        for index in entries.indices where entries[index].status != .pending && !isRunning(entries[index]) {
            let request = JobRequest(url: entries[index].url, format: entries[index].format)
            entries[index].jobID = request.id
            entries[index].status = .pending
            jobToEntry[request.id] = entries[index].id
            requests.append(request)
        }
        guard !requests.isEmpty else { return }
        activeJobs += requests.count
        let engine = engine!
        Task { await engine.enqueue(requests, settings: snapshot) }
    }

    func clear() {
        entries.removeAll()
        jobToEntry.removeAll()
    }

    func remove(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
    }

    func revert(entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              let jobID = entries[index].jobID else { return }
        let url = entries[index].url
        let engine = engine!
        Task { await engine.revert(id: jobID, url: url) }
    }

    // MARK: - Background removal

    var backgroundRemovalError: String?

    func removeBackground(entryIDs: Set<UUID>) {
        for id in entryIDs {
            guard let index = entries.firstIndex(where: { $0.id == id }),
                  entries[index].format != .svg,
                  !isRunning(entries[index]) else { continue }

            let entry = entries[index]
            let previousStatus = entry.status
            entries[index].status = .running(L("Removing background"))

            Task.detached(priority: .userInitiated) {
                let output = BackgroundRemover.outputURL(for: entry.url)
                do {
                    try BackgroundRemover.removeBackground(from: entry.url, output: output)
                    await MainActor.run {
                        self.restoreStatus(entryID: id, to: previousStatus)
                        // The extracted PNG joins the queue and gets optimized.
                        self.add(urls: [output])
                    }
                } catch {
                    await MainActor.run {
                        self.restoreStatus(entryID: id, to: previousStatus)
                        self.backgroundRemovalError = "\(entry.name): \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func restoreStatus(entryID: UUID, to status: Entry.DisplayStatus) {
        if let index = entries.firstIndex(where: { $0.id == entryID }) {
            entries[index].status = status
        }
    }

    func canRevert(entryID: UUID) async -> Bool {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return false }
        return await engine.canRevert(entry.url)
    }

    func shutdown() async {
        await engine.shutdown()
    }

    // MARK: - Engine events

    private func apply(_ event: JobEvent) {
        guard let entryID = jobToEntry[event.id],
              let index = entries.firstIndex(where: { $0.id == entryID }) else { return }

        switch event.status {
        case .pending:
            entries[index].status = .pending
        case .running(let step):
            entries[index].status = .running(step)
        case .optimized(_, let newBytes):
            entries[index].currentBytes = newBytes
            entries[index].status = .optimized
            activeJobs = max(0, activeJobs - 1)
        case .converted(_, let newBytes, let outputURL):
            entries[index].currentBytes = newBytes
            entries[index].status = .converted(outputURL)
            activeJobs = max(0, activeJobs - 1)
        case .alreadyOptimal:
            entries[index].status = .alreadyOptimal
            activeJobs = max(0, activeJobs - 1)
        case .reverted(let bytes):
            entries[index].currentBytes = bytes
            entries[index].status = .reverted
        case .failed(let message):
            entries[index].status = .failed(message)
            activeJobs = max(0, activeJobs - 1)
        }
    }
}
