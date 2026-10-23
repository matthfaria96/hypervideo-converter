import HyperVideoCore
import SwiftUI

/// One finished, failed or cancelled conversion: the result's picture with a status
/// badge, its name, coloured tags (mode, status, format, size change, New) and actions.
struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let job: EncodeJob
    @State private var sourceBytes: Int64?

    private var look: JobStatusLook { JobStatusLook(job.state) }

    var body: some View {
        HStack(spacing: Spacing.m) {
            cover
            VStack(alignment: .leading, spacing: Spacing.xs + 1) {
                HStack(spacing: Spacing.xs + 2) {
                    Text(job.destination.lastPathComponent)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if model.isFromLastRun(job) {
                        StatusTag(text: String(localized: "New"), tone: .success, isLive: true)
                            .motionTransition(.pop)
                    }
                }
                tags
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(isFailure ? Theme.danger : .secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .task(id: job.destination) {
            await model.loadHistoryThumbnail(for: job)
            sourceBytes = await Self.size(of: job.source)
        }
        .contextMenu { menu }
    }

    private var cover: some View {
        Thumbnail(image: model.ui.thumbnails[job.destination], symbol: look.symbol, isLoading: false,
                  duration: job.mediaDuration, size: .large)
            .saturation(isFailure || isCancelled ? 0.2 : 1)
            .overlay(alignment: .topLeading) {
                Image(systemName: look.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, look.tone.color)
                    .padding(3)
                    .background(look.tone == .neutral ? AnyShapeStyle(.gray) : AnyShapeStyle(look.tone.color), in: .circle)
                    .overlay { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
                    .offset(x: -5, y: -5)
                    .symbolEffect(.bounce, value: model.isFromLastRun(job))
            }
            .padding([.top, .leading], 5)
    }

    @ViewBuilder
    private var tags: some View {
        HStack(spacing: Spacing.xs) {
            JobKindLook(settings: job.settings, presetID: job.presetID).tag
            look.tag
            let format = job.destination.pathExtension.uppercased()
            if !format.isEmpty { StatusTag(text: format, tone: ContainerTag.tone(for: format)) }
            if case .completed(let bytes, _) = job.state, let sourceBytes,
               let change = SizeChangeLook(before: sourceBytes, after: bytes) {
                change.tag.help(Text("Compared with the original file"))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.s) {
            if case .completed = job.state {
                Button("Open", systemImage: "play.fill") { NSWorkspace.shared.open(job.destination) }
                    .help("Play the converted video")
                Button("Show in Finder", systemImage: "folder") { SystemIntegration.reveal([job.destination]) }
                    .labelStyle(.iconOnly)
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

    @ViewBuilder
    private var menu: some View {
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

    private var isFailure: Bool { if case .failed = job.state { true } else { false } }
    private var isCancelled: Bool { job.state == .cancelled }

    private var detail: String {
        switch job.state {
        case .completed(let bytes, let elapsed):
            var parts = [model.presetName(for: job), Format.bytes(bytes), String(localized: "finished in \(Format.duration(elapsed))")]
            if let duration = job.mediaDuration, elapsed > 0 {
                parts.append(String(localized: "\(Format.speed(duration / elapsed)) realtime"))
            }
            return parts.joined(separator: " · ")
        case .failed(let message): return message
        case .cancelled, .queued, .running: return model.presetName(for: job)
        }
    }

    /// The original's size, read off the main thread (it may sit on a slow volume).
    private static func size(of url: URL) async -> Int64? {
        await Task.detached {
            (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        }.value
    }
}
