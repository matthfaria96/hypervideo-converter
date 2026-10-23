import Foundation
import HyperVideoCore

/// Totals of the AI Upscale plans for the videos the panel talks about.
struct UpscaleEstimate: Equatable {
    var count = 0
    var sourceBytes: Int64 = 0
    var predictedBytes: Int64 = 0
    var seconds: Double = 0
    /// Distinct "before → after" sizes, most common first (one entry when they all match).
    var sizes: [ResolutionChange] = []
    var anyLimited = false

    struct ResolutionChange: Hashable {
        let from: CGSize
        let to: CGSize
    }

    var growth: Double? {
        guard count > 0, sourceBytes > 0 else { return nil }
        return Double(predictedBytes) / Double(sourceBytes) - 1
    }

    init() {}

    init(plans: [UpscalePlan]) {
        count = plans.count
        sourceBytes = plans.reduce(0) { $0 + $1.sourceBytes }
        predictedBytes = plans.reduce(0) { $0 + $1.predictedBytes }
        seconds = plans.reduce(0) { $0 + $1.estimatedSeconds }
        anyLimited = plans.contains(where: \.isLimited)
        let changes = plans.map { ResolutionChange(from: $0.sourceSize, to: $0.outputSize) }
        let counts = Dictionary(changes.map { ($0, 1) }, uniquingKeysWith: +)
        sizes = counts.sorted { $0.value > $1.value }.map(\.key)
    }
}

extension AppModel {
    /// Whether this build has the Upscayl backend.
    static let upscaleAvailable = UpscaleBackend.bundled() != nil

    /// The selected videos, or every video, that are analysed.
    var upscaleTargets: [SourceItem] {
        let ids = Set(inspectorTargetIDs)
        return sources.filter { ids.contains($0.id) && $0.info != nil }
    }

    var upscaleEstimate: UpscaleEstimate {
        UpscaleEstimate(plans: upscaleTargets.compactMap { item in
            item.info.map { UpscalePlan(info: $0, settings: upscaleSettings) }
        })
    }

    func upscalePlan(for item: SourceItem) -> UpscalePlan? {
        item.info.map { UpscalePlan(info: $0, settings: upscaleSettings) }
    }

    /// A video's settings as queued: in AI Upscale mode they carry the upscale choices
    /// and go to MP4 or MOV.
    func jobSettings(for item: SourceItem) -> EncodeSettings {
        guard mode == .upscale else { return item.settings }
        var settings = item.settings
        settings.upscale = upscaleSettings
        settings.container = item.settings.container == .mov ? .mov : .mp4
        return settings
    }

    /// "AI Upscale · 2× · Fast", shown on the job and in History.
    var upscaleJobName: String {
        let model = String(localized: String.LocalizationValue(upscaleSettings.model.displayName))
        return String(localized: "AI Upscale · \(upscaleSettings.scale.displayName) · \(model)")
    }
}
