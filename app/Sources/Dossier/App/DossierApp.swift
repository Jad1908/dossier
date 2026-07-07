import SwiftUI

// Dossier — a native macOS editor for a `dossier` context.toml spec, with a
// live preview of the rendered prompt. WindowGroup lifecycle; the unit of work
// is a project folder, not a single document (DESKTOP_APP_SPEC §4).
@main
struct DossierApp: App {
    var body: some Scene {
        WindowGroup {
            WindowRoot()
        }
        .windowToolbarStyle(.unified)
        .commands { DossierCommands() }

        Settings {
            SettingsView()
        }
    }
}

/// One window's content. Each window owns its own AppModel, so ⌘N opens an
/// independent window that can hold a different project. The model is published
/// as a focused scene value so the menu-bar commands always act on the key
/// window's model, not on whichever window happened to be created first.
private struct WindowRoot: View {
    @State private var model = AppModel()

    var body: some View {
        ContentView()
            .environment(model)
            .focusedSceneValue(\.appModel, model)
            .frame(minWidth: 960, minHeight: 600)
    }
}

/// The key window's AppModel, for menu-bar commands. Nil while no Dossier
/// window is key (e.g. only Settings is open) — commands disable themselves.
struct AppModelFocusedKey: FocusedValueKey {
    typealias Value = AppModel
}

extension FocusedValues {
    var appModel: AppModel? {
        get { self[AppModelFocusedKey.self] }
        set { self[AppModelFocusedKey.self] = newValue }
    }
}

/// Menu-bar commands. `.newItem` is no longer replaced, so the system's
/// "New Window" (⌘N) is back and each press opens a fresh, independent window.
private struct DossierCommands: Commands {
    @FocusedValue(\.appModel) private var model

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") { model?.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model == nil)
        }
        CommandGroup(after: .saveItem) {
            Button("Copy Prompt") { model?.copyPrompt() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model?.canOutput != true)
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { model?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(model?.canZoomIn != true)
            Button("Zoom Out") { model?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model?.canZoomOut != true)
            Button("Actual Size") { model?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(model == nil)
            Divider()
        }
    }
}
