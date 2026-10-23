import Foundation
import HyperVideoCore
import Testing
@testable import HyperVideoConverter

@Suite("Polish", .serialized)
@MainActor
struct PolishTests {
    /// Jobs restored from the saved queue have no picture yet; their rows load one.
    @Test func queueRowsLoadAMissingThumbnail() async throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        let clip = try await AppTestClip.make(in: env.root, .init(name: "clip"))
        let job = EncodeJob(source: clip, destination: env.output.appendingPathComponent("o.mp4"),
                            settings: EncodeSettings(), presetName: "Test", mediaDuration: 1)
        #expect(model.ui.thumbnails[clip] == nil)
        await model.loadQueueThumbnail(for: job)
        #expect(model.ui.thumbnails[clip] != nil)
    }

    @Test func aMissingSourceLeavesThePlaceholder() async throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        let missing = env.root.appendingPathComponent("gone.mov")
        let job = EncodeJob(source: missing, destination: env.output.appendingPathComponent("o.mp4"),
                            settings: EncodeSettings(), presetName: "Test")
        await model.loadQueueThumbnail(for: job)
        #expect(model.ui.thumbnails[missing] == nil)
    }

    @Test func videoListHeaderHidesWhenOnlyTheQueueHasItems() throws {
        let env = try TestEnvironment()
        let model = env.makeModel()
        #expect(!model.showsVideoListHeader)
        model.setSources([WorkspaceTests.source("a.mov")])
        #expect(model.showsVideoListHeader)
    }
}
