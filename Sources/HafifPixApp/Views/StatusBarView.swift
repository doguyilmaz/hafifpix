import SwiftUI
import HafifPixCore

struct StatusBarView: View {
    @Environment(AppModel.self) private var model

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

            Spacer()

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

    private var statusText: String {
        if model.isBusy {
            let remaining = model.activeJobs
            return "Optimizing… \(remaining) file\(remaining == 1 ? "" : "s") remaining"
        }
        if let totals = model.totals, totals.saved > 0 {
            let percent = Formatting.savings(original: totals.original, new: totals.original - totals.saved)
            return "Saved \(Formatting.bytes(totals.saved)) out of \(Formatting.bytes(totals.original)) (\(percent))"
        }
        return model.settings.summaryLine
    }
}
