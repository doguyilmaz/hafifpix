import Foundation
import Testing
@testable import HafifPixCore

@Suite("Format detection")
struct FormatDetectionTests {
    @Test func sniffsPNG() {
        let header = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0 as UInt8, count: 8))
        #expect(ImageFormat.sniff(header) == .png)
    }

    @Test func sniffsJPEG() {
        let header = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0 as UInt8, count: 12))
        #expect(ImageFormat.sniff(header) == .jpeg)
    }

    @Test func sniffsWebP() {
        var bytes: [UInt8] = Array("RIFF".utf8)
        bytes += [0, 0, 0, 0]
        bytes += Array("WEBP".utf8)
        bytes += [0, 0, 0, 0]
        #expect(ImageFormat.sniff(Data(bytes)) == .webp)
    }

    @Test func sniffsSVGText() {
        let svg = Data("<?xml version=\"1.0\"?><svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)
        #expect(ImageFormat.sniff(svg) == .svg)
    }

    @Test func rejectsGarbage() {
        #expect(ImageFormat.sniff(Data(repeating: 0xAB, count: 32)) == nil)
    }
}

@Suite("SVG minifier")
struct SVGMinifierTests {
    @Test func stripsCommentsAndMetadata() throws {
        let source = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <!-- exported from an editor -->
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="10" height="10">
            <metadata>junk</metadata>
            <title>My drawing</title>
            <rect inkscape:label="r1" x="0" y="0" width="10" height="10" fill="red"/>
        </svg>
        """
        let output = try SVGMinifier.minify(Data(source.utf8))
        let text = String(decoding: output, as: UTF8.self)

        #expect(!text.contains("<!--"))
        #expect(!text.contains("metadata"))
        #expect(!text.contains("<title>"))
        #expect(!text.contains("inkscape"))
        #expect(text.contains("<rect"))
        #expect(text.contains("fill=\"red\""))
        #expect(output.count < source.utf8.count)
    }

    @Test func rejectsNonSVG() {
        let html = Data("<html><body>hi</body></html>".utf8)
        #expect(throws: (any Error).self) {
            try SVGMinifier.minify(html)
        }
    }

    @Test func minifiedOutputStillParses() throws {
        let source = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
          <g><path d="M0 0h24v24H0z" fill="none"/><circle cx="12" cy="12" r="10"/></g>
        </svg>
        """
        let output = try SVGMinifier.minify(Data(source.utf8))
        let doc = try XMLDocument(data: output, options: [])
        #expect(doc.rootElement()?.name == "svg")
    }
}

@Suite("File collection")
struct FileCollectorTests {
    @Test func expandsDirectoriesAndFiltersByFormat() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hafif-test-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0 as UInt8, count: 64))
        try pngHeader.write(to: dir.appendingPathComponent("a.png"))
        try pngHeader.write(to: dir.appendingPathComponent("nested/b.png"))
        try Data("not an image".utf8).write(to: dir.appendingPathComponent("readme.txt"))
        // Extension lies: text content in a .png is rejected by sniffing.
        try Data("plain text".utf8).write(to: dir.appendingPathComponent("fake.png"))

        let requests = FileCollector.collect(from: [dir])
        let names = Set(requests.map(\.url.lastPathComponent))
        #expect(names == ["a.png", "b.png"])
        #expect(requests.allSatisfy { $0.format == .png })
    }
}

@Suite("Replacement safety")
struct FileReplacerTests {
    @Test func preservesPermissions() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hafif-replace-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let original = dir.appendingPathComponent("image.png")
        let candidate = dir.appendingPathComponent("candidate.png")
        try Data(repeating: 1, count: 1000).write(to: original)
        try Data(repeating: 2, count: 100).write(to: candidate)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: original.path)

        var settings = OptimizationSettings()
        settings.preservePermissions = true
        settings.backupMode = .none
        try FileReplacer.replace(original: original, with: candidate, settings: settings)

        let attributes = try fm.attributesOfItem(atPath: original.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #expect(original.fileSize == 100)
    }

    @Test func sidecarBackupKeepsOriginalBytes() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hafif-backup-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let original = dir.appendingPathComponent("photo.jpg")
        let candidate = dir.appendingPathComponent("optimized.jpg")
        try Data(repeating: 7, count: 500).write(to: original)
        try Data(repeating: 8, count: 50).write(to: candidate)

        var settings = OptimizationSettings()
        settings.backupMode = .sidecar
        try FileReplacer.replace(original: original, with: candidate, settings: settings)

        let backup = dir.appendingPathComponent("photo.orig.jpg")
        #expect(fm.fileExists(atPath: backup.path))
        #expect(backup.fileSize == 500)
        #expect(original.fileSize == 50)
    }
}

@Suite("Convert pipeline")
struct ConvertNamingTests {
    @Test func siblingNamesAvoidClobbering() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hafif-name-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let source = dir.appendingPathComponent("pic.png")
        try Data().write(to: source)
        try Data().write(to: dir.appendingPathComponent("pic.webp"))

        let sibling = ConvertPipeline.nonClobberingSibling(of: source, ext: "webp")
        #expect(sibling.lastPathComponent == "pic-1.webp")
    }
}
