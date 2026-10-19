import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Folder import preset")
struct FolderImportTests {
    /// A folder with two placeholder videos (inspection fails, but they're still added) and a loose file.
    private static func layout(_ env: TestEnvironment) throws -> (folder: URL, loose: URL) {
        let folder = env.root.appendingPathComponent("Shoot")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Day 2"), withIntermediateDirectories: true)
        for path in ["a.mov", "Day 2/b.mp4"] {
            try Data("x".utf8).write(to: folder.appendingPathComponent(path))
        }
        let loose = env.root.appendingPathComponent("loose.mov")
        try Data("x".utf8).write(to: loose)
        return (folder, loose)
    }

    private static func otherPreset(than model: AppModel) throws -> Preset {
        try #require(model.presets.all.first { $0.id != model.defaultPreset.id && $0.settings.container == .mkv }
            ?? model.presets.all.first { $0.id != model.defaultPreset.id })
    }

    @Test func filesAreAddedRightAwayWithTheDefaultPreset() async throws {
        let env = try TestEnvironment()
        let (_, loose) = try Self.layout(env)
        let model = env.makeModel()
        await model.addSources([loose])
        #expect(model.pendingFolderImport == nil)
        #expect(model.sources.map(\.presetID) == [model.defaultPreset.id])
    }

    @Test func foldersWaitForAPresetDefaultingToTheDefault() async throws {
        let env = try TestEnvironment()
        let (folder, _) = try Self.layout(env)
        let model = env.makeModel()
        await model.addSources([folder])
        #expect(model.sources.isEmpty)
        let pending = try #require(model.pendingFolderImport)
        #expect(pending.folders == [folder])
        #expect(pending.presetID == model.defaultPreset.id)
    }

    @Test func chosenPresetAppliesToEveryVideoInTheFolderOnly() async throws {
        let env = try TestEnvironment()
        let (folder, loose) = try Self.layout(env)
        let model = env.makeModel()
        let chosen = try Self.otherPreset(than: model)
        await model.addSources([folder, loose])
        await model.confirmFolderImport(preset: chosen)

        #expect(model.pendingFolderImport == nil)
        let byName = Dictionary(uniqueKeysWithValues: model.sources.map { ($0.name, $0) })
        #expect(byName.count == 3)
        for name in ["a.mov", "b.mp4"] {
            #expect(byName[name]?.presetID == chosen.id)
            #expect(byName[name]?.settings == chosen.settings.presetSettings)
        }
        #expect(byName["loose.mov"]?.presetID == model.defaultPreset.id)
    }

    @Test func cancellingAddsNothing() async throws {
        let env = try TestEnvironment()
        let (folder, _) = try Self.layout(env)
        let model = env.makeModel()
        await model.addSources([folder])
        model.cancelFolderImport()
        #expect(model.pendingFolderImport == nil)
        #expect(model.sources.isEmpty)
    }
}
