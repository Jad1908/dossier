import SwiftUI

// The single main window. Three-pane NavigationSplitView when a project is open
// (DESKTOP_APP_SPEC §6, DESIGN.md §Layout): explorer · builder · preview.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showPreview = true
    @State private var showPromptLibrary = false

    var body: some View {
        Group {
            if model.engineMissing {
                MissingEngineView()
            } else if !model.hasProject {
                WelcomeView()
            } else {
                projectView
            }
        }
        .background(Theme.Colors.canvas)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showPromptLibrary) {
            PromptLibraryView().environment(model)
        }
    }

    // MARK: - Three-pane project view

    private var projectView: some View {
        NavigationSplitView {
            FileExplorerView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } content: {
            BuilderView(showPromptLibrary: $showPromptLibrary)
                .navigationSplitViewColumnWidth(min: 320, ideal: 440)
        } detail: {
            if showPreview {
                PreviewView()
                    .navigationSplitViewColumnWidth(min: 320, ideal: 440)
            } else {
                Color.clear.frame(width: 0)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Toolbar (DESIGN.md §toolbar)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ProjectMenu()
        }
        if model.hasProject {
            ToolbarItem(placement: .principal) {
                SpecSwitcher()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let status = model.transientStatus {
                    StatusBadge(tone: .success, text: status)
                }
                Button("Save…") { model.savePrompt() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.canOutput)
                Button("Copy") { model.copyPrompt() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canOutput)
                Button {
                    withAnimation { showPreview.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle preview")
            }
        }
    }
}

// MARK: - Project folder menu (toolbar, left)

private struct ProjectMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button("Open Folder…") { model.presentOpenPanel() }
            if !model.recentProjectURLs.isEmpty {
                Divider()
                Section("Recent") {
                    ForEach(model.recentProjectURLs, id: \.self) { url in
                        Button(url.lastPathComponent) { model.openProject(url) }
                    }
                }
            }
        } label: {
            Label(model.projectURL?.lastPathComponent ?? "Open Folder",
                  systemImage: "folder")
        }
    }
}

// MARK: - Spec switcher (toolbar, center)

private struct SpecSwitcher: View {
    @Environment(AppModel.self) private var model
    @State private var creatingName = ""
    @State private var showCreate = false

    var body: some View {
        Menu {
            ForEach(model.availableSpecs) { ref in
                Button {
                    model.switchSpec(to: ref)
                } label: {
                    if ref == model.currentSpec {
                        Label(ref.displayName, systemImage: "checkmark")
                    } else {
                        Text(ref.displayName)
                    }
                }
            }
            Divider()
            Button("New Spec…") { showCreate = true }
        } label: {
            Label(model.currentSpec.displayName, systemImage: "doc.text")
        }
        .popover(isPresented: $showCreate) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("New spec name").font(Theme.Typography.headingSm)
                    .foregroundStyle(Theme.Colors.ink)
                Text("Leave blank for the default context.toml.")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.mute)
                TextField("name", text: $creatingName)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                HStack {
                    Spacer()
                    Button("Cancel") { showCreate = false }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Create") {
                        model.createSpec(named: creatingName.isEmpty ? nil : creatingName)
                        creatingName = ""
                        showCreate = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }
}
