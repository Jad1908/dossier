import SwiftUI

// Empty / blocking states (DESKTOP_APP_SPEC §10). The empty state is the one
// place the display type and a faint accent-soft wash appear (DESIGN.md).

/// No project folder open.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.Colors.accentText)
            Text("Dossier")
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Colors.ink)
            Text("Open a project folder to build its context.toml prompt.")
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.mute)
                .multilineTextAlignment(.center)
            Button("Open Folder…") { model.presentOpenPanel() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Theme.Spacing.sm)

            if !model.recentProjectURLs.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("RECENT")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.mute)
                    ForEach(model.recentProjectURLs.prefix(5), id: \.self) { url in
                        Button {
                            model.openProject(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "clock")
                                .font(Theme.Typography.bodyMd)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Colors.accentText)
                    }
                }
                .padding(.top, Theme.Spacing.md)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Theme.Colors.accentSoft.opacity(0.5)
                .frame(maxWidth: 520, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        )
    }
}

/// The `dossier` binary could not be located (DESKTOP_APP_SPEC §10).
struct MissingEngineView: View {
    @State private var path = Defaults.enginePathOverride ?? ""

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.Colors.warning)
            Text("dossier not found")
                .font(Theme.Typography.headingLg)
                .foregroundStyle(Theme.Colors.ink)
            Text("Dossier needs the `dossier` command-line tool on your PATH. "
                 + "Install it (uv tool install …) or point to it manually below.")
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.mute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            HStack(spacing: Theme.Spacing.sm) {
                TextField("/path/to/dossier", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                Button("Browse…") { browse() }
                    .buttonStyle(TertiaryButtonStyle())
            }
            Button("Use This Path") {
                // Broadcast: every window's model re-resolves, not just this one's.
                AppModel.setEngineOverride(path.isEmpty ? nil : path)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}

/// The folder is open but the selected spec doesn't exist yet (§10).
struct NoSpecView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Colors.accentText)
            Text("No \(model.currentSpec.fileName) yet")
                .font(Theme.Typography.headingMd)
                .foregroundStyle(Theme.Colors.ink)
            Text("Create a starter spec to begin building a prompt.")
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.mute)
            Button("Create Spec") { model.createCurrentSpec() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
