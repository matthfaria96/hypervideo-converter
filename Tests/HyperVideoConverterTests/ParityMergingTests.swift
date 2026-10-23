import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@Suite("Parity merging")
struct ParityMergingTests {
    /// A video that carries every per-video value.
    static func perVideo() -> EncodeSettings {
        var s = EncodeSettings()
        s.trim = TrimRange(start: 1, end: 2)
        s.crop = Crop(top: 4, bottom: 4, left: 2, right: 2)
        s.audioOptions.tracks = [AudioTrackSetting(sourceTrackID: 2, encoding: AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 128))]
        s.subtitleOptions.tracks = [SubtitleTrackSetting(sourceTrackID: 3)]
        s.chapterOptions.titles = ["Intro", "End"]
        s.tags.title = "My Movie"
        return s
    }

    /// A template with generic choices plus other tags.
    static func generic() -> EncodeSettings {
        var s = EncodeSettings()
        s.audioOptions.languages = ["eng"]
        s.audioOptions.fallback = .heAAC
        s.pictureOptions.cropMode = .automatic
        s.videoOptions.profile = .high
        s.chapterOptions.markers = true
        s.tags.director = "Someone"
        s.alignAVStart = true
        return s
    }

    @Test func presetSettingsDropsPerVideoData() {
        var s = Self.perVideo()
        s = s.mergedGeneric(from: Self.generic())
        let saved = s.presetSettings
        #expect(saved.audioOptions.tracks.isEmpty && saved.subtitleOptions.tracks.isEmpty)
        #expect(saved.chapterOptions.titles.isEmpty && saved.tags.title == nil)
        #expect(saved.trim == nil && saved.crop.isZero)
        #expect(saved.audioOptions.languages == ["eng"] && saved.audioOptions.fallback == .heAAC)
        #expect(saved.pictureOptions.cropMode == .automatic && saved.videoOptions.profile == .high)
        #expect(saved.chapterOptions.markers == true && saved.tags.director == "Someone" && saved.alignAVStart)
    }

    @Test func adoptingKeepsPerVideoData() {
        let video = Self.perVideo()
        var template = Self.generic()
        template.tags.title = "Template Title"
        template.chapterOptions.titles = ["X"]
        let result = video.adopting(template)
        #expect(result.audioOptions.tracks.map(\.id) == video.audioOptions.tracks.map(\.id))
        #expect(result.audioOptions.tracks == video.retuningAudioTracksTo(template).audioOptions.tracks,
                "the list stays; its encoder and bitrate follow the preset")
        #expect(result.subtitleOptions.tracks == video.subtitleOptions.tracks)
        #expect(result.chapterOptions.titles == ["Intro", "End"] && result.tags.title == "My Movie")
        #expect(result.trim == video.trim && result.crop == video.crop)
        #expect(result.audioOptions.languages == ["eng"] && result.tags.director == "Someone")
        #expect(result.videoOptions.profile == .high && result.alignAVStart)
    }

    @Test func adoptingKeepsAdvancedChoicesTheTemplateLeavesAtDefaults() {
        var video = Self.perVideo()
        video.pictureOptions.cropMode = .conservative
        video.videoOptions.frameRateMode = .variable
        video.videoOptions.profile = .main
        video.videoOptions.level = .l41
        video.audioOptions.languages = ["por"]
        video.subtitleOptions.languages = ["por"]
        video.chapterOptions.markers = false
        video.tags.director = "Mine"
        video.alignAVStart = true
        var template = EncodeSettings()
        template.videoOptions.speed = .quality
        let result = video.adopting(template)
        #expect(result.pictureOptions.cropMode == .conservative)
        #expect(result.videoOptions.frameRateMode == .variable && result.videoOptions.profile == .main)
        #expect(result.videoOptions.level == .l41)
        #expect(result.videoOptions.speed == .quality, "speed always comes from the template")
        #expect(result.audioOptions.languages == ["por"] && result.subtitleOptions.languages == ["por"])
        #expect(result.chapterOptions.markers == false && result.tags.director == "Mine" && result.alignAVStart)
    }

    @Test func adoptingADefaultTemplateKeepsEveryEncoderOption() {
        var video = EncodeSettings()
        video.videoOptions.frameRateMode = .peak
        video.videoOptions.speed = .speed
        video.videoOptions.profile = .high
        video.videoOptions.level = .l42
        // Every field must differ from its default, so a new field can't be missed here.
        let fields = zip(Mirror(reflecting: video.videoOptions).children, Mirror(reflecting: VideoEncoderOptions()).children)
        for (set, standard) in fields {
            #expect("\(set.value)" != "\(standard.value)", "set \(set.label ?? "?") in this test")
        }
        #expect(video.adopting(EncodeSettings()).videoOptions == video.videoOptions)
    }

    @Test func profilesAndPresetsRetuneExplicitAudioTracks() {
        var video = EncodeSettings()
        let own = AudioEncoding(codec: .alac, mixdown: .mono, bitrateKbps: 96, trackName: "Mine")
        video.audioOptions.tracks = [AudioTrackSetting(sourceTrackID: 1, encoding: own)]
        let small = QualityProfile.smallerFile.settings
        let profiled = video.applyingProfile(small)
        let track = profiled.audioOptions.tracks.first?.encoding
        #expect(track?.codec == small.audioCodec && track?.bitrateKbps == small.audioBitrateKbps)
        #expect(track?.mixdown == .mono && track?.trackName == "Mine", "the track keeps its other choices")
        #expect(profiled.matchesProfile(small))
        var template = EncodeSettings()
        template.audioCodec = .heAAC
        template.audioBitrateKbps = 64
        let adopted = video.adopting(template).audioOptions.tracks.first?.encoding
        #expect(adopted?.codec == .heAAC && adopted?.bitrateKbps == 64)
    }

    @Test func copyingAllKeepsPerVideoData() {
        let video = Self.perVideo()
        var template = Self.generic()
        template.tags.title = "Other"
        template.chapterOptions.titles = ["Z"]
        template.audioOptions.tracks = []
        let result = video.copyingAll(from: template)
        #expect(result.audioOptions.tracks == video.audioOptions.tracks)
        #expect(result.subtitleOptions.tracks == video.subtitleOptions.tracks)
        #expect(result.chapterOptions.titles == ["Intro", "End"] && result.tags.title == "My Movie")
        #expect(result.trim == video.trim && result.crop == video.crop)
        #expect(result.audioOptions.languages == ["eng"] && result.tags.director == "Someone")
    }
}

private extension EncodeSettings {
    func retuningAudioTracksTo(_ template: EncodeSettings) -> EncodeSettings {
        var s = self
        s.audioCodec = template.audioCodec
        s.audioBitrateKbps = template.audioBitrateKbps
        return s.retuningAudioTracks()
    }

    /// Test helper: a per-video settings value that also carries the template's generic choices.
    func mergedGeneric(from template: EncodeSettings) -> EncodeSettings {
        var s = template
        s.trim = trim
        s.crop = crop
        s.audioOptions.tracks = audioOptions.tracks
        s.subtitleOptions.tracks = subtitleOptions.tracks
        s.chapterOptions.titles = chapterOptions.titles
        s.tags.title = tags.title
        return s
    }
}
