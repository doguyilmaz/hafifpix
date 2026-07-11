import SwiftUI
import HafifPixCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            QualitySettingsView()
                .tabItem { Label(L("Quality"), systemImage: "dial.medium") }
            SpeedSettingsView()
                .tabItem { Label(L("Speed"), systemImage: "speedometer") }
            ExtrasSettingsView()
                .tabItem { Label(L("Extras"), systemImage: "wand.and.stars") }
            ToolsSettingsView()
                .tabItem { Label(L("Engines"), systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdaterModel.self) private var updater

    // Language codes must match the lproj folders. Names are endonyms on purpose:
    // a reader hunting for their language recognizes it in any UI language.
    private static let languages: [(code: String?, name: String)] = [
        (nil, ""), // placeholder; title resolved at render time (localized)
        ("en", "English"), ("tr", "Türkçe"), ("de", "Deutsch"), ("fr", "Français"),
        ("es", "Español"), ("ja", "日本語"), ("zh-Hans", "简体中文"),
    ]
    private static let launchLanguage: String? =
        UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first
    @State private var language: String? =
        UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first

    var body: some View {
        @Bindable var model = model
        @Bindable var updater = updater
        Form {
            Section(L("Language")) {
                Picker(L("Language"), selection: $language) {
                    ForEach(Self.languages, id: \.code) { option in
                        Text(option.code == nil ? L("System Default") : option.name)
                            .tag(option.code)
                    }
                }
                .labelsHidden()
                .onChange(of: language) { _, newValue in
                    if let newValue {
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    }
                }
                if language != Self.launchLanguage {
                    HStack {
                        Text(L("Takes effect after the app is relaunched."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Relaunch Now")) { relaunch() }
                    }
                }
            }

            Section(L("Updates")) {
                Toggle(L("Automatically check for updates"), isOn: $updater.automaticallyChecksForUpdates)
                Toggle(L("Automatically download and install updates"), isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)
            }

            Section(L("Metadata")) {
                Toggle(L("Strip PNG metadata"), isOn: $model.settings.stripPNGMetadata)
                Text(L("Gamma chunks, color profiles and optional chunks. Web browsers expect these removed."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(L("Strip JPEG metadata"), isOn: $model.settings.stripJPEGMetadata)
                Text(L("EXIF, GPS position, color profiles, rotation. Keep it if you rely on embedded copyright info."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Writing files")) {
                Toggle(L("Preserve file permissions and attributes"), isOn: $model.settings.preservePermissions)
                Toggle(L("Preserve file creation and modification dates"), isOn: $model.settings.preserveDates)
                Picker(L("Originals"), selection: $model.settings.backupMode) {
                    ForEach(OptimizationSettings.BackupMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(L("Regardless of this setting, every file can be reverted from the right-click menu while the app is open."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.4; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

private struct QualitySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(L("Enable lossy minification"), isOn: $model.settings.lossyEnabled)
                Text(L("Makes files much smaller, but may subtly change how images look."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Quality targets")) {
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
            Text(verbatim: label)
                .frame(width: 50, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            Text(verbatim: "\(value)%")
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
            Section(L("Optimization level")) {
                Picker(L("Level"), selection: $model.settings.level) {
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

            Section(L("Parallelism")) {
                Stepper(value: $model.settings.maxConcurrentJobs, in: 0...32) {
                    HStack {
                        Text(L("Simultaneous files"))
                        Spacer()
                        Text(model.settings.maxConcurrentJobs == 0
                             ? L("Auto (\(ProcessInfo.processInfo.activeProcessorCount) cores)")
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
        case .fast: L("Quick single-pass compression. Good for large batches.")
        case .normal: L("Balanced effort: the sweet spot for everyday use.")
        case .extra: L("Exhaustive compression trials. Noticeably slower on big images.")
        case .insane: L("Adds Zopfli deflate to PNGs. Can take minutes per image, saves the last few percent.")
        }
    }
}

private struct ExtrasSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section(L("Resize")) {
                Toggle(L("Fit images within a maximum size"), isOn: $model.settings.resizeEnabled)
                if model.settings.resizeEnabled {
                    HStack {
                        Text(L("Longest side"))
                        TextField(
                            L("Pixels"),
                            value: $model.settings.maxDimension,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        Text(verbatim: "px")
                            .foregroundStyle(.secondary)
                    }
                    Text(L("Larger images are downscaled before compression. Animations are resized too (GIF)."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("Convert to modern formats")) {
                Picker(L("Convert images to"), selection: $model.settings.convertTarget) {
                    ForEach(OptimizationSettings.ConvertTarget.allCases, id: \.self) { target in
                        if target != .avif || ImageIOCodec.supportsAVIFEncoding {
                            Text(target.displayName).tag(target)
                        }
                    }
                }
                if model.settings.convertTarget != .none {
                    QualitySlider(label: L("Quality"), value: $model.settings.convertQuality, range: 40...100)
                    Toggle(L("Move original to Trash when converted file is smaller"), isOn: $model.settings.convertRemovesOriginal)
                    Text(L("Converted files are written next to the original (photo.png → photo.\(model.settings.convertTarget.fileExtension ?? "")). SVGs are minified as usual."))
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
                Text(L("Engines"))
            } footer: {
                Text(L("Every engine's output is only kept when it is smaller and still decodes correctly. Disabling engines mainly trades savings for speed."))
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
