import Foundation

public struct SVGMinifyStep: OptimizationStep {
    public let name = "svg minifier"

    public init() {}

    public func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool {
        let data = try Data(contentsOf: input)
        let minified = try SVGMinifier.minify(data)
        try minified.write(to: output)
        return true
    }
}
