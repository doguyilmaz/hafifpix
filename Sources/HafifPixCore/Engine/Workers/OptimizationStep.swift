import Foundation

public struct WorkContext: Sendable {
    public let settings: OptimizationSettings
    public let tempDir: URL
    public let format: ImageFormat

    public init(settings: OptimizationSettings, tempDir: URL, format: ImageFormat) {
        self.settings = settings
        self.tempDir = tempDir
        self.format = format
    }
}

/// One engine pass. Reads `input`, writes a candidate to `output`.
/// Returns false when the step decided it has nothing to contribute
/// (tool disabled upstream handles most of that; this covers runtime cases
/// like pngquant's "result would be larger" exit).
public protocol OptimizationStep: Sendable {
    var name: String { get }
    /// Resize legitimately changes dimensions; everything else must not.
    var allowsDimensionChange: Bool { get }
    func produce(from input: URL, to output: URL, context: WorkContext) async throws -> Bool
}

public extension OptimizationStep {
    var allowsDimensionChange: Bool { false }
}
