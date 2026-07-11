// Renders the HafifPix app icon: a feather-light down arrow inside a dashed
// drop square on an indigo→teal gradient, following the macOS icon grid.
// Usage: swift scripts/make-icon.swift <output.iconset>

import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: swift make-icon.swift <output.iconset>")
    exit(1)
}
let iconsetURL = URL(fileURLWithPath: args[1])
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

    // macOS icon grid: square content ~824pt centered in the 1024 canvas.
    let plateSize = 824.0 * scale
    let plateOrigin = (canvas - plateSize) / 2
    let plateRect = NSRect(x: plateOrigin, y: plateOrigin, width: plateSize, height: plateSize)
    let plateRadius = 185.0 * scale
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: plateRadius, yRadius: plateRadius)

    // Soft drop shadow.
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

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.22, green: 0.16, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.29, green: 0.35, blue: 0.85, alpha: 1),
        NSColor(calibratedRed: 0.15, green: 0.65, blue: 0.72, alpha: 1),
    ])!
    gradient.draw(in: plate, angle: 60)

    // Subtle top highlight for depth.
    let highlight = NSGradient(
        starting: NSColor.white.withAlphaComponent(0.18),
        ending: NSColor.white.withAlphaComponent(0.0)
    )!
    NSGraphicsContext.current?.saveGraphicsState()
    plate.addClip()
    let highlightRect = NSRect(x: plateRect.minX, y: plateRect.midY, width: plateRect.width, height: plateRect.height / 2)
    highlight.draw(in: highlightRect, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Dashed drop square, echoing the drop zone.
    let squareSize = 430.0 * scale
    let squareRect = NSRect(
        x: (canvas - squareSize) / 2,
        y: (canvas - squareSize) / 2,
        width: squareSize,
        height: squareSize
    )
    let square = NSBezierPath(roundedRect: squareRect, xRadius: 80 * scale, yRadius: 80 * scale)
    square.lineWidth = 26 * scale
    square.setLineDash([58 * scale, 38 * scale], count: 2, phase: 20 * scale)
    NSColor.white.withAlphaComponent(0.85).setStroke()
    square.stroke()

    // Bold down arrow.
    let arrow = NSBezierPath()
    let cx = canvas / 2
    let cy = canvas / 2
    let shaftW = 66.0 * scale
    let headW = 168.0 * scale
    let headH = 118.0 * scale
    let top = cy + 130.0 * scale
    let bottom = cy - 128.0 * scale
    arrow.move(to: NSPoint(x: cx - shaftW / 2, y: top))
    arrow.line(to: NSPoint(x: cx + shaftW / 2, y: top))
    arrow.line(to: NSPoint(x: cx + shaftW / 2, y: bottom + headH))
    arrow.line(to: NSPoint(x: cx + headW / 2, y: bottom + headH))
    arrow.line(to: NSPoint(x: cx, y: bottom))
    arrow.line(to: NSPoint(x: cx - headW / 2, y: bottom + headH))
    arrow.line(to: NSPoint(x: cx - shaftW / 2, y: bottom + headH))
    arrow.close()
    NSColor.white.setFill()
    arrow.fill()

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
print("iconset written to \(iconsetURL.path)")
