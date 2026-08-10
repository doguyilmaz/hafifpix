import SwiftUI
import UniformTypeIdentifiers
import HafifPixCore

@main
struct HafifPixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var updater = UpdaterModel()

    init() {
        // Hand the model to the delegate once, from the App initializer,
        // instead of a global static assigned from a view's onAppear (which
        // never fires reliably and cannot be a menu-bar/windowless app).
        appDelegate.model = model
    }

    var body: some Scene {
        Window("HafifPix", id: "main") {
            ContentView()
                .environment(model)
                .environment(updater)
        }
        .defaultSize(width: 780, height: 480)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L("Check for Updates…")) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button(L("Open…")) {
                    model.openFromMenu()
                }
                .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button(L("Optimize Again")) {
                    model.again()
                }
                .keyboardShortcut("r")
                .disabled(model.entries.isEmpty || model.isBusy)

                Button(L("Clear List")) {
                    model.clear()
                }
                .keyboardShortcut("k")
                .disabled(model.entries.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(updater)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once from the App initializer. Any file-open events that arrive
    /// before that (unlikely, but possible) are buffered and flushed on
    /// assignment so nothing is dropped.
    var model: AppModel? {
        didSet {
            guard let model, !pendingURLs.isEmpty else { return }
            let urls = pendingURLs
            pendingURLs = []
            model.add(urls: urls)
        }
    }
    private var pendingURLs: [URL] = []

    private func deliver(_ urls: [URL]) {
        if let model {
            model.add(urls: urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.servicesProvider = self
        }
    }

    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            deliver(urls)
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Best-effort temp cleanup; the revert cache lives under /tmp anyway.
            if let model {
                Task { await model.shutdown() }
            }
        }
    }

    /// Finder Services entry: "Optimize with HafifPix".
    @objc nonisolated func optimizeFiles(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let items = pboard.readObjects(forClasses: [NSURL.self]) as? [URL], !items.isEmpty else {
            return
        }
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
            deliver(items)
        }
    }
}

extension AppModel {
    /// Non-blocking file picker; a modal runModal() would freeze the main
    /// thread (and the two former call sites had drifted configurations).
    func openFromMenu() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .svg, .webP, .folder]
        panel.message = L("Choose images or folders to optimize")
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.add(urls: panel.urls)
        }
    }
}
