import Foundation
import HyperVideoCore
import Testing
@testable import HyperVideoConverter

@Suite("All-videos settings panel")
@MainActor
struct AllVideosPanelTests {
    private func makeModel(_ count: Int) throws -> AppModel {
        let model = try TestEnvironment().makeModel()
        model.setSources((0..<count).map { WorkspaceTests.source("v\($0).mov") })
        return model
    }

    @Test func editingAllVideosReachesEveryOneAndKeepsTheirOwnTrim() throws {
        let model = try makeModel(3)
        model.update(model.sources[1].id) { $0.settings.trim = TrimRange(start: 2, end: 5) }
        let binding = model.allVideosSettingsBinding
        var changed = binding.wrappedValue
        changed.filters.grayscale = true
        changed.videoCodec = .hevc
        binding.wrappedValue = changed
        #expect(model.sources.allSatisfy { $0.settings.filters.grayscale && $0.settings.videoCodec == .hevc })
        #expect(model.sources[1].settings.trim == TrimRange(start: 2, end: 5))
    }

    @Test func withASelectionOnlyTheSelectedChange() throws {
        let model = try makeModel(3)
        model.selectedIDs = [model.sources[0].id, model.sources[2].id]
        var changed = model.allVideosSettingsBinding.wrappedValue
        changed.filters.grayscale = true
        model.allVideosSettingsBinding.wrappedValue = changed
        #expect(model.sources.map(\.settings.filters.grayscale) == [true, false, true])
    }

    @Test func withAnEmptyListTheNextVideosGetTheSettings() throws {
        let model = try makeModel(0)
        var changed = model.allVideosSettingsBinding.wrappedValue
        changed.filters.grayscale = true
        model.allVideosSettingsBinding.wrappedValue = changed
        #expect(model.draftSettings?.filters.grayscale == true)
    }

    @Test func referenceInfoIsTheFirstTargetsOrAnEmptyPlaceholder() throws {
        let model = try makeModel(2)
        #expect(model.panelReferenceInfo.url == model.sources[0].info?.url)
        let empty = try makeModel(0)
        #expect(empty.panelReferenceInfo.audioTracks.isEmpty && empty.panelReferenceInfo.duration == 0)
    }

    @Test func convertShowsTheFullPanelCompressTheSimpleOne() throws {
        let model = try makeModel(2)
        #expect(model.settingsPanelKind == .allVideos)
        model.selectedIDs = [model.sources[0].id]
        #expect(model.settingsPanelKind == .oneVideo)
        model.setMode(.compress)
        #expect(model.settingsPanelKind == .simple)
        model.setMode(.upscale)
        #expect(model.settingsPanelKind == .upscale)
    }

    @Test func tabsSitInTwoRowsOfFour() {
        #expect(SettingsTab.rows.count == 2 && SettingsTab.rows.allSatisfy { $0.count == 4 })
        #expect(SettingsTab.rows.flatMap { $0 } == SettingsTab.allCases)
    }
}
