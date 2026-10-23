import CoreGraphics
import Foundation
import HyperVideoCore

/// Compress to "at most N MB": the average bitrate that fills the target after the
/// audio, with the resolution lowered when the bitrate would be too thin for the
/// picture (a smaller sharp video beats a big blurry one).
struct TargetSizePlan: Equatable {
    let settings: EncodeSettings
    let videoKbps: Int
    let audioKbps: Int
    /// False when even the lowest bitrate overshoots the target.
    let fits: Bool

    static let minimumVideoKbps = 150
    /// Room for the file's boxes and the encoder's small overshoots.
    static let margin = 0.96
    /// Below this many bits per pixel and frame HEVC starts to smear; the plan then
    /// steps down the resolution.
    static let minimumBitsPerPixel = 0.045
    static let steps: [MaxResolution] = [.source, .fhd1080, .hd720, .sd576, .sd480]

    init(bytes: Int64, info: MediaInfo, settings base: EncodeSettings) {
        let duration = max(1, base.outputDuration(sourceDuration: info.duration))
        let totalKbps = Double(bytes) * 8 * Self.margin / duration / 1000
        let tracks = max(1, min(info.audioTracks.count, base.audioTracks == .all ? info.audioTracks.count : 1))
        let audio = info.audioTracks.isEmpty ? 0 : (totalKbps > 2_000 ? 128 : totalKbps > 600 ? 96 : 64)
        let rawVideo = Int(totalKbps) - audio * tracks
        videoKbps = max(Self.minimumVideoKbps, rawVideo)
        audioKbps = audio * tracks
        fits = rawVideo >= Self.minimumVideoKbps

        var settings = base
        settings.videoCodec = .hevc
        settings.rateControl = .averageBitrate(videoKbps)
        settings.maxResolution = Self.resolution(videoKbps: videoKbps, info: info)
        if !info.audioTracks.isEmpty {
            settings.audioCodec = .aac
            settings.audioBitrateKbps = audio
        }
        self.settings = settings.retuningAudioTracks()
    }

    /// The largest step whose picture still gets enough bits per pixel.
    static func resolution(videoKbps: Int, info: MediaInfo) -> MaxResolution {
        let source = info.displaySize ?? CGSize(width: 1920, height: 1080)
        let fps = info.frameRate.flatMap { $0 > 0 ? $0 : nil } ?? 30
        let shortSide = min(source.width, source.height)
        for step in steps {
            let height = step == .source ? shortSide : min(shortSide, CGFloat(step.rawValue))
            guard step == .source || CGFloat(step.rawValue) < shortSide else { continue }
            let scale = height / shortSide
            let pixels = source.width * scale * source.height * scale
            if Double(videoKbps) * 1000 / (Double(pixels) * fps) >= minimumBitsPerPixel { return step }
        }
        return .sd480
    }
}

extension AppModel {
    /// Compress mode's "at most N MB per video"; nil compresses by quality level.
    var compressTargetMB: Double? {
        get { ui.compressTargetMB }
        set {
            ui.compressTargetMB = newValue.map { max(1, $0) }
            defaults.set(ui.compressTargetMB, forKey: PreferenceKey.compressTargetMB)
        }
    }

    /// The target plan for one video, in Compress mode with a target set.
    func targetPlan(for item: SourceItem) -> TargetSizePlan? {
        guard mode == .compress, let mb = compressTargetMB, let info = item.info else { return nil }
        return TargetSizePlan(bytes: Int64(mb * 1_000_000), info: info, settings: item.settings)
    }

    /// Before → after for the Compress panel's targets, as they'll be queued.
    var compressEstimate: SizeEstimate {
        let ids = Set(inspectorTargetIDs)
        return SizeEstimate(sources.filter { ids.contains($0.id) }.map { item in
            var copy = item
            copy.settings = jobSettings(for: item)
            return copy
        })
    }
}
