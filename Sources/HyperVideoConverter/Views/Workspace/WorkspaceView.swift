import SwiftUI

/// Centre of the window: the drop target while the list is empty, then the native list
/// of videos and jobs, with the finished banner above and the status footer below.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var model

    private var isEmpty: Bool { model.sources.isEmpty && model.activeJobs.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
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
            Divider()
            StatusFooter()
        }
        .overlay { DropHighlight(isTargeted: model.ui.isDropTargeted) }
        .background(.background)
    }

    /// The drop target, centred in the page (and scrollable in a short window).
    private var emptyState: some View {
        GeometryReader { proxy in
            ScrollView {
                DropZoneView(compact: false)
                    .frame(maxWidth: 520)
                    .padding(Spacing.xxl)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
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
        .padding(.horizontal, Spacing.l)
        .padding(.top, isEmpty && model.finishedBatch == nil ? 0 : Spacing.m)
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
