import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

/// The Summary tab of one video (panel or Advanced sheet) acts on that video only.
@MainActor
@Suite("Per-video quality profile", .serialized)
struct PerVideoProfileTests {
    private func source(_ name: String, bytes: Int64 = 100_000_000) -> SourceItem {
        WorkspaceTests.source(name, bytes: bytes)
    }

    @Test func applyingToOneVideoLeavesTheOthersAndTheDraft() throws {
        let model = try TestEnvironment().makeModel()
        let a = source("a.mov"), b = source("b.mov")
        model.setSources([a, b])
        let draftBefore = model.draftSettings
        model.applyProfile(.smallerFile, to: b.id)
        let first = try #require(model.sources.first { $0.id == a.id })
        let second = try #require(model.sources.first { $0.id == b.id })
        #expect(first.settings == a.settings && first.presetID == a.presetID)
        #expect(second.settings.videoCodec == .hevc && second.presetID == QualityProfile.smallerFile.presetID)
        #expect(model.draftSettings == draftBefore)
    }

    @Test func profileOfOneVideoIgnoresTheOthers() throws {
        let model = try TestEnvironment().makeModel()
        let a = source("a.mov"), b = source("b.mov")
        model.setSources([a, b])
        model.applyProfile(.smallerFile, to: b.id)
        #expect(model.profile(of: b.id) == .smallerFile)
        #expect(model.profile(of: a.id) == .balanced)
        #expect(model.inspectorProfile == nil, "the all-videos inspector sees mixed profiles")
        model.update(b.id) { $0.settings.rateControl = .quality(0.99) }
        #expect(model.profile(of: b.id) == nil)
    }

    @Test func estimateOfOneVideoCountsOnlyIt() throws {
        let model = try TestEnvironment().makeModel()
        let a = source("a.mov", bytes: 100_000_000), b = source("b.mov", bytes: 300_000_000)
        model.setSources([a, b])
        let estimate = model.sizeEstimate(for: b.id)
        #expect(estimate.count == 1 && estimate.originalBytes == 300_000_000)
        #expect(model.sizeEstimate.count == 2)
    }

    @Test func savingAPresetFromOneVideoUsesItsSettingsAndNamesOnlyIt() throws {
        let model = try TestEnvironment().makeModel()
        let a = source("a.mov")
        var b = source("b.mov")
        b.settings.rateControl = .quality(0.4)
        model.setSources([a, b])
        let preset = try #require(model.saveAsPreset(name: "Mine", from: b.id))
        #expect(preset.settings.rateControl == .quality(0.4))
        #expect(model.sources.first { $0.id == b.id }?.presetID == preset.id)
        #expect(model.sources.first { $0.id == a.id }?.presetID == a.presetID)
    }
}
