import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Presets ignore per-video trim and crop")
struct PresetTrimCropTests {
    private static func trimmedCropped() -> EncodeSettings {
        var settings = EncodeSettings()
        settings.trim = TrimRange(start: 1, end: 2)
        settings.crop = Crop(top: 8, bottom: 8, left: 4, right: 4)
        return settings
    }

    /// A file with a video extension; inspection fails but the source is still added.
    private static func placeholder(_ env: TestEnvironment, _ name: String) throws -> URL {
        let url = env.root.appendingPathComponent("\(name).mov")
        try Data("not a movie".utf8).write(to: url)
        return url
    }

    @Test func saveStripsTrimAndCrop() throws {
        let env = try TestEnvironment()
        let store = PresetStore(directory: env.support)
        let preset = store.save(name: "Mine", category: "", settings: Self.trimmedCropped())
        #expect(preset.settings.trim == nil)
        #expect(preset.settings.crop == .zero)
        let reloaded = PresetStore(directory: env.support)
        #expect(reloaded.custom.first?.settings.trim == nil)
        #expect(reloaded.custom.first?.settings.crop == .zero)
    }

    @Test func updateStripsTrimAndCrop() throws {
        let env = try TestEnvironment()
        let store = PresetStore(directory: env.support)
        let preset = store.save(name: "Mine", category: "", settings: EncodeSettings())
        var changed = Self.trimmedCropped()
        changed.videoCodec = .hevc
        store.update(preset.id, settings: changed)
        let updated = try #require(store.preset(id: preset.id))
        #expect(updated.settings.videoCodec == .hevc)
        #expect(updated.settings.trim == nil)
        #expect(updated.settings.crop == .zero)
    }

    @Test func storesUseIsolatedFolder() throws {
        let env = try TestEnvironment()
        PresetStore(directory: env.support).save(name: "Mine", category: "", settings: EncodeSettings())
        #expect(FileManager.default.fileExists(atPath: env.support.appendingPathComponent("presets.json").path))
    }

    @Test func addSourcesUsesDefaultPresetWithoutTrimOrCrop() async throws {
        let env = try TestEnvironment()
        // A custom default preset saved with trim/crop by an older build must not leak them.
        var legacy = Self.trimmedCropped()
        legacy.videoCodec = .hevc
        let preset = Preset(name: "Legacy", category: "Mine", symbol: "x", summary: "", settings: legacy)
        try JSONEncoder().encode([preset]).write(to: env.support.appendingPathComponent("presets.json"))
        env.defaults.set(preset.id.uuidString, forKey: PreferenceKey.defaultPresetID)
        let fresh = env.makeModel()
        await fresh.addSources([try Self.placeholder(env, "legacy")])
        if let item = fresh.sources.first {
            #expect(item.settings.videoCodec == .hevc)
            #expect(item.settings.trim == nil)
            #expect(item.settings.crop == .zero)
            #expect(fresh.presetName(for: item) == "Legacy")
        } else {
            Issue.record("source was not added")
        }
    }

    @Test func applyPresetAndApplyToAllKeepEachVideosTrimAndCrop() async throws {
        let env = try TestEnvironment()
        let a = try await AppTestClip.make(in: env.root, .init(name: "a"))
        let b = try await AppTestClip.make(in: env.root, .init(name: "b"))
        let model = env.makeModel()
        await model.addSources([a, b])
        let ids = model.sources.map(\.id)
        #expect(ids.count == 2)
        model.update(ids[0]) { $0.settings.trim = TrimRange(start: 0.1, end: 0.5); $0.settings.crop = Crop(top: 2) }
        model.update(ids[1]) { $0.settings.trim = TrimRange(start: 0.3); $0.settings.crop = Crop(left: 6) }

        let hevc = try #require(BuiltInPresets.all.first { $0.settings.videoCodec == .hevc })
        model.applyPreset(hevc, to: ids[0])
        var first = try #require(model.sources.first)
        #expect(first.settings.videoCodec == .hevc)
        #expect(first.settings.trim == TrimRange(start: 0.1, end: 0.5))
        #expect(first.settings.crop == Crop(top: 2))
        #expect(model.presetName(for: first) == hevc.name)

        model.applyToAll(from: ids[0])
        first = try #require(model.sources.first)
        let second = try #require(model.sources.last)
        #expect(second.settings.videoCodec == .hevc)
        #expect(second.presetID == hevc.id)
        #expect(second.settings.trim == TrimRange(start: 0.3))
        #expect(second.settings.crop == Crop(left: 6))
        #expect(first.settings.trim == TrimRange(start: 0.1, end: 0.5))
        #expect(model.presetName(for: second) == hevc.name)
    }

    @Test func presetNameReportsRealChanges() async throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        await model.addSources([try Self.placeholder(env, "x")])
        let id = try #require(model.sources.first?.id)
        model.update(id) { $0.settings.rateControl = .quality(0.99) }
        let item = try #require(model.sources.first)
        #expect(model.presetName(for: item).hasSuffix("(personalized)"))
    }
}
