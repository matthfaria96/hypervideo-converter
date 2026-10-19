import CoreGraphics
import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Workspace", .serialized)
struct WorkspaceTests {
    /// A source that looks inspected, without a real file.
    static func source(_ name: String, bytes: Int64 = 100_000_000, duration: Double = 100,
                       settings: EncodeSettings = QualityProfile.balanced.settings) -> SourceItem {
        let url = URL(fileURLWithPath: "/tmp/hvc-missing-\(UUID().uuidString)/\(name)")
        var item = SourceItem(url: url, settings: settings, presetID: QualityProfile.balanced.presetID)
        item.info = MediaInfo(url: url, duration: duration, displaySize: CGSize(width: 1920, height: 1080), frameRate: 30,
                              videoCodec: "H.264", videoBitrate: 8_000_000, dynamicRange: .sdr,
                              audioTracks: [AudioTrackInfo(id: 2, codec: "AAC", channels: 2, sampleRate: 48_000, language: "en")],
                              fileBytes: bytes)
        return item
    }

    // MARK: Quality profiles

    @Test func profilesMapToRealSettings() {
        let balanced = QualityProfile.balanced.settings
        #expect(balanced.videoCodec == .h264 && balanced.rateControl == .quality(0.62) && balanced.container == .mp4)
        #expect(QualityProfile.highQuality.settings.rateControl == .quality(0.85))
        let small = QualityProfile.smallerFile.settings
        #expect(small.videoCodec == .hevc && small.maxResolution == .fhd1080 && small.audioBitrateKbps == 128)
        let original = QualityProfile.keepOriginal.settings
        #expect(original.maxResolution == .source && original.frameRate == .source && original.audioCodec == .passthrough)
        #expect(QualityProfile.allCases.allSatisfy { $0.settings.isValid })
    }

    @Test func profilesAreBuiltInPresetsWithUniqueIDs() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        let ids = model.presets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for profile in QualityProfile.allCases {
            #expect(model.presets.preset(id: profile.presetID)?.name == profile.name)
            #expect(QualityProfile.profile(presetID: profile.presetID) == profile)
        }
        // With no default chosen, new videos get the balanced profile.
        #expect(model.defaultPreset.id == QualityProfile.balanced.presetID)
    }

    @Test func applyingAProfileKeepsFormatAndPerVideoEdits() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        var item = Self.source("a.mov")
        item.settings.container = .mkv
        item.settings.trim = TrimRange(start: 5, end: 20)
        model.setSources([item])
        model.applyProfile(.smallerFile)
        let settings = try #require(model.sources.first?.settings)
        #expect(settings.container == .mkv)
        #expect(settings.trim == TrimRange(start: 5, end: 20))
        #expect(settings.videoCodec == .hevc && settings.maxResolution == .fhd1080)
        #expect(model.sources.first?.presetID == QualityProfile.smallerFile.presetID)
        #expect(model.inspectorProfile == .smallerFile)
    }

    @Test func codecAndFormatChoicesStayValid() {
        var settings = QualityProfile.balanced.settings
        settings = settings.choosing(codec: .proRes422)
        #expect(settings.container == .mov && settings.isValid)
        settings = settings.choosing(container: .mp4)
        #expect(settings.videoCodec == .hevc && settings.isValid)
        #expect(settings.choosing(container: .mkv).videoCodec == .hevc)
    }

    // MARK: Inspector targets

    @Test func inspectorEditsAllVideosWhenNoneIsSelected() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        model.setSources([Self.source("a.mov"), Self.source("b.mov")])
        #expect(!model.inspectsSelection)
        model.editTargets { $0.keepMetadata = false }
        #expect(model.sources.allSatisfy { !$0.settings.keepMetadata })
    }

    @Test func inspectorEditsOnlyTheSelection() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        let a = Self.source("a.mov"), b = Self.source("b.mov"), c = Self.source("c.mov")
        model.setSources([a, b, c])
        model.selectedIDs = [b.id]
        #expect(model.inspectsSelection)
        #expect(model.inspectorTargetIDs == [b.id])
        #expect(model.selectedSource?.id == b.id)
        model.editTargets { $0 = $0.choosing(container: .mov) }
        #expect(model.sources.map(\.settings.container) == [.mp4, .mov, .mp4])
        model.applyProfile(.highQuality)
        #expect(model.sources.map(\.presetID) == [QualityProfile.balanced.presetID, QualityProfile.highQuality.presetID,
                                                  QualityProfile.balanced.presetID])
    }

    @Test func emptyListEditsTheDraftForNewVideos() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        model.applyProfile(.highQuality)
        model.editTargets { $0.keepMetadata = false }
        #expect(model.inspectorProfile == .highQuality)
        let item = model.newSource(url: URL(fileURLWithPath: "/tmp/x.mov"), preset: model.defaultPreset, usesDraft: true)
        #expect(item.presetID == QualityProfile.highQuality.presetID)
        #expect(item.settings.rateControl == .quality(0.85) && !item.settings.keepMetadata)
    }

    // MARK: Compress mode

    @Test func compressModeSetsCompactMP4() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        var item = Self.source("a.mov")
        item.settings = QualityProfile.balanced.settings.choosing(codec: .proRes422)
        model.setSources([item])
        model.setMode(.compress)
        let settings = try #require(model.sources.first?.settings)
        #expect(model.mode == .compress && model.section == .conversion)
        #expect(settings.container == .mp4 && settings.videoCodec == .hevc && settings.isValid)
        #expect(model.inspectorProfile == .balanced)
    }

    @Test func compressModeAppliesToVideosAddedLater() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        model.setMode(.compress)
        let item = model.newSource(url: URL(fileURLWithPath: "/tmp/x.mov"), preset: model.defaultPreset, usesDraft: true)
        #expect(item.settings == QualityProfile.compressSettings)
    }

    // MARK: Converting, history and progress

    @Test func convertAllMovesReadyVideosIntoTheQueue() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        var notReady = Self.source("pending.mov")
        notReady.info = nil
        let ready = Self.source("ready.mov")
        model.setSources([ready, notReady])
        model.selectedIDs = [ready.id]
        model.queue.pause()
        model.convertAll()
        #expect(model.sources.map(\.id) == [notReady.id])
        #expect(model.queue.jobs.count == 1)
        #expect(model.selectedIDs.isEmpty)
        model.queue.cancelAll()
    }

    @Test func historyHoldsFinishedJobsNewestFirst() throws {
        let env = try TestEnvironment()
        func job(_ name: String, _ state: JobState) throws -> EncodeJob {
            // Waiting jobs whose source is gone fail on load, so the sources must exist.
            try Data().write(to: env.root.appendingPathComponent("\(name).mov"))
            return EncodeJob(source: env.root.appendingPathComponent("\(name).mov"),
                      destination: env.output.appendingPathComponent("\(name).mp4"),
                      settings: EncodeSettings(), presetName: "Test").with(state: state)
        }
        let jobs = [try job("done", .completed(outputBytes: 10, elapsed: 1)), try job("waiting", .queued),
                    try job("failed", .failed(message: "x")), try job("stopped", .cancelled)]
        try JSONEncoder().encode(jobs).write(to: env.support.appendingPathComponent("queue.json"))
        let model = env.makeModel()
        #expect(model.historyJobs.map(\.source.lastPathComponent) == ["stopped.mov", "failed.mov", "done.mov"])
        #expect(model.activeJobs.map(\.source.lastPathComponent) == ["waiting.mov"])
        model.queue.retry(model.historyJobs[1].id)
        #expect(model.activeJobs.count == 2 && model.historyJobs.count == 2)
    }

    @Test func editingAWaitingJobBringsItBack() throws {
        let env = try TestEnvironment()
        try Data().write(to: env.root.appendingPathComponent("w.mov"))
        let waiting = EncodeJob(source: env.root.appendingPathComponent("w.mov"), destination: env.output.appendingPathComponent("w.mp4"),
                                settings: QualityProfile.smallerFile.settings, presetName: "Smaller File")
        try JSONEncoder().encode([waiting]).write(to: env.support.appendingPathComponent("queue.json"))
        let model = env.makeModel()
        model.editJob(waiting.id)
        #expect(model.queue.jobs.isEmpty)
        #expect(model.sources.first?.settings == QualityProfile.smallerFile.settings)
        #expect(model.sources.first?.presetID == QualityProfile.smallerFile.presetID)
    }

    @Test func progressCountsFilesOfTheRun() {
        let progress = QueueProgress(finished: 2, running: [0.5], waiting: 1)
        #expect(progress.total == 4 && progress.current == 3)
        #expect(abs(progress.fraction - 0.625) < 0.0001)
        #expect(QueueProgress(finished: 0, running: [], waiting: 0).fraction == 0)
    }

    @Test func sizeEstimateUsesTheCoreModel() {
        var bitrate = QualityProfile.balanced.settings
        bitrate.rateControl = .averageBitrate(4_000)
        bitrate.audioBitrateKbps = 160
        let estimate = SizeEstimate([Self.source("a.mov", settings: bitrate)])
        // (4000 + 160) kbit/s for 100 s = 52 MB, from 100 MB.
        #expect(estimate.estimatedBytes == 52_000_000)
        #expect(abs((estimate.savings ?? 0) - 0.48) < 0.0001)
        // Constant quality depends on the content: no number is made up.
        #expect(SizeEstimate([Self.source("b.mov")]).estimatedBytes == nil)
        #expect(SizeEstimate([]).count == 0)
    }

    @Test func sourcesReorder() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        let a = Self.source("a.mov"), b = Self.source("b.mov"), c = Self.source("c.mov")
        model.setSources([a, b, c])
        model.moveSource(c.id, onto: a.id)
        #expect(model.sources.map(\.id) == [c.id, a.id, b.id])
        model.moveSource(c.id, .down)
        #expect(model.sources.map(\.id) == [a.id, c.id, b.id])
        #expect(!model.canMoveSource(a.id, .up))
    }
}
