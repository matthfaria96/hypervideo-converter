import HyperVideoCore
import SwiftUI

/// Finished, failed and cancelled conversions, newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var ui = model.ui
        PageScaffold(subtitle: "Finished, failed and cancelled conversions.") {
            Button("Clear History", systemImage: "trash") { ui.confirmingClearHistory = true }
                .compatGlassButtonStyle()
                .disabled(model.historyJobs.isEmpty)
                .confirmationDialog("Clear History?", isPresented: $ui.confirmingClearHistory) {
                    Button("Clear History", role: .destructive) { model.queue.clearFinished() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(verbatim: model.clearHistoryMessage)
                }
        } content: {
            if model.historyJobs.isEmpty {
                EmptyPage(symbol: "clock.arrow.circlepath", text: "Converted videos will appear here.")
                    .motionTransition(.pop)
            } else {
                ListCard {
                    ForEach(model.historyJobs) { job in
                        HistoryRow(job: job)
                            .listCardRow()
                            .motionTransition(.row)
                    }
                }
                .motionTransition(.content)
            }
        }
        .motion(value: model.historyJobs.map(\.id))
    }
}

private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let job: EncodeJob

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: Radius.s + 2))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(job.destination.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(isFailure ? Theme.danger : .secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .contextMenu {
            if case .completed = job.state {
                Button("Show in Finder", systemImage: "folder") { SystemIntegration.reveal([job.destination]) }
                Button("Open", systemImage: "play.fill") { NSWorkspace.shared.open(job.destination) }
            } else {
                Button("Try Again", systemImage: "arrow.clockwise") { model.queue.retry(job.id) }
            }
            Button("Show Source in Finder", systemImage: "film") { SystemIntegration.reveal([job.source]) }
            Divider()
            Button("Remove from History", systemImage: "trash", role: .destructive) { model.queue.remove([job.id]) }
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.s) {
            if case .completed = job.state {
                Button("Open", systemImage: "play.fill") { NSWorkspace.shared.open(job.destination) }
                    .help("Play the converted video")
                Button("Show in Finder", systemImage: "folder") { SystemIntegration.reveal([job.destination]) }
                    .help("Show the converted file in Finder")
            } else {
                Button("Try Again", systemImage: "arrow.clockwise") { model.queue.retry(job.id) }
                    .help("Put this video back in the queue")
            }
            Button("Remove from History", systemImage: "trash") { model.queue.remove([job.id]) }
                .labelStyle(.iconOnly)
                .help("Remove from History (the file isn't deleted)")
                .accessibilityLabel(Text("Remove from History"))
        }
        .compatGlassButtonStyle()
        .controlSize(.small)
    }

    private var isFailure: Bool { if case .failed = job.state { true } else { false } }

    private var detail: String {
        switch job.state {
        case .completed(let bytes, let elapsed):
            var parts = [model.presetName(for: job), Format.bytes(bytes), String(localized: "finished in \(Format.duration(elapsed))")]
            if let duration = job.mediaDuration, elapsed > 0 {
                parts.append(String(localized: "\(Format.speed(duration / elapsed)) realtime"))
            }
            return parts.joined(separator: " · ")
        case .failed(let message): return message
        case .cancelled: return String(localized: "Cancelled") + " · " + model.presetName(for: job)
        case .queued, .running: return model.presetName(for: job)
        }
    }

    private var symbol: String {
        switch job.state {
        case .completed: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        default: "stop.fill"
        }
    }

    private var tint: Color {
        switch job.state {
        case .completed: Theme.success
        case .failed: Theme.danger
        default: Theme.accent
        }
    }
}
