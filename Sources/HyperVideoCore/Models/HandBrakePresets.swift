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

        // Combinations only QuickTime can hold.
        let needsALAC = s.audioEncodings.contains(where: { $0.codec == .alac }) && !s.container.supportsALAC
        if s.videoCodec.isProRes || needsALAC { s.container = .mov }

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
}
