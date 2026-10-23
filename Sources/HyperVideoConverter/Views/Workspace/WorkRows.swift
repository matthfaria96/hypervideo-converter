import HyperVideoCore
import SwiftUI

/// A video being set up: thumbnail, name, media facts, sizes and a remove button.
struct SourceRowView: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            Thumbnail(image: source.thumbnail, symbol: source.errorMessage == nil ? "play.fill" : "exclamationmark.triangle",
                      isLoading: source.isLoading, duration: source.info?.duration, size: .large)
            VStack(alignment: .leading, spacing: Spacing.xs + 2) {
                Text(source.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            sizes
            RowRemoveButton(help: "Remove from the list (the file stays on your Mac)",
                            label: "Remove \(source.name)") { model.removeSource(source.id) }
        }
        .padding(.vertical, Spacing.xs)
        .hoverLift(1.005)
    }

    @ViewBuilder
    private var meta: some View {
        if let error = source.errorMessage {
            Text("Unsupported format or damaged file")
                .font(.caption).foregroundStyle(Theme.danger).lineLimit(1)
                .help(error)
        } else if let info = source.info {
            HStack(spacing: Spacing.xs) {
                ForEach(RowFacts.tags(url: source.url, info: info), id: \.self) { MetaTag(text: $0) }
                if !source.settings.isValid {
                    MetaTag(text: String(localized: "Check settings"), tint: Theme.warning)
                }
            }
            .lineLimit(1)
        } else {
            Text("Analyzing…").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sizes: some View {
        if let info = source.info {
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(Format.bytes(info.fileBytes)).font(.callout).monospacedDigit()
                Group {
                    if let estimate = OutputEstimate.prediction(info: info, settings: source.settings) {
                        Text(verbatim: String(localized: "\(SizeEstimate.label(bytes: estimate.bytes, kind: estimate.kind)) output"))
                            .help(model.presetName(for: source))
                    } else {
                        Text(verbatim: model.presetName(for: source))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
            }
            .fixedSize()
            .motion(Motion.snappy, value: source.settings)
        }
    }
}

/// A job waiting or encoding, with its progress.
struct JobRowView: View {
    @Environment(AppModel.self) private var model
    let job: EncodeJob

    var body: some View {
        HStack(spacing: Spacing.m) {
            Thumbnail(image: model.ui.thumbnails[job.source], symbol: "clock", isLoading: false,
                      duration: job.mediaDuration, size: .large)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(job.source.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: "\(model.presetName(for: job)) → \(job.destination.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if job.state.isRunning {
                    JobProgressBar(progress: model.queue.progress(for: job.id))
                        .motionTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            status.fixedSize()
            RowRemoveButton(help: "Cancel this conversion", label: "Cancel \(job.source.lastPathComponent)") {
                model.queue.cancel(job.id)
            }
        }
        .padding(.vertical, Spacing.xs)
        .motion(value: job.state.isRunning)
    }

    @ViewBuilder
    private var status: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            if job.state.isRunning {
                JobProgressStatus(job: job, progress: model.queue.progress(for: job.id))
            } else {
                Text("Waiting").font(.callout).foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}

/// The running job's bar. It reads the job's own progress object, so a tick redraws
/// only this view and not the list.
private struct JobProgressBar: View {
    let progress: JobProgress

    var body: some View {
        ProgressView(value: progress.fraction)
            .progressViewStyle(.linear)
            .controlSize(.small)
            .motion(Motion.snappy, value: progress.fraction)
    }
}

/// Percentage, speed and time left of a running job.
private struct JobProgressStatus: View {
    @Environment(AppModel.self) private var model
    let job: EncodeJob
    let progress: JobProgress

    var body: some View {
        Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
            .font(.callout.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .contentTransition(.numericText())
            .motion(Motion.snappy, value: progress.fraction)
        Text(verbatim: rate)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var rate: String {
        guard let rate = model.queue.rate(for: job), let remaining = rate.remaining else {
            return String(localized: "Estimating…")
        }
        let parts = [rate.speed.map(Format.speed), String(localized: "\(Format.duration(remaining)) left")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// The picture at the start of a row; the real frame fades in over the placeholder,
/// with the duration in a corner badge like Photos and Finder show it.
struct Thumbnail: View {
    enum Size {
        case regular, large
        var frame: CGSize { self == .large ? CGSize(width: 72, height: 44) : CGSize(width: 48, height: 36) }
    }

    let image: NSImage?
    let symbol: String
    let isLoading: Bool
    var duration: Double?
    var size: Size = .regular

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x3B5765), Color(hex: 0x16232D)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: isLoading ? "rays" : symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xC7E7F7))
                    .symbolEffect(.rotate, isActive: isLoading)
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .motionTransition(.opacity)
                }
            }
            if let duration, duration > 0 {
                Text(Format.duration(duration))
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: .rect(cornerRadius: 3))
                    .padding(3)
            }
        }
        .frame(width: size.frame.width, height: size.frame.height)
        .clipShape(.rect(cornerRadius: Radius.s))
        .overlay { RoundedRectangle(cornerRadius: Radius.s).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .motion(Motion.quick, value: image != nil)
    }
}

/// A small rounded tag for a media fact ("MP4", "H.264", "1280 × 720").
struct MetaTag: View {
    let text: String
    var tint: Color?

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.map { AnyShapeStyle($0.opacity(0.15)) } ?? AnyShapeStyle(.fill.tertiary), in: .rect(cornerRadius: 4))
    }
}

/// The quiet ✕ at the end of a row: tertiary until hovered, red while pressed.
struct RowRemoveButton: View {
    let help: LocalizedStringKey
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .motion(Motion.quick, value: hovered)
        .help(help)
        .accessibilityLabel(Text(verbatim: label))
    }
}

enum RowFacts {
    /// "MOV · H.264 · 1920 × 1080 · 2:15"
    static func meta(url: URL, info: MediaInfo) -> String {
        [
            url.pathExtension.uppercased(),
            info.videoCodec,
            info.displaySize.map(Format.size),
            Format.duration(info.duration)
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The row's tags: container, codec and size (the duration sits on the thumbnail).
    static func tags(url: URL, info: MediaInfo) -> [String] {
        [url.pathExtension.uppercased(), info.videoCodec, info.displaySize.map(Format.size)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }
}
