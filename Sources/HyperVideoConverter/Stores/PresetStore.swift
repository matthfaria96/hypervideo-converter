import Foundation
import HyperVideoCore
import Observation

@Observable
@MainActor
final class PresetStore {
    private(set) var custom: [Preset]
    private let store: JSONStore<[Preset]>

    /// `directory` overrides where presets are saved (tests); nil uses Application Support.
    init(directory: URL? = nil) {
        store = JSONStore(fileName: "presets.json", directory: directory)
        custom = store.load() ?? []
    }

    /// Quality profiles first, then the other built-in presets, then the user's.
    static let builtIn: [Preset] = QualityProfile.presets + BuiltInPresets.all

    var all: [Preset] { Self.builtIn + custom }

    /// Presets grouped by category, custom ones first so personal work is on top.
    var grouped: [(category: String, presets: [Preset])] {
        let order = (custom.map(\.category) + Self.builtIn.map(\.category)).uniqued()
        return order.map { category in (category, all.filter { $0.category == category }) }
    }

    func preset(id: UUID?) -> Preset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    @discardableResult
    func save(name: String, category: String, settings: EncodeSettings) -> Preset {
        let settings = settings.presetSettings
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = Preset(
            name: trimmed.isEmpty ? "Custom Preset" : trimmed,
            category: category.isEmpty ? "My Presets" : category,
            symbol: "slider.horizontal.3",
            summary: Self.describe(settings),
            settings: settings
        )
        custom = custom + [preset]
        store.save(custom)
        return preset
    }

    func update(_ id: UUID, settings: EncodeSettings) {
        let settings = settings.presetSettings
        custom = custom.map { preset in
            guard preset.id == id else { return preset }
            var updated = preset
            updated.settings = settings
            updated.summary = Self.describe(settings)
            return updated
        }
        store.save(custom)
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        custom = custom.map { preset in
            guard preset.id == id else { return preset }
            var updated = preset
            updated.name = trimmed
            return updated
        }
        store.save(custom)
    }

    func delete(_ id: UUID) {
        custom = custom.filter { $0.id != id }
        store.save(custom)
    }

    /// Imports a HyperVideo export or a HandBrake preset export. Returns how many
    /// presets were added and notes on HandBrake settings that had to change.
    func importPresets(from url: URL) throws -> (count: Int, notes: [String]) {
        let data = try Data(contentsOf: url)
        let imported: [Preset]
        var notes: [String] = []
        if HandBrakePresets.isHandBrakeExport(data) {
            let converted = try HandBrakePresets.parse(data)
            imported = converted.map(\.preset)
            notes = converted.flatMap(\.notes)
        } else {
            imported = try JSONDecoder().decode([Preset].self, from: data)
                .map { Preset(name: $0.name, category: $0.category, symbol: $0.symbol, summary: $0.summary, settings: $0.settings) }
        }
        custom = custom + imported
        store.save(custom)
        return (imported.count, notes)
    }

    func exportPresets(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(custom).write(to: url, options: .atomic)
    }

    static func describe(_ settings: EncodeSettings) -> String {
        [
            settings.videoCodec.displayName,
            settings.maxResolution == .source ? nil : settings.maxResolution.displayName,
            settings.frameRate == .source ? nil : settings.frameRate.displayName,
            settings.audioCodec == .none ? "No audio" : settings.audioCodec.displayName
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

extension Preset {
    /// The name shown in the interface: built-in names are translated.
    var displayName: String {
        isBuiltIn ? String(localized: String.LocalizationValue(name)) : name
    }

    var displayCategory: String {
        isBuiltIn ? String(localized: String.LocalizationValue(category)) : category
    }

    var displaySummary: String {
        isBuiltIn ? String(localized: String.LocalizationValue(summary)) : summary
    }
}

extension EncodeSettings {
    /// Settings with the per-video values (trim, crop and burned-in subtitle, which only
    /// make sense for one source) reset, as stored in and applied from presets.
    var presetSettings: EncodeSettings {
        var copy = self
        copy.trim = nil
        copy.crop = .zero
        copy.burnIn = nil
        return copy
    }

    /// Keeps this video's trim, crop and burned-in subtitle while taking everything else from `template`.
    func adopting(_ template: EncodeSettings) -> EncodeSettings {
        var settings = template
        settings.trim = trim
        settings.crop = crop
        settings.burnIn = burnIn
        return settings
    }
}

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
