import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Folder access and output (DESKTOP_APP_SPEC §9): NSOpenPanel to pick a project,
// NSPasteboard for Copy, NSSavePanel for Save. The app does its own clipboard
// handling and never relies on the engine's --copy.
extension AppModel {

    /// Choose a project folder.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a project folder"
        if panel.runModal() == .OK, let url = panel.url {
            openProject(url)
        }
    }

    /// Copy the full materialized prompt (everything inlined) to the clipboard.
    func copyPrompt() {
        guard let prompt = materializedPrompt, !prompt.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
        flashStatus("Copied")
    }

    /// Save the full materialized prompt to a file via NSSavePanel.
    func savePrompt() {
        guard let prompt = materializedPrompt, !prompt.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(currentSpec.displayName)-prompt.txt"
        panel.prompt = "Save"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try prompt.write(to: url, atomically: true, encoding: .utf8)
                flashStatus("Saved")
            } catch {
                flashStatus("Save failed")
            }
        }
    }
}
