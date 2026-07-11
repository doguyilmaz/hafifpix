import Foundation

public enum Formatting {
    public static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    public static func savings(original: Int64, new: Int64) -> String {
        guard original > 0, new < original else { return "—" }
        let percent = Double(original - new) / Double(original) * 100
        return String(format: "%.1f%%", percent)
    }

    public static func savedDescription(original: Int64, new: Int64) -> String {
        guard original > 0, new < original else { return "no savings" }
        return "\(bytes(original - new)) (\(savings(original: original, new: new)))"
    }
}

public extension URL {
    var fileSize: Int64 {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }
}
