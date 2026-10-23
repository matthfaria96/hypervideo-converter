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
        @Bindable var ui = model.ui
        List(selection: $model.listSelection) {
            if model.showsVideoListHeader {
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
            }

            if !model.activeJobs.isEmpty {
                Section {
                    ForEach(model.activeJobs) { job in
                        JobRowView(job: job)
                            .task(id: job.source) { await model.loadQueueThumbnail(for: job) }
                            .selectionDisabled()
                            .contextMenu { JobMenu(job: job) }
                            .motionTransition(.row)
                    }
                    .onMove { model.queue.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "list.bullet.rectangle").foregroundStyle(.secondary)
                        Text("Queue")
                        Text(verbatim: "(\(model.activeJobs.count))").foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .listStyle(.inset)
        // On the list, not the header: the toolbar's Clear List works when only the queue shows.
        .confirmationDialog("Clear the video list?", isPresented: $ui.confirmingClearList) {
            Button("Clear List", role: .destructive) { model.clearWorkspace() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: model.clearListMessage)
        }
        .motion(value: model.showsVideoListHeader)
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

    /// Title and count only: selecting is the Mac's ⌘A on the list, clearing lives in
    /// the toolbar's "…" menu.
    private var listHeader: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "film.stack").foregroundStyle(.secondary)
            Text("Video List")
            Text(verbatim: "(\(model.sources.count))")
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
        }
        .textCase(nil)
    }
}

private struct SourceMenu: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem

    var body: some View {
        Button("Analyze Video", systemImage: "info.circle") {
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
