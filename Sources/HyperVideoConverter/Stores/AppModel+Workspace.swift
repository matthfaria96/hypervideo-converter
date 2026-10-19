import Foundation
import HyperVideoCore

/// The conversion workspace: the list of videos and jobs, the output inspector's
/// targets, Compress mode and the Convert button.
extension AppModel {
    // MARK: New sources

    /// A source with `preset`'s settings, or with what the inspector set while the list
    /// was empty (`usesDraft`, for loose files).
    func newSource(url: URL, preset: Preset, usesDraft: Bool = false) -> SourceItem {
        if usesDraft, let draftSettings {
            return SourceItem(url: url, settings: draftSettings, presetID: draftPresetID)
        }
        return SourceItem(url: url, settings: preset.settings.presetSettings, presetID: preset.id)
    }

    // MARK: Inspector targets

    /// Whether the inspector edits only the selected videos (else every video).
    var inspectsSelection: Bool { sources.contains { selectedIDs.contains($0.id) } }

    /// The sources the output inspector edits: the selected ones, or all when none is selected.
    var inspectorTargetIDs: [UUID] {
        let selected = sources.filter { selectedIDs.contains($0.id) }.map(\.id)
        return selected.isEmpty ? sources.map(\.id) : selected
    }

    /// The settings the inspector shows: the first target's, or the default preset's.
    var inspectorSettings: EncodeSettings {
        let first = inspectorTargetIDs.first.flatMap { id in sources.first { $0.id == id } }
        return first?.settings ?? draftSettings ?? defaultPreset.settings.presetSettings
    }

    /// The profile the inspector highlights, when every target was set from the same one.
    var inspectorProfile: QualityProfile? {
        let targets = sources.filter { inspectorTargetIDs.contains($0.id) }
        guard let first = targets.first, targets.allSatisfy({ $0.presetID == first.presetID }) else {
            return targets.isEmpty ? QualityProfile.profile(presetID: draftSettings == nil ? defaultPreset.id : draftPresetID) : nil
        }
        return QualityProfile.profile(presetID: first.presetID)
    }

    /// Applies one inspector edit to every target, keeping each one's other settings.
    func editTargets(_ change: (inout EncodeSettings) -> Void) {
        guard !sources.isEmpty else {
            var draft = inspectorSettings
            change(&draft)
            draftPresetID = draftSettings == nil ? defaultPreset.id : draftPresetID
            draftSettings = draft
            return
        }
        let ids = Set(inspectorTargetIDs)
        setSources(sources.map { item in
            guard ids.contains(item.id) else { return item }
            var copy = item
            change(&copy.settings)
            return copy
        })
    }

    /// Gives the targets `profile`'s settings, keeping their output format and per-video edits.
    func applyProfile(_ profile: QualityProfile) {
        guard !sources.isEmpty else {
            draftSettings = Self.profileSettings(profile, over: inspectorSettings)
            draftPresetID = profile.presetID
            return
        }
        let ids = Set(inspectorTargetIDs)
        setSources(sources.map { item in
            guard ids.contains(item.id) else { return item }
            var copy = item
            copy.settings = Self.profileSettings(profile, over: item.settings)
            copy.presetID = profile.presetID
            return copy
        })
    }

    /// `profile`'s settings, keeping the output format, metadata choice and per-video edits of `current`.
    static func profileSettings(_ profile: QualityProfile, over current: EncodeSettings) -> EncodeSettings {
        var settings = current.adopting(profile.settings)
        settings.container = current.container
        settings.keepMetadata = current.keepMetadata
        return settings.fixingCodecForContainer()
    }

    func applyPresetToTargets(_ preset: Preset) {
        inspectorTargetIDs.forEach { applyPreset(preset, to: $0) }
    }

    // MARK: Mode

    /// Compress mode resets the targets to the compact MP4 settings, like the prototype.
    func setMode(_ newMode: WorkMode) {
        mode = newMode
        section = .conversion
        guard newMode == .compress else { return }
        guard !sources.isEmpty else {
            draftSettings = QualityProfile.compressSettings
            draftPresetID = QualityProfile.balanced.presetID
            return
        }
        let ids = Set(inspectorTargetIDs)
        setSources(sources.map { item in
            guard ids.contains(item.id) else { return item }
            var copy = item
            copy.settings = item.settings.adopting(QualityProfile.compressSettings)
            copy.presetID = QualityProfile.balanced.presetID
            return copy
        })
    }

    // MARK: Converting

    var readySourceCount: Int { sources.filter { $0.info != nil && $0.settings.isValid }.count }

    /// Queues every ready video, takes it off the editing list and starts the queue.
    func convertAll() {
        let queued = Set(enqueueSources(sources.map(\.id)))
        if !queued.isEmpty {
            for item in sources where queued.contains(item.id) {
                if let image = item.thumbnail { ui.thumbnails[item.url] = image }
            }
            setSources(sources.filter { !queued.contains($0.id) })
            selectedIDs.subtract(queued)
        }
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
        let preset = presets.all.first { $0.displayName == job.presetName || $0.name == job.presetName }
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
        if queue.runningCount > 0 { return String(localized: "Processing…") }
        let count = sources.count + queue.pendingCount
        return count == 0 ? String(localized: "Ready to convert") : String(localized: "\(count) videos in the queue")
    }
}

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
        return copy
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
                  running: queue.jobs.compactMap { if case .running(let p) = $0.state { p } else { nil } },
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

/// Size of the inspector's targets before and after, from the core's estimate model.
struct SizeEstimate: Equatable {
    /// Inspected videos counted.
    var count: Int
    var originalBytes: Int64
    /// Nil when any video's size depends on its content (constant quality).
    var estimatedBytes: Int64?

    /// Fraction saved (negative when the output is larger).
    var savings: Double? {
        guard let estimatedBytes, originalBytes > 0 else { return nil }
        return 1 - Double(estimatedBytes) / Double(originalBytes)
    }

    init(count: Int, originalBytes: Int64, estimatedBytes: Int64?) {
        self.count = count
        self.originalBytes = originalBytes
        self.estimatedBytes = estimatedBytes
    }

    init(_ items: [SourceItem]) {
        let inspected = items.compactMap { item in item.info.map { (info: $0, settings: item.settings) } }
        let estimates = inspected.map { OutputEstimate.bytes(info: $0.info, settings: $0.settings) }
        self.init(count: inspected.count,
                  originalBytes: inspected.reduce(0) { $0 + $1.info.fileBytes },
                  estimatedBytes: estimates.contains(nil) || estimates.isEmpty ? nil : estimates.compactMap { $0 }.reduce(0, +))
    }
}

extension AppModel {
    var sizeEstimate: SizeEstimate {
        let ids = Set(inspectorTargetIDs)
        return SizeEstimate(sources.filter { ids.contains($0.id) })
    }
}
