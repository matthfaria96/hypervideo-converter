import Foundation
import SwiftUI
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@Suite("Design system")
struct DesignSystemTests {
    @Test func reduceMotionShortensEveryAnimationToACrossfade() {
        #expect(Motion.resolve(Motion.standard, reduceMotion: false) == Motion.standard)
        #expect(Motion.resolve(Motion.standard, reduceMotion: true) == Motion.crossfade)
        #expect(Motion.resolve(nil, reduceMotion: true) == nil)
    }

    @Test func spacingAndRadiiFollowTheEightPointGrid() {
        for value in [Spacing.xs, Spacing.s, Spacing.m, Spacing.l, Spacing.xl, Spacing.xxl] {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0, "\(value)")
        }
        #expect(Spacing.xs < Spacing.s && Spacing.s < Spacing.m && Spacing.m < Spacing.l && Spacing.l < Spacing.xl)
        #expect(Radius.s < Radius.m && Radius.m < Radius.l)
    }
}

@Suite("Sidebar navigation")
@MainActor
struct SidebarNavigationTests {
    @Test func everySidebarItemMapsToASectionAndBack() {
        for item in SidebarItem.allCases {
            #expect(SidebarItem.current(section: item.section, mode: item.mode ?? .convert) == item)
        }
    }

    @Test func compressIsTheConversionSectionInCompressMode() {
        #expect(SidebarItem.compress.section == .conversion && SidebarItem.compress.mode == .compress)
        #expect(SidebarItem.current(section: .conversion, mode: .compress) == .compress)
        #expect(SidebarItem.current(section: .conversion, mode: .convert) == .conversion)
    }

    @Test func initialSectionLaunchArgumentOpensThatPage() throws {
        let env = try TestEnvironment()
        env.defaults.set("favorites", forKey: "InitialSection")
        #expect(env.makeModel().section == .favorites)
        env.defaults.set("compress", forKey: "InitialSection")
        let compress = env.makeModel()
        #expect(compress.section == .conversion && compress.mode == .compress)
        env.defaults.set("bogus", forKey: "InitialSection")
        #expect(env.makeModel().section == .conversion)
    }

    @Test func selectingAnItemDrivesSectionAndMode() throws {
        let model = try TestEnvironment().makeModel()
        model.sidebarSelection = .history
        #expect(model.section == .history && model.sidebarSelection == .history)
        model.sidebarSelection = .compress
        #expect(model.section == .conversion && model.mode == .compress && model.sidebarSelection == .compress)
        model.sidebarSelection = .conversion
        #expect(model.mode == .convert)
        // Deselecting in the list (nil) keeps the current page.
        model.sidebarSelection = nil
        #expect(model.section == .conversion && model.sidebarSelection == .conversion)
    }
}

@Suite("Launch state")
@MainActor
struct LaunchStateTests {
    @Test func settingsNeedNoVideoOthersNeedAnAnalysedOne() throws {
        let model = try TestEnvironment().makeModel()
        #expect(LaunchState.isReady(.settings, model: model))
        #expect(!LaunchState.isReady(.advanced, model: model))
        model.setSources([WorkspaceTests.source("a.mov")])
        #expect(LaunchState.isReady(.advanced, model: model) && LaunchState.isReady(.converting, model: model))
    }

    @Test func parsesTheLaunchArgument() {
        UserDefaults.standard.set("converting", forKey: "LaunchState")
        #expect(LaunchState.requested == .converting)
        UserDefaults.standard.set("nope", forKey: "LaunchState")
        #expect(LaunchState.requested == nil)
        UserDefaults.standard.removeObject(forKey: "LaunchState")
    }
}

@Suite("Row facts")
struct RowFactsTests {
    @Test func tagsAreContainerCodecAndSizeWithoutTheDuration() {
        let url = URL(fileURLWithPath: "/tmp/clip.mov")
        let info = MediaInfo(url: url, duration: 135, displaySize: CGSize(width: 1920, height: 1080), frameRate: 30,
                             videoCodec: "HEVC", videoBitrate: nil, dynamicRange: .sdr, audioTracks: [], fileBytes: 1)
        #expect(RowFacts.tags(url: url, info: info) == ["MOV", "HEVC", "1920 × 1080"])
    }

    @Test func missingFactsAreLeftOut() {
        let url = URL(fileURLWithPath: "/tmp/noext")
        let info = MediaInfo(url: url, duration: 10, displaySize: nil, frameRate: nil,
                             videoCodec: nil, videoBitrate: nil, dynamicRange: .sdr, audioTracks: [], fileBytes: 1)
        #expect(RowFacts.tags(url: url, info: info).isEmpty)
    }
}

@Suite("Native list wiring")
@MainActor
struct NativeListTests {
    private func makeModel(_ count: Int) throws -> AppModel {
        let model = try TestEnvironment().makeModel()
        model.setSources((0..<count).map { SourceItem(url: URL(fileURLWithPath: "/tmp/v\($0).mov"), settings: EncodeSettings()) })
        return model
    }

    @Test func listSelectionOnlyKeepsVideosOnTheEditingList() throws {
        let model = try makeModel(2)
        let video = model.sources[1].id
        model.listSelection = [video, UUID()]
        #expect(model.selectedIDs == [video])
        #expect(model.listSelection == [video])
    }

    @Test func moveSourcesUsesListOffsets() throws {
        let model = try makeModel(3)
        let ids = model.sources.map(\.id)
        model.moveSources(fromOffsets: [0], toOffset: 3)
        #expect(model.sources.map(\.id) == [ids[1], ids[2], ids[0]])
        model.moveSources(fromOffsets: [2], toOffset: 0)
        #expect(model.sources.map(\.id) == ids)
    }

    @Test func inspectorStartsVisibleAndSidebarExpanded() {
        let ui = UIState()
        #expect(ui.isInspectorShown)
        #expect(!ui.isSidebarCollapsed)
        ui.isSidebarCollapsed = true
        #expect(ui.sidebarVisibility == .detailOnly)
        ui.sidebarVisibility = .all
        #expect(!ui.isSidebarCollapsed)
    }
}
