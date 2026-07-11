import SwiftUI
import HafifPixCore

struct FileTableView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Set<UUID>
    @Binding var quickLookURL: URL?
    // Persists the user's column widths and arrangement across launches.
    @SceneStorage("fileTableColumns") private var columnCustomization: TableColumnCustomization<AppModel.Entry>
    @State private var sortOrder: [KeyPathComparator<AppModel.Entry>] = []

    var body: some View {
        // Ideal widths must sum below the default window width: overflowing
        // triggers a horizontal scrollbar and drops the rounded inset row style.
        Table(model.entries.sorted(using: sortOrder), selection: $selection,
              sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("", value: \.statusRank) { entry in
                StatusIndicator(status: entry.status)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(28)
            .customizationID("state")
            .disabledCustomizationBehavior(.all)

            TableColumn("Name", value: \.name, comparator: .localizedStandard) { entry in
                HStack(spacing: 6) {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.format.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .help(entry.url.path)
            }
            .width(min: 150, ideal: 250)
            .customizationID("name")

            TableColumn("Size", value: \.originalBytes) { entry in
                if entry.currentBytes != entry.originalBytes {
                    Text("\(Formatting.bytes(entry.originalBytes)) → \(Formatting.bytes(entry.currentBytes))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text(Formatting.bytes(entry.originalBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 140)
            .customizationID("size")

            TableColumn("Savings", value: \.savingsFraction) { entry in
                if entry.savedBytes > 0 {
                    Text(Formatting.savings(original: entry.originalBytes, new: entry.currentBytes))
                        .monospacedDigit()
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 56, ideal: 70)
            .customizationID("savings")

            TableColumn("Status", value: \.statusText) { entry in
                Text(entry.statusText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(statusColor(entry.status))
                    .help(entry.statusText)
            }
            .width(min: 110, ideal: 165)
            .customizationID("status")
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            reveal(ids: ids)
        }
        .onKeyPress(.space) {
            if let id = selection.first,
               let entry = model.entries.first(where: { $0.id == id }) {
                quickLookURL = entry.url
                return .handled
            }
            return .ignored
        }
        .onDeleteCommand {
            model.remove(ids: selection)
            selection.removeAll()
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        Button("Reveal in Finder") { reveal(ids: ids) }
        Button("Preview") {
            if let id = ids.first, let entry = model.entries.first(where: { $0.id == id }) {
                quickLookURL = entry.url
            }
        }
        Divider()
        Button("Remove Background") {
            model.removeBackground(entryIDs: ids)
        }
        Divider()
        Button("Revert to Original") {
            for id in ids { model.revert(entryID: id) }
        }
        Button("Remove from List") {
            model.remove(ids: ids)
            selection.subtract(ids)
        }
        Divider()
        Button("Copy Path") {
            let paths = model.entries.filter { ids.contains($0.id) }.map(\.url.path)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        }
    }

    private func reveal(ids: Set<UUID>) {
        let urls = model.entries.filter { ids.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func statusColor(_ status: AppModel.Entry.DisplayStatus) -> Color {
        switch status {
        case .failed: .red
        case .optimized: .green
        case .converted: .blue
        case .reverted: .orange
        default: .secondary
        }
    }
}

struct StatusIndicator: View {
    let status: AppModel.Entry.DisplayStatus

    var body: some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .optimized:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .converted:
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.blue)
        case .alreadyOptimal:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .reverted:
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
    }
}
