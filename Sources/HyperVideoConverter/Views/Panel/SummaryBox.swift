import SwiftUI

/// The floating box at the foot of the settings panel: where files go, the run's
/// progress and the Convert / Stop buttons (HyperImage's summary box).
struct SummaryBox: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.progress
        let showsProgress = progress.isActive || model.queue.isProcessing && progress.total > 0
        VStack(alignment: .leading, spacing: Spacing.m) {
            destination
            if showsProgress {
                ProgressRow(progress: progress).motionTransition(.banner)
            }
            HStack(spacing: Spacing.s) {
                convertButton
                if model.queue.runningCount > 0 || model.queue.isProcessing {
                    Button {
                        model.queue.cancelAll()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .compatGlassButtonStyle()
                    .controlSize(.large)
                    .fixedSize()
                    .help("Cancel every running and waiting conversion")
                    .motionTransition(.pop)
                }
            }
            if let reason = model.convertBlockedReason {
                Label { Text(verbatim: reason) } icon: { Image(systemName: "info.circle") }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .motionTransition(.opacity)
            }
        }
        .motion(value: showsProgress)
        .motion(value: model.convertBlockedReason)
        .motion(value: model.queue.isProcessing)
    }

    /// "Save to  [📁 Movies ▾]": a pop-up with the folder's name, like a save panel's.
    private var destination: some View {
        HStack(spacing: Spacing.s) {
            Text("Save to").foregroundStyle(.secondary).fixedSize()
            Spacer(minLength: 0)
            Menu {
                Button("Change Folder…", systemImage: "folder.badge.gearshape") { model.chooseDestination() }
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.open(model.destinationFolder) }
            } label: {
                Label {
                    Text(verbatim: model.destinationFolder.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "folder")
                }
            }
            .menuStyle(.button)
            .compatGlassButtonStyle()
            .controlSize(.small)
            .fixedSize()
            .help(model.destinationFolder.path)
        }
    }

    @ViewBuilder
    private var convertButton: some View {
        let ready = model.readySourceCount
        let working = model.queue.runningCount > 0
        let reason = model.convertBlockedReason
        Button {
            model.convertAll()
        } label: {
            HStack(spacing: Spacing.s) {
                if working && ready == 0 {
                    Text("Processing…")
                } else {
                    Image(systemName: model.mode == .compress ? "arrow.down.right.and.arrow.up.left" : "arrow.triangle.2.circlepath")
                    Text(verbatim: model.convertButtonTitle).contentTransition(.numericText())
                }
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .compatGlassProminentButtonStyle()
        .controlSize(.large)
        .disabled(reason != nil || (working && ready == 0))
        .keyboardShortcut(.return, modifiers: .command)
        .help(reason.map { Text(verbatim: $0) } ?? Text("Queue every ready video and start (⌘↩)"))
        .motion(Motion.snappy, value: model.convertButtonTitle)
    }
}

private struct ProgressRow: View {
    let progress: QueueProgress

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .motion(Motion.snappy, value: progress.fraction)
            HStack {
                Text("File \(progress.current) of \(progress.total)")
                Spacer()
                Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                    .contentTransition(.numericText())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .motion(Motion.snappy, value: progress.fraction)
        }
    }
}
