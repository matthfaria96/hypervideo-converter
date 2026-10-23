import AudioToolbox
import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Parity model")
struct ParityModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: Video, picture, filters

    @Test func filterStrengthAmounts() {
        #expect(FilterStrength.off.amount == 0)
        #expect(FilterStrength.ultralight.amount == 1.0 / 6)
        #expect(FilterStrength.light.amount == 1.0 / 3)
        #expect(FilterStrength.medium.amount == 2.0 / 3)
        #expect(FilterStrength.strong.amount == 1)
        #expect(FilterStrength.stronger.amount == 4.0 / 3)
        #expect(FilterStrength.verystrong.amount == 5.0 / 3)
        #expect(FilterStrength.allCases.map(\.displayName)
            == ["Off", "Ultralight", "Light", "Medium", "Strong", "Stronger", "Very Strong"])
    }

    @Test func legacyFiltersDecodeWithDefaults() throws {
        let f = try decode(VideoFilters.self, #"{"deinterlace":"auto","denoise":"light","sharpen":"strong","grayscale":false}"#)
        #expect(f.deinterlaceMethod == .blend)
        #expect(f.denoiseFilter == .nlmeans)
        #expect(f.denoiseTune == .none)
        #expect(f.chromaSmooth == .off)
        #expect(f.chromaSmoothTune == .none)
        #expect(f.sharpenFilter == .lapsharp)
        #expect(f.sharpenTune == .none)
        #expect(f.colorspace == .off)
        #expect(f.denoise == .light)
        #expect(f.sharpen == .strong)
    }

    @Test func filterActivity() {
        var f = VideoFilters()
        f.chromaSmooth = .light
        #expect(f.isActive(sourceIsInterlaced: false))
        var g = VideoFilters()
        g.colorspace = .bt709
        #expect(!g.isActive(sourceIsInterlaced: false))
    }

    @Test func sharpenTuneOptions() {
        #expect(SharpenTune.options(for: .unsharp) == [.none, .ultrafine, .fine, .medium, .coarse, .verycoarse])
        #expect(SharpenTune.options(for: .lapsharp) == [.none, .film, .grain, .animation, .sprite])
        #expect(SharpenTune.film.resolved(for: .unsharp) == .none)
    }

    @Test func profileAndLevelOptions() {
        #expect(VideoProfile.options(for: .h264) == [.auto, .baseline, .main, .high])
        #expect(VideoProfile.options(for: .hevc10) == [.auto, .main10])
        #expect(VideoProfile.high.resolved(for: .hevc) == .auto)
        #expect(VideoLevel.options(for: .hevc) == [.auto])
        #expect(VideoLevel.options(for: .h264).count == 10)
    }

    private func close(_ p: Padding, _ r: Double, _ g: Double, _ b: Double) -> Bool {
        abs(p.red - r) < 1e-9 && abs(p.green - g) < 1e-9 && abs(p.blue - b) < 1e-9
    }

    @Test func paddingColors() {
        let k: Double = 255
        #expect(close(Padding(color: .gray), 112 / k, 128 / k, 144 / k))
        #expect(close(Padding(color: .darkGray), 47 / k, 79 / k, 79 / k))
        #expect(close(Padding(color: .white), 1, 1, 1))
        #expect(close(Padding(color: .custom, customHex: "FF8000"), 1, 128 / k, 0))
        #expect(close(Padding(color: .custom, customHex: "zz"), 0, 0, 0))
    }

    @Test func cropModeDetects() {
        #expect(CropMode.automatic.detects && CropMode.conservative.detects)
        #expect(!CropMode.custom.detects && !CropMode.none.detects)
    }

    @Test func emptyJSONGivesDefaults() throws {
        #expect(try decode(VideoEncoderOptions.self, "{}") == VideoEncoderOptions())
        #expect(try decode(PictureOptions.self, "{}") == PictureOptions())
    }

    // MARK: Audio, subtitles, chapters, tags, languages

    @Test func sampleRateResolution() {
        #expect(AudioSampleRate.auto.resolved(sourceRate: 44_100, codec: .aac) == 44_100)
        #expect(AudioSampleRate.auto.resolved(sourceRate: 96_000, codec: .aac) == 48_000)
        #expect(AudioSampleRate.auto.resolved(sourceRate: 8_000, codec: .aac) == 8_000)
        #expect(AudioSampleRate.auto.resolved(sourceRate: 6_000, codec: .aac) == 8_000)
        #expect(AudioSampleRate.auto.resolved(sourceRate: 22_050, codec: .heAAC) == 32_000)
        #expect(AudioSampleRate.hz22050.resolved(sourceRate: 48_000, codec: .aac) == 22_050)
        #expect(AudioSampleRate.auto.resolved(sourceRate: 96_000, codec: .alac) == 96_000)
        #expect(AudioSampleRate.auto.displayName == "Auto")
        #expect(AudioSampleRate.hz44100.displayName == "44.1 kHz")
        #expect(AudioSampleRate.hz48000.displayName == "48 kHz")
        #expect(AudioSampleRate.hz11025.displayName == "11.025 kHz")
    }

    @Test func passthruFormatMapping() {
        #expect(PassthruCodec.from(formatID: kAudioFormatMPEG4AAC) == .aac)
        #expect(PassthruCodec.from(formatID: kAudioFormatMPEG4AAC_HE) == .aac)
        #expect(PassthruCodec.from(formatID: kAudioFormatAC3) == .ac3)
        #expect(PassthruCodec.from(formatID: kAudioFormatEnhancedAC3) == .eac3)
        #expect(PassthruCodec.from(formatID: kAudioFormatMPEGLayer3) == .mp3)
        #expect(PassthruCodec.from(formatID: kAudioFormatAppleLossless) == .alac)
        #expect(PassthruCodec.from(formatID: kAudioFormatFLAC) == .flac)
        #expect(PassthruCodec.from(formatID: kAudioFormatOpus) == .opus)
        #expect(PassthruCodec.from(formatID: kAudioFormatLinearPCM) == nil)
    }

    @Test func mixdown71() {
        #expect(AudioMixdown.surround71.channelCount == 8)
        #expect(AudioMixdown.surround71.resolved(sourceChannels: 6) == .surround51)
        #expect(AudioMixdown.surround71.resolved(sourceChannels: 2) == .stereo)
        #expect(AudioMixdown.surround71.resolved(sourceChannels: 8) == .surround71)
        #expect(AudioTrackSelection.none.displayName == "None")
    }

    @Test func legacyAudioEncodingDecodes() throws {
        let e = try decode(AudioEncoding.self, #"{"codec":"aac","mixdown":"stereo","bitrateKbps":160}"#)
        #expect(e.sampleRate == .hz48000)
        #expect(e.gainDb == 0)
        #expect(e.trackName == nil)
        #expect(e == AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 160))
    }

    @Test func legacySubtitleFileDecodes() throws {
        let f = try decode(SubtitleFile.self, #"{"url":"file:///tmp/a.srt","language":"en"}"#)
        #expect(f.offsetMs == 0)
        #expect(f.title == nil)
        #expect(!f.isDefault)
        #expect(!f.isForced)
    }

    @Test func languageMatching() {
        #expect(LanguageFilter.matches("pt-BR", in: ["por"]))
        #expect(LanguageFilter.matches("en", in: ["eng"]))
        #expect(!LanguageFilter.matches("fr", in: ["eng"]))
        #expect(LanguageFilter.matches(nil, in: []))
        #expect(LanguageFilter.matches("fr", in: ["any"]))
        #expect(!LanguageFilter.matches(nil, in: ["eng"]))
    }

    @Test func chapterAndTagHelpers() {
        #expect(!ChapterOptions().writesMarkers(keepMetadata: false))
        var chapters = ChapterOptions()
        chapters.markers = true
        #expect(chapters.writesMarkers(keepMetadata: false))
        #expect(MetadataTags().isEmpty)
        #expect(MetadataTags(title: "  ").isEmpty)
        #expect(!MetadataTags(genre: "Drama").isEmpty)
    }
}
