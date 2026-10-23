import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Workspace UX rules", .serialized)
struct UXLogicTests {
    private func source(_ name: String) -> SourceItem { WorkspaceTests.source(name) }

    // MARK: Compress mode

    @Test func compressRestoresConvertSettingsOnLeaving() throws {
        let model = try TestEnvironment().makeModel()
        var a = source("a.mov")
        a.settings.container = .mkv
        a.settings.rateControl = .quality(0.8)
        model.setSources([a])
        model.editTargets { $0.keepMetadata = false }
        let before = try #require(model.sources.first)
        let draftBefore = model.draftSettings

        model.setMode(.compress)
        let compressed = try #require(model.sources.first)
        #expect(compressed.settings.videoCodec == .hevc && compressed.settings.container == .mp4)
        #expect(!compressed.settings.keepMetadata, "compress keeps the metadata choice")
        #expect(model.presetName(for: compressed) == "Balanced Compression")

        model.setMode(.convert)
        let restored = try #require(model.sources.first)
        #expect(restored.settings == before.settings && restored.presetID == before.presetID)
        #expect(model.draftSettings == draftBefore)
    }

    @Test func pressingCompressAgainKeepsEdits() throws {
        let model = try TestEnvironment().makeModel()
        model.setSources([source("a.mov")])
        model.setMode(.compress)
        model.editTargets { $0.rateControl = .quality(0.3) }
        model.setMode(.compress)
        #expect(model.sources.first?.settings.rateControl == .quality(0.3))
    }

    @Test func compressAppliesToAllVideosEvenWithSelection() throws {
        let model = try TestEnvironment().makeModel()
        let a = source("a.mov"), b = source("b.mov")
        model.setSources([a, b])
        model.selectedIDs = [a.id]
        model.setMode(.compress)
        #expect(model.sources.allSatisfy { $0.settings.videoCodec == .hevc })
        let added = model.newSource(url: URL(fileURLWithPath: "/tmp/new.mov"), preset: model.defaultPreset, usesDraft: true)
        #expect(added.settings.videoCodec == .hevc && added.presetID == QualityProfile.balanced.compressPresetID)
        let fromFolder = model.newSource(url: URL(fileURLWithPath: "/tmp/f.mov"), preset: QualityProfile.highQuality.preset)
        #expect(fromFolder.settings.videoCodec == .hevc && fromFolder.settings.container == .mp4)
    }

    @Test func compressShowsPersonalizedOnlyAfterRealChange() throws {
        let model = try TestEnvironment().makeModel()
        model.setSources([source("a.mov")])
        model.setMode(.compress)
        #expect(model.inspectorProfile == .balanced && model.inspectorPersonalizedProfile == nil)
        model.editTargets { $0.maxResolution = .hd720 }
        #expect(model.inspectorProfile == nil && model.inspectorPersonalizedProfile == .balanced)
        let item = try #require(model.sources.first)
        #expect(model.presetName(for: item) == "Balanced Compression (personalized)")
        model.applyProfile(.balanced)
        #expect(model.inspectorProfile == .balanced)
    }

    // MARK: Profiles keep advanced settings

    @Test func profileKeepsAdvancedPerVideoSettings() throws {
        let model = try TestEnvironment().makeModel()
        var a = source("a.mov")
        a.settings.extraAudio = AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 128)
        a.settings.filters.denoise = .medium
        a.settings.rotation = .cw90
        a.settings.flipHorizontal = true
        a.settings.audioTracks = .all
        a.settings.subtitles = .none
        a.settings.keepMetadata = false
        model.setSources([a])
        model.applyProfile(.smallerFile)
        let s = try #require(model.sources.first?.settings)
        #expect(s.videoCodec == .hevc && s.maxResolution == .fhd1080 && s.audioBitrateKbps == 128)
        #expect(s.extraAudio != nil && s.filters.denoise == .medium && s.rotation == .cw90 && s.flipHorizontal)
        #expect(s.audioTracks == .all && s.subtitles == SubtitleSelection.none && !s.keepMetadata)
        #expect(model.inspectorProfile == .smallerFile)
    }

    @Test func favoriteKeepsAdvancedSettingsItDoesNotSet() {
        var current = EncodeSettings()
        current.filters.sharpen = .light
        current.rotation = .cw180
        current.subtitles = .first
        var template = EncodeSettings()
        template.videoCodec = .h264
        let adopted = current.adopting(template)
        #expect(adopted.videoCodec == .h264 && adopted.filters.sharpen == .light)
        #expect(adopted.rotation == .cw180 && adopted.subtitles == .first)
        template.rotation = .cw90
        #expect(current.adopting(template).rotation == .cw90)
    }

    @Test func manualEditClearsProfileHighlight() throws {
        let model = try TestEnvironment().makeModel()
        model.setSources([source("a.mov")])
        #expect(model.inspectorProfile == .balanced)
        model.editTargets { $0.rateControl = .quality(0.9) }
        #expect(model.inspectorProfile == nil)
        #expect(model.inspectorPersonalizedProfile == .balanced)
        // Advanced choices outside the profile don't count as a change.
        model.applyProfile(.balanced)
        model.editTargets { $0.keepMetadata = false }
        #expect(model.inspectorProfile == .balanced)
    }

    // MARK: Draft and jobs

    @Test func editingAllAlsoUpdatesTheDraft() throws {
        let model = try TestEnvironment().makeModel()
        let a = source("a.mov")
        model.setSources([a])
        model.applyProfile(.highQuality)
        #expect(model.draftPresetID == QualityProfile.highQuality.presetID)
        model.selectedIDs = [a.id]
        model.editTargets { $0.rateControl = .quality(0.3) }
        #expect(model.draftSettings?.rateControl == .quality(0.85), "a selection leaves the draft alone")
    }

    @Test func jobsRememberTheirPreset() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        try Data().write(to: env.root.appendingPathComponent("w.mov"))
        var item = source("w.mov")
        item = SourceItem(url: env.root.appendingPathComponent("w.mov"), info: item.info,
                          settings: QualityProfile.smallerFile.settings, presetID: QualityProfile.smallerFile.presetID)
        model.setSources([item])
        model.queue.pause()
        model.enqueue([item.id])
        let job = try #require(model.queue.jobs.first)
        #expect(job.presetID == QualityProfile.smallerFile.presetID)
        model.editJob(job.id)
        #expect(model.sources.last?.presetID == QualityProfile.smallerFile.presetID)
    }

    // MARK: Confirmations and button

    @Test func confirmationsCountWhatIsRemoved() throws {
        let model = try TestEnvironment().makeModel()
        #expect(!model.canClearList)
        model.setSources([source("a.mov"), source("b.mov")])
        #expect(model.clearListCounts.videos == 2 && model.clearListCounts.waiting == 0)
        #expect(model.clearListMessage.contains("2 videos"))
        #expect(model.clearListMessage.contains("original files"))
        #expect(model.applyToAllMessage(from: model.sources[0].id).contains("1 other video"))
        #expect(model.applyToAllMessage(from: model.sources[0].id).contains("track lists, chapter names and title"))
        #expect(model.clearHistoryMessage.contains("0 items"))
    }

    @Test func convertButtonCountsVideos() throws {
        let model = try TestEnvironment().makeModel()
        #expect(model.convertBlockedReason == "Add videos to start")
        model.setSources([source("a.mov"), source("b.mov"), source("c.mov")])
        #expect(model.convertButtonTitle == "Convert 3 Videos" && model.convertBlockedReason == nil)
        model.setMode(.compress)
        #expect(model.convertButtonTitle == "Compress 3 Videos")
        model.toggleSelectAll()
        #expect(model.allSourcesSelected)
        model.removeSelectedSources()
        #expect(model.sources.isEmpty)
    }

    @Test func statusCountsAreSingularAndPlural() {
        #expect(AppModel.queueCountText(1) == "1 video in the list")
        #expect(AppModel.queueCountText(3) == "3 videos in the list")
    }
}
