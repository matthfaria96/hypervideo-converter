import HyperVideoCore
import SwiftUI

/// Finished, failed and cancelled conversions, newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScaffold(eyebrow: "Library", title: "History",
                     subtitle: "Finished, failed and cancelled conversions.") {
            Button("Clear History") { model.queue.clearFinished() }
                .buttonStyle(.subtle)
                .disabled(model.historyJobs.isEmpty)
        } content: {
            if model.historyJobs.isEmpty {
                EmptyPage(symbol: "clock.arrow.circlepath", text: "Converted videos will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.historyJobs) { job in
                        HistoryRow(job: job)
                            .padding(12)
                            .overlay(alignment: .bottom) { Color(hex: 0x333338).frame(height: 1) }
                    }
                }
                .clipShape(.rect(cornerRadius: 11))
                .card(fill: Color(hex: 0x202023))
            }
        }
    }
}

private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let job: EncodeJob

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(job.destination.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: detail)
                    .font(.system(size: 10))
                    .foregroundStyle(isFailure ? Theme.red : Theme.muted)
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
                Button("Retry", systemImage: "arrow.clockwise") { model.queue.retry(job.id) }
            }
            Button("Show Source in Finder", systemImage: "film") { SystemIntegration.reveal([job.source]) }
            Divider()
            Button("Remove from History", systemImage: "trash", role: .destructive) { model.queue.remove([job.id]) }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if case .completed = job.state {
                Button("Show in Finder", systemImage: "magnifyingglass") { SystemIntegration.reveal([job.destination]) }
                Button("Open", systemImage: "play.fill") { NSWorkspace.shared.open(job.destination) }
            } else {
                Button("Retry", systemImage: "arrow.clockwise") { model.queue.retry(job.id) }
            }
            Button("Remove from History", systemImage: "xmark") { model.queue.remove([job.id]) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.subtle)
    }

    private var isFailure: Bool { if case .failed = job.state { true } else { false } }

    private var detail: String {
        switch job.state {
        case .completed(let bytes, let elapsed):
            var parts = [job.presetName, Format.bytes(bytes), String(localized: "finished in \(Format.duration(elapsed))")]
            if let duration = job.mediaDuration, elapsed > 0 {
                parts.append(String(localized: "\(Format.speed(duration / elapsed)) realtime"))
            }
            return parts.joined(separator: " · ")
        case .failed(let message): return message
        case .cancelled: return String(localized: "Cancelled") + " · " + job.presetName
        case .queued, .running: return job.presetName
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
        case .completed: Theme.green
        case .failed: Theme.red
        default: Theme.accent
        }
    }
}
