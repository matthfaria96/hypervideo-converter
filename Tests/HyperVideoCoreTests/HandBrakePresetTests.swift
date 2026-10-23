import Foundation
import Testing
@testable import HyperVideoCore

@Suite("HandBrake preset import")
struct HandBrakePresetTests {
    /// Trimmed-down HandBrake 1.10 export: a folder plus a top-level preset.
    let export = """
    {
      "PresetList": [
        {
          "Folder": true,
          "PresetName": "Family",
          "ChildrenArray": [
            {
              "PresetName": "Phone Clips",
              "PresetDescription": "Small H.264 for phones",
              "FileFormat": "av_mp4",
              "VideoEncoder": "x264", "VideoQualityType": 2, "VideoQualitySlider": 22.0, "VideoAvgBitrate": 6000,
              "VideoPreset": "veryfast", "VideoFramerate": "30", "VideoFramerateMode": "pfr",
              "PictureWidth": 1280, "PictureHeight": 720, "PictureRotate": "angle=0:hflip=0",
              "PictureDeinterlaceFilter": "decomb", "PictureDenoiseFilter": "off", "PictureSharpenFilter": "off",
              "VideoGrayScale": false, "Optimize": true, "ChapterMarkers": true,
              "AudioTrackSelectionBehavior": "first",
              "AudioList": [{ "AudioEncoder": "av_aac", "AudioBitrate": 128, "AudioMixdown": "stereo" }],
              "SubtitleTrackSelectionBehavior": "none"
            }
          ]
        },
        {
          "PresetName": "Archive 4K",
          "FileFormat": "av_mkv",
          "VideoEncoder": "x265_10bit", "VideoQualityType": 1, "VideoAvgBitrate": 13000,
          "VideoPreset": "slow", "VideoFramerate": "23.976", "VideoFramerateMode": "cfr",
          "PictureWidth": 3840, "PictureHeight": 2160, "PictureRotate": "angle=90:hflip=1",
          "PictureCropMode": 3, "PictureTopCrop": 4, "PictureBottomCrop": 6, "PictureLeftCrop": 0, "PictureRightCrop": 2,
          "PictureDeinterlaceFilter": "off", "PictureDenoiseFilter": "nlmeans", "PictureDenoisePreset": "medium",
          "PictureSharpenFilter": "lapsharp", "PictureSharpenPreset": "ultralight", "VideoGrayScale": true,
          "Optimize": false, "ChapterMarkers": false,
          "AudioTrackSelectionBehavior": "all",
          "AudioList": [{ "AudioEncoder": "copy", "AudioBitrate": 0, "AudioMixdown": "none" },
                        { "AudioEncoder": "av_aac", "AudioBitrate": 160, "AudioMixdown": "stereo" }],
          "SubtitleTrackSelectionBehavior": "all"
        },
        {
          "PresetName": "Tiny AV1",
          "FileFormat": "av_webm",
          "VideoEncoder": "svt_av1_10bit", "VideoQualityType": 2, "VideoQualitySlider": 35,
          "VideoFramerate": "auto", "VideoFramerateMode": "vfr", "PictureHeight": 0,
          "AudioTrackSelectionBehavior": "first", "AudioList": [{ "AudioEncoder": "opus", "AudioBitrate": 96, "AudioMixdown": "5point1" }]
        }
      ],
      "VersionMajor": 66, "VersionMicro": 0, "VersionMinor": 0
    }
    """

    func imported() throws -> [HandBrakePresets.Imported] {
        try HandBrakePresets.parse(Data(export.utf8))
    }

    @Test func recognisesHandBrakeExports() {
        #expect(HandBrakePresets.isHandBrakeExport(Data(export.utf8)))
        #expect(!HandBrakePresets.isHandBrakeExport(Data("[]".utf8)))
    }

    @Test func mapsAQualityPreset() throws {
        let phone = try #require(try imported().first)
        #expect(phone.preset.name == "Phone Clips")
        #expect(phone.preset.category == "HandBrake · Family")
        let s = phone.preset.settings
        #expect(s.container == .mp4 && s.videoCodec == .h264)
        #expect(s.rateControl == .quality(0.57))
        #expect(s.prioritizeSpeed && s.optimizeForWeb && s.keepMetadata)
        #expect(s.maxResolution == .hd720)
        #expect(s.frameRate == .fps30 && s.videoOptions.frameRateMode == .peak)
        #expect(s.filters.deinterlace == .auto)
        #expect(s.audioCodec == .aac && s.audioBitrateKbps == 128 && s.audioMixdown == .stereo && s.audioTracks == .first)
        #expect(s.subtitles == .none)
        #expect(phone.notes.isEmpty)
    }

    @Test func mapsABitratePresetWithPictureSettings() throws {
        let archive = try imported()[1]
        let s = archive.preset.settings
        #expect(archive.preset.category == "HandBrake")
        #expect(s.videoCodec == .hevc10 && s.rateControl == .averageBitrate(13_000))
        #expect(s.frameRate == .fps23976 && s.maxResolution == .uhd2160)
        #expect(s.rotation == .cw90 && s.flipHorizontal)
        #expect(s.crop == Crop(top: 4, bottom: 6, left: 0, right: 2))
        #expect(s.filters.deinterlace == .off && s.filters.denoise == .medium && s.filters.sharpen == .ultralight && s.filters.grayscale)
        #expect(s.audioCodec == .autoPassthru && s.audioTracks == .all && s.subtitles == .all)
        #expect(s.keepMetadata, "chapter markers off must not drop other tags")
        #expect(!s.prioritizeSpeed)
        #expect(s.container == .mkv, "av_mkv maps to Matroska instead of falling back")
        #expect(s.extraAudio == AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 160))
        #expect(archive.notes.isEmpty, "\(archive.notes)")
        #expect(s.isValid)
    }

    @Test func unsupportedChoicesFallBackWithNotes() throws {
        let tiny = try imported()[2]
        let s = tiny.preset.settings
        #expect(s.videoCodec == .hevc10 && s.audioCodec == .aac && s.audioMixdown == .surround51)
        #expect(s.maxResolution == .source && s.frameRate == .source && s.videoOptions.frameRateMode == .variable)
        #expect(tiny.notes.count == 3, "\(tiny.notes)")
        #expect(s.isValid)
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: HandBrakePresets.ImportError.self) { try HandBrakePresets.parse(Data("{\"a\":1}".utf8)) }
    }
}
