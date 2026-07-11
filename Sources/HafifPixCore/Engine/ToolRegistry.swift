import Foundation

/// External engine binaries the app drives. In a bundled app they live in
/// Contents/Resources/bin; during development they resolve from Homebrew.
public enum ExternalTool: String, CaseIterable, Sendable {
    case pngquant
    case oxipng
    case jpegoptim
    case jpegtran
    case gifsicle
    case cwebp
    case gif2webp
    case cjpegli

    var developmentPaths: [String] {
        switch self {
        case .jpegtran:
            // MozJPEG is keg-only; its jpegtran must not be confused with libjpeg's.
            ["/opt/homebrew/opt/mozjpeg/bin/jpegtran"]
        default:
            ["/opt/homebrew/bin/\(rawValue)", "/usr/local/bin/\(rawValue)"]
        }
    }
}

public enum ToolRegistry {
    /// Cached lookups; tools don't move while the app runs.
    private static let cache: [ExternalTool: URL] = {
        var result: [ExternalTool: URL] = [:]
        for tool in ExternalTool.allCases {
            result[tool] = locate(tool)
        }
        return result
    }()

    public static func url(for tool: ExternalTool) -> URL? {
        cache[tool]
    }

    public static func require(_ tool: ExternalTool) throws -> URL {
        guard let url = cache[tool] else {
            throw ProcessError.toolNotFound(tool.rawValue)
        }
        return url
    }

    public static var missingTools: [ExternalTool] {
        ExternalTool.allCases.filter { cache[$0] == nil }
    }

    private static func locate(_ tool: ExternalTool) -> URL? {
        var candidates: [String] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("bin/\(tool.rawValue)").path)
        }
        // The bundled CLI lives in Resources/bin next to the engines.
        if let executableURL = Bundle.main.executableURL {
            candidates.append(
                executableURL.deletingLastPathComponent()
                    .appendingPathComponent(tool.rawValue).path
            )
        }
        if let override = ProcessInfo.processInfo.environment["HAFIFPIX_TOOLS_DIR"] {
            candidates.append("\(override)/\(tool.rawValue)")
        }
        candidates.append(contentsOf: tool.developmentPaths)

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
