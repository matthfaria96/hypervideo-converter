import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Preset import reads files off the main actor")
struct PresetImportTests {
    private static let handBrake = """
    {
      "PresetList": [
        {
          "PresetName": "Phone Clips",
          "FileFormat": "av_mp4",
          "VideoEncoder": "x264", "VideoQualityType": 2, "VideoQualitySlider": 22.0,
          "VideoPreset": "veryfast", "VideoFramerate": "30", "VideoFramerateMode": "pfr",
          "PictureWidth": 1280, "PictureHeight": 720,
          "AudioList": [{ "AudioEncoder": "av_aac", "AudioBitrate": 128, "AudioMixdown": "stereo" }]
        }
      ],
      "VersionMajor": 63
    }
    """

    private static func write(_ data: Data, in env: TestEnvironment) throws -> URL {
        let url = env.root.appendingPathComponent("import-\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    @Test func importsHyperVideoExportWithFreshIDs() async throws {
        let env = try TestEnvironment()
        let source = PresetStore(directory: env.root.appendingPathComponent("src"))
        let a = source.save(name: "A", category: "", settings: EncodeSettings())
        let b = source.save(name: "B", category: "", settings: EncodeSettings())
        let file = env.root.appendingPathComponent("export.json")
        try source.exportPresets(to: file)

        let store = PresetStore(directory: env.support)
        let result = try await store.importPresets(from: file)
        #expect(result.count == 2)
        #expect(result.notes.isEmpty)
        #expect(store.custom.map(\.name) == ["A", "B"])
        #expect(Set(store.custom.map(\.id)).isDisjoint(with: [a.id, b.id]))
    }

    @Test func importsHandBrakeExportWithNotes() async throws {
        let env = try TestEnvironment()
        let url = try Self.write(Data(Self.handBrake.utf8), in: env)
        let store = PresetStore(directory: env.support)
        let result = try await store.importPresets(from: url)
        #expect(result.count == 1)
        #expect(store.custom.first?.name == "Phone Clips")
    }

    @Test func garbageThrowsAndLeavesPresetsUnchanged() async throws {
        let env = try TestEnvironment()
        let store = PresetStore(directory: env.support)
        store.save(name: "Keep", category: "", settings: EncodeSettings())
        let before = store.custom
        let url = try Self.write(Data("not json".utf8), in: env)
        await #expect(throws: (any Error).self) { try await store.importPresets(from: url) }
        #expect(store.custom == before)
    }

    @Test func parseImportRunsDetached() async throws {
        let data = Data(Self.handBrake.utf8)
        let parsed = try await Task.detached { try PresetStore.parseImport(data) }.value
        #expect(parsed.presets.count == 1)
    }
}
