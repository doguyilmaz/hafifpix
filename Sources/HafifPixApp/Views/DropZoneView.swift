import SwiftUI

struct DropZoneView: View {
    let isTargeted: Bool
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2.5, dash: [10, 6])
                    )
                    .frame(width: 180, height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                    )

                Image(systemName: "arrow.down")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .animation(.easeInOut(duration: 0.15), value: isTargeted)

            VStack(spacing: 6) {
                Text("Drop images or folders here")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("PNG · JPEG · GIF · SVG · WebP")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            Button("Browse…", action: onBrowse)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
