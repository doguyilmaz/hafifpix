import Foundation

/// Keeps pristine copies of optimized files for the lifetime of the session so
/// any optimization can be undone, regardless of the backup setting.
/// Keyed by file path: re-running a file ("Again") keeps its *first* original.
public actor RevertCache {
    private let cacheDir: URL
    private var entries: [String: URL] = [:]

    public init() {
        cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HafifPix-revert-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Stash the original before it gets replaced. Only the first version seen
    /// per path is kept, so repeated runs revert to the true original.
    public func stash(original: URL) throws {
        let key = original.standardizedFileURL.path
        guard entries[key] == nil else { return }
        let stashURL = cacheDir.appendingPathComponent("\(UUID().uuidString).\(original.pathExtension)")
        try FileManager.default.copyItem(at: original, to: stashURL)
        entries[key] = stashURL
    }

    public func canRevert(_ url: URL) -> Bool {
        entries[url.standardizedFileURL.path] != nil
    }

    /// Restores the stashed original to its on-disk location.
    public func revert(_ url: URL) throws -> Int64 {
        guard let stashURL = entries[url.standardizedFileURL.path] else {
            throw RevertError.nothingStashed
        }
        let fm = FileManager.default
        let working = cacheDir.appendingPathComponent("restore-\(UUID().uuidString)")
        try fm.copyItem(at: stashURL, to: working)
        _ = try fm.replaceItemAt(url, withItemAt: working)
        return url.fileSize
    }

    public func cleanup() {
        try? FileManager.default.removeItem(at: cacheDir)
        entries.removeAll()
    }

    public enum RevertError: Error, LocalizedError {
        case nothingStashed
        public var errorDescription: String? { LC("No original stored for this file") }
    }
}
