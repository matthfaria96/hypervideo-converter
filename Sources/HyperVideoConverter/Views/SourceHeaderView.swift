import AppKit
import HyperVideoCore
import SwiftUI

struct SourceHeaderView: View {
    let source: SourceItem
    let presetName: String
    /// The big picture, once loaded; the list thumbnail meanwhile.
    var picture: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipped()

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
            .background(.black.opacity(0.5), in: .rect(cornerRadius: 14))
            .padding(14)
        }
        .clipShape(.rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = picture {
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
        Group {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if let size = info.displaySize { InfoChip(symbol: "aspectratio", text: Format.size(size)) }
                    if let codec = info.videoCodec { InfoChip(symbol: "film", text: codec) }
                    if let fps = info.frameRate { InfoChip(symbol: "speedometer", text: Format.fps(fps)) }
                    InfoChip(symbol: "clock", text: Format.duration(info.duration))
                    if let rate = info.videoBitrate { InfoChip(symbol: "gauge.with.dots.needle.67percent", text: Format.bitrate(rate)) }
                    InfoChip(symbol: "internaldrive", text: Format.bytes(info.fileBytes))
                    if info.isInterlaced { InfoChip(symbol: "line.3.horizontal", text: String(localized: "Interlaced")) }
                    if info.dynamicRange != .sdr {
                        InfoChip(symbol: "sun.max.fill", text: info.dynamicRange.rawValue, tint: .yellow)
                    }
                    if !info.audioTracks.isEmpty {
                        InfoChip(symbol: "speaker.wave.2", text: String(localized: "\(info.audioTracks.count) audio"))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
