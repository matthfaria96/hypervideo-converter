import Foundation
import HyperVideoCore

/// Quality profile and size estimate of one video, for its Summary tab (panel or
/// Advanced sheet). Unlike the inspector's versions, these never touch other videos
/// or the draft for videos added later.
extension AppModel {
    /// The profile card to highlight for video `id`: the one it was set from, while
    /// its settings still match it.
    func profile(of id: UUID) -> QualityProfile? {
        guard let item = sources.first(where: { $0.id == id }),
              let profile = QualityProfile.profile(presetID: item.presetID) else { return nil }
        let compress = QualityProfile.isCompressPreset(item.presetID)
        return item.settings.matchesProfile(profile.settings(compress: compress)) ? profile : nil
    }

    /// Gives video `id` the profile's fields, keeping its format, metadata and advanced settings.
    func applyProfile(_ profile: QualityProfile, to id: UUID) {
        let compress = mode == .compress
        let template = profile.settings(compress: compress)
        let presetID = profile.presetID(compress: compress)
        update(id) { item in
            item.settings = item.settings.applyingProfile(template)
            item.presetID = presetID
        }
    }

    /// Size before and after for video `id` alone.
    func sizeEstimate(for id: UUID) -> SizeEstimate {
        SizeEstimate(sources.filter { $0.id == id })
    }
}
