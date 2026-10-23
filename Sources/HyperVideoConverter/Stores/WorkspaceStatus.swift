import Foundation
import HyperVideoCore

extension EncodeSettings {
    /// ProRes only fits in MOV: outside it the video falls back to HEVC.
    func fixingCodecForContainer() -> EncodeSettings {
        guard videoCodec.isProRes, container != .mov else { return self }
        var copy = self
        copy.videoCodec = .hevc
        return copy
    }

    /// Picking a codec: ProRes moves the output to MOV, which is the only container it fits.
    func choosing(codec: VideoCodec) -> EncodeSettings {
        var copy = self
        copy.videoCodec = codec
        if codec.isProRes { copy.container = .mov }
        return copy.normalizingEncoderOptions()
    }

    /// Drops a video profile the codec doesn't offer, and the level outside H.264.
    func normalizingEncoderOptions() -> EncodeSettings {
        var copy = self
        copy.videoOptions.profile = videoOptions.profile.resolved(for: videoCodec)
        if videoCodec != .h264 { copy.videoOptions.level = .auto }
        return copy
    }

    /// Normalizes only when the codec differs from `previous`'s, like picking it would.
    func normalizingEncoderOptions(after previous: EncodeSettings) -> EncodeSettings {
        videoCodec == previous.videoCodec ? self : normalizingEncoderOptions()
    }

    /// Picking a format: a ProRes video that can't go there becomes HEVC.
    func choosing(container: ContainerFormat) -> EncodeSettings {
        var copy = self
        copy.container = container
        return copy.fixingCodecForContainer()
    }
}

/// Progress of the current run, for the bottom bar: "file X of N" and an overall fraction.
struct QueueProgress: Equatable {
    var finished: Int
    var running: [Double]
    var waiting: Int

    @MainActor
    init(queue: QueueStore) {
        self.init(finished: queue.batchFinishedCount,
                  running: queue.runningFractions,
                  waiting: queue.pendingCount)
    }

    init(finished: Int, running: [Double], waiting: Int) {
        self.finished = finished
        self.running = running
        self.waiting = waiting
    }

    var total: Int { finished + running.count + waiting }
    var isActive: Bool { !running.isEmpty }
    /// The file being worked on, counting from 1.
    var current: Int { min(total, finished + 1) }
    var fraction: Double {
        guard total > 0 else { return 0 }
        return (Double(finished) + running.reduce(0, +)) / Double(total)
    }
}

/// Size of the inspector's targets before and after, from the core's predictions.
struct SizeEstimate: Equatable {
    /// Inspected videos counted.
    var count: Int
    var originalBytes: Int64
    /// Nil when no inspected video could be predicted.
    var estimatedBytes: Int64?
    /// How far the sum can be trusted: the least certain video decides.
    var kind: SizePrediction.Kind

    /// Fraction saved (negative when the output is larger).
    var savings: Double? {
        guard let estimatedBytes, originalBytes > 0 else { return nil }
        return 1 - Double(estimatedBytes) / Double(originalBytes)
    }

    init(count: Int, originalBytes: Int64, estimatedBytes: Int64?, kind: SizePrediction.Kind = .approximate) {
        self.count = count
        self.originalBytes = originalBytes
        self.estimatedBytes = estimatedBytes
        self.kind = kind
    }

    init(_ items: [SourceItem]) {
        let inspected = items.compactMap { item in item.info.map { (info: $0, settings: item.settings) } }
        let predictions = inspected.map { OutputEstimate.prediction(info: $0.info, settings: $0.settings) }
        let known = predictions.compactMap { $0 }
        self.init(count: inspected.count,
                  originalBytes: inspected.reduce(0) { $0 + $1.info.fileBytes },
                  estimatedBytes: known.isEmpty || known.count < predictions.count ? nil : known.reduce(0) { $0 + $1.bytes },
                  kind: known.map(\.kind).max() ?? .approximate)
    }

    /// "≈ 120 MB", "up to ~120 MB" or "120 MB", for the headline and the Advanced sheet.
    static func label(bytes: Int64, kind: SizePrediction.Kind) -> String {
        let size = Format.bytes(bytes)
        switch kind {
        case .exact: return size
        case .upTo: return String(localized: "up to ~\(size)")
        case .approximate: return "≈ " + size
        }
    }
}

extension AppModel {
    var sizeEstimate: SizeEstimate {
        let ids = Set(inspectorTargetIDs)
        return SizeEstimate(sources.filter { ids.contains($0.id) })
    }
}
