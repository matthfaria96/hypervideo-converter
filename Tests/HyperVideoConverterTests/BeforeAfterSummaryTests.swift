import CoreGraphics
import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

/// The Summary's Before → After counts agree with the core's track planners.
@Suite("Before → After summary")
struct BeforeAfterSummaryTests {
    private func info(audio: [AudioTrackInfo] = [], subtitles: [SubtitleTrackInfo] = []) -> MediaInfo {
        MediaInfo(url: URL(fileURLWithPath: "/tmp/a.mov"), duration: 60, displaySize: CGSize(width: 1920, height: 1080),
                  frameRate: 30, videoCodec: "H.264", videoBitrate: 8_000_000, dynamicRange: .sdr,
                  audioTracks: audio, subtitleTracks: subtitles, fileBytes: 1_000)
    }

    private let subs = [
        SubtitleTrackInfo(id: 3, kind: .subtitle, format: "Timed Text", language: "en"),
        SubtitleTrackInfo(id: 4, kind: .subtitle, format: "Timed Text", language: "pt"),
        SubtitleTrackInfo(id: 5, kind: .closedCaption, format: "CEA-608", language: "en")
    ]

    @Test func explicitSubtitleListCountsOnlyIncludedTracks() {
        var settings = EncodeSettings()
        settings.subtitles = .all
        settings.container = .mp4
        settings.subtitleOptions.tracks = [
            SubtitleTrackSetting(sourceTrackID: 3, include: true),
            SubtitleTrackSetting(sourceTrackID: 4, include: false),
            SubtitleTrackSetting(sourceTrackID: 5, include: true)
        ]
        #expect(settings.keptSubtitleTrackCount(info: info(subtitles: subs)) == 1, "captions don't fit in MP4")
    }

    @Test func behaviourSubtitlesFollowLanguages() {
        var settings = EncodeSettings()
        settings.subtitles = .all
        settings.container = .mov
        settings.subtitleOptions.languages = ["pt"]
        #expect(settings.keptSubtitleTrackCount(info: info(subtitles: subs)) == 1)
        settings.subtitleOptions.languages = []
        #expect(settings.keptSubtitleTrackCount(info: info(subtitles: subs)) == 3)
        settings.subtitles = .first
        #expect(settings.keptSubtitleTrackCount(info: info(subtitles: subs)) == 1)
    }

    @Test func singleExplicitAudioTrackUsesItsOwnEncoding() {
        let audio = [AudioTrackInfo(id: 2, codec: "AAC", channels: 2, sampleRate: 48_000, language: "en")]
        var settings = EncodeSettings()
        let own = AudioEncoding(codec: .heAAC, mixdown: .mono, bitrateKbps: 64)
        settings.audioOptions.tracks = [AudioTrackSetting(sourceTrackID: 2, encoding: own),
                                        AudioTrackSetting(sourceTrackID: 99, encoding: own)]
        #expect(settings.explicitAudioEncodings(info: info(audio: audio)) == [own], "unknown source tracks are dropped")
        settings.audioOptions.tracks = []
        #expect(settings.explicitAudioEncodings(info: info(audio: audio)) == nil)
    }
}
