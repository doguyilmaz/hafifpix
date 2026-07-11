import Foundation
import UniformTypeIdentifiers

/// Optional pre-pass: fit the image inside settings.maxDimension before the
/// compressors run. GIFs go through gifsicle to preserve animation.
public struct ResizeStep: OptimizationStep {
    public let name = "resize"
    public let allowsDimensionChange = true

    public init() {}

    public func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool {
        let maxDimension = context.settings.maxDimension
        guard maxDimension > 0 else { return false }

        switch context.format {
        case .png:
            return try ImageIOCodec.resize(input, maxDimension: maxDimension, to: .png, quality: 100, output: output)
        case .jpeg:
            // Encode near-lossless here; the JPEG chain applies the real target quality.
            return try ImageIOCodec.resize(input, maxDimension: maxDimension, to: .jpeg, quality: 92, output: output)
        case .gif:
            return try await resizeGIF(input, maxDimension: maxDimension, output: output)
        case .webp:
            return try await resizeWebP(input, maxDimension: maxDimension, output: output, context: context)
        case .svg:
            return false
        }
    }

    private func resizeGIF(_ input: URL, maxDimension: Int, output: URL) async throws -> Bool {
        guard let info = ImageIOCodec.info(of: input),
              max(info.pixelWidth, info.pixelHeight) > maxDimension else {
            return false
        }
        let tool = try ToolRegistry.require(.gifsicle)
        let args = ["--resize-fit", "\(maxDimension)x\(maxDimension)", "-o", output.path, input.path]
        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: name, exitCode: result.exitCode, stderr: result.stderrText)
        }
        return FileManager.default.fileExists(atPath: output.path)
    }

    private func resizeWebP(_ input: URL, maxDimension: Int, output: URL, context: WorkContext) async throws -> Bool {
        guard let info = ImageIOCodec.info(of: input), info.frameCount == 1,
              max(info.pixelWidth, info.pixelHeight) > maxDimension else {
            return false
        }
        let tool = try ToolRegistry.require(.cwebp)
        let intermediate = context.tempDir.appendingPathComponent("resize-intermediate-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: intermediate) }
        guard try ImageIOCodec.resize(input, maxDimension: maxDimension, to: .png, quality: 100, output: intermediate) else {
            return false
        }
        let args = ["-q", String(context.settings.webpQuality), "-m", "6", "-quiet", intermediate.path, "-o", output.path]
        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: name, exitCode: result.exitCode, stderr: result.stderrText)
        }
        return FileManager.default.fileExists(atPath: output.path)
    }
}
