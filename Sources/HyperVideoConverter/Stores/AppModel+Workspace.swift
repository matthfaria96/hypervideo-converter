import Foundation
import HyperVideoCore

/// The conversion workspace: the list of videos and jobs, the output inspector's
/// targets, Compress mode and the Convert button.
extension AppModel {
    // MARK: New sources

    /// A source with `preset`'s settings, or with the draft (what the inspector set for
    /// the next videos) for loose files. In Compress mode folder videos get compressed too.
    func newSource(url: URL, preset: Preset, usesDraft: Bool = false) -> SourceItem {
        if usesDraft, let draftSettings {
            return SourceItem(url: url, settings: draftSettings, presetID: draftPresetID)
        }
        guard mode == .compress else {
            return SourceItem(url: url, settings: preset.settings.presetSettings, presetID: preset.id)
        }
        let profile = QualityProfile.balanced
        let settings = preset.settings.presetSettings.applyingProfile(profile.settings(compress: true)).choosing(container: .mp4)
        return SourceItem(url: url, settings: settings, presetID: profile.compressPresetID)
    }

    // MARK: Inspector targets

    /// Whether the inspector edits only the selected videos (else every video).
    var inspectsSelection: Bool { sources.contains { selectedIDs.contains($0.id) } }

    /// The sources the output inspector edits: the selected ones, or all when none is selected.
    var inspectorTargetIDs: [UUID] {
        let selected = sources.filter { selectedIDs.contains($0.id) }.map(\.id)
        return selected.isEmpty ? sources.map(\.id) : selected
    }

    /// Settings the next added videos get, and the preset they name.
    var draftBase: EncodeSettings { draftSettings ?? defaultPreset.settings.presetSettings }
    var draftBasePresetID: UUID? { draftSettings == nil ? defaultPreset.id : draftPresetID }

    /// The settings the inspector shows: the first target's, or the draft's.
    var inspectorSettings: EncodeSettings {
        let first = inspectorTargetIDs.first.flatMap { id in sources.first { $0.id == id } }
        return first?.settings ?? draftBase
    }

    /// Settings and preset of every target (the draft when the list is empty).
    private var inspectorTargets: [(settings: EncodeSettings, presetID: UUID?)] {
        let ids = Set(inspectorTargetIDs)
        let targets = sources.filter { ids.contains($0.id) }.map { ($0.settings, $0.presetID) }
        return targets.isEmpty ? [(draftBase, draftBasePresetID)] : targets
    }

    /// The profile every target was set from, edited or not.
    var inspectorBaseProfile: QualityProfile? {
        let profiles = inspectorTargets.map { QualityProfile.profile(presetID: $0.presetID) }
        guard let first = profiles.first, profiles.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// The profile card to highlight: only when every target still has its settings.
    var inspectorProfile: QualityProfile? {
        guard let profile = inspectorBaseProfile else { return nil }
        let unchanged = inspectorTargets.allSatisfy { target in
            let compress = QualityProfile.isCompressPreset(target.presetID)
            return target.settings.matchesProfile(profile.settings(compress: compress))
        }
        return unchanged ? profile : nil
    }

    /// Set when the targets came from a profile but the user changed its settings since.
    var inspectorPersonalizedProfile: QualityProfile? {
        inspectorProfile == nil ? inspectorBaseProfile : nil
    }

    /// Applies one inspector edit to every target, keeping each one's other settings.
    /// With no selection the edit also goes to the draft, so videos added later match.
    func editTargets(_ change: (inout EncodeSettings) -> Void) {
        if !inspectsSelection {
            var draft = draftBase
            change(&draft)
            draftPresetID = draftBasePresetID
            draftSettings = draft
        }
        let ids = Set(inspectorTargetIDs)
        setSources(sources.map { item in
            guard ids.contains(item.id) else { return item }
            var copy = item
            change(&copy.settings)
            return copy
        })
    }

    /// Gives the targets `profile`'s fields (codec, quality, resolution, frame rate,
    /// audio), keeping format, metadata and every advanced per-video setting.
    func applyProfile(_ profile: QualityProfile) {
        let compress = mode == .compress
        let template = profile.settings(compress: compress)
        let presetID = profile.presetID(compress: compress)
        if !inspectsSelection {
            draftSettings = draftBase.applyingProfile(template)
            draftPresetID = presetID
        }
        let ids = Set(inspectorTargetIDs)
        setSources(sources.map { item in
            guard ids.contains(item.id) else { return item }
            var copy = item
            copy.settings = item.settings.applyingProfile(template)
            copy.presetID = presetID
            return copy
        })
    }

    func applyPresetToTargets(_ preset: Preset) {
        if !inspectsSelection {
            draftSettings = draftBase.adopting(preset.settings.presetSettings)
            draftPresetID = preset.id
        }
        let ids = Set(inspectorTargetIDs)
        setSources(sources.map { item in
            guard ids.contains(item.id) else { return item }
            var copy = item
            copy.settings = item.settings.adopting(preset.settings)
            copy.presetID = preset.id
            return copy
        })
    }

    // MARK: Converting

    var readySourceCount: Int { sources.filter { $0.info != nil && $0.settings.isValid }.count }

    /// Queues every ready video, takes it off the editing list and starts the queue.
    func convertAll() {
        ui.batchStartedAt = ui.batchStartedAt ?? Date()
        enqueue(sources.map(\.id))
        if queue.pendingCount > 0 { queue.start() }
    }

    /// Jobs waiting or encoding; finished ones live in History.
    var activeJobs: [EncodeJob] { queue.jobs.filter { !$0.state.isFinished } }

    /// Finished, failed and cancelled jobs, newest first.
    var historyJobs: [EncodeJob] { queue.jobs.filter(\.state.isFinished).reversed() }

    /// Puts a waiting job back on the editing list with its settings, to change them.
    func editJob(_ id: UUID) {
        guard let job = queue.jobs.first(where: { $0.id == id }), job.state == .queued else { return }
        queue.remove([id])
        let preset = presets.preset(id: job.presetID)
            ?? presets.all.first { $0.displayName == job.presetName || $0.name == job.presetName }
        var item = SourceItem(url: job.source, settings: job.settings, presetID: preset?.id)
        item.subtitleFiles = job.subtitleFiles ?? []
        setSources(sources + [item])
        selectedIDs = [item.id]
        Task { await inspect(item) }
    }

    /// Clears the editing list and every waiting job; running encodes keep going.
    func clearWorkspace() {
        clearSources()
        queue.remove(Set(queue.jobs.filter { $0.state == .queued }.map(\.id)))
    }

    // MARK: Ordering sources

    func moveSource(_ id: UUID, onto target: UUID) {
        guard id != target, let from = sources.firstIndex(where: { $0.id == id }),
              let to = sources.firstIndex(where: { $0.id == target }) else { return }
        var reordered = sources
        reordered.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        setSources(reordered)
    }

    func canMoveSource(_ id: UUID, _ movement: QueueStore.Movement) -> Bool {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return false }
        return movement == .down ? index < sources.count - 1 : index > 0
    }

    func moveSource(_ id: UUID, _ movement: QueueStore.Movement) {
        guard canMoveSource(id, movement), let index = sources.firstIndex(where: { $0.id == id }) else { return }
        var reordered = sources
        switch movement {
        case .up: reordered.move(fromOffsets: [index], toOffset: index - 1)
        case .down: reordered.move(fromOffsets: [index], toOffset: index + 2)
        case .top: reordered.move(fromOffsets: [index], toOffset: 0)
        }
        setSources(reordered)
    }

    // MARK: Status

    var progress: QueueProgress { QueueProgress(queue: queue) }

    var statusText: String {
        let progress = self.progress
        if queue.runningCount > 0 {
            let percent = Int((progress.fraction * 100).rounded())
            return String(localized: "Converting \(progress.current) of \(progress.total) · \(percent)%")
        }
        return Self.queueCountText(sources.count + queue.pendingCount)
    }

    static func queueCountText(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Ready to convert")
        case 1: String(localized: "1 video in the list")
        default: String(localized: "\(count) videos in the list")
        }
    }
}

