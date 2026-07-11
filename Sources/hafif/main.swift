import Foundation
import HafifPixCore

let usage = """
hafif: image optimizer (HafifPix CLI)

USAGE: hafif [options] <files or directories...>

OPTIONS:
  --lossless              Disable lossy minification (pixels never change)
  --quality <n>           Set JPEG, PNG, GIF and WebP quality at once (1-100)
  --jpeg-quality <n>      JPEG quality (default 82)
  --png-quality <n>       PNG quality (default 80)
  --gif-quality <n>       GIF quality (default 80)
  --webp-quality <n>      WebP quality (default 80)
  --level <l>             fast | normal | extra | insane (default normal)
  --convert <f>           Convert to webp | heic | avif (writes sibling files)
  --resize <n>            Fit images within n pixels on the longest side
  --jobs <n>              Parallel jobs (default: CPU count)
  --backup <mode>         none | trash | sidecar (default none)
  --keep-metadata         Don't strip EXIF/color profile metadata
  --keep-dates            Preserve file modification dates
  --quiet                 Only print the summary
  --version               Print version
  --help                  Show this help
"""

struct CLIOptions {
    var settings = SettingsStorage.load()
    var paths: [URL] = []
    var quiet = false
}

func parseArguments(_ arguments: [String]) -> CLIOptions? {
    var options = CLIOptions()
    var iterator = arguments.makeIterator()

    func nextValue(for flag: String) -> String? {
        guard let value = iterator.next() else {
            FileHandle.standardError.write(Data("error: \(flag) requires a value\n".utf8))
            return nil
        }
        return value
    }
    func nextInt(for flag: String, in range: ClosedRange<Int>) -> Int? {
        guard let raw = nextValue(for: flag), let value = Int(raw), range.contains(value) else {
            FileHandle.standardError.write(Data("error: \(flag) expects a number in \(range)\n".utf8))
            return nil
        }
        return value
    }

    while let arg = iterator.next() {
        switch arg {
        case "--help", "-h":
            print(usage)
            return nil
        case "--version":
            print("hafif 1.0.0 (HafifPix)")
            return nil
        case "--lossless":
            options.settings.lossyEnabled = false
        case "--quality":
            guard let q = nextInt(for: arg, in: 1...100) else { return nil }
            options.settings.jpegQuality = q
            options.settings.pngQuality = q
            options.settings.gifQuality = q
            options.settings.webpQuality = q
            options.settings.convertQuality = q
        case "--jpeg-quality":
            guard let q = nextInt(for: arg, in: 1...100) else { return nil }
            options.settings.jpegQuality = q
        case "--png-quality":
            guard let q = nextInt(for: arg, in: 1...100) else { return nil }
            options.settings.pngQuality = q
        case "--gif-quality":
            guard let q = nextInt(for: arg, in: 1...100) else { return nil }
            options.settings.gifQuality = q
        case "--webp-quality":
            guard let q = nextInt(for: arg, in: 1...100) else { return nil }
            options.settings.webpQuality = q
        case "--level":
            guard let raw = nextValue(for: arg) else { return nil }
            switch raw {
            case "fast": options.settings.level = .fast
            case "normal": options.settings.level = .normal
            case "extra": options.settings.level = .extra
            case "insane": options.settings.level = .insane
            default:
                FileHandle.standardError.write(Data("error: unknown level '\(raw)'\n".utf8))
                return nil
            }
        case "--convert":
            guard let raw = nextValue(for: arg),
                  let target = OptimizationSettings.ConvertTarget(rawValue: raw) else {
                FileHandle.standardError.write(Data("error: --convert expects webp, heic or avif\n".utf8))
                return nil
            }
            options.settings.convertTarget = target
        case "--resize":
            guard let n = nextInt(for: arg, in: 16...100_000) else { return nil }
            options.settings.resizeEnabled = true
            options.settings.maxDimension = n
        case "--jobs":
            guard let n = nextInt(for: arg, in: 1...64) else { return nil }
            options.settings.maxConcurrentJobs = n
        case "--backup":
            guard let raw = nextValue(for: arg),
                  let mode = OptimizationSettings.BackupMode(rawValue: raw) else {
                FileHandle.standardError.write(Data("error: --backup expects none, trash or sidecar\n".utf8))
                return nil
            }
            options.settings.backupMode = mode
        case "--keep-metadata":
            options.settings.stripJPEGMetadata = false
            options.settings.stripPNGMetadata = false
        case "--keep-dates":
            options.settings.preserveDates = true
        case "--quiet", "-q":
            options.quiet = true
        default:
            if arg.hasPrefix("-") {
                FileHandle.standardError.write(Data("error: unknown option '\(arg)'\n\(usage)\n".utf8))
                return nil
            }
            options.paths.append(URL(fileURLWithPath: arg))
        }
    }

    guard !options.paths.isEmpty else {
        print(usage)
        return nil
    }
    return options
}

guard let options = parseArguments(Array(CommandLine.arguments.dropFirst())) else {
    exit(CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") ? 0 : 1)
}

let requests = FileCollector.collect(from: options.paths)
guard !requests.isEmpty else {
    FileHandle.standardError.write(Data("no optimizable images found (png, jpeg, gif, svg, webp)\n".utf8))
    exit(1)
}

// Track progress; the event handler fires from worker threads.
final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = 0
    private var failed = 0
    private var totalOriginal: Int64 = 0
    private var totalNew: Int64 = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private let names: [JobID: String]
    private let quiet: Bool
    let total: Int

    init(requests: [JobRequest], quiet: Bool) {
        total = requests.count
        names = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0.url.lastPathComponent) })
        self.quiet = quiet
    }

    func waitUntilDone() async {
        await withCheckedContinuation { cont in
            lock.lock()
            if finished == total {
                lock.unlock()
                cont.resume()
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }

    func handle(_ event: JobEvent) {
        let name = names[event.id] ?? "?"
        lock.lock()
        defer { lock.unlock() }

        switch event.status {
        case .pending, .running, .reverted:
            return
        case .optimized(let original, let new):
            totalOriginal += original
            totalNew += new
            if !quiet { print("✓ \(name): \(Formatting.bytes(original)) → \(Formatting.bytes(new)) saved \(Formatting.savings(original: original, new: new))") }
        case .converted(let original, let new, let output):
            totalOriginal += original
            totalNew += new
            if !quiet { print("✓ \(name) → \(output.lastPathComponent): \(Formatting.bytes(original)) → \(Formatting.bytes(new))") }
        case .alreadyOptimal(let bytes):
            totalOriginal += bytes
            totalNew += bytes
            if !quiet { print("• \(name): already optimized (\(Formatting.bytes(bytes)))") }
        case .failed(let message):
            failed += 1
            FileHandle.standardError.write(Data("✗ \(name): \(message)\n".utf8))
        }

        finished += 1
        if finished == total {
            continuation?.resume()
            continuation = nil
        }
    }

    func summary() -> (String, Int32) {
        lock.lock()
        defer { lock.unlock() }
        let saved = totalOriginal - totalNew
        var line = "Optimized \(total - failed)/\(total) files"
        if saved > 0, totalOriginal > 0 {
            line += " — saved \(Formatting.bytes(saved)) (\(Formatting.savings(original: totalOriginal, new: totalNew)))"
        }
        return (line, failed > 0 ? 2 : 0)
    }
}

let progress = Progress(requests: requests, quiet: options.quiet)
let engine = OptimizationEngine { event in
    progress.handle(event)
}

if !options.quiet {
    print("hafif: \(requests.count) file(s), \(options.settings.summaryLine)")
}

let settings = options.settings
await engine.enqueue(requests, settings: settings)
await progress.waitUntilDone()

let (summary, exitCode) = progress.summary()
print(summary)
await engine.shutdown()
exit(exitCode)
