import Foundation
import UniformTypeIdentifiers

/// Converting to a modern format writes a *sibling* file (photo.png → photo.webp)
/// instead of replacing in place — a format change is never silently destructive.
public enum ConvertPipeline {
    public struct Result: Sendable {
        public let outputURL: URL
        public let originalBytes: Int64
        public let newBytes: Int64
    }

    public static func convert(
        original: URL,
        format: ImageFormat,
        context: WorkContext
    ) async throws -> Result {
        let target = context.settings.convertTarget
        guard let ext = target.fileExtension else {
            throw ConvertError.noTarget
        }

        guard let info = ImageIOCodec.info(of: original) else {
            throw ConvertError.undecodable
        }
        if info.frameCount > 1 {
            // Animated GIF → WebP survives via gif2webp; everything else can't
            // keep its animation through a single-frame encoder.
            if format == .gif, target == .webp, ToolRegistry.url(for: .gif2webp) != nil {
                return try await convertAnimatedGIF(original: original, ext: ext, context: context)
            }
            throw ConvertError.animatedUnsupported(target.displayName)
        }

        // Optional resize happens on the decode side of the conversion.
        var source = original
        let scratch = context.tempDir.appendingPathComponent("convert-src.png")
        if context.settings.resizeEnabled,
           max(info.pixelWidth, info.pixelHeight) > context.settings.maxDimension,
           try ImageIOCodec.resize(original, maxDimension: context.settings.maxDimension, to: .png, quality: 100, output: scratch) {
            source = scratch
        }

        let converted = context.tempDir.appendingPathComponent("converted.\(ext)")
        let quality = context.settings.convertQuality

        switch target {
        case .webp:
            try await encodeWebP(source: source, quality: quality, output: converted, tempDir: context.tempDir)
        case .heic:
            try ImageIOCodec.transcode(source, to: .heic, quality: quality, output: converted)
        case .avif:
            guard ImageIOCodec.supportsAVIFEncoding else {
                throw ImageIOCodec.CodecError.encoderUnavailable("public.avif")
            }
            try ImageIOCodec.transcode(source, to: UTType("public.avif")!, quality: quality, output: converted)
        case .none:
            throw ConvertError.noTarget
        }

        guard ImageIOCodec.verifyDecodable(converted) else {
            throw ConvertError.verificationFailed
        }

        let destination = nonClobberingSibling(of: original, ext: ext)
        try FileManager.default.copyItem(at: converted, to: destination)

        return Result(
            outputURL: destination,
            originalBytes: original.fileSize,
            newBytes: destination.fileSize
        )
    }

    private static func convertAnimatedGIF(original: URL, ext: String, context: WorkContext) async throws -> Result {
        let tool = try ToolRegistry.require(.gif2webp)
        let converted = context.tempDir.appendingPathComponent("converted.\(ext)")
        let args = ["-q", String(context.settings.convertQuality), "-m", "6", "-quiet", original.path, "-o", converted.path]
        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: "gif2webp", exitCode: result.exitCode, stderr: result.stderrText)
        }
        guard ImageIOCodec.verifyDecodable(converted) else {
            throw ConvertError.verificationFailed
        }
        let destination = nonClobberingSibling(of: original, ext: ext)
        try FileManager.default.copyItem(at: converted, to: destination)
        return Result(outputURL: destination, originalBytes: original.fileSize, newBytes: destination.fileSize)
    }

    private static func encodeWebP(source: URL, quality: Int, output: URL, tempDir: URL) async throws {
        let tool = try ToolRegistry.require(.cwebp)
        // cwebp reads PNG/JPEG/TIFF directly; anything else goes through PNG.
        var input = source
        let ext = source.pathExtension.lowercased()
        if !["png", "jpg", "jpeg", "tif", "tiff"].contains(ext) {
            let intermediate = tempDir.appendingPathComponent("cwebp-in.png")
            try ImageIOCodec.transcode(source, to: .png, quality: 100, output: intermediate)
            input = intermediate
        }
        let args = ["-q", String(quality), "-m", "6", "-metadata", "none", "-quiet", input.path, "-o", output.path]
        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: "cwebp", exitCode: result.exitCode, stderr: result.stderrText)
        }
    }

    static func nonClobberingSibling(of url: URL, ext: String) -> URL {
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(stem).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    public enum ConvertError: Error, LocalizedError {
        case noTarget
        case undecodable
        case animatedUnsupported(String)
        case verificationFailed

        public var errorDescription: String? {
            switch self {
            case .noTarget: "No conversion target selected"
            case .undecodable: "Could not decode source image"
            case .animatedUnsupported(let format): "Animated images can't be converted to \(format)"
            case .verificationFailed: "Converted file failed verification"
            }
        }
    }
}
