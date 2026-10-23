import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@Suite("Track list editing")
struct TrackListEditingTests {
    private func info(audio: [Int] = [1, 2], subtitles: [SubtitleTrackInfo] = []) -> MediaInfo {
        MediaInfo(
            url: URL(fileURLWithPath: "/tmp/a.mov"), duration: 10, displaySize: nil, frameRate: nil,
            videoCodec: nil, videoBitrate: nil, dynamicRange: .sdr,
            audioTracks: audio.map { AudioTrackInfo(id: $0, codec: "aac", channels: 2, sampleRate: 48_000, language: nil) },
            subtitleTracks: subtitles, fileBytes: 1)
    }

    private var subs: [SubtitleTrackInfo] {
        [SubtitleTrackInfo(id: 1, kind: .subtitle, format: "Timed Text", language: "eng"),
         SubtitleTrackInfo(id: 2, kind: .subtitle, format: "Timed Text", language: "por"),
         SubtitleTrackInfo(id: 3, kind: .closedCaption, format: "CEA-608", language: nil)]
    }

    @Test func languageListParsesAndFormats() {
        #expect(LanguageList.parse("eng, pt-BR;spa  eng") == ["eng", "pt-BR", "spa"])
        #expect(LanguageList.parse("") == [])
        #expect(LanguageList.format(["eng", "por"]) == "eng, por")
    }

    @Test func addingTracksCyclesThroughSources() {
        let media = info()
        var s = EncodeSettings()
        s = s.addingAudioTrack(from: media)
        s = s.addingAudioTrack(from: media)
        s = s.addingAudioTrack(from: media)
        #expect(s.audioOptions.tracks.map(\.sourceTrackID) == [1, 2, 1])
    }

    @Test func updatingAudioTrackByIDIgnoresRemovedTracks() throws {
        var s = EncodeSettings().addingAllAudioTracks(from: info())
        let first = try #require(s.audioOptions.tracks.first)
        var renamed = first
        renamed.encoding.trackName = "Main"
        s = s.updatingAudioTrack(renamed)
        #expect(s.audioOptions.tracks.first?.encoding.trackName == "Main" && s.audioOptions.tracks.count == 2)
        let removed = s.removingAudioTrack(first.id)
        #expect(removed.updatingAudioTrack(renamed) == removed, "a late write to a removed card changes nothing")
    }

    @Test func defaultEncodingWithoutAudioIsAAC() {
        var s = EncodeSettings()
        s.audioCodec = .none
        #expect(s.defaultTrackEncoding == AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 160))
    }

    @Test func addAllRemoveAndReset() throws {
        let media = info(audio: [1, 2, 3])
        var s = EncodeSettings().addingAudioTrack(from: media)
        s = s.addingAllAudioTracks(from: media)
        #expect(s.audioOptions.tracks.map(\.sourceTrackID) == [1, 2, 3])
        let first = try #require(s.audioOptions.tracks.first)
        s = s.removingAudioTrack(first.id)
        #expect(s.audioOptions.tracks.map(\.sourceTrackID) == [2, 3])
        #expect(s.resettingAudioTracks().audioOptions.tracks.isEmpty)
    }

    @Test func materializesFromSelectionBehavior() {
        var s = EncodeSettings()
        s.container = .mp4
        s.subtitles = .first
        let tracks = s.materializedSubtitleTracks(info: info(subtitles: subs))
        #expect(tracks.map(\.include) == [true, false, false])
        #expect(tracks.allSatisfy { !$0.isDefault })
        s.subtitles = .all
        s.subtitleOptions.languages = ["por"]
        let filtered = s.materializedSubtitleTracks(info: info(subtitles: subs))
        #expect(filtered.filter(\.include).map(\.sourceTrackID) == [2])
    }

    @Test func nonEmptyListGetsMissingTracksAppended() {
        var s = EncodeSettings()
        s.subtitleOptions.tracks = [SubtitleTrackSetting(sourceTrackID: 2, include: true)]
        let tracks = s.materializedSubtitleTracks(info: info(subtitles: subs))
        #expect(tracks.map(\.sourceTrackID) == [2, 1, 3])
        #expect(tracks.map(\.include) == [true, false, false])
    }

    @Test func defaultTrackIsExclusive() {
        var s = EncodeSettings()
        s.container = .mov
        let media = info(subtitles: subs)
        s = s.updatingSubtitleTrack(1, info: media) { $0.isDefault = true }
        s = s.updatingSubtitleTrack(2, info: media) { $0.isDefault = true }
        #expect(s.subtitleOptions.tracks.filter(\.isDefault).map(\.sourceTrackID) == [2])
        #expect(s.resettingSubtitleTracks().subtitleOptions.tracks.isEmpty)
    }

    @MainActor
    @Test func subtitleFileUpdatesStayOnTheirFile() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        let a = URL(fileURLWithPath: "/tmp/a.srt"), b = URL(fileURLWithPath: "/tmp/b.srt")
        var item = SourceItem(url: URL(fileURLWithPath: "/tmp/v.mov"), settings: EncodeSettings())
        item.subtitleFiles = [SubtitleFile(url: a, language: nil), SubtitleFile(url: b, language: nil, isDefault: true)]
        model.setSources([item])
        model.updateSubtitleFile(a, in: item.id) { $0.offsetMs = 500 }
        #expect(model.sources[0].subtitleFiles.map(\.offsetMs) == [500, 0])
        model.updateSubtitleFile(a, in: item.id) { $0.isDefault = true }
        #expect(model.sources[0].subtitleFiles.map(\.isDefault) == [true, false])
    }
}
