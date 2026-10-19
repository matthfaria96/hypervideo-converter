import AppKit
import HyperVideoCore
import QuickLook
import SwiftUI

/// Videos being set up, then the jobs waiting or encoding. Click selects a row (⌘-click
/// adds to the selection), drag reorders, right-click shows more.
struct WorkListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Lazy: with hundreds of videos only the rows on screen are built.
        LazyVStack(spacing: 0) {
            if model.sources.isEmpty && model.activeJobs.isEmpty {
                Text("No videos added. Your files will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            }
            ForEach(model.sources) { source in
                rowContainer(id: source.id, isSelected: model.selectedIDs.contains(source.id)) {
                    SourceRowView(source: source, isSelected: model.selectedIDs.contains(source.id))
                }
                .onTapGesture { select(source.id) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(model.selectedIDs.contains(source.id) ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { select(source.id) }
                .contextMenu { SourceMenu(source: source) }
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                    model.moveSource(dragged, onto: source.id)
                    return true
                }
            }
            ForEach(model.activeJobs) { job in
                rowContainer(id: job.id, isSelected: false) { JobRowView(job: job) }
                    .accessibilityElement(children: .combine)
                    .contextMenu { JobMenu(job: job) }
                    .dropDestination(for: String.self) { items, _ in
                        guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                        model.queue.move(dragged, onto: job.id)
                        return true
                    }
            }
        }
        .clipShape(.rect(cornerRadius: 11))
        .card(fill: Color(hex: 0x202023), radius: 11)
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand { if !model.selectedIDs.isEmpty { model.removeSelectedSources() } }
        .onKeyPress(.space) {
            guard let url = model.selectedSource?.url, model.inspectsSelection else { return .ignored }
            model.ui.quickLookURL = url
            return .handled
        }
        .quickLookPreview(Bindable(model.ui).quickLookURL)
    }

    /// The row's frame. Only videos on the editing list can be selected; jobs can't, and
    /// are dragged by their own ID to reorder the queue.
    private func rowContainer<Content: View>(id: UUID, isSelected: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(isSelected ? Theme.selectedCard : .clear)
            .overlay(alignment: .bottom) { Color(hex: 0x333338).frame(height: 1) }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(Color(hex: 0xD9A33A), lineWidth: 1.5).padding(2)
                }
            }
            .contentShape(.rect)
            .draggable(id.uuidString)
    }

    private func select(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            model.selectedIDs.formSymmetricDifference([id])
        } else {
            model.selectedIDs = model.selectedIDs == [id] ? [] : [id]
        }
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
            model.section = .analyze
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
