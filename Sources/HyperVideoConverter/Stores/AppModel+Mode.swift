import Foundation
import HyperVideoCore

/// Convert mode's settings, kept while Compress mode is on.
struct ModeSnapshot: Equatable {
    var sources: [UUID: Saved]
    var draftSettings: EncodeSettings?
    var draftPresetID: UUID?

    struct Saved: Equatable {
        var settings: EncodeSettings
        var presetID: UUID?
    }
}

/// Compress mode, the finished-run banner, confirmations and the Convert button.
extension AppModel {
    // MARK: Mode

    /// Compress mode gives every video (and the next ones) the compact MP4 profile,
    /// after saving their Convert settings; going back to Convert restores them.
    func setMode(_ newMode: WorkMode) {
        section = .conversion
        guard newMode != mode else { return }
        let old = mode
        mode = newMode
        // Only Compress rewrites the videos' settings; Convert and AI Upscale share them.
        if old == .compress { leaveCompress() }
        if newMode == .compress { enterCompress() }
    }

    private func enterCompress() {
        convertSnapshot = ModeSnapshot(
            sources: Dictionary(uniqueKeysWithValues: sources.map { ($0.id, .init(settings: $0.settings, presetID: $0.presetID)) }),
            draftSettings: draftSettings, draftPresetID: draftPresetID
        )
        let profile = QualityProfile.balanced
        let template = profile.settings(compress: true)
        draftSettings = draftBase.applyingProfile(template).choosing(container: .mp4)
        draftPresetID = profile.compressPresetID
        setSources(sources.map { item in
            var copy = item
            copy.settings = item.settings.applyingProfile(template).choosing(container: .mp4)
            copy.presetID = profile.compressPresetID
            return copy
        })
    }

    private func leaveCompress() {
        let snapshot = convertSnapshot ?? ModeSnapshot(sources: [:])
        convertSnapshot = nil
        draftSettings = snapshot.draftSettings
        draftPresetID = snapshot.draftPresetID
        let fallback = defaultPreset
        setSources(sources.map { item in
            var copy = item
            if let saved = snapshot.sources[item.id] {
                copy.settings = item.settings.copyingAll(from: saved.settings)
                copy.presetID = saved.presetID
            } else {
                // Added while compressing: it gets what new videos get in Convert mode.
                copy.settings = item.settings.copyingAll(from: draftSettings ?? fallback.settings.presetSettings)
                copy.presetID = draftSettings == nil ? fallback.id : draftPresetID
            }
            return copy
        })
    }

    // MARK: Selection

    var allSourcesSelected: Bool { !sources.isEmpty && sources.allSatisfy { selectedIDs.contains($0.id) } }

    /// "Select All" / "Deselect All".
    func toggleSelectAll() {
        selectedIDs = allSourcesSelected ? [] : Set(sources.map(\.id))
    }

    func removeSelectedSources() {
        let ids = selectedIDs
        setSources(sources.filter { !ids.contains($0.id) })
        selectedIDs = []
    }

    // MARK: Confirmations

    /// What "Clear List" removes: videos being set up and jobs still waiting.
    var clearListCounts: (videos: Int, waiting: Int) {
        (sources.count, queue.pendingCount)
    }

    var canClearList: Bool { clearListCounts.videos + clearListCounts.waiting > 0 }

    var clearListMessage: String {
        let (videos, waiting) = clearListCounts
        let parts = [
            videos == 0 ? nil : videos == 1 ? String(localized: "1 video from the list") : String(localized: "\(videos) videos from the list"),
            waiting == 0 ? nil : waiting == 1 ? String(localized: "1 waiting conversion") : String(localized: "\(waiting) waiting conversions")
        ].compactMap { $0 }
        return String(localized: "Removes \(parts.joined(separator: " + ")). Your original files aren't deleted.")
    }

    var clearHistoryMessage: String {
        let count = historyJobs.count
        let items = count == 1 ? String(localized: "1 item") : String(localized: "\(count) items")
        return String(localized: "Removes \(items) from History. Converted files stay where they are.")
    }

    /// "Apply to All" overwrites the other videos' settings.
    func applyToAllMessage(from id: UUID) -> String {
        let others = sources.filter { $0.id != id }.count
        let videos = others == 1 ? String(localized: "1 other video") : String(localized: "\(others) other videos")
        return String(localized: "Gives \(videos) these settings. Each keeps its own trim, crop, burned-in subtitle, track lists, chapter names and title.")
    }

    // MARK: Finished run

    /// Videos converted since the last Convert press, once nothing is left to do.
    var finishedBatch: (count: Int, folder: URL)? {
        guard let start = ui.batchStartedAt, queue.runningCount == 0, queue.pendingCount == 0 else { return nil }
        let done = queue.jobs.filter { job in
            if case .completed = job.state { return job.createdAt >= start }
            return false
        }
        guard let last = done.last else { return nil }
        return (done.count, last.destination.deletingLastPathComponent())
    }

    func dismissFinishedBatch() { ui.batchStartedAt = nil }

    // MARK: Convert button

    /// Why Convert is disabled, nil when it can run.
    var convertBlockedReason: String? {
        if mode == .upscale && !Self.upscaleAvailable { return String(localized: "The AI engine isn't included in this build") }
        if readySourceCount > 0 || queue.runningCount > 0 { return nil }
        if queue.pendingCount > 0 { return nil }
        if sources.isEmpty { return String(localized: "Add videos to start") }
        if sources.contains(where: \.isLoading) { return String(localized: "Analyzing the videos…") }
        return String(localized: "Check the settings of the videos in the list")
    }

    var convertButtonTitle: String {
        let count = readySourceCount
        if count == 0 && queue.pendingCount > 0 { return String(localized: "Start Queue") }
        switch (mode, count) {
        case (.upscale, 1): return String(localized: "Upscale 1 Video")
        case (.upscale, let n) where n > 1: return String(localized: "Upscale \(n) Videos")
        case (.upscale, _): return String(localized: "Upscale Videos")
        case (.compress, 1): return String(localized: "Compress 1 Video")
        case (.compress, let n) where n > 1: return String(localized: "Compress \(n) Videos")
        case (.compress, _): return String(localized: "Compress Videos")
        case (.convert, 1): return String(localized: "Convert 1 Video")
        case (.convert, let n) where n > 1: return String(localized: "Convert \(n) Videos")
        case (.convert, _): return String(localized: "Convert Videos")
        }
    }
}
