import Foundation

/// Expands dropped/opened URLs into optimizable files: directories are walked
/// recursively (hidden files and packages skipped), formats are verified by
/// magic bytes, duplicates removed.
public enum FileCollector {
    public static func collect(from urls: [URL]) -> [JobRequest] {
        var seen = Set<String>()
        var requests: [JobRequest] = []
        let fm = FileManager.default

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let child = enumerator?.nextObject() as? URL {
                    appendIfImage(child, seen: &seen, into: &requests)
                }
            } else {
                appendIfImage(url, seen: &seen, into: &requests)
            }
        }
        return requests
    }

    private static func appendIfImage(_ url: URL, seen: inout Set<String>, into requests: inout [JobRequest]) {
        let standardized = url.standardizedFileURL
        guard !seen.contains(standardized.path) else { return }
        let ext = standardized.pathExtension.lowercased()
        guard ImageFormat.allExtensions.contains(ext),
              let format = ImageFormat.detect(url: standardized) else { return }
        seen.insert(standardized.path)
        requests.append(JobRequest(url: standardized, format: format))
    }
}
