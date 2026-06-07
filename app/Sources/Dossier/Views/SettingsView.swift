import SwiftUI

// The Settings window (⌘,). A real, multi-tab macOS preferences window
// (DESKTOP_APP_SPEC §6, §10): General, Engine, Preview, and About. macOS renders
// a TabView with `.tabItem` as the standard toolbar-tabbed settings window.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            EngineSettings()
                .tabItem { Label("Engine", systemImage: "terminal") }
            PreviewSettings()
                .tabItem { Label("Preview", systemImage: "sidebar.right") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(Defaults.Key.appearance) private var appearance = "system"
    @AppStorage(Defaults.Key.reopenLastProject) private var reopenLast = true

    var body: some View {
        SettingsForm {
            SettingsGroup("Appearance") {
                SettingsRow(label: "Theme",
                            help: "Dossier ships light and dark as equal modes.") {
                    Picker("", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            SettingsGroup("Startup") {
                SettingsRow(label: "Reopen last project on launch") {
                    Toggle("", isOn: $reopenLast).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}

// MARK: - Engine

private struct EngineSettings: View {
    @Environment(AppModel.self) private var model
    @State private var path = Defaults.enginePathOverride ?? ""

    var body: some View {
        SettingsForm {
            SettingsGroup("dossier binary") {
                Text("Dossier shells out to the `dossier` CLI for every preview. "
                     + "It is auto-detected on your PATH; override the location here "
                     + "if needed.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.mute)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsRow(label: "Path") {
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("auto-detected", text: $path)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                        Button("Browse…") { browse() }
                            .buttonStyle(TertiaryButtonStyle())
                    }
                }

                SettingsRow(label: "Status") {
                    if let engine = model.engine {
                        Label(engine.binaryURL.path, systemImage: "checkmark.circle.fill")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.success)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Label("not found", systemImage: "xmark.circle.fill")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.error)
                    }
                }

                HStack {
                    Spacer()
                    Button("Re-detect") {
                        model.enginePathOverride = nil
                        path = ""
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Apply") {
                        model.enginePathOverride = path.isEmpty ? nil : path
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}

// MARK: - Preview

private struct PreviewSettings: View {
    @AppStorage(Defaults.Key.defaultPreviewMode) private var defaultMode = "outline"

    var body: some View {
        SettingsForm {
            SettingsGroup("Default view") {
                SettingsRow(label: "Preview opens in",
                            help: "Outline collapses file bodies; Full prompt shows "
                                + "the materialized text Copy/Save emit.") {
                    Picker("", selection: $defaultMode) {
                        Text("Outline").tag("outline")
                        Text("Full prompt").tag("full")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                Text("Applies to newly opened windows.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.mute)
            }
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    @Environment(AppModel.self) private var model

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v ?? "1.0"
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.Colors.accentText)
            Text("Dossier")
                .font(Theme.Typography.headingLg)
                .foregroundStyle(Theme.Colors.ink)
            Text("Version \(version)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
            Text("A native editor for a dossier context.toml, with a live preview "
                 + "of the rendered prompt. Rendering stays in the engine.")
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let engine = model.engine {
                Text(engine.binaryURL.path)
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Colors.mute)
                    .textSelection(.enabled)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings building blocks (DESIGN.md §settings-row)

/// A scrollable, padded container for a settings tab's groups.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                content()
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled group of settings rows.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                content()
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceTile(fill: Theme.Colors.surface, radius: Theme.Radius.lg)
        }
    }
}

/// A settings line item: label (with optional help) left, control right.
struct SettingsRow<Control: View>: View {
    let label: String
    var help: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(Theme.Colors.body)
                if let help {
                    Text(help)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.lg)
            control()
        }
    }
}
