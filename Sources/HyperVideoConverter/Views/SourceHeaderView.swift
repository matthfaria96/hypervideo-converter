import HyperVideoCore
import SwiftUI

struct SourceHeaderView: View {
    let source: SourceItem
    let presetName: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
                .backgroundExtensionEffect()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.title.bold())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(presetName).foregroundStyle(.secondary)
                }
                if let info = source.info { chips(info) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(14)
        }
        .clipShape(.rect(cornerRadius: 28))
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = source.thumbnail {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    Image(systemName: source.info?.hasVideo == false ? "waveform" : "film")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(.white.opacity(0.7))
                }
        }
    }

    private func chips(_ info: MediaInfo) -> some View {
        GlassEffectContainer(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if let size = info.displaySize { InfoChip(symbol: "aspectratio", text: Format.size(size)) }
                    if let codec = info.videoCodec { InfoChip(symbol: "film", text: codec) }
                    if let fps = info.frameRate { InfoChip(symbol: "speedometer", text: Format.fps(fps)) }
                    InfoChip(symbol: "clock", text: Format.duration(info.duration))
                    if let rate = info.videoBitrate { InfoChip(symbol: "gauge.with.dots.needle.67percent", text: Format.bitrate(rate)) }
                    InfoChip(symbol: "internaldrive", text: Format.bytes(info.fileBytes))
                    if info.dynamicRange != .sdr {
                        InfoChip(symbol: "sun.max.fill", text: info.dynamicRange.rawValue, tint: .yellow)
                    }
                    if !info.audioTracks.isEmpty {
                        InfoChip(symbol: "speaker.wave.2", text: "\(info.audioTracks.count) audio")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
