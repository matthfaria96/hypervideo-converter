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

        applyVideo(p, to: &s, notes: &notes)
        applyPicture(p, to: &s, notes: &notes)
        applyFilters(p, to: &s, notes: &notes)
        applyAudio(p, to: &s, notes: &notes)
        applySubtitles(p, to: &s, notes: &notes)
        applySummary(p, to: &s, notes: &notes)

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
        return Imported(preset: preset, notes: unique(notes).map { "\(name): \($0)" })
    }

    /// The same limitation reported by both audio entries is listed once.
    private static func unique(_ notes: [String]) -> [String] {
        var seen = Set<String>()
        return notes.filter { seen.insert($0).inserted }
    }
}
