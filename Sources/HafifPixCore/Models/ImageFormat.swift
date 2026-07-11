import Foundation
import UniformTypeIdentifiers

public enum ImageFormat: String, CaseIterable, Sendable, Codable, Hashable {
    case png
    case jpeg
    case gif
    case svg
    case webp

    public var fileExtensions: [String] {
        switch self {
        case .png: ["png"]
        case .jpeg: ["jpg", "jpeg", "jpe"]
        case .gif: ["gif"]
        case .svg: ["svg"]
        case .webp: ["webp"]
        }
    }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .gif: .gif
        case .svg: .svg
        case .webp: .webP
        }
    }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .gif: "GIF"
        case .svg: "SVG"
        case .webp: "WebP"
        }
    }

    public static func detect(url: URL) -> ImageFormat? {
        let ext = url.pathExtension.lowercased()
        let byExtension = ImageFormat.allCases.first { $0.fileExtensions.contains(ext) }

        guard let handle = try? FileHandle(forReadingFrom: url),
              let header = try? handle.read(upToCount: 4096) else {
            return byExtension
        }
        try? handle.close()

        // Content decides, not the extension: a mislabeled file sent to the
        // wrong tool would either fail or, worse, be silently mangled — and a
        // readable file with no recognizable image content is not an image.
        return sniff(header)
    }

    public static func sniff(_ data: Data) -> ImageFormat? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data.prefix(16))

        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .png
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .jpeg
        }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { // GIF8
            return .gif
        }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]), // RIFF
           data.count >= 12,
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { // WEBP
            return .webp
        }
        // SVG is text; look for an <svg tag in the first few KB.
        if let text = String(data: data, encoding: .utf8)?.lowercased(),
           text.contains("<svg") {
            return .svg
        }
        return nil
    }

    /// All extensions the app accepts, for open panels and directory scans.
    public static var allExtensions: Set<String> {
        Set(allCases.flatMap(\.fileExtensions))
    }
}
