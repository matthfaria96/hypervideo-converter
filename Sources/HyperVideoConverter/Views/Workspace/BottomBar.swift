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
                Text(verbatim: abbreviated(model.destinationFolder))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(model.destinationFolder.path)
                Text(verbatim: "·").foregroundStyle(Theme.muted)
                Button("Change") { model.chooseDestination() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: 0xE8B54B))
            }
            .font(.system(size: 10))
        }
    }

    @ViewBuilder
    private var convertButton: some View {
        let ready = model.readySourceCount
        let working = model.queue.runningCount > 0
        Button {
            model.convertAll()
        } label: {
            HStack(spacing: 7) {
                if working && ready == 0 {
                    Text("Processing…")
                } else {
                    Text(model.mode == .compress ? "Compress Videos" : "Convert Videos")
                    Image(systemName: "arrow.right")
                }
            }
            .frame(minWidth: 140)
        }
        .buttonStyle(.primary)
        .disabled(ready == 0 && (working || model.queue.pendingCount == 0))
        .keyboardShortcut(.return, modifiers: .command)
        .help(ready == 0 && model.queue.pendingCount == 0 ? "Add videos to convert first" : "Queue every ready video and start (⌘↩)")
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
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
