import Foundation

/// Converts presets exported from HandBrake (File ▸ Export Presets, JSON) into
/// HyperVideo presets. Choices HyperVideo can't reproduce fall back to the closest
/// supported setting and are listed in `notes`.
public enum HandBrakePresets {
    public enum ImportError: LocalizedError {
        case notHandBrakeExport

        public var errorDescription: String? { "That file isn't a HandBrake preset export." }
    }

    public struct Imported: Sendable {
        public var preset: Preset
        public var notes: [String]
    }

    public static func isHandBrakeExport(_ data: Data) -> Bool {
        presetList(in: data) != nil
    }

    public static func parse(_ data: Data) throws -> [Imported] {
        guard let list = presetList(in: data) else { throw ImportError.notHandBrakeExport }
        return flatten(list, folder: nil).map { convert($0.preset, folder: $0.folder) }
    }

    private static func presetList(in data: Data) -> [[String: Any]]? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return root?["PresetList"] as? [[String: Any]]
    }

    /// HandBrake nests presets in folders; HyperVideo keeps the folder as the category.
    private static func flatten(_ items: [[String: Any]], folder: String?) -> [(preset: [String: Any], folder: String?)] {
        items.flatMap { item -> [(preset: [String: Any], folder: String?)] in
            if item["Folder"] as? Bool == true {
                return flatten(item["ChildrenArray"] as? [[String: Any]] ?? [], folder: item["PresetName"] as? String)
            }
            return [(item, folder)]
        }
    }

    private static func convert(_ raw: [String: Any], folder: String?) -> Imported {
        let p = Fields(raw)
        var notes: [String] = []
        var s = EncodeSettings()

        s.container = container(p.string("FileFormat"), notes: &notes)
        s.videoCodec = videoCodec(p.string("VideoEncoder"), notes: &notes)
        s.rateControl = rateControl(p, codec: p.string("VideoEncoder"))
        s.prioritizeSpeed = ["ultrafast", "superfast", "veryfast", "faster", "fast", "speed"].contains(p.string("VideoPreset"))
        s.frameRate = frameRate(p.string("VideoFramerate"), mode: p.string("VideoFramerateMode"))
        s.maxResolution = maxResolution(height: p.int("PictureHeight"))
        (s.rotation, s.flipHorizontal) = rotation(p.string("PictureRotate"))
        if p.int("PictureCropMode") == 1 {
            s.crop = Crop(top: p.int("PictureTopCrop"), bottom: p.int("PictureBottomCrop"),
                          left: p.int("PictureLeftCrop"), right: p.int("PictureRightCrop"))
        }

        s.filters.deinterlace = (p.string("PictureDeinterlaceFilter") ?? "off") == "off" ? .off : .auto
        s.filters.denoise = strength(filter: p.string("PictureDenoiseFilter"), preset: p.string("PictureDenoisePreset"))
        s.filters.sharpen = strength(filter: p.string("PictureSharpenFilter"), preset: p.string("PictureSharpenPreset"))
        s.filters.grayscale = p.bool("VideoGrayScale") ?? false

        applyAudio(p, to: &s, notes: &notes)
        s.subtitles = SubtitleSelection(rawValue: p.string("SubtitleTrackSelectionBehavior") ?? "") ?? .none
        s.optimizeForWeb = p.bool("Optimize") ?? s.optimizeForWeb
        s.keepMetadata = p.bool("ChapterMarkers") ?? s.keepMetadata

        // Combinations only QuickTime can hold.
        if s.videoCodec.isProRes || s.audioCodec == .alac { s.container = .mov }

        let name = p.string("PresetName").flatMap { $0.isEmpty ? nil : $0 } ?? "HandBrake Preset"
        let preset = Preset(
            name: name,
            category: folder.map { "HandBrake · \($0)" } ?? "HandBrake",
            symbol: "arrow.down.doc",
            summary: p.string("PresetDescription") ?? "Imported from HandBrake",
            settings: s
        )
        return Imported(preset: preset, notes: notes.map { "\(name): \($0)" })
    }

    // MARK: Video

    private static func container(_ format: String?, notes: inout [String]) -> ContainerFormat {
        switch format?.replacingOccurrences(of: "av_", with: "") {
        case "mp4", nil: return .mp4
        case "m4v": return .m4v
        case "mov": return .mov
        case let other?:
            notes.append("\(other.uppercased()) output isn't available, so it saves as MP4.")
            return .mp4
        }
    }

    private static func videoCodec(_ encoder: String?, notes: inout [String]) -> VideoCodec {
        let name = encoder ?? "x264"
        let tenBit = name.contains("10bit") || name.contains("12bit")
        if name.contains("264") { return .h264 }
        if name.contains("265") || name.contains("hevc") { return tenBit ? .hevc10 : .hevc }
        if name.contains("prores") { return .proRes422 }
        notes.append("The \(name) encoder isn't available, so it uses HEVC\(tenBit ? " 10-bit" : "").")
        return tenBit ? .hevc10 : .hevc
    }

    /// HandBrake's constant quality is a rate factor where lower is better (0–51 for
    /// x264/x265, 0–63 for AV1); VideoToolbox encoders use 0–100 where higher is better.
    private static func rateControl(_ p: Fields, codec: String?) -> RateControl {
        guard p.int("VideoQualityType") == 2 else { return .averageBitrate(max(100, p.int("VideoAvgBitrate"))) }
        let slider = p.double("VideoQualitySlider") ?? 22
        let encoder = codec ?? ""
        let quality: Double
        if encoder.hasPrefix("vt_") {
            quality = slider / 100
        } else {
            quality = 1 - slider / (encoder.contains("av1") ? 63 : 51)
        }
        return .quality((min(max(quality, 0.2), 1) * 100).rounded() / 100)
    }

    /// "pfr" is a peak, which HyperVideo honours by keeping the source rate rather
    /// than duplicating frames to reach it.
    private static func frameRate(_ value: String?, mode: String?) -> FrameRate {
        guard mode == "cfr", let fps = value.flatMap(Double.init) else { return .source }
        return FrameRate.allCases.filter { $0 != .source }.min { abs($0.rawValue - fps) < abs($1.rawValue - fps) } ?? .source
    }

    private static func maxResolution(height: Int) -> MaxResolution {
        guard height > 0 else { return .source }
        let limits = MaxResolution.allCases.filter { $0 != .source }.sorted { $0.rawValue > $1.rawValue }
        return limits.first { $0.rawValue <= height } ?? .sd480
    }

    private static func rotation(_ value: String?) -> (Rotation, Bool) {
        let parts = Dictionary(
            (value ?? "").split(separator: ":").compactMap { pair -> (String, Int)? in
                let kv = pair.split(separator: "=")
                guard kv.count == 2, let number = Int(kv[1]) else { return nil }
                return (String(kv[0]), number)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return (Rotation(rawValue: parts["angle"] ?? 0) ?? .none, parts["hflip"] == 1)
    }

    private static func strength(filter: String?, preset: String?) -> FilterStrength {
        guard let filter, filter != "off" else { return .off }
        switch preset {
        case "ultralight", "light": return .light
        case "strong", "stronger", "verystrong": return .strong
        default: return .medium
        }
    }

    // MARK: Audio

    private static func applyAudio(_ p: Fields, to s: inout EncodeSettings, notes: inout [String]) {
        let behavior = p.string("AudioTrackSelectionBehavior") ?? "first"
        let list = p.raw["AudioList"] as? [[String: Any]] ?? []
        guard behavior != "none", let track = list.first else {
            s.audioCodec = .none
            return
        }
        if list.count > 1 {
            notes.append("Only the first of its \(list.count) audio encoders is used.")
        }
        s.audioTracks = behavior == "all" ? .all : .first
        let audio = Fields(track)
        let encoder = audio.string("AudioEncoder") ?? "aac"
        switch encoder {
        case _ where encoder.hasPrefix("copy"):
            s.audioCodec = .passthrough
        case _ where encoder.contains("aac"):
            s.audioCodec = .aac
        case "alac", "alac16", "alac24":
            s.audioCodec = .alac
        default:
            s.audioCodec = .aac
            notes.append("\(encoder) audio isn't available, so it uses AAC.")
        }
        if audio.int("AudioBitrate") > 0 { s.audioBitrateKbps = audio.int("AudioBitrate") }
        switch audio.string("AudioMixdown") {
        case "mono", "left_only", "right_only": s.audioMixdown = .mono
        case "5point1", "6point1", "7point1", "5_2_lfe": s.audioMixdown = .surround51
        default: s.audioMixdown = .stereo
        }
    }

    /// Typed, forgiving access to a preset dictionary.
    private struct Fields {
        let raw: [String: Any]
        init(_ raw: [String: Any]) { self.raw = raw }

        func string(_ key: String) -> String? { raw[key] as? String }
        func bool(_ key: String) -> Bool? { raw[key] as? Bool }
        func double(_ key: String) -> Double? { (raw[key] as? NSNumber)?.doubleValue }
        func int(_ key: String) -> Int { (raw[key] as? NSNumber)?.intValue ?? 0 }
    }
}
