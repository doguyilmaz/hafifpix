import Foundation

public struct GifsicleStep: OptimizationStep {
    public let name = "gifsicle"

    public init() {}

    public func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool {
        let tool = try ToolRegistry.require(.gifsicle)

        let optimizeLevel = switch context.settings.level {
        case .fast: 1
        case .normal: 2
        case .extra, .insane: 3
        }

        var args = ["-O\(optimizeLevel)"]
        if context.settings.lossyEnabled {
            let lossiness = min(200, max(20, (100 - context.settings.gifQuality) * 2))
            args.append("--lossy=\(lossiness)")
        }
        args.append(contentsOf: ["--no-comments", "--no-names", "-o", output.path, input.path])

        let result = try await ProcessRunner.run(tool, arguments: args)
        guard result.exitCode == 0 else {
            throw ProcessError.failed(tool: name, exitCode: result.exitCode, stderr: result.stderrText)
        }
        return FileManager.default.fileExists(atPath: output.path)
    }
}
