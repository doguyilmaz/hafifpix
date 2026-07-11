import SwiftUI
import HafifPixCore

@main
struct HafifPixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var updater = UpdaterModel()

    var body: some Scene {
        Window("HafifPix", id: "main") {
            ContentView()
                .environment(model)
                .environment(updater)
                .onAppear {
                    AppDelegate.model = model
                }
        }
        .defaultSize(width: 780, height: 480)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    AppDelegate.model?.openFromMenu()
                }
                .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Optimize Again") {
                    model.again()
                }
                .keyboardShortcut("r")
                .disabled(model.entries.isEmpty || model.isBusy)

                Button("Clear List") {
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            Self.model?.add(urls: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort temp cleanup; the revert cache lives under /tmp anyway.
        if let model = Self.model {
            Task { await model.shutdown() }
        }
    }

    /// Finder Services entry: "Optimize with HafifPix".
    @objc func optimizeFiles(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let items = pboard.readObjects(forClasses: [NSURL.self]) as? [URL], !items.isEmpty else {
            return
        }
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            Self.model?.add(urls: items)
        }
    }
}

extension AppModel {
    func openFromMenu() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose images or folders to optimize"
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }
}
