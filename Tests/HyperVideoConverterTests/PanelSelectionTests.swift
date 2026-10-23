import Foundation
import Testing
@testable import HyperVideoConverter

@Suite("Panel selection")
@MainActor
struct PanelSelectionTests {
    private func makeItems(_ count: Int) -> [SourceItem] {
        (0..<count).map { SourceItem(url: URL(fileURLWithPath: "/tmp/v\($0).mov"), settings: EncodeSettings()) }
    }

    private func makeModel(_ count: Int) throws -> AppModel {
        let model = try TestEnvironment().makeModel()
        model.setSources(makeItems(count))
        return model
    }

    @Test func noSourcesHasNoPanel() throws {
        #expect(try makeModel(0).panelSource == nil)
    }

    @Test func singleSourceShowsPanel() throws {
        let model = try makeModel(1)
        #expect(model.panelSource?.id == model.sources[0].id)
    }

    @Test func severalSourcesNothingSelectedHasNoPanel() throws {
        #expect(try makeModel(2).panelSource == nil)
    }

    @Test func oneSelectedShowsPanelTwoSelectedDoesNot() throws {
        let model = try makeModel(3)
        model.selectedIDs = [model.sources[1].id]
        #expect(model.panelSource?.id == model.sources[1].id)
        model.selectedIDs = [model.sources[0].id, model.sources[1].id]
        #expect(model.panelSource == nil)
    }

    @Test func closeThenReselectReopens() throws {
        let model = try makeModel(1)
        model.closePanel()
        #expect(model.panelSource == nil)
        model.selectedIDs = [model.sources[0].id]
        #expect(model.panelSource?.id == model.sources[0].id)
    }

    @Test func showFirstVideoSettingsSelectsFirst() throws {
        let model = try makeModel(3)
        model.showFirstVideoSettings()
        #expect(model.selectedIDs == [model.sources[0].id])
        #expect(model.panelSource?.id == model.sources[0].id)
    }

    @Test func settingsBindingWritesThrough() throws {
        let model = try makeModel(2)
        var changed = EncodeSettings()
        changed.audioBitrateKbps = 96
        model.settingsBinding(for: model.sources[1].id).wrappedValue = changed
        #expect(model.sources[1].settings == changed)
    }

    @Test func tabsAreTheEightHandBrakeTabs() {
        #expect(SettingsTab.allCases == [.summary, .dimensions, .filters, .video, .audio, .subtitles, .chapters, .tags])
        #expect(SettingsTab.allCases.map(\.symbol) == ["doc.text.magnifyingglass", "crop", "camera.filters", "film", "waveform", "captions.bubble", "list.bullet.indent", "tag"])
    }

    @Test func initialTabFollowsDefaults() {
        UserDefaults.standard.set("filters", forKey: "InitialSettingsTab")
        #expect(UIState().detailTab == .filters)
        UserDefaults.standard.set("bogus", forKey: "InitialSettingsTab")
        #expect(UIState().detailTab == .summary)
        UserDefaults.standard.removeObject(forKey: "InitialSettingsTab")
    }
}
