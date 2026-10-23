@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Subtitle parity")
struct SubtitleParityTests {
    private let sources = [
        SubtitleSourceTrack(id: 1, kind: .subtitle, language: "en", forcedOnly: false),
        SubtitleSourceTrack(id: 2, kind: .subtitle, language: "pt", forcedOnly: false),
        SubtitleSourceTrack(id: 3, kind: .closedCaption, language: "en", forcedOnly: false)
    ]

    private func plan(
        _ sources: [SubtitleSourceTrack]? = nil, files: [SubtitleFile] = [],
        container: ContainerFormat = .mp4, configure: (inout EncodeSettings) -> Void = { _ in }
    ) -> SubtitlePlan {
        var settings = EncodeSettings()
        settings.container = container
        configure(&settings)
        return SubtitleTrackPlanner.plan(sources: sources ?? self.sources, files: files, settings: settings)
    }

    @Test func defaultsKeepSupportedTracks() {
        let result = plan()
        #expect(result.entries.map(\.sourceTrackID) == [1, 2])
        #expect(result.trackLimit == nil)
        #expect(result.entries.allSatisfy { !$0.isDefault && !$0.forced && $0.name == nil })
        #expect(result.defaultFileURL == nil)
    }

    @Test func firstLimitsAndNoneDropsTracks() {
        #expect(plan { $0.subtitles = .first }.trackLimit == 1)
        #expect(plan { $0.subtitles = .none }.entries.isEmpty)
    }

    @Test func languageFilterAndBurnIn() {
        #expect(plan { $0.subtitleOptions.languages = ["por"] }.entries.map(\.sourceTrackID) == [2])
        #expect(plan { $0.burnIn = .track(id: 2) }.entries.map(\.sourceTrackID) == [1])
    }

    @Test func explicitListDrivesEntries() {
        let result = plan(container: .mov) {
            $0.subtitleOptions.tracks = [
                SubtitleTrackSetting(sourceTrackID: 3, isDefault: true),
                SubtitleTrackSetting(sourceTrackID: 1, include: false),
                SubtitleTrackSetting(sourceTrackID: 2, isDefault: true, name: "Português")
            ]
        }
        #expect(result.entries.map(\.sourceTrackID) == [2, 3])
        #expect(result.entries.map(\.isDefault) == [true, false])
        #expect(result.entries.first?.name == "Português")
    }

    @Test func noneOverridesExplicitList() {
        let result = plan {
            $0.subtitles = .none
            $0.subtitleOptions.tracks = [SubtitleTrackSetting(sourceTrackID: 1, isDefault: true)]
        }
        #expect(result.entries.isEmpty)
    }

    @Test func closedCaptionIsNeverDefault() {
        let result = plan(container: .mov) {
            $0.subtitleOptions.tracks = [
                SubtitleTrackSetting(sourceTrackID: 3, isDefault: true),
                SubtitleTrackSetting(sourceTrackID: 1)
            ]
        }
        #expect(result.entries.map(\.sourceTrackID) == [1, 3])
        #expect(result.entries.allSatisfy { !$0.isDefault })
    }

    @Test func groupIgnoresDefaultOutsideInputs() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, ParityClip.Spec(frameTimes: [0]))
        let url = dir.appendingPathComponent("group.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let format = try #require(TimedText.format(mediaType: kCMMediaType_Subtitle))
        let inputs = (0..<2).map { _ in AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: format) }
        let caption = AVAssetWriterInput(mediaType: .closedCaption, outputSettings: nil)
        (inputs + [caption]).forEach { if writer.canAdd($0) { writer.add($0) } }
        let asset = AVURLAsset(url: source)
        let reader = try AVAssetReader(asset: asset)
        let factory = PipelineFactory(asset: asset, reader: reader, writer: writer, settings: EncodeSettings(), subtitleFiles: [])
        factory.groupAlternates(inputs, defaultInput: caption)
        #expect(inputs.allSatisfy { !$0.marksOutputTrackAsEnabled })
    }

    /// HandBrake's "Forced only" keeps a mixed track and filters its cues; captions can't be filtered.
    @Test func forcedOnlyKeepsTextTracksForCueFiltering() {
        let forced = SubtitleSourceTrack(id: 4, kind: .subtitle, language: "en", forcedOnly: true)
        let result = plan(sources + [forced], container: .mov) {
            $0.subtitleOptions.tracks = [
                SubtitleTrackSetting(sourceTrackID: 1, forcedOnly: true),
                SubtitleTrackSetting(sourceTrackID: 3, forcedOnly: true),
                SubtitleTrackSetting(sourceTrackID: 4, forcedOnly: true)
            ]
        }
        #expect(result.entries.map(\.sourceTrackID) == [1, 4])
        #expect(result.entries.allSatisfy { $0.forced })
    }

    @Test func forcedBoxIsFoundAfterTheText() {
        let text: [UInt8] = [0, 2, 0x48, 0x69]
        let style: [UInt8] = [0, 0, 0, 10] + Array("styl".utf8) + [0, 0]
        let forced: [UInt8] = [0, 0, 0, 8] + Array("frcd".utf8)
        #expect(ForcedSubtitles.hasForcedBox(text + style + forced))
        #expect(!ForcedSubtitles.hasForcedBox(text + style))
        #expect(!ForcedSubtitles.hasForcedBox([0, 9, 1]))
    }

    @Test func fileDefaultOnlyWithoutSourceDefault() {
        let file = SubtitleFile(url: URL(fileURLWithPath: "/tmp/a.srt"), language: nil, isDefault: true)
        #expect(plan(files: [file]).defaultFileURL == file.url)
        let withDefault = plan(files: [file]) {
            $0.subtitleOptions.tracks = [SubtitleTrackSetting(sourceTrackID: 1, isDefault: true)]
        }
        #expect(withDefault.defaultFileURL == nil)
        #expect(plan(files: [file]) { $0.burnIn = .file(file.url) }.defaultFileURL == nil)
    }

    @Test func shiftedMovesAndClampsCues() {
        let cues = [SubtitleCue(start: 1, end: 2, text: "a"), SubtitleCue(start: 3, end: 4, text: "b")]
        let later = SubtitleParser.shifted(cues, byMs: 1500)
        #expect(later.map(\.start) == [2.5, 4.5] && later.map(\.end) == [3.5, 5.5])
        let earlier = SubtitleParser.shifted(cues, byMs: -1500)
        #expect(earlier.map(\.start) == [0, 1.5] && earlier.map(\.end) == [0.5, 2.5])
        #expect(SubtitleParser.shifted(cues, byMs: -2500).map(\.text) == ["b"])
    }

    @Test func forcedFormatSetsDisplayFlag() throws {
        let plain = try #require(TimedText.format(mediaType: kCMMediaType_Subtitle))
        let forced = try #require(TimedText.format(mediaType: kCMMediaType_Subtitle, forced: true))
        func flags(_ format: CMFormatDescription) -> UInt32 {
            let value = CMFormatDescriptionGetExtension(format, extensionKey: kCMTextFormatDescriptionExtension_DisplayFlags)
            return (value as? NSNumber)?.uint32Value ?? 0
        }
        #expect(flags(plain) == 0)
        #expect(flags(forced) & UInt32(kCMTextDisplayFlag_allSubtitlesForced) != 0)
    }
}
