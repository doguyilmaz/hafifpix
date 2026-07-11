import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Native decode/encode/verify built on Apple ImageIO. Used for integrity
/// verification, resizing, and HEIC/AVIF/JPEG/PNG encoding.
public enum ImageIOCodec {
    public struct ImageInfo: Sendable {
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let frameCount: Int
    }

    public static func info(of url: URL) -> ImageInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return ImageInfo(pixelWidth: width, pixelHeight: height, frameCount: CGImageSourceGetCount(source))
    }

    /// Full-decode check: every frame must produce a CGImage. This is the last
    /// line of defense against a tool emitting truncated or corrupt output.
    public static func verifyDecodable(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return false }
        for index in 0..<count {
            guard CGImageSourceCreateImageAtIndex(source, index, nil) != nil else { return false }
        }
        return true
    }

    public static var supportsAVIFEncoding: Bool {
        let types = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return types.contains("public.avif")
    }

    /// Downscales so the longest side is at most `maxDimension`, writing the
    /// result in the given format. Returns nil if the image is already small enough.
    public static func resize(
        _ url: URL,
        maxDimension: Int,
        to type: UTType,
        quality: Int,
        output: URL
    ) throws -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let info = info(of: url) else {
            throw CodecError.unreadable
        }
        guard max(info.pixelWidth, info.pixelHeight) > maxDimension else {
            return false
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw CodecError.decodeFailed
        }
        try encode(images: [scaled], to: type, quality: quality, output: output)
        return true
    }

    /// Re-encodes url into the given format (used for HEIC/AVIF/JPEG/PNG conversion).
    public static func transcode(
        _ url: URL,
        to type: UTType,
        quality: Int,
        output: URL
    ) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary) else {
            throw CodecError.unreadable
        }
        try encode(images: [image], to: type, quality: quality, output: output)
    }

    public static func encode(images: [CGImage], to type: UTType, quality: Int, output: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, type.identifier as CFString, images.count, nil
        ) else {
            throw CodecError.encoderUnavailable(type.identifier)
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0,
        ]
        for image in images {
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw CodecError.encodeFailed(type.identifier)
        }
    }

    public enum CodecError: Error, LocalizedError {
        case unreadable
        case decodeFailed
        case encoderUnavailable(String)
        case encodeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable: LC("Could not read image")
            case .decodeFailed: LC("Could not decode image")
            case .encoderUnavailable(let type): LC("No encoder for \(type) on this system")
            case .encodeFailed(let type): LC("Encoding to \(type) failed")
            }
        }
    }
}
