import Foundation

/// Lossy palette quantization. The single biggest PNG win when lossy is on.
public struct PngquantStep: OptimizationStep {
    public let name = "pngquant"

    public init() {}

    public func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool {
        let tool = try ToolRegistry.require(.pngquant)
        let quality = context.settings.pngQuality
        let minQuality = max(0, quality - 25)

        let speed = switch context.settings.level {
        case .fast: 10
        case .normal: 4
        case .extra: 2
        case .insane: 1
        }

        var args = [
            "--quality=\(minQuality)-\(quality)",
            "--speed", String(speed),
            "--skip-if-larger",
            "--force",
            "--output", output.path,
        ]
        if context.settings.stripPNGMetadata {
            args.append("--strip")
        }
        args.append(input.path)

        let result = try await ProcessRunner.run(tool, arguments: args)
        switch result.exitCode {
        case 0:
            return FileManager.default.fileExists(atPath: output.path)
        case 98, 99:
            // 98: result would be larger; 99: quality floor not reachable.
            // Both mean "no candidate", not failure.
            return false
        default:
            throw ProcessError.failed(tool: name, exitCode: result.exitCode, stderr: result.stderrText)
        }
    }
}

/// Lossless PNG recompression; replaces OptiPNG/PNGCrush/AdvPNG from the
/// original app. At Insane level it adds oxipng's built-in Zopfli pass.
public struct OxipngStep: OptimizationStep {
    public let name = "oxipng"

    public init() {}

    public func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool {
        let tool = try ToolRegistry.require(.oxipng)

        var args: [String]
        switch context.settings.level {
        case .fast: args = ["-o", "2"]
        case .normal: args = ["-o", "4"]
        case .extra: args = ["-o", "6"]
        case .insane: args = ["-o", "6"]
        }
        if context.settings.level == .insane, context.settings.isEnabled(.zopfli) {
            args.append("--zopfli")
        }
        if context.settings.stripPNGMetadata {
            args.append(contentsOf: ["--strip", "safe"])
        }
        args.append(contentsOf: ["--quiet", "--force", "--out", output.path, input.path])

        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: name, exitCode: result.exitCode, stderr: result.stderrText)
        }
        return FileManager.default.fileExists(atPath: output.path)
    }
}
