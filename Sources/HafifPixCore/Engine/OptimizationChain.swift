import Foundation

public enum ChainBuilder {
    /// Assembles the step sequence for a format, honoring tool toggles.
    /// Order matters: lossy passes first (they change pixels), lossless
    /// recompression last (it squeezes whatever the lossy pass produced).
    public static func steps(for format: ImageFormat, settings: OptimizationSettings) -> [any OptimizationStep] {
        var steps: [any OptimizationStep] = []

        if settings.resizeEnabled, format != .svg {
            steps.append(ResizeStep())
        }

        switch format {
        case .png:
            if settings.lossyEnabled, settings.isEnabled(.pngquant), ToolRegistry.url(for: .pngquant) != nil {
                steps.append(PngquantStep())
            }
            if settings.isEnabled(.oxipng), ToolRegistry.url(for: .oxipng) != nil {
                steps.append(OxipngStep())
            }
        case .jpeg:
            let jpegliActive = settings.lossyEnabled
                && settings.isEnabled(.jpegli)
                && ToolRegistry.url(for: .cjpegli) != nil
            if jpegliActive {
                steps.append(CjpegliStep())
            }
            if settings.isEnabled(.jpegoptim), ToolRegistry.url(for: .jpegoptim) != nil,
               settings.lossyEnabled || settings.stripJPEGMetadata {
                // jpegli owns the lossy pass when active; jpegoptim then only
                // strips/optimizes losslessly instead of re-encoding again.
                steps.append(JpegoptimStep(lossyAllowed: !jpegliActive))
            }
            if settings.isEnabled(.jpegtran), ToolRegistry.url(for: .jpegtran) != nil {
                steps.append(JpegtranStep())
            }
        case .gif:
            if settings.isEnabled(.gifsicle), ToolRegistry.url(for: .gifsicle) != nil {
                steps.append(GifsicleStep())
            }
        case .svg:
            if settings.isEnabled(.svgMinifier) {
                steps.append(SVGMinifyStep())
            }
        case .webp:
            if settings.isEnabled(.cwebp), ToolRegistry.url(for: .cwebp) != nil {
                steps.append(WebPRecompressStep())
            }
        }
        return steps
    }
}

public enum ChainRunner {
    public struct Outcome: Sendable {
        /// Best candidate produced by the chain, or nil when nothing beat the original.
        public let bestURL: URL?
        public let originalBytes: Int64
        public let bestBytes: Int64
    }

    /// Runs each step against the current best candidate, adopting a step's
    /// output only if it is strictly smaller AND still decodes correctly with
    /// unchanged dimensions/frame count. The original file is never touched.
    public static func run(
        original: URL,
        format: ImageFormat,
        context: WorkContext,
        onStep: @Sendable @escaping (String) -> Void
    ) async throws -> Outcome {
        let fm = FileManager.default
        let originalBytes = original.fileSize
        // Reference for verification; re-captured after an adopted resize so
        // later steps compare against the new legitimate dimensions.
        var referenceInfo = format == .svg ? nil : ImageIOCodec.info(of: original)

        var bestURL = original
        var bestBytes = originalBytes
        var stepIndex = 0

        for step in ChainBuilder.steps(for: format, settings: context.settings) {
            try Task.checkCancellation()
            onStep(step.name)

            stepIndex += 1
            let candidate = context.tempDir.appendingPathComponent("step-\(stepIndex).\(original.pathExtension)")
            if fm.fileExists(atPath: candidate.path) { try? fm.removeItem(at: candidate) }

            let produced: Bool
            do {
                produced = try await step.produce(from: bestURL, to: candidate, context: context)
            } catch let error as ProcessError {
                // A single engine failing shouldn't kill the whole file's chain —
                // mirror the original app, which just skips a misbehaving worker.
                if case .toolNotFound = error { continue }
                throw error
            }
            guard produced else { continue }

            let candidateBytes = candidate.fileSize
            guard candidateBytes > 0, candidateBytes < bestBytes else {
                try? fm.removeItem(at: candidate)
                continue
            }
            guard verify(candidate: candidate, format: format, originalInfo: referenceInfo, step: step) else {
                try? fm.removeItem(at: candidate)
                continue
            }

            bestURL = candidate
            bestBytes = candidateBytes
            if step.allowsDimensionChange, format != .svg {
                referenceInfo = ImageIOCodec.info(of: candidate)
            }
        }

        if bestURL == original || bestBytes >= originalBytes {
            return Outcome(bestURL: nil, originalBytes: originalBytes, bestBytes: originalBytes)
        }
        return Outcome(bestURL: bestURL, originalBytes: originalBytes, bestBytes: bestBytes)
    }

    private static func verify(
        candidate: URL,
        format: ImageFormat,
        originalInfo: ImageIOCodec.ImageInfo?,
        step: any OptimizationStep
    ) -> Bool {
        if format == .svg {
            guard let data = try? Data(contentsOf: candidate),
                  let doc = try? XMLDocument(data: data, options: []),
                  doc.rootElement()?.name?.lowercased() == "svg" else {
                return false
            }
            return true
        }

        guard ImageIOCodec.verifyDecodable(candidate),
              let newInfo = ImageIOCodec.info(of: candidate) else {
            return false
        }
        if let originalInfo {
            // Frame count must survive (animation), dimensions too unless resizing.
            guard newInfo.frameCount == originalInfo.frameCount else { return false }
            if !step.allowsDimensionChange {
                guard newInfo.pixelWidth == originalInfo.pixelWidth,
                      newInfo.pixelHeight == originalInfo.pixelHeight else {
                    return false
                }
            }
        }
        return true
    }
}
