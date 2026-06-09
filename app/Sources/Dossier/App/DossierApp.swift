import SwiftUI

// Dossier — a native macOS editor for a `dossier` context.toml spec, with a
// live preview of the rendered prompt. WindowGroup lifecycle; the unit of work
// is a project folder, not a single document (DESKTOP_APP_SPEC §4).
@main
struct DossierApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") { model.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Copy Prompt") { model.copyPrompt() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!model.canOutput)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
