import Foundation
import Vision
import CoreImage
import UniformTypeIdentifiers

/// Subject-from-background extraction using Apple's Vision framework —
/// the same on-device model behind "copy subject" in Photos and Preview.
/// Output is a PNG with alpha next to the original; sources are never touched.
public enum BackgroundRemover {
    public static func removeBackground(from url: URL, output: URL) throws {
        let handler = VNImageRequestHandler(url: url)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw RemovalError.noSubjectFound
        }

        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw RemovalError.renderFailed
        }
        try ImageIOCodec.encode(images: [cgImage], to: .png, quality: 100, output: output)

        guard ImageIOCodec.verifyDecodable(output) else {
            throw RemovalError.renderFailed
        }
    }

    /// photo.jpg becomes photo-nobg.png (never clobbers existing files).
    public static func outputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(stem)-nobg.png")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem)-nobg-\(counter).png")
            counter += 1
        }
        return candidate
    }

    public enum RemovalError: Error, LocalizedError {
        case noSubjectFound
        case renderFailed

        public var errorDescription: String? {
            switch self {
            case .noSubjectFound: "No subject found in the image"
            case .renderFailed: "Could not render the extracted subject"
            }
        }
    }
}
