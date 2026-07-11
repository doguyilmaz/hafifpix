import SwiftUI
import HafifPixCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            QualitySettingsView()
                .tabItem { Label("Quality", systemImage: "dial.medium") }
            SpeedSettingsView()
                .tabItem { Label("Speed", systemImage: "speedometer") }
            ExtrasSettingsView()
                .tabItem { Label("Extras", systemImage: "wand.and.stars") }
            ToolsSettingsView()
                .tabItem { Label("Engines", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Metadata") {
                Toggle("Strip PNG metadata", isOn: $model.settings.stripPNGMetadata)
                Text("Gamma chunks, color profiles and optional chunks. Web browsers expect these removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Strip JPEG metadata", isOn: $model.settings.stripJPEGMetadata)
                Text("EXIF, GPS position, color profiles, rotation. Keep it if you rely on embedded copyright info.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Writing files") {
                Toggle("Preserve file permissions and attributes", isOn: $model.settings.preservePermissions)
                Toggle("Preserve file creation and modification dates", isOn: $model.settings.preserveDates)
                Picker("Originals", selection: $model.settings.backupMode) {
                    ForEach(OptimizationSettings.BackupMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("Regardless of this setting, every file can be reverted from the right-click menu while the app is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct QualitySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Enable lossy minification", isOn: $model.settings.lossyEnabled)
                Text("Makes files much smaller, but may subtly change how images look.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quality targets") {
                QualitySlider(label: "JPEG", value: $model.settings.jpegQuality, range: 50...99)
                QualitySlider(label: "PNG", value: $model.settings.pngQuality, range: 40...100)
                QualitySlider(label: "GIF", value: $model.settings.gifQuality, range: 40...100)
                QualitySlider(label: "WebP", value: $model.settings.webpQuality, range: 40...100)
            }
            .disabled(!model.settings.lossyEnabled)
        }
        .formStyle(.grouped)
    }
}

private struct QualitySlider: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 50, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            Text("\(value)%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SpeedSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Optimization level") {
                Picker("Level", selection: $model.settings.level) {
                    ForEach(OptimizationSettings.Level.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(levelDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Parallelism") {
                Stepper(value: $model.settings.maxConcurrentJobs, in: 0...32) {
                    HStack {
                        Text("Simultaneous files")
                        Spacer()
                        Text(model.settings.maxConcurrentJobs == 0
                             ? "Auto (\(ProcessInfo.processInfo.activeProcessorCount) cores)"
                             : "\(model.settings.maxConcurrentJobs)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var levelDescription: String {
        switch model.settings.level {
        case .fast: "Quick single-pass compression. Good for large batches."
        case .normal: "Balanced effort — the sweet spot for everyday use."
        case .extra: "Exhaustive compression trials. Noticeably slower on big images."
        case .insane: "Adds Zopfli deflate to PNGs. Can take minutes per image, saves the last few percent."
        }
    }
}

private struct ExtrasSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Resize") {
                Toggle("Fit images within a maximum size", isOn: $model.settings.resizeEnabled)
                if model.settings.resizeEnabled {
                    HStack {
                        Text("Longest side")
                        TextField(
                            "Pixels",
                            value: $model.settings.maxDimension,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        Text("px")
                            .foregroundStyle(.secondary)
                    }
                    Text("Larger images are downscaled before compression. Animations are resized too (GIF).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Convert to modern formats") {
                Picker("Convert images to", selection: $model.settings.convertTarget) {
                    ForEach(OptimizationSettings.ConvertTarget.allCases, id: \.self) { target in
                        if target != .avif || ImageIOCodec.supportsAVIFEncoding {
                            Text(target.displayName).tag(target)
                        }
                    }
                }
                if model.settings.convertTarget != .none {
                    QualitySlider(label: "Quality", value: $model.settings.convertQuality, range: 40...100)
                    Toggle("Move original to Trash when converted file is smaller", isOn: $model.settings.convertRemovesOriginal)
                    Text("Converted files are written next to the original (photo.png → photo.\(model.settings.convertTarget.fileExtension ?? "")). SVGs are minified as usual.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ToolsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ForEach(OptimizationSettings.ToolID.allCases, id: \.self) { tool in
                    Toggle(tool.displayName, isOn: toolBinding(tool, model: model))
                }
            } header: {
                Text("Engines")
            } footer: {
                Text("Every engine's output is only kept when it is smaller and still decodes correctly — disabling engines mainly trades savings for speed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func toolBinding(_ tool: OptimizationSettings.ToolID, model: AppModel) -> Binding<Bool> {
        Binding(
            get: { model.settings.isEnabled(tool) },
            set: { enabled in
                if enabled {
                    model.settings.disabledTools.remove(tool)
                } else {
                    model.settings.disabledTools.insert(tool)
                }
            }
        )
    }
}
