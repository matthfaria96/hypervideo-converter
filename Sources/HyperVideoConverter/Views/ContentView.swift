import SwiftUI
import UniformTypeIdentifiers

/// The window: a native split view with the sidebar, the page and, on the conversion
/// page, the inspector column. The system draws the toolbar, sidebar and inspector
/// materials (Liquid Glass on macOS 26+).
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var ui = model.ui

        NavigationSplitView(columnVisibility: $ui.sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            pages
                .navigationTitle(pageTitle)
                .navigationSubtitle(model.section == .conversion ? model.statusText : "")
                .inspector(isPresented: inspectorIsShown) {
                    InspectorColumn()
                        .inspectorColumnWidth(min: 320, ideal: 400, max: 600)
                }
                .toolbar { WindowToolbar() }
        }
        .navigationSplitViewStyle(.balanced)
        .modifier(LaunchStateModifier())
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.audiovisualContent, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.addSources(urls) } }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.section = .conversion
            Task { await model.addSources(urls) }
            return true
        } isTargeted: { model.ui.isDropTargeted = $0 }
        .sheet(item: $model.pendingFolderImport) { FolderImportSheet(pending: $0) }
        .sheet(isPresented: advancedIsShown) { AdvancedSettingsSheet() }
        .alert(Text(verbatim: model.alertTitle ?? String(localized: "Something went wrong")),
               isPresented: .constant(model.alertMessage != nil)) {
            Button("OK") { model.alertMessage = nil; model.alertTitle = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var inspectorIsShown: Binding<Bool> {
        Binding(get: { model.section == .conversion && model.ui.isInspectorShown },
                set: { model.ui.isInspectorShown = $0 })
    }

    private var advancedIsShown: Binding<Bool> {
        Binding(get: { model.ui.advancedSourceID != nil }, set: { if !$0 { model.ui.advancedSourceID = nil } })
    }

    private var pageTitle: LocalizedStringKey {
        switch model.section {
        case .conversion: model.mode == .compress ? "Compress Videos" : "Convert Videos"
        case .history: "History"
        case .favorites: "Favorites"
        case .analyze: "Analyze Video"
        }
    }

    /// One page at a time, crossfading between them.
    private var pages: some View {
        ZStack {
            switch model.section {
            case .conversion: WorkspaceView().motionTransition(.content)
            case .history: HistoryView().motionTransition(.content)
            case .favorites: FavoritesView().motionTransition(.content)
            case .analyze: AnalyzeView().motionTransition(.content)
            }
        }
        .motion(value: model.section)
    }
}

/// Add Videos, the Convert | Compress switch and the inspector toggle.
private struct WindowToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        if model.section == .conversion {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: modeSelection) {
                    Text("Convert").tag(WorkMode.convert)
                    Text("Compress").tag(WorkMode.compress)
                }
                .pickerStyle(.segmented)
                .help("Convert changes the format; Compress reduces the size")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.section = .conversion
                model.isImporting = true
            } label: {
                Label("Choose Videos…", systemImage: "plus")
            }
            .help("Choose Videos… (⌘O)")
            if model.section == .conversion {
                Button {
                    model.ui.isInspectorShown.toggle()
                } label: {
                    Label("Output Settings", systemImage: "sidebar.trailing")
                }
                .help(model.ui.isInspectorShown ? "Hide the output settings (⌥⌘I)" : "Show the output settings (⌥⌘I)")
            }
        }
    }

    private var modeSelection: Binding<WorkMode> {
        Binding(get: { model.mode }, set: { model.setMode($0) })
    }
}
