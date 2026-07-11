import Foundation

private final class BundleToken {}

/// Resolve the core resource bundle explicitly (see the app-side note): the
/// bundle sits in Contents/Resources for the app and next to the executable
/// for the CLI, neither of which SPM's Bundle.module reliably finds.
private let coreBundle: Bundle = {
    let name = "HafifPix_HafifPixCore"
    let bases: [URL?] = [
        Bundle.main.resourceURL,
        Bundle.main.bundleURL,
        Bundle(for: BundleToken.self).resourceURL,
        Bundle(for: BundleToken.self).bundleURL,
        Bundle.main.executableURL?.deletingLastPathComponent(),
    ]
    for base in bases.compactMap({ $0 }) {
        let url = base.appendingPathComponent("\(name).bundle")
        if let bundle = Bundle(url: url) { return bundle }
    }
    return Bundle.main
}()

/// Core-module string lookup (settings names, statuses, error messages).
func LC(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "HafifPixCore", bundle: coreBundle)
}
