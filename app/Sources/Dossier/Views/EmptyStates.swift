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
                 + "Install it by running:")
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.mute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Text(verbatim: "uv tool install git+https://github.com/Jad1908/dossier.git")
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Colors.ink)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Colors.accentSoft.opacity(0.5))
                )
            Text("…or point to an existing binary manually below.")
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.mute)

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

/// The folder is open but holds no spec at all. Blocks the entire window —
/// ContentView never mounts the three-pane project view while this shows, so
/// explorer adds, drops, and shortcuts simply don't exist yet. Creating a spec
/// is the only way forward.
struct CreateSpecGateView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.Colors.accentText)
            Text("No spec in \(model.projectURL?.lastPathComponent ?? "this folder") yet")
                .font(Theme.Typography.headingLg)
                .foregroundStyle(Theme.Colors.ink)
            Text("Dossier builds prompts from a context.toml spec. "
                 + "Create one to start working in this folder.")
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.mute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Spec name (blank = default context.toml)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(create)
                Button("Create Spec", action: create)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Theme.Colors.accentSoft.opacity(0.5)
                .frame(maxWidth: 520, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        )
    }

    private func create() {
        // No name-taken check: the gate only shows while the folder has no
        // spec at all, so any target file is necessarily free.
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        model.createSpec(named: trimmed.isEmpty ? nil : trimmed)
        name = ""
    }
}

/// The folder is open but the selected spec doesn't exist yet (§10). With the
/// create gate above, this is only reachable transiently — e.g. the current
/// spec's file vanished on disk an instant before the watcher falls back.
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
