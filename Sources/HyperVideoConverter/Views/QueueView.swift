import HyperVideoCore
import SwiftUI

struct QueueView: View {
    @Environment(AppModel.self) private var model

    private var queue: QueueStore { model.queue }

    var body: some View {
        Group {
            if queue.jobs.isEmpty {
                ContentUnavailableView(
                    "Queue is Empty",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add videos with “Add to Queue” or press ⌘B.")
                )
            } else {
                ScrollView {
                    GlassEffectContainer(spacing: 12) {
                        LazyVStack(spacing: 12) {
                            ForEach(queue.jobs) { job in
                                JobCard(job: job)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
            }
        }
        .navigationTitle("Queue")
        .navigationSubtitle(subtitle)
        .safeAreaInset(edge: .bottom) { controls }
    }

    private var subtitle: String {
        let done = queue.jobs.filter { if case .completed = $0.state { true } else { false } }.count
        return "\(queue.pendingCount) waiting · \(queue.runningCount) encoding · \(done) done"
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 12) {
                if let progress = queue.overallProgress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 260)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let remaining = queue.remainingForRunning {
                        Text("· about \(Format.duration(remaining)) left")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Clear Finished", systemImage: "checkmark.circle.badge.xmark") { queue.clearFinished() }
                    .buttonStyle(.glass)
                    .disabled(!queue.hasFinished)
                Button("Cancel All", systemImage: "stop.fill", role: .destructive) { queue.cancelAll() }
                    .buttonStyle(.glass)
                    .disabled(queue.runningCount == 0 && queue.pendingCount == 0)
                if queue.isProcessing {
                    Button("Pause", systemImage: "pause.fill") { queue.pause() }
                        .buttonStyle(.glassProminent)
                } else {
                    Button("Start Queue", systemImage: "play.fill") { queue.start() }
                        .buttonStyle(.glassProminent)
                        .disabled(queue.pendingCount == 0)
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct JobCard: View {
    @Environment(AppModel.self) private var model
    let job: EncodeJob

    var body: some View {
        HStack(spacing: 16) {
            statusIcon
                .font(.title2)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(tint.opacity(0.3)), in: .circle)

            VStack(alignment: .leading, spacing: 6) {
                Text(job.source.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                Text("\(job.presetName) → \(job.destination.lastPathComponent)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                detail
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    @ViewBuilder
    private var detail: some View {
        switch job.state {
        case .queued:
            Text("Waiting").font(.caption).foregroundStyle(.secondary)
        case .running(let progress):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ProgressView(value: progress)
                    Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit().font(.caption)
                }
                Text(rateDescription(model.queue.rate(for: job)))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        case .completed(let bytes, let elapsed):
            Text(completedDescription(bytes: bytes, elapsed: elapsed)).font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
        case .cancelled:
            Text("Cancelled").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func rateDescription(_ rate: EncodeRate?) -> String {
        guard let rate, let remaining = rate.remaining else { return "Estimating time left…" }
        let parts = [
            rate.speed.map(Format.speed),
            rate.framesPerSecond.map { "\(Int($0.rounded())) fps" },
            "\(Format.duration(remaining)) left"
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func completedDescription(bytes: Int64, elapsed: TimeInterval) -> String {
        let summary = "\(Format.bytes(bytes)) · finished in \(Format.duration(elapsed))"
        guard let duration = job.mediaDuration, elapsed > 0 else { return summary }
        return summary + " · \(Format.speed(duration / elapsed)) realtime"
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            switch job.state {
            case .queued, .running:
                Button("Cancel", systemImage: "xmark") { model.queue.cancel(job.id) }
            case .completed:
                Button("Show in Finder", systemImage: "magnifyingglass") { SystemIntegration.reveal([job.destination]) }
                Button("Open", systemImage: "play.fill") { NSWorkspace.shared.open(job.destination) }
            case .failed, .cancelled:
                Button("Retry", systemImage: "arrow.clockwise") { model.queue.retry(job.id) }
            }
            if !job.state.isRunning {
                Button("Remove", systemImage: "trash") { model.queue.remove([job.id]) }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var tint: Color {
        switch job.state {
        case .queued: .gray
        case .running: .accentColor
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.state {
        case .queued: Image(systemName: "clock")
        case .running: Image(systemName: "gearshape.2.fill").symbolEffect(.rotate)
        case .completed: Image(systemName: "checkmark").symbolEffect(.bounce, value: job.state)
        case .failed: Image(systemName: "exclamationmark.triangle.fill")
        case .cancelled: Image(systemName: "stop.fill")
        }
    }
}
