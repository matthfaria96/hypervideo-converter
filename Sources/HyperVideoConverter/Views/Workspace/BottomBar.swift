import SwiftUI

/// Destination folder, run progress and the Convert / Stop buttons, on the window's
/// bar material.
struct BottomBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.progress
        let showsProgress = progress.isActive || model.queue.isProcessing && progress.total > 0
        VStack(spacing: Spacing.m) {
            if showsProgress {
                ProgressRow(progress: progress).motionTransition(.banner)
            }
            HStack(spacing: Spacing.m) {
                destination
                Spacer(minLength: Spacing.s)
                // With an empty list the page itself says to add videos.
                if let reason = model.convertBlockedReason, !model.sources.isEmpty {
                    Text(verbatim: reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .layoutPriority(1)
                        .motionTransition(.opacity)
                }
                if model.queue.runningCount > 0 || model.queue.isProcessing {
                    Button {
                        model.queue.cancelAll()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .compatGlassButtonStyle()
                    .fixedSize()
                    .help("Cancel every running and waiting conversion")
                    .motionTransition(.pop)
                }
                convertButton
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.m)
        .motion(value: showsProgress)
        .motion(value: model.convertBlockedReason)
        .motion(value: model.queue.isProcessing)
        .overlay(alignment: .top) { Divider() }
        .compatBarBackground()
    }

    /// "Save to  [📁 Movies ▾]": a pop-up with the folder's name, like a save panel's.
    private var destination: some View {
        HStack(spacing: Spacing.s) {
            Text("Save to").foregroundStyle(.secondary).fixedSize()
            Menu {
                Button("Change Folder…", systemImage: "folder.badge.gearshape") { model.chooseDestination() }
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.open(model.destinationFolder) }
            } label: {
                Label {
                    Text(verbatim: model.destinationFolder.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200)
                } icon: {
                    Image(systemName: "folder")
                }
            }
            .menuStyle(.button)
            .compatGlassButtonStyle()
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
                    Text(verbatim: model.convertButtonTitle).contentTransition(.numericText())
                    Image(systemName: "arrow.right")
                }
            }
            .fontWeight(.semibold)
            .frame(minWidth: 130)
            .fixedSize()
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
