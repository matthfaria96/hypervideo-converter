import Foundation
import Testing
@testable import HyperVideoCore

@Suite("HandBrake parity import")
struct HandBrakeParityImportTests {
    func imported(_ body: String) throws -> HandBrakePresets.Imported {
        let json = "{\"PresetList\":[{\"PresetName\":\"T\",\(body)}]}"
        return try #require(try HandBrakePresets.parse(Data(json.utf8)).first)
    }

    let everything = """
    "FileFormat": "av_mp4", "VideoEncoder": "vt_h264", "VideoQualityType": 2, "VideoQualitySlider": 60,
    "VideoPreset": "quality", "VideoProfile": "high", "VideoLevel": "4.1",
    "VideoFramerate": "24", "VideoFramerateMode": "cfr",
    "PictureCropMode": 1, "PictureAllowUpscaling": true, "PictureHeight": 2160,
    "PicturePAR": "auto", "PicturePadMode": "letterbox", "PicturePadColor": "#FF8000",
    "PictureDeinterlaceFilter": "decomb", "PictureCombDetectPreset": "off", "PictureDeinterlacePreset": "bob",
    "PictureDenoiseFilter": "hqdn3d", "PictureDenoisePreset": "strong", "PictureDenoiseTune": "grain",
    "PictureChromaSmoothPreset": "light", "PictureChromaSmoothTune": "wide",
    "PictureSharpenFilter": "unsharp", "PictureSharpenPreset": "medium", "PictureSharpenTune": "fine",
    "PictureColorspacePreset": "bt601-6-625",
    "AudioTrackSelectionBehavior": "all", "AudioLanguageList": ["eng", "any", "por"],
    "AudioList": [
      { "AudioEncoder": "ca_haac", "AudioBitrate": 96, "AudioMixdown": "7point1", "AudioSamplerate": "44.1",
        "AudioTrackGainSlider": 30, "AudioTrackName": "Main" },
      { "AudioEncoder": "alac", "AudioBitrate": 0, "AudioMixdown": "mono", "AudioSamplerate": "auto" }
    ],
    "AudioCopyMask": ["copy:ac3", "copy:dts"], "AudioEncoderFallback": "ca_haac",
    "AudioSecondaryEncoderMode": true, "AudioAutomaticNamingBehavior": "unnamed",
    "SubtitleTrackSelectionBehavior": "all", "SubtitleLanguageList": ["eng", "any"],
    "SubtitleBurnBehavior": "none", "ChapterMarkers": true, "MetadataPassthrough": false,
    "AlignAVStart": true, "Optimize": false, "Mp4HttpOptimize": true
    """

    @Test func mapsEveryKey() throws {
        let r = try imported(everything)
        let s = r.preset.settings
        #expect(s.videoOptions.speed == .quality && s.videoOptions.profile == .high && s.videoOptions.level == .l41)
        #expect(s.frameRate == .fps24 && s.videoOptions.frameRateMode == .constant)
        #expect(s.pictureOptions.cropMode == .conservative && s.pictureOptions.allowUpscaling)
        #expect(s.maxResolution == .uhd2160 && s.pictureOptions.anamorphic == .automatic)
        #expect(s.pictureOptions.padding.mode == .letterbox && s.pictureOptions.padding.color == .custom)
        #expect(s.pictureOptions.padding.customHex == "FF8000")
        #expect(s.filters.deinterlace == .always && s.filters.deinterlaceMethod == .bob)
        #expect(s.filters.denoise == .strong && s.filters.denoiseFilter == .hqdn3d && s.filters.denoiseTune == .grain)
        #expect(s.filters.chromaSmooth == .light && s.filters.chromaSmoothTune == .wide)
        #expect(s.filters.sharpen == .medium && s.filters.sharpenFilter == .unsharp && s.filters.sharpenTune == .fine)
        #expect(s.filters.colorspace == .bt601pal)
        #expect(s.audioTracks == .all && s.audioOptions.languages == ["eng", "por"])
        #expect(s.audioCodec == .heAAC && s.audioMixdown == .surround71 && s.audioBitrateKbps == 96)
        #expect(s.audioOptions.sampleRate == .hz44100 && s.audioOptions.gainDb == 20 && s.audioOptions.trackName == "Main")
        #expect(s.extraAudio?.codec == .alac && s.extraAudio?.mixdown == .mono)
        #expect(s.audioOptions.allowedPassthru == [.ac3, .dts])
        #expect(s.audioOptions.fallback == .heAAC && s.audioOptions.extraFirstTrackOnly && s.audioOptions.automaticNaming)
        #expect(s.subtitleOptions.languages == ["eng"] && s.chapterOptions.markers == true)
        #expect(!s.keepMetadata && s.alignAVStart && s.optimizeForWeb == false)
        #expect(r.notes.isEmpty, "\(r.notes)")
        #expect(s.isValid)
    }

    @Test func unsupportedKeysAddNotes() throws {
        let r = try imported("""
        "PictureDeblockPreset": "medium", "PictureDetelecine": "default", "PictureDeinterlaceFilter": "decomb",
        "PictureDeinterlacePreset": "eedi2", "Mp4iPodCompatible": true, "SubtitleAddForeignAudioSearch": true,
        "AudioTrackSelectionBehavior": "first",
        "AudioList": [{ "AudioEncoder": "av_aac", "AudioBitrate": 128, "AudioMixdown": "dpl2", "AudioTrackDRCSlider": 2.0 }]
        """)
        let text = r.notes.joined(separator: "\n")
        for expected in ["Deblock isn't available on macOS's video engine.", "Detelecine isn't available on macOS's video engine.",
                         "EEDI2 deinterlacing isn't available, so it blends.", "iPod 5G support isn't available.",
                         "Foreign audio search isn't available.", "Dolby Surround mixdowns aren't available, so it uses Stereo.",
                         "Dynamic range compression isn't available."] {
            #expect(text.contains(expected), "\(expected)")
        }
        #expect(r.notes.count == 7, "\(r.notes)")
        #expect(r.preset.settings.isValid)
    }

    @Test func copyCodecIsConditionalPassthru() throws {
        let r = try imported("""
        "AudioTrackSelectionBehavior": "first",
        "AudioList": [{ "AudioEncoder": "copy:ac3" }, { "AudioEncoder": "copy:aac" }]
        """)
        let s = r.preset.settings
        #expect(s.audioCodec == .autoPassthru && s.audioOptions.passthruOnly == .ac3)
        #expect(s.extraAudio?.codec == .autoPassthru && s.extraAudio?.passthruOnly == .aac)
        #expect(s.audioEncodings.map(\.passthruOnly) == [.ac3, .aac])
        #expect(r.notes.isEmpty, "\(r.notes)")
    }

    @Test(arguments: [(0, CropMode.automatic), (1, .conservative), (2, .none), (3, .custom)])
    func cropModes(raw: Int, mode: CropMode) throws {
        #expect(try imported("\"PictureCropMode\": \(raw)").preset.settings.pictureOptions.cropMode == mode)
    }

    @Test(arguments: [("44.1", AudioSampleRate.hz44100), ("48", .hz48000), ("22050", .hz22050), ("auto", .auto)])
    func sampleRates(raw: String, rate: AudioSampleRate) throws {
        let r = try imported("\"AudioList\": [{ \"AudioEncoder\": \"av_aac\", \"AudioSamplerate\": \"\(raw)\" }]")
        #expect(r.preset.settings.audioOptions.sampleRate == rate)
    }

    /// Keys of HandBrake 1.10's built-in "Fast 1080p30".
    @Test func builtInFast1080p30() throws {
        let r = try imported("""
        "FileFormat": "av_mp4", "VideoEncoder": "x264", "VideoQualityType": 2, "VideoQualitySlider": 22.0,
        "VideoPreset": "veryfast", "VideoProfile": "high", "VideoLevel": "4.0", "VideoTune": "",
        "VideoFramerate": "30", "VideoFramerateMode": "pfr", "VideoMultiPass": false,
        "PictureWidth": 1920, "PictureHeight": 1080, "PictureCropMode": 0, "PicturePAR": "auto",
        "PicturePadMode": "none", "PicturePadColor": "black", "PictureAllowUpscaling": false,
        "PictureDeinterlaceFilter": "decomb", "PictureDeinterlacePreset": "default", "PictureCombDetectPreset": "default",
        "PictureDeblockPreset": "off", "PictureDetelecine": "off", "PictureColorspacePreset": "off",
        "PictureDenoiseFilter": "off", "PictureSharpenFilter": "off", "PictureChromaSmoothPreset": "off",
        "AudioTrackSelectionBehavior": "first", "AudioEncoderFallback": "av_aac",
        "AudioList": [{ "AudioEncoder": "av_aac", "AudioBitrate": 160, "AudioMixdown": "stereo", "AudioSamplerate": "auto",
                        "AudioTrackGainSlider": 0, "AudioTrackDRCSlider": 0 }],
        "SubtitleTrackSelectionBehavior": "none", "SubtitleBurnBehavior": "foreign", "ChapterMarkers": true,
        "Optimize": false, "Mp4iPodCompatible": false
        """)
        let s = r.preset.settings
        #expect(s.videoCodec == .h264 && s.frameRate == .fps30 && s.videoOptions.frameRateMode == .peak)
        #expect(s.maxResolution == .fhd1080 && s.pictureOptions.cropMode == .automatic)
        #expect(s.pictureOptions.anamorphic == .automatic && s.filters.deinterlace == .auto)
        #expect(s.audioCodec == .aac && s.audioMixdown == .stereo && s.audioBitrateKbps == 160)
        #expect(r.notes.isEmpty, "\(r.notes)")
        #expect(s.isValid)
    }

    @Test func rareValuesFallBackWithNotes() throws {
        let r = try imported("""
        "VideoEncoder": "x265", "VideoProfile": "weird", "VideoLevel": "4.1", "PicturePAR": "custom",
        "PicturePadMode": "custom", "PicturePadColor": "pink", "PictureColorspacePreset": "custom",
        "VideoMultiPass": true, "VideoQualityType": 1, "VideoAvgBitrate": 5000, "VideoTune": "film"
        """)
        let s = r.preset.settings
        #expect(s.videoOptions.profile == .auto && s.videoOptions.level == .auto)
        #expect(s.pictureOptions.padding.mode == .both && s.pictureOptions.padding.color == .black)
        #expect(s.filters.colorspace == .off)
        #expect(r.notes.count == 8, "\(r.notes)")
    }
}
