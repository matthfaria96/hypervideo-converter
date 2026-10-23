import SwiftUI

/// The conversion page: the drop target while the list is empty, then the native list
/// of videos and jobs, with the finished banner above and the Convert bar below.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var model

    private var isEmpty: Bool { model.sources.isEmpty && model.activeJobs.isEmpty }

    var body: some View {
        ZStack {
            if isEmpty {
                emptyState.motionTransition(.pop)
            } else {
                WorkListView().motionTransition(.content)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .motion(value: isEmpty)
        .safeAreaInset(edge: .top, spacing: 0) { topInset }
        .safeAreaInset(edge: .bottom, spacing: 0) { BottomBar() }
        .overlay { DropHighlight(isTargeted: model.ui.isDropTargeted) }
        .background(Theme.background)
    }

    private var emptyState: some View {
        ScrollView {
            DropZoneView(compact: false)
                .frame(maxWidth: 560)
                .padding(Spacing.xxl)
                .frame(maxWidth: .infinity)
        }
    }

    /// The finished banner and, once the list has items, the quiet "add more" strip.
    private var topInset: some View {
        VStack(spacing: Spacing.m) {
            if let batch = model.finishedBatch {
                FinishedBanner(count: batch.count, folder: batch.folder)
                    .motionTransition(.banner)
            }
            if !isEmpty {
                DropZoneView(compact: true)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, isEmpty && model.finishedBatch == nil ? 0 : Spacing.l)
        .motion(Motion.emphasized, value: model.finishedBatch?.count)
    }
}

/// A dashed accent frame over the page while files are dragged across the window.
private struct DropHighlight: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.l)
            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .background(Theme.accent.opacity(0.06), in: .rect(cornerRadius: Radius.l))
            .padding(Spacing.s)
            .opacity(isTargeted ? 1 : 0)
            .allowsHitTesting(false)
            .motion(Motion.quick, value: isTargeted)
    }
}
