import AppKit
import HyperVideoCore
import QuickLook
import SwiftUI

/// Videos being set up, then the jobs waiting or encoding, in a native list: click
/// selects (⌘-click adds), drag reorders, right-click shows more, Space previews.
struct WorkListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.listSelection) {
            Section {
                ForEach(model.sources) { source in
                    SourceRowView(source: source, isSelected: model.selectedIDs.contains(source.id))
                        .tag(source.id)
                        .contextMenu { SourceMenu(source: source) }
                        .motionTransition(.row)
                }
                .onMove { model.moveSources(fromOffsets: $0, toOffset: $1) }
            } header: {
                listHeader
            }

            if !model.activeJobs.isEmpty {
                Section {
                    ForEach(model.activeJobs) { job in
                        JobRowView(job: job)
                            .selectionDisabled()
                            .contextMenu { JobMenu(job: job) }
                            .motionTransition(.row)
                    }
                    .onMove { model.queue.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Queue")
                }
            }
        }
        .listStyle(.inset)
        .motion(value: model.sources.map(\.id))
        .motion(value: model.activeJobs.map(\.id))
        .onDeleteCommand { if !model.selectedIDs.isEmpty { model.removeSelectedSources() } }
        .onKeyPress(.space) {
            guard let url = model.selectedSource?.url, model.inspectsSelection else { return .ignored }
            model.ui.quickLookURL = url
            return .handled
        }
        .quickLookPreview(Bindable(model.ui).quickLookURL)
    }

    private var listHeader: some View {
        @Bindable var ui = model.ui
        return HStack(spacing: Spacing.s) {
            Text("Video List")
            Text(verbatim: "(\(model.sources.count))")
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
            if !model.sources.isEmpty {
                Button(model.allSourcesSelected ? "Deselect All" : "Select All") { model.toggleSelectAll() }
                    .keyboardShortcut("a")
                    .help("Select every video to edit them together (⌘A)")
            }
            Button("Clear List") { ui.confirmingClearList = true }
                .disabled(!model.canClearList)
                .help("Removes the videos from the list; the original files stay on your Mac")
                .confirmationDialog("Clear the video list?", isPresented: $ui.confirmingClearList) {
                    Button("Clear List", role: .destructive) { model.clearWorkspace() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(verbatim: model.clearListMessage)
                }
        }
        .buttonStyle(.accessoryBar)
        .controlSize(.small)
        .textCase(nil)
    }
}

private struct SourceMenu: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem

    var body: some View {
        Button("Advanced Settings…", systemImage: "slider.horizontal.3") { model.ui.advancedSourceID = source.id }
            .disabled(source.info == nil)
        Button("Analyze Video", systemImage: "magnifyingglass") {
            model.selectedIDs = [source.id]
            model.presentedPage = .analyze
        }
        Divider()
        Button("Move to Top", systemImage: "arrow.up.to.line") { model.moveSource(source.id, .top) }
            .disabled(!model.canMoveSource(source.id, .top))
        Button("Move Up", systemImage: "arrow.up") { model.moveSource(source.id, .up) }
            .disabled(!model.canMoveSource(source.id, .up))
        Button("Move Down", systemImage: "arrow.down") { model.moveSource(source.id, .down) }
            .disabled(!model.canMoveSource(source.id, .down))
        Divider()
        Button("Add to Queue", systemImage: "text.badge.plus") { model.enqueue([source.id]) }
            .disabled(source.info == nil)
        Button("Quick Look", systemImage: "eye") { model.ui.quickLookURL = source.url }
        Button("Show in Finder", systemImage: "folder") { SystemIntegration.reveal([source.url]) }
        Divider()
        Button("Remove", systemImage: "trash", role: .destructive) { model.removeSource(source.id) }
    }
}

/// Pending jobs start from the top, so moving one up gives it priority.
private struct JobMenu: View {
    @Environment(AppModel.self) private var model
    let job: EncodeJob

    var body: some View {
        let queue = model.queue
        Button("Move to Top", systemImage: "arrow.up.to.line") { queue.move(job.id, .top) }
            .disabled(!queue.canMove(job.id, .top))
        Button("Move Up", systemImage: "arrow.up") { queue.move(job.id, .up) }
            .disabled(!queue.canMove(job.id, .up))
        Button("Move Down", systemImage: "arrow.down") { queue.move(job.id, .down) }
            .disabled(!queue.canMove(job.id, .down))
        Divider()
        Button("Edit Settings", systemImage: "slider.horizontal.3") { model.editJob(job.id) }
            .disabled(job.state != .queued)
        Button("Show Source in Finder", systemImage: "folder") { SystemIntegration.reveal([job.source]) }
        Divider()
        Button("Cancel", systemImage: "xmark", role: .destructive) { queue.cancel(job.id) }
    }
}
