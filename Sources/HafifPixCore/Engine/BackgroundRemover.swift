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

        // Speck cleanup: small surviving islands whose color is still close to
        // the background are residue (soft halos, dust), not subject. The real
        // subject is a large connected component and is never touched.
        var componentID = [Int](repeating: -1, count: width * height)
        var component = 0
        for start in 0..<(width * height) where !removed[start] && componentID[start] == -1 {
            var members = [start]
            var head = 0
            componentID[start] = component
            var nearBackground = 0
            while head < members.count {
                let index = members[head]; head += 1
                if distance(index * 4) < tolerance * 6 { nearBackground += 1 }
                let x = index % width, y = index / width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let n = ny * width + nx
                    if !removed[n], componentID[n] == -1 {
                        componentID[n] = component
                        members.append(n)
                    }
                }
            }
            let maxSpeck = max(64, width * height / 2000)
            if members.count < maxSpeck, Double(nearBackground) / Double(members.count) > 0.6 {
                for index in members { removed[index] = true }
            }
            component += 1
        }

        // Edge band: pixels within 2px of the removed region hold the source's
        // anti-aliasing, i.e. a blend of subject color and background.
        var band = [Bool](repeating: false, count: width * height)
        for pass in 0..<2 {
            var next = [Int]()
            for index in 0..<(width * height) where !removed[index] && !band[index] {
                let x = index % width, y = index / width
                inner: for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let n = ny * width + nx
                        if pass == 0 ? removed[n] : band[n] {
                            next.append(index)
                            break inner
                        }
                    }
                }
            }
            for index in next { band[index] = true }
        }

        // Apply mask. Band pixels get color decontamination: un-blend the
        // background share (t) out of the pixel instead of just fading it —
        // this is what kills the white fringe line on the rim.
        for index in 0..<(width * height) {
            let o = index * 4
            if removed[index] {
                pixels[o] = 0; pixels[o + 1] = 0; pixels[o + 2] = 0; pixels[o + 3] = 0
            } else if band[index] {
                let d = (Double(distance(o)) / 3.0).squareRoot()
                let bgShare = max(0.0, 1.0 - d / 170.0)
                if bgShare >= 0.999 {
                    pixels[o] = 0; pixels[o + 1] = 0; pixels[o + 2] = 0; pixels[o + 3] = 0
                    continue
                }
                let alpha = 1.0 - bgShare
                // Premultiplied space: observed = subject*alpha + bg*bgShare,
                // so subtracting bg*bgShare leaves the premultiplied subject.
                pixels[o] = UInt8(max(0.0, Double(pixels[o]) - Double(bgR) * bgShare))
                pixels[o + 1] = UInt8(max(0.0, Double(pixels[o + 1]) - Double(bgG) * bgShare))
                pixels[o + 2] = UInt8(max(0.0, Double(pixels[o + 2]) - Double(bgB) * bgShare))
                pixels[o + 3] = UInt8(alpha * 255)
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
