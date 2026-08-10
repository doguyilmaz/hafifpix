import Foundation

/// Installs the bundled `hafif` command by symlinking it into a directory on
/// the user's PATH. /usr/local/bin is the universal choice: it is on the
/// default macOS PATH (via /etc/paths) whether or not Homebrew is installed.
enum CLIInstaller {
    static let targetPath = "/usr/local/bin/hafif"

    /// The `hafif` binary shipped inside the app bundle.
    static var bundledToolPath: String? {
        Bundle.main.resourceURL?.appendingPathComponent("bin/hafif").path
    }

    static var isInstalled: Bool {
        guard let bundled = bundledToolPath,
              let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: targetPath) else {
            return false
        }
        return destination == bundled
    }

    static func install() throws {
        guard let source = bundledToolPath,
              FileManager.default.fileExists(atPath: source) else {
            throw CLIError.toolMissing
        }
        let directory = (targetPath as NSString).deletingLastPathComponent

        // No prompt when the directory is already writable (e.g. Homebrew set
        // up /usr/local/bin for the user). Otherwise ask for admin rights.
        if FileManager.default.isWritableFile(atPath: directory) {
            try? FileManager.default.removeItem(atPath: targetPath)
            try FileManager.default.createSymbolicLink(atPath: targetPath, withDestinationPath: source)
        } else {
            try runPrivileged([
                "/bin/mkdir", "-p", directory,
                "&&", "/bin/ln", "-sf", source, targetPath,
            ])
        }
    }

    static func uninstall() throws {
        let directory = (targetPath as NSString).deletingLastPathComponent
        if FileManager.default.isWritableFile(atPath: directory) {
            try? FileManager.default.removeItem(atPath: targetPath)
        } else {
            try runPrivileged(["/bin/rm", "-f", targetPath])
        }
    }

    /// Runs a command as root via the standard macOS admin authorization
    /// dialog. Each argument is individually shell-quoted (bare `&&` passes
    /// through as an operator) and the whole command is escaped for the
    /// AppleScript string literal, so a path containing quotes or spaces
    /// cannot break out or inject. Must be called on the main thread
    /// (NSAppleScript requirement).
    private static func runPrivileged(_ arguments: [String]) throws {
        let command = arguments.map { $0 == "&&" ? $0 : shellQuoted($0) }.joined(separator: " ")
        let script = "do shell script \"\(appleScriptQuoted(command))\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: script) else {
            throw CLIError.installFailed(nil)
        }
        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            // -128 is the user cancelling the auth dialog; treat as a no-op.
            if (errorInfo["NSAppleScriptErrorNumber"] as? Int) == -128 {
                throw CLIError.cancelled
            }
            throw CLIError.installFailed(errorInfo["NSAppleScriptErrorMessage"] as? String)
        }
    }

    /// POSIX single-quote escaping: wrap in single quotes and close/escape
    /// any embedded single quote. Safe for arbitrary paths.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a string for embedding in an AppleScript double-quoted literal.
    static func appleScriptQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    enum CLIError: Error, LocalizedError {
        case toolMissing
        case cancelled
        case installFailed(String?)

        var errorDescription: String? {
            switch self {
            case .toolMissing: L("The command line tool is missing from the app bundle.")
            case .cancelled: nil
            case .installFailed(let message): message ?? L("Could not install the command line tool.")
            }
        }
    }
}
