import SwiftUI
import HafifPixCore

struct StatusBarView: View {
    @Environment(AppModel.self) private var model
    let selection: Set<UUID>
    // Keyed by entry id + byte size so re-optimized files recompute but
    // reselecting a file never flickers.
    @State private var dimensionsCache: [String: String] = [:]

    var body: some View {
        HStack(spacing: 10) {
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 20)

            selectionDetail

            if !ToolRegistry.missingTools.isEmpty {
                let count = ToolRegistry.missingTools.count
                Label("\(count) engine\(count == 1 ? "" : "s") unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Missing: \(ToolRegistry.missingTools.map(\.rawValue).joined(separator: ", "))")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var selectedEntries: [AppModel.Entry] {
        model.entries.filter { selection.contains($0.id) }
    }

    @ViewBuilder
    private var selectionDetail: some View {
        let selected = selectedEntries
        if selected.count == 1, let entry = selected.first {
            let cacheKey = "\(entry.id)-\(entry.currentBytes)"
            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                } label: {
                    Text((entry.url.path as NSString).abbreviatingWithTildeInPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                .frame(maxWidth: 380, alignment: .trailing)

                // Rightmost and never cleared, so it doesn't shift or flicker.
                if let dimensions = dimensionsCache[cacheKey] {
                    Text(dimensions)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
            .layoutPriority(1)
            .task(id: cacheKey) {
                guard dimensionsCache[cacheKey] == nil else { return }
                let url = entry.url
                let info = await Task.detached { ImageIOCodec.info(of: url) }.value
                if let info {
                    dimensionsCache[cacheKey] = "\(info.pixelWidth)×\(info.pixelHeight)"
                }
            }
        } else if selected.count > 1 {
            let total = selected.reduce(Int64(0)) { $0 + $1.currentBytes }
            Text("\(selected.count) files · \(Formatting.bytes(total))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
    }

    private var statusText: String {
        if model.isBusy {
            let remaining = model.activeJobs
            return "Optimizing… \(remaining) file\(remaining == 1 ? "" : "s") remaining"
        }
        if let totals = model.totals, totals.saved > 0 {
            let percent = Formatting.savings(original: totals.original, new: totals.original - totals.saved)
            return "Saved \(Formatting.bytes(totals.saved)) out of \(Formatting.bytes(totals.original)) (\(percent))"
        }
        // Files processed but nothing shrank: say that instead of leaving
        // the settings hint up. The hint belongs to the empty state only.
        let finished = model.entries.filter { status in
            if case .pending = status.status { return false }
            if case .running = status.status { return false }
            return true
        }
        if !finished.isEmpty {
            return "Already optimized (\(finished.count) file\(finished.count == 1 ? "" : "s"))"
        }
        return model.settings.summaryLine
    }
}
