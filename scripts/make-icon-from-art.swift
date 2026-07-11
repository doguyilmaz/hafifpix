// Builds the app iconset from a source artwork PNG (e.g. AI-generated):
// trims flat background outside the artwork, masks it to the macOS squircle,
// composites onto the 1024 icon grid with margins + shadow.
// Usage: swift scripts/make-icon-from-art.swift <source.png> <output.iconset>

import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: swift make-icon-from-art.swift <source.png> <output.iconset>")
    exit(1)
}
let sourceURL = URL(fileURLWithPath: args[1])
let iconsetURL = URL(fileURLWithPath: args[2])

guard let source = NSImage(contentsOf: sourceURL),
      let sourceRep = source.representations.compactMap({ $0 as? NSBitmapImageRep }).first
        ?? NSBitmapImageRep(data: source.tiffRepresentation ?? Data()) else {
    print("cannot read \(sourceURL.path)")
    exit(1)
}

// Trim near-white / near-uniform border: bounding box of pixels that differ
// from the corner background color.
let width = sourceRep.pixelsWide
let height = sourceRep.pixelsHigh
let corner = sourceRep.colorAt(x: 2, y: 2) ?? .white

func isBackground(_ color: NSColor?) -> Bool {
    guard let c = color?.usingColorSpace(.deviceRGB),
          let b = corner.usingColorSpace(.deviceRGB) else { return false }
    return abs(c.redComponent - b.redComponent) < 0.06
        && abs(c.greenComponent - b.greenComponent) < 0.06
        && abs(c.blueComponent - b.blueComponent) < 0.06
}

var minX = width, minY = height, maxX = 0, maxY = 0
let step = max(1, width / 512)
for y in stride(from: 0, to: height, by: step) {
    for x in stride(from: 0, to: width, by: step) {
        if !isBackground(sourceRep.colorAt(x: x, y: y)) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard minX < maxX, minY < maxY else {
    print("could not find artwork bounds")
    exit(1)
}
// colorAt uses top-left origin; NSImage drawing uses bottom-left. Flip Y.
let cropRect = NSRect(
    x: CGFloat(minX),
    y: CGFloat(height - 1 - maxY),
    width: CGFloat(maxX - minX + 1),
    height: CGFloat(maxY - minY + 1)
)

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func render(canvas: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let scale = canvas / 1024.0
    let plateSize = 824.0 * scale
    let plateOrigin = (canvas - plateSize) / 2
    let plateRect = NSRect(x: plateOrigin, y: plateOrigin, width: plateSize, height: plateSize)
    // Apple icon grid corner radius ≈ 22.4% of the squircle size.
    let plateRadius = plateSize * 0.224
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: plateRadius, yRadius: plateRadius)

    if canvas >= 64 {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
        shadow.shadowBlurRadius = 24 * scale
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        NSColor.black.withAlphaComponent(0.2).setFill()
        plate.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    NSGraphicsContext.current?.saveGraphicsState()
    plate.addClip()
    source.draw(in: plateRect, from: cropRect, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.current?.restoreGraphicsState()

    return rep
}

let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let rep = render(canvas: variant.size)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("failed to encode \(variant.name)")
        exit(1)
    }
    try png.write(to: iconsetURL.appendingPathComponent("\(variant.name).png"))
}
print("iconset written from \(sourceURL.lastPathComponent) (art bounds: \(Int(cropRect.width))×\(Int(cropRect.height)))")
