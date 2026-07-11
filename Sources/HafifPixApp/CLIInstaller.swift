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
            try runPrivileged("mkdir -p '\(directory)' && ln -sf '\(source)' '\(targetPath)'")
        }
    }

    static func uninstall() throws {
        let directory = (targetPath as NSString).deletingLastPathComponent
        if FileManager.default.isWritableFile(atPath: directory) {
            try? FileManager.default.removeItem(atPath: targetPath)
        } else {
            try runPrivileged("rm -f '\(targetPath)'")
        }
    }

    /// Runs a shell command via the standard macOS admin authorization dialog.
    /// Must be called on the main thread (NSAppleScript requirement).
    private static func runPrivileged(_ command: String) throws {
        let script = "do shell script \"\(command)\" with administrator privileges"
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
