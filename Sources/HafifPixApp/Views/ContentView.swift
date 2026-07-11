import SwiftUI
import QuickLook
import HafifPixCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<UUID>()
    @State private var isDropTargeted = false
    @State private var quickLookURL: URL?

    var body: some View {
        ZStack {
            if model.entries.isEmpty {
                DropZoneView(isTargeted: isDropTargeted) {
                    openPanel()
                }
            } else {
                FileTableView(selection: $selection, quickLookURL: $quickLookURL)
            }

            if isDropTargeted && !model.entries.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(6)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls: urls)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBarView(selection: selection)
        }
        .quickLookPreview($quickLookURL)
        .alert(L("Background Removal Failed"), isPresented: Binding(
            get: { model.backgroundRemovalError != nil },
            set: { if !$0 { model.backgroundRemovalError = nil } }
        )) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(model.backgroundRemovalError ?? "")
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openPanel()
                } label: {
                    Label(L("Add Images"), systemImage: "plus")
                }
                .help(L("Add images or folders (⌘O)"))

                Button {
                    model.again()
                } label: {
                    Label(L("Again"), systemImage: "arrow.clockwise")
                }
                .disabled(model.entries.isEmpty || model.isBusy)
                .help(L("Re-run optimization with current settings (⌘R)"))

                Button {
                    selection.removeAll()
                    model.clear()
                } label: {
                    Label(L("Clear"), systemImage: "xmark.circle")
                }
                .disabled(model.entries.isEmpty)
                .help(L("Clear the list (⌘K)"))

                SettingsLink {
                    Label(L("Settings"), systemImage: "gearshape")
                }
                .help(L("Open settings (⌘,)"))
            }
        }
        .navigationTitle("HafifPix")
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .svg, .webP, .folder]
        panel.message = L("Choose images or folders to optimize")
        if panel.runModal() == .OK {
            model.add(urls: panel.urls)
        }
    }
}
