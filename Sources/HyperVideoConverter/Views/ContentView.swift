import SwiftUI
import UniformTypeIdentifiers

/// Sidebar, page and (on the conversion page) the output inspector, side by side.
/// Plain stacks with fixed side widths instead of a split view: the centre takes what
/// is left and never feeds an ideal width back into AppKit's split-view layout.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 0) {
            SidebarView()
                .frame(width: model.ui.isSidebarCollapsed ? 64 : 220)
            Theme.separator.frame(width: 1)
            page
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            if model.section == .conversion {
                Theme.separator.frame(width: 1)
                if let source = model.panelSource {
                    VideoSettingsPanel(source: source).frame(width: 460)
                } else {
                    OutputInspector().frame(width: 310)
                }
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .animation(.smooth(duration: 0.2), value: model.ui.isSidebarCollapsed)
        .animation(.smooth(duration: 0.2), value: model.panelSource?.id)
        .toolbar { WindowToolbar() }
        .toolbar(removing: .title)
        .toolbarBackground(Color(hex: 0x202023), for: .windowToolbar)
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

    private var advancedIsShown: Binding<Bool> {
        Binding(get: { model.ui.advancedSourceID != nil }, set: { if !$0 { model.ui.advancedSourceID = nil } })
    }

    @ViewBuilder
    private var page: some View {
        switch model.section {
        case .conversion: WorkspaceView()
        case .history: HistoryView()
        case .favorites: FavoritesView()
        case .analyze: AnalyzeView()
        }
    }
}

/// Brand on the left; status and settings on the right.
private struct WindowToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                Text(verbatim: "HyperVideo Converter").font(.system(size: 14, weight: .bold))
                Text("BETA").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 6)
        }
        .compatHiddenSharedBackground()

        ToolbarItem(placement: .primaryAction) {
            Text(model.statusText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
                .padding(.horizontal, 8)
        }
        .compatHiddenSharedBackground()

        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings (⌘,)")
        }
    }
}
