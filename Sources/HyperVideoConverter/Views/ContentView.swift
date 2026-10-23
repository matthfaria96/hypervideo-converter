import SwiftUI
import UniformTypeIdentifiers

/// The window, laid out like its sibling HyperImage: the video list in the centre with a
/// status footer, the settings panel on the right with the Convert box floating at its
/// foot, and the mode switch leading the toolbar. History, Favorites and Analyze open
/// from the footer as sheets.
///
/// Plain columns rather than NavigationSplitView/.inspector: on macOS 26 those leave an
/// empty "»" overflow item in the toolbar and re-layout the toolbar on narrow windows.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 0) {
            WorkspaceView()
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            // Always there: the settings are half of the job. Clipped as a last line of
            // defence, so a control wider than the column never spills over the list.
            SettingsColumn()
                .frame(width: 400)
                .clipped()
        }
        .navigationTitle(Text(model.mode.title))
        .toolbar(removing: .title)
        .toolbar { WindowToolbar() }
        .modifier(LaunchStateModifier())
        // AppKit focuses the first text field at launch; start with nothing focused.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.audiovisualContent, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.addSources(urls) } }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.presentedPage = nil
            Task { await model.addSources(urls) }
            return true
        } isTargeted: { model.ui.isDropTargeted = $0 }
        .sheet(item: $model.presentedPage) { PageSheet(page: $0) }
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
}

extension WorkMode {
    var title: LocalizedStringKey {
        switch self {
        case .convert: "Convert Videos"
        case .compress: "Compress Videos"
        case .upscale: "AI Upscale"
        }
    }

    var shortTitle: LocalizedStringKey {
        switch self {
        case .convert: "Convert"
        case .compress: "Compress"
        case .upscale: "AI Upscale"
        }
    }

    var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .upscale: "sparkles"
        }
    }
}

extension AppSection: Identifiable {
    var id: Self { self }
}

/// The right column: in Convert the eight HandBrake tabs (one video, or every target),
/// in Compress the everyday choices, in AI Upscale its panel — with the Convert box
/// floating in glass at the bottom.
private struct SettingsColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.settingsPanelKind {
            case .upscale:
                UpscalePanel().motionTransition(.content)
            case .simple:
                OutputInspector().motionTransition(.content)
            case .allVideos:
                AllVideosSettingsPanel().motionTransition(.content)
            case .oneVideo:
                if let source = model.panelSource {
                    VideoSettingsPanel(source: source)
                        .id(source.id)
                        .motionTransition(.content)
                }
            }
        }
        .motion(value: model.panelSource?.id)
        .motion(value: model.mode)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SummaryBox()
                .padding(Spacing.m + 2)
                .compatGlass(in: .rect(cornerRadius: Radius.xl))
                .padding(.horizontal, Spacing.m + 2)
                .padding(.bottom, Spacing.m)
                .padding(.top, Spacing.xs)
        }
        .background(.background.secondary)
    }
}

/// Mode switch leading (Finder style), then add and list actions.
/// Separate items, not a group: grouped items overflow into "»" on macOS 26.
private struct WindowToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Mode", selection: modeSelection) {
                ForEach([WorkMode.convert, .compress, .upscale], id: \.self) { mode in
                    Label(mode.shortTitle, systemImage: mode.symbol)
                        .labelStyle(.titleAndIcon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("⌘1 Convert · ⌘2 Compress · ⌘3 AI Upscale")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Choose Videos…", systemImage: "plus") { model.isImporting = true }
                .help("Choose Videos… (⌘O)")
        }
        ToolbarItem(placement: .primaryAction) { ListActionsMenu() }
    }

    private var modeSelection: Binding<WorkMode> {
        Binding(get: { model.mode }, set: { model.setMode($0) })
    }
}

/// "…" menu: selection and list actions.
private struct ListActionsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("List Actions", systemImage: "ellipsis") {
            Button(model.allSourcesSelected ? "Deselect All" : "Select All") { model.toggleSelectAll() }
                .disabled(model.sources.isEmpty)
            Button("Advanced Settings…", systemImage: "slider.horizontal.3") {
                model.ui.advancedSourceID = model.selectedSource?.id
            }
            .disabled(model.selectedSource?.info == nil)
            Divider()
            Button("Clear List", systemImage: "trash", role: .destructive) { model.ui.confirmingClearList = true }
                .disabled(!model.canClearList)
        }
        .menuIndicator(.hidden)
        .help("List actions")
    }
}

/// History, Favorites or Analyze over the workspace, with a title bar and Done.
private struct PageSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let page: AppSection

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(page.title, systemImage: page.symbol).font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .compatGlassProminentButtonStyle()
            }
            .padding(Spacing.l)
            Divider()
            content
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 640)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .history: HistoryView()
        case .favorites: FavoritesView()
        case .analyze: AnalyzeView()
        case .conversion: EmptyView()
        }
    }
}
