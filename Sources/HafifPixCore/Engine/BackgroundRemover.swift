import Foundation
import Vision
import CoreImage
import UniformTypeIdentifiers

/// Subject-from-background extraction using Apple's Vision framework —
/// the same on-device model behind "copy subject" in Photos and Preview.
/// Output is a PNG with alpha next to the original; sources are never touched.
public enum BackgroundRemover {
    public static func removeBackground(from url: URL, output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RemovalError.renderFailed
        }

        // Graphics/screenshots/logos sit on a uniform background: flood-fill
        // beats any ML model there (crisp edges, keeps enclosed regions).
        // Photos have varied borders: Vision's subject-lift model handles those.
        let result: CGImage
        if let flat = try flatBackgroundRemoval(of: image) {
            result = flat
        } else {
            result = try visionRemoval(of: url)
        }

        try ImageIOCodec.encode(images: [result], to: .png, quality: 100, output: output)
        guard ImageIOCodec.verifyDecodable(output) else {
            throw RemovalError.renderFailed
        }
    }

    private static func visionRemoval(of url: URL) throws -> CGImage {
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
        return cgImage
    }

    // MARK: - Flat background (flood fill)

    /// Returns nil when the border isn't uniform enough (defer to Vision).
    private static func flatBackgroundRemoval(of image: CGImage) throws -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 2, height > 2, width * height <= 64_000_000 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        @inline(__always) func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

        // Flat background test: all four corners agree on one color.
        // (Subjects often touch the edges; corners are the reliable signal.)
        func cornerAverage(_ cx: Int, _ cy: Int) -> (Int, Int, Int) {
            var r = 0, g = 0, b = 0
            for dy in 0..<3 {
                for dx in 0..<3 {
                    let o = offset(cx + dx, cy + dy)
                    r += Int(pixels[o]); g += Int(pixels[o + 1]); b += Int(pixels[o + 2])
                }
            }
            return (r / 9, g / 9, b / 9)
        }
        let corners = [
            cornerAverage(0, 0),
            cornerAverage(width - 3, 0),
            cornerAverage(0, height - 3),
            cornerAverage(width - 3, height - 3),
        ]
        for a in corners {
            for b in corners {
                if abs(a.0 - b.0) > 16 || abs(a.1 - b.1) > 16 || abs(a.2 - b.2) > 16 {
                    return nil // corners disagree: not a flat background, use Vision
                }
            }
        }
        let bgR = corners.reduce(0) { $0 + $1.0 } / 4
        let bgG = corners.reduce(0) { $0 + $1.1 } / 4
        let bgB = corners.reduce(0) { $0 + $1.2 } / 4

        let tolerance = 30 * 30 * 3
        @inline(__always) func distance(_ o: Int) -> Int {
            let dr = Int(pixels[o]) - bgR
            let dg = Int(pixels[o + 1]) - bgG
            let db = Int(pixels[o + 2]) - bgB
            return dr * dr + dg * dg + db * db
        }

        // BFS flood fill from all border pixels within tolerance.
        var removed = [Bool](repeating: false, count: width * height)
        var queue = [Int]()
        queue.reserveCapacity(width * 4)
        for x in 0..<width {
            for y in [0, height - 1] {
                let index = y * width + x
                if !removed[index], distance(index * 4) < tolerance { removed[index] = true; queue.append(index) }
            }
        }
        for y in 0..<height {
            for x in [0, width - 1] {
                let index = y * width + x
                if !removed[index], distance(index * 4) < tolerance { removed[index] = true; queue.append(index) }
            }
        }

        var head = 0
        while head < queue.count {
            let index = queue[head]; head += 1
            let x = index % width, y = index / width
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let n = ny * width + nx
                if !removed[n], distance(n * 4) < tolerance {
                    removed[n] = true
                    queue.append(n)
                }
            }
        }

        // Apply mask: removed pixels go transparent; edge pixels bordering the
        // removed region get partial alpha by color distance (de-fringing).
        for index in 0..<(width * height) {
            let o = index * 4
            if removed[index] {
                pixels[o] = 0; pixels[o + 1] = 0; pixels[o + 2] = 0; pixels[o + 3] = 0
            } else {
                let x = index % width, y = index / width
                var touchesRemoved = false
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    if removed[ny * width + nx] { touchesRemoved = true; break }
                }
                if touchesRemoved {
                    let d = distance(o)
                    let alpha = min(1.0, Double(d) / Double(tolerance * 2))
                    let a = UInt8(alpha * 255)
                    // Premultiplied: scale color with the new alpha.
                    pixels[o] = UInt8(Double(pixels[o]) * alpha)
                    pixels[o + 1] = UInt8(Double(pixels[o + 1]) * alpha)
                    pixels[o + 2] = UInt8(Double(pixels[o + 2]) * alpha)
                    pixels[o + 3] = a
                }
            }
        }

        return context.makeImage()
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
