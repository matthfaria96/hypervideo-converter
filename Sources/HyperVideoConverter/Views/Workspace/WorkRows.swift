import HyperVideoCore
import SwiftUI

/// A video being set up: thumbnail, name, media facts, sizes and a remove button.
struct SourceRowView: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Thumbnail(image: source.thumbnail, symbol: source.errorMessage == nil ? "play.fill" : "exclamationmark.triangle",
                      isLoading: source.isLoading)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            sizes
            if source.errorMessage != nil {
                Button("Remove") { model.removeSource(source.id) }
                    .buttonStyle(.subtle)
            }
            Button {
                model.removeSource(source.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(RemoveButtonStyle())
            .help("Remove from the list (the file stays on your Mac)")
            .accessibilityLabel(Text("Remove \(source.name)"))
        }
    }

    @ViewBuilder
    private var meta: some View {
        if let error = source.errorMessage {
            Text("Unsupported format or damaged file")
                .font(.system(size: 10)).foregroundStyle(Theme.red).lineLimit(1)
                .help(error)
        } else if let info = source.info {
            HStack(spacing: 6) {
                Text(verbatim: RowFacts.meta(url: source.url, info: info))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if !source.settings.isValid {
                    Text("Check settings").foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 10))
        } else {
            Text("Analyzing…").font(.system(size: 10)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private var sizes: some View {
        if let info = source.info {
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.bytes(info.fileBytes)).font(.system(size: 11)).foregroundStyle(Color(hex: 0xDDDDDD))
                Group {
                    if let estimate = OutputEstimate.prediction(info: info, settings: source.settings) {
                        Text(verbatim: String(localized: "\(SizeEstimate.label(bytes: estimate.bytes, kind: estimate.kind)) output"))
                            .help(model.presetName(for: source))
                    } else {
                        Text(verbatim: model.presetName(for: source))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }
            .fixedSize()
        }
    }
}

/// A job waiting or encoding, with its progress.
struct JobRowView: View {
    @Environment(AppModel.self) private var model
    let job: EncodeJob

    var body: some View {
        HStack(spacing: 11) {
            Thumbnail(image: model.ui.thumbnails[job.source], symbol: "clock", isLoading: false)
            VStack(alignment: .leading, spacing: 5) {
                Text(job.source.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: "\(job.presetName) → \(job.destination.lastPathComponent)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .running(let progress) = job.state {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            status.fixedSize()
            Button {
                model.queue.cancel(job.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(RemoveButtonStyle())
            .help("Cancel this conversion")
            .accessibilityLabel(Text("Cancel \(job.source.lastPathComponent)"))
        }
    }

    @ViewBuilder
    private var status: some View {
        VStack(alignment: .trailing, spacing: 4) {
            switch job.state {
            case .running(let progress):
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentLight)
                Text(verbatim: rate)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            default:
                Text("Waiting").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .monospacedDigit()
    }

    private var rate: String {
        guard let rate = model.queue.rate(for: job), let remaining = rate.remaining else {
            return String(localized: "Estimating…")
        }
        let parts = [rate.speed.map(Format.speed), String(localized: "\(Format.duration(remaining)) left")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// The small picture at the start of a row.
struct Thumbnail: View {
    let image: NSImage?
    let symbol: String
    let isLoading: Bool

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(hex: 0x3B5765), Color(hex: 0x16232D)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: isLoading ? "rays" : symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0xC7E7F7))
                            .symbolEffect(.rotate, isActive: isLoading)
                    }
            }
        }
        .frame(width: 46, height: 34)
        .clipShape(.rect(cornerRadius: 6))
    }
}

struct RemoveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Theme.red : Color(hex: 0xA6A6AD))
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.05), in: .circle)
            .contentShape(.rect)
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
}
