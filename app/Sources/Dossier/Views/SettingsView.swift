import SwiftUI

// Settings (DESKTOP_APP_SPEC §6, §10): the path to the `dossier` binary,
// auto-detected and overridable.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var path = Defaults.enginePathOverride ?? ""

    var body: some View {
        Form {
            Section("Engine") {
                SettingsRow(label: "dossier binary") {
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("auto-detected", text: $path)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                        Button("Browse…") { browse() }
                            .buttonStyle(TertiaryButtonStyle())
                    }
                }
                SettingsRow(label: "Status") {
                    if let engine = model.engine {
                        Label(engine.binaryURL.path, systemImage: "checkmark.circle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.success)
                    } else {
                        Label("not found", systemImage: "xmark.circle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.error)
                    }
                }
                HStack {
                    Spacer()
                    Button("Apply") {
                        model.enginePathOverride = path.isEmpty ? nil : path
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 480, height: 200)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}

/// A settings line item (DESIGN.md §settings-row).
struct SettingsRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.body)
            Spacer()
            control()
        }
    }
}
