import Foundation
import HyperVideoCore
import Testing
@testable import HyperVideoConverter

@Suite("Preset picker", .serialized)
@MainActor
struct PresetPickerTests {
    private func makeModel(_ count: Int) throws -> AppModel {
        let model = try TestEnvironment().makeModel()
        model.setSources((0..<count).map { WorkspaceTests.source("v\($0).mov") })
        return model
    }

    @Test func showsThePresetEveryTargetShares() throws {
        let model = try makeModel(2)
        #expect(model.targetsPresetID == QualityProfile.balanced.presetID)
        model.update(model.sources[1].id) { $0.presetID = QualityProfile.highQuality.presetID }
        #expect(model.targetsPresetID == nil, "mixed presets show no single one")
        model.selectedIDs = [model.sources[1].id]
        #expect(model.targetsPresetID == QualityProfile.highQuality.presetID)
    }

    @Test func titleSaysPersonalisedOrMixed() throws {
        let model = try makeModel(2)
        #expect(model.targetsPresetTitle == model.presetName(for: model.sources[0]))
        model.update(model.sources[1].id) { $0.presetID = QualityProfile.highQuality.presetID }
        #expect(model.targetsPresetTitle == String(localized: "Mixed presets"))
    }

    @Test func savingNamesTheTargetsAfterTheNewPreset() throws {
        let model = try makeModel(2)
        let preset = try #require(model.saveTargetsAsPreset(name: "Mine"))
        #expect(model.sources.allSatisfy { $0.presetID == preset.id })
        #expect(model.presets.custom.contains { $0.id == preset.id })
    }

    @Test func emptyNamesAreNotSaved() throws {
        let model = try makeModel(1)
        #expect(model.saveTargetsAsPreset(name: "   ") == nil)
    }
}
