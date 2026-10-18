import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            // Report a small ideal width to the split view. If the detail's ideal width
            // is wider than the space left between sidebar and inspector, AppKit's
            // split view loops on constraint updates until it throws.
            detail
                .frame(minWidth: 0, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .inspector(isPresented: $model.showsPresetInspector) {
            PresetInspector()
                .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
        }
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.audiovisualContent, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addSources(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addSources(urls)
            return true
        } isTargeted: { model.ui.isDropTargeted = $0 }
        .overlay { if model.ui.isDropTargeted { DropHighlight() } }
        .alert("HyperVideo Converter", isPresented: .constant(model.alertMessage != nil)) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .queue:
            QueueView()
        case .source:
            if let source = model.selectedSource {
                SourceDetailView(sourceID: source.id)
            } else {
                EmptyStateView()
            }
        case nil:
            EmptyStateView()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Open Video", systemImage: "plus") { model.isImporting = true }
                .help("Open video files (⌘O)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Add to Queue", systemImage: "text.badge.plus") {
                if let id = model.selectedSource?.id { model.enqueue([id]) }
            }
            .disabled(model.selectedSource?.info == nil)
            .help("Add the selected video to the queue (⌘B)")

            if model.queue.isProcessing {
                Button("Pause", systemImage: "pause.fill") { model.queue.pause() }
                    .help("Finish running jobs, then pause")
            } else {
                Button("Start", systemImage: "play.fill") {
                    if model.queue.pendingCount == 0, let id = model.selectedSource?.id {
                        model.encodeNow(id)
                    } else {
                        model.queue.start()
                    }
                }
                .disabled(model.queue.pendingCount == 0 && model.selectedSource?.info == nil)
                .help("Start encoding (⌘R)")
            }
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button("Presets", systemImage: "square.stack.3d.up") { model.showsPresetInspector.toggle() }
                .help("Show or hide presets (⌥⌘I)")
        }
    }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            .padding(12)
            .overlay {
                Label("Drop to add", systemImage: "arrow.down.circle.fill")
                    .font(.title2.bold())
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.3)), in: .capsule)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
