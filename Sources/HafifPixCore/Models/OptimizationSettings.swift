import Foundation

public struct OptimizationSettings: Codable, Sendable, Equatable {
    public enum Level: Int, Codable, Sendable, CaseIterable {
        case fast = 0
        case normal = 1
        case extra = 2
        case insane = 3

        public var displayName: String {
            switch self {
            case .fast: "Fast"
            case .normal: "Normal"
            case .extra: "Extra"
            case .insane: "Insane"
            }
        }
    }

    public enum BackupMode: String, Codable, Sendable, CaseIterable {
        case none
        case trash
        case sidecar

        public var displayName: String {
            switch self {
            case .none: "No backup (overwrite in place)"
            case .trash: "Move originals to Trash"
            case .sidecar: "Keep originals as .orig files"
            }
        }
    }

    public enum ConvertTarget: String, Codable, Sendable, CaseIterable {
        case none
        case webp
        case heic
        case avif

        public var displayName: String {
            switch self {
            case .none: "Don't convert"
            case .webp: "WebP"
            case .heic: "HEIC"
            case .avif: "AVIF"
            }
        }

        public var fileExtension: String? {
            switch self {
            case .none: nil
            case .webp: "webp"
            case .heic: "heic"
            case .avif: "avif"
            }
        }
    }

    /// Individually toggleable engines, mirroring the original app's tool list.
    public enum ToolID: String, Codable, Sendable, CaseIterable {
        case pngquant
        case oxipng
        case zopfli      // oxipng's built-in zopfli pass (Insane level)
        case jpegoptim
        case jpegtran    // MozJPEG
        case jpegli      // modern encoder; preferred for lossy JPEG when present
        case gifsicle
        case svgMinifier
        case cwebp

        public var displayName: String {
            switch self {
            case .pngquant: "pngquant (lossy PNG)"
            case .oxipng: "OxiPNG (lossless PNG)"
            case .zopfli: "Zopfli (extreme PNG deflate)"
            case .jpegoptim: "JPEGOptim"
            case .jpegtran: "MozJPEG jpegtran"
            case .jpegli: "jpegli (modern lossy JPEG)"
            case .gifsicle: "Gifsicle"
            case .svgMinifier: "SVG Minifier (built-in)"
            case .cwebp: "cwebp (WebP)"
            }
        }
    }

    public var lossyEnabled: Bool = true
    public var jpegQuality: Int = 82
    public var pngQuality: Int = 80
    public var gifQuality: Int = 80
    public var webpQuality: Int = 80
    public var level: Level = .normal

    public var stripPNGMetadata: Bool = true
    public var stripJPEGMetadata: Bool = true
    public var preservePermissions: Bool = true
    public var preserveDates: Bool = false

    public var backupMode: BackupMode = .none

    public var resizeEnabled: Bool = false
    public var maxDimension: Int = 2048

    public var convertTarget: ConvertTarget = .none
    public var convertQuality: Int = 85
    /// When converting, delete the source file if conversion won (smaller file).
    public var convertRemovesOriginal: Bool = false

    public var disabledTools: Set<ToolID> = []
    /// 0 means automatic (one job per CPU core).
    public var maxConcurrentJobs: Int = 0

    public init() {}

    public func isEnabled(_ tool: ToolID) -> Bool {
        !disabledTools.contains(tool)
    }

    public var effectiveConcurrency: Int {
        maxConcurrentJobs > 0 ? maxConcurrentJobs : ProcessInfo.processInfo.activeProcessorCount
    }

    /// One-line summary shown in the status bar, like the original app.
    public var summaryLine: String {
        var parts: [String] = []
        if lossyEnabled {
            parts.append("Lossy minification enabled (JPEG \(jpegQuality)%, PNG \(pngQuality)%, GIF \(gifQuality)%)")
        } else {
            parts.append("Lossless optimization")
        }
        parts.append("Level: \(level.displayName)")
        if resizeEnabled { parts.append("Fit to \(maxDimension)px") }
        if convertTarget != .none { parts.append("Convert to \(convertTarget.displayName)") }
        return parts.joined(separator: " · ")
    }
}

/// Shared persistence between the app and the CLI.
public enum SettingsStorage {
    public static let suiteName = "com.doguyilmaz.HafifPix"
    static let key = "settings.v1"

    public static func load() -> OptimizationSettings {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(OptimizationSettings.self, from: data) else {
            return OptimizationSettings()
        }
        return settings
    }

    public static func save(_ settings: OptimizationSettings) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
