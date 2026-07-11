import Foundation

private final class BundleToken {}

/// SPM's generated `Bundle.module` only searches the .app root and the original
/// build directory for executable targets, so a hand-assembled app that keeps
/// the resource bundle in Contents/Resources fails to find it. Resolve it
/// explicitly across every location it might live.
private let appBundle: Bundle = {
    let name = "HafifPix_HafifPixApp"
    let bases: [URL?] = [
        Bundle.main.resourceURL,
        Bundle.main.bundleURL,
        Bundle(for: BundleToken.self).resourceURL,
        Bundle(for: BundleToken.self).bundleURL,
    ]
    for base in bases.compactMap({ $0 }) {
        let url = base.appendingPathComponent("\(name).bundle")
        if let bundle = Bundle(url: url) { return bundle }
    }
    return Bundle.main
}()

/// Looks a string up in this module's catalog.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "HafifPixApp", bundle: appBundle)
}
