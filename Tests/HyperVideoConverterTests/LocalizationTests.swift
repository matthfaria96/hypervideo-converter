import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@Suite("Localization")
struct LocalizationTests {
    /// The Brazilian Portuguese table shipped in the app's resources.
    private func portuguese() throws -> Bundle {
        let path = try #require(Bundle.module.path(forResource: "Localizable", ofType: "strings",
                                                    inDirectory: nil, forLocalization: "pt-BR"))
        return try #require(Bundle(path: (path as NSString).deletingLastPathComponent))
    }

    @Test(arguments: [
        ("Convert Videos", "Converter vídeos"),
        ("Output Settings", "Configurações de saída"),
        ("Ready to convert", "Pronto para converter"),
        ("Balanced", "Equilibrado"),
        ("%lld videos in the list", "%lld vídeos na lista")
    ])
    func translatesToPortuguese(key: String, expected: String) throws {
        #expect(try portuguese().localizedString(forKey: key, value: nil, table: nil) == expected)
    }

    @Test func formatsCountsInPortuguese() throws {
        let format = try portuguese().localizedString(forKey: "File %lld of %lld", value: nil, table: nil)
        #expect(String(format: format, 2, 5) == "Arquivo 2 de 5")
    }

    @Test func formatsInsufficientSpaceInPortuguese() throws {
        let key = "There isn't enough free space in the destination folder. This video needs about %@, but only %@ is free."
        let format = try portuguese().localizedString(forKey: key, value: "MISSING", table: nil)
        #expect(String(format: format, "A", "B")
            == "Não há espaço livre suficiente na pasta de destino. Este vídeo precisa de cerca de A, mas só há B livres.")
    }

    @Test func everyQualityProfileIsTranslated() throws {
        let bundle = try portuguese()
        for name in ["Balanced", "High Quality", "Smaller File", "Keep Original", "Quality Profiles"] {
            #expect(bundle.localizedString(forKey: name, value: "MISSING", table: nil) != "MISSING", "\(name)")
        }
    }
}

@Suite("Localization tables")
struct LocalizationTableTests {
    private func table() throws -> [String: String] {
        let path = try #require(Bundle.module.path(forResource: "Localizable", ofType: "strings",
                                                    inDirectory: nil, forLocalization: "pt-BR"))
        return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    /// Format specifiers (%@, %lld, %1$@, %%…) normalized to their types, in order.
    static func specifiers(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(lld|ld|d|@|lf|f|%)")
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let found = matches.compactMap { match -> (Int, String)? in
            let type = String(text[Range(match.range(at: 2), in: text)!])
            guard type != "%" else { return nil }
            return (Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) } ?? 0, type)
        }
        let positional = found.contains { $0.0 > 0 }
        return (positional ? found.sorted { $0.0 < $1.0 } : found).map(\.1)
    }

    @Test func everyTranslationKeepsTheFormatSpecifiers() throws {
        for (key, value) in try table() {
            #expect(Self.specifiers(key) == Self.specifiers(value), "\(key) → \(value)")
        }
    }

    @Test(arguments: [
        "%@ (personalized)", "Editing: all %lld videos", "Editing: %@", "Convert %lld Videos", "Convert 1 Video",
        "Compress %lld Videos", "1 video in the list", "%lld videos in the list", "Removes %@. Your original files aren't deleted.",
        "Unsupported format or damaged file", "Queue finished", "1 video converted", "%lld videos converted",
        "Import “%@”", "Import %lld Folders", "up to ~%@", "Balanced Compression",
        "Fast 1080p30", "HQ 1080p30 Surround", "HEVC 10-bit · 2160p · 60 fps · HDR preserved", "Video List"
    ])
    func newKeysAreTranslated(key: String) throws {
        let value = try #require(try table()[key], "missing \(key)")
        #expect(!value.isEmpty)
    }

    @Test(arguments: [
        "Summary",
        "Dimensions",
        "Filters",
        "Video",
        "Audio",
        "Subtitles",
        "Chapters",
        "Tags",
        "All HandBrake settings",
        "Select one video to see every setting: dimensions, filters, video, audio, subtitles, chapters and tags.",
        "Show Settings of First Video",
        "Back to the settings for all videos",
        "Close",
        "Save as Preset…",
        "Align A/V start",
        "Starts every track at the first video frame",
        "Passthru common metadata",
        "Keeps titles, dates and other tags from the source",
        "Range",
        "From chapter",
        "To chapter",
        "Orientation & Cropping",
        "Cropping",
        "Conservative",
        "Detect",
        "Detecting…",
        "Analyse 10 frames for black bars again",
        "The picture is kept whole.",
        "Resolution & Scaling",
        "Resolution limit",
        "Allow upscaling",
        "Enlarges smaller videos up to the limit",
        "Anamorphic",
        "Automatic keeps the source's pixel shape",
        "Borders",
        "Fill",
        "Color",
        "Height (Letterbox)",
        "Width (Pillarbox)",
        "Width & Height",
        "Black",
        "White",
        "Gray",
        "Dark Gray",
        "Final Dimensions",
        "Storage",
        "Display",
        "Method",
        "Blend",
        "Bob",
        "Denoise",
        "Strength",
        "Tune",
        "Ultralight",
        "Stronger",
        "Very Strong",
        "Film",
        "Grain",
        "High Motion",
        "Animation",
        "Tape",
        "Sprite",
        "Chroma smooth",
        "Tiny",
        "Small",
        "Wide",
        "Very Wide",
        "Sharpen",
        "Ultrafine",
        "Fine",
        "Coarse",
        "Very Coarse",
        "Colorspace",
        "Detelecine and Deblock aren't available on macOS's video engine.",
        "Filters need the video to be re-encoded. Choose an encoder in Video.",
        "Video encoder",
        "Framerate",
        "Framerate (FPS)",
        "Mode",
        "Constant Framerate",
        "Peak Framerate",
        "Variable Framerate",
        "Peak never goes above the chosen rate; Variable keeps the source's timing",
        "Encoder Options",
        "Speed",
        "Quality",
        "Profile",
        "Level",
        "Apple ProRes 422 LT — editing, lighter files",
        "Apple ProRes 422 Proxy — offline editing",
        "H.264 can't encode 8K (4320p); choose H.265 or a lower resolution.",
        "Selection Behavior",
        "Languages",
        "Empty keeps every language",
        "Auto Passthru",
        "Copied as is when the source uses them",
        "Passthru fallback",
        "Only first track gets the extra version",
        "Name tracks automatically",
        "Sample rate",
        "Gain",
        "Name",
        "Encoder",
        "Tracks follow the selection behavior above.",
        "Add Track",
        "Add All Tracks",
        "Reload from Behavior",
        "Remove Track",
        "7.1 Surround",
        "Default",
        "Default track",
        "Forced only",
        "Forced",
        "Include",
        "Burn",
        "Keeps the track only if it holds forced subtitles",
        "External Files",
        "Offset",
        "Title",
        "Create chapter markers",
        "Import…",
        "Export…",
        "This video has no chapters.",
        "Chapters not imported",
        "Line %lld of the chapter file isn't “number,title”.",
        "The chapter file is too large.",
        "Actors",
        "Director",
        "Release Date",
        "Comment",
        "Genre",
        "Description",
        "Plot",
        "Saved into MP4, MOV and MKV files.",
        "Can't read this video"
    ])
    func parityKeysAreTranslated(key: String) throws {
        let value = try #require(try table()[key], "missing \(key)")
        #expect(!value.isEmpty)
    }

    @Test func everyParityDisplayNameIsTranslated() throws {
        let table = try table()
        let untranslatable: Set<String> = ["NLMeans", "HQDN3D", "Unsharp", "Lapsharp", "BT.709", "BT.601 NTSC", "BT.601 PAL",
                                           "BT.2020", "HE-AAC", "AAC", "H.264", "Main 10", "Baseline", "High", "Main",
                                           "Apple ProRes 422 LT", "Apple ProRes 422 Proxy", "Sprite", "Bob"]
        var names: [String] = []
        names += FrameRateMode.allCases.map(\.displayName)
        names += EncoderSpeed.allCases.map(\.displayName)
        names += VideoProfile.allCases.map(\.displayName)
        names += CropMode.allCases.map(\.displayName)
        names += Anamorphic.allCases.map(\.displayName)
        names += PaddingMode.allCases.map(\.displayName)
        names += PadColor.allCases.map(\.displayName)
        names += FilterStrength.allCases.map(\.displayName)
        names += DeinterlaceMethod.allCases.map(\.displayName)
        names += DenoiseFilter.allCases.map(\.displayName)
        names += DenoiseTune.allCases.map(\.displayName)
        names += ChromaSmoothTune.allCases.map(\.displayName)
        names += SharpenFilter.allCases.map(\.displayName)
        names += SharpenTune.allCases.map(\.displayName)
        names += ColorspaceTarget.allCases.map(\.displayName)
        names += AudioCodec.allCases.map(\.displayName)
        names += AudioMixdown.allCases.map(\.displayName)
        names += AudioTrackSelection.allCases.map(\.displayName)
        names += VideoCodec.allCases.map(\.displayName)
        for name in names where !untranslatable.contains(name) {
            #expect(table[name] != nil, "\(name)")
        }
    }

    @Test func settingsTabsAreTranslated() throws {
        let table = try table()
        for key in ["Summary", "Dimensions", "Filters", "Video", "Audio", "Subtitles", "Chapters", "Tags"] {
            #expect(table[key] != nil, "\(key)")
        }
    }

    @Test func everyBuiltInPresetIsTranslated() throws {
        let table = try table()
        for preset in BuiltInPresets.all + QualityProfile.presets + QualityProfile.compressPresets {
            #expect(table[preset.name] != nil, "\(preset.name)")
            #expect(table[preset.summary] != nil, "\(preset.summary)")
        }
    }

    @Test func termsAreConsistent() throws {
        for (key, value) in try table() {
            #expect(!value.localizedCaseInsensitiveContains("predefinid"), "\(key)")
        }
    }
}
