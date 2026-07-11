import Foundation

/// Swaps an optimized candidate into the original's place atomically,
/// honoring the permission/date preservation and backup settings.
public enum FileReplacer {
    public static func replace(
        original: URL,
        with candidate: URL,
        settings: OptimizationSettings
    ) throws {
        let fm = FileManager.default
        let attributes = try fm.attributesOfItem(atPath: original.path)

        try makeBackupIfNeeded(of: original, settings: settings)

        // Stage the candidate on the original's volume first — the temp dir may
        // live on a different volume, where an atomic swap isn't possible.
        let staged = original.deletingLastPathComponent()
            .appendingPathComponent(".\(original.lastPathComponent).hafifpix-\(UUID().uuidString.prefix(8))")
        try fm.copyItem(at: candidate, to: staged)

        do {
            // replaceItemAt is an atomic swap that keeps the original's
            // metadata (creation date, extended attributes) on the surviving file.
            _ = try fm.replaceItemAt(original, withItemAt: staged)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }

        if settings.preservePermissions, let permissions = attributes[.posixPermissions] {
            try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: original.path)
        }
        if settings.preserveDates {
            var dateAttributes: [FileAttributeKey: Any] = [:]
            if let modified = attributes[.modificationDate] { dateAttributes[.modificationDate] = modified }
            if let created = attributes[.creationDate] { dateAttributes[.creationDate] = created }
            if !dateAttributes.isEmpty {
                try? fm.setAttributes(dateAttributes, ofItemAtPath: original.path)
            }
        }
    }

    private static func makeBackupIfNeeded(of original: URL, settings: OptimizationSettings) throws {
        let fm = FileManager.default
        switch settings.backupMode {
        case .none:
            return
        case .sidecar:
            let backup = original.deletingPathExtension()
                .appendingPathExtension("orig")
                .appendingPathExtension(original.pathExtension)
            if !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: original, to: backup)
            }
        case .trash:
            let stem = original.deletingPathExtension().lastPathComponent
            let tempName = "\(stem) (original).\(original.pathExtension)"
            let tempCopy = original.deletingLastPathComponent().appendingPathComponent(tempName)
            if fm.fileExists(atPath: tempCopy.path) { try fm.removeItem(at: tempCopy) }
            try fm.copyItem(at: original, to: tempCopy)
            try fm.trashItem(at: tempCopy, resultingItemURL: nil)
        }
    }
}
