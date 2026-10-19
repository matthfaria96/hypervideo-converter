import SwiftUI

/// Destination folder, run progress and the Convert / Stop buttons.
struct BottomBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.progress
        VStack(spacing: 12) {
            if progress.isActive || model.queue.isProcessing && progress.total > 0 {
                ProgressRow(progress: progress)
            }
            HStack(spacing: 12) {
                destination
                Spacer(minLength: 8)
                if model.queue.runningCount > 0 || model.queue.isProcessing {
                    Button {
                        model.queue.cancelAll()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.subtle)
                    .help("Cancel every running and waiting conversion")
                }
                convertButton
            }
        }
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Save to").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xDDDDDD))
            HStack(spacing: 4) {
                Button {
                    NSWorkspace.shared.open(model.destinationFolder)
                } label: {
                    Text(verbatim: abbreviated(model.destinationFolder))
                        .underline(color: Theme.muted.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(minHeight: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .help("Open \(model.destinationFolder.path) in Finder")
                Text(verbatim: "·").foregroundStyle(Theme.muted)
                Button("Change") { model.chooseDestination() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: 0xE8B54B))
                    .frame(minHeight: 22)
                    .contentShape(.rect)
                    .help("Choose where converted videos are saved")
            }
            .font(.system(size: 10))
        }
    }

    @ViewBuilder
    private var convertButton: some View {
        let ready = model.readySourceCount
        let working = model.queue.runningCount > 0
        let reason = model.convertBlockedReason
        HStack(spacing: 10) {
            if let reason {
                Text(verbatim: reason).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Button {
                model.convertAll()
            } label: {
                HStack(spacing: 7) {
                    if working && ready == 0 {
                        Text("Processing…")
                    } else {
                        Text(verbatim: model.convertButtonTitle)
                        Image(systemName: "arrow.right")
                    }
                }
                .frame(minWidth: 140)
            }
            .buttonStyle(.primary)
            .disabled(reason != nil || (working && ready == 0))
            .keyboardShortcut(.return, modifiers: .command)
            .help(reason.map { Text(verbatim: $0) } ?? Text("Queue every ready video and start (⌘↩)"))
        }
    }

    private func abbreviated(_ url: URL) -> String {
        Format.path(url)
    }
}

private struct ProgressRow: View {
    let progress: QueueProgress

    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
            HStack {
                Text("File \(progress.current) of \(progress.total)")
                Spacer()
                Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.muted)
            .monospacedDigit()
        }
    }
}
