import Foundation
import UniformTypeIdentifiers

/// Recompresses existing WebP files. Lossless sources (VP8L) are re-encoded
/// losslessly at a higher effort; lossy sources are only touched when lossy
/// minification is on. Animated WebP is left alone — cwebp is single-frame.
public struct WebPRecompressStep: OptimizationStep {
    public let name = "cwebp"

    public init() {}

    public func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool {
        let tool = try ToolRegistry.require(.cwebp)

        guard let info = ImageIOCodec.info(of: input), info.frameCount == 1 else {
            return false
        }

        let sourceIsLossless = try isLosslessWebP(input)
        if !sourceIsLossless && !context.settings.lossyEnabled {
            return false
        }

        // cwebp's WebP input support is inconsistent; go through a PNG intermediate.
        let intermediate = context.tempDir.appendingPathComponent("webp-intermediate-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: intermediate) }
        try ImageIOCodec.transcode(input, to: .png, quality: 100, output: intermediate)

        let effort = switch context.settings.level {
        case .fast: 4
        case .normal: 6
        case .extra, .insane: 9
        }

        var args: [String]
        if sourceIsLossless {
            args = ["-z", String(effort)]
        } else {
            args = ["-q", String(context.settings.webpQuality), "-m", "6"]
        }
        if context.settings.stripJPEGMetadata {
            args.append(contentsOf: ["-metadata", "none"])
        }
        args.append(contentsOf: ["-quiet", intermediate.path, "-o", output.path])

        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: name, exitCode: result.exitCode, stderr: result.stderrText)
        }
        return FileManager.default.fileExists(atPath: output.path)
    }

    /// WebP container: bytes 12-15 name the first chunk — "VP8L" is lossless,
    /// "VP8 " lossy, "VP8X" extended (search its payload for the actual codec).
    func isLosslessWebP(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 1024), header.count >= 16 else {
            return false
        }
        let chunk = String(decoding: header[12..<16], as: UTF8.self)
        switch chunk {
        case "VP8L":
            return true
        case "VP8X":
            // Look for a VP8L chunk in the extended container.
            return header.range(of: Data("VP8L".utf8)) != nil
        default:
            return false
        }
    }
}
