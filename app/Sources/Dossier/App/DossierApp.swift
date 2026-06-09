import SwiftUI

// Dossier — a native macOS editor for a `dossier` context.toml spec, with a
// live preview of the rendered prompt. WindowGroup lifecycle; the unit of work
// is a project folder, not a single document (DESKTOP_APP_SPEC §4).
@main
struct DossierApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ZoomableRoot()
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
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { model.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(!model.canZoomIn)
                Button("Zoom Out") { model.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!model.canZoomOut)
                Button("Actual Size") { model.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Applies the app's UI zoom uniformly to the whole window. Content lays out in
/// an inversely-scaled frame, then scales back up to fill — so ⌘+/⌘- show more
/// or less of the same layout at a larger or smaller size, rather than just
/// clipping it. Hit-testing and text editing follow the transform.
private struct ZoomableRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            ContentView()
                .frame(width: geo.size.width / model.zoom,
                       height: geo.size.height / model.zoom)
                .scaleEffect(model.zoom, anchor: .topLeading)
        }
    }
}
