import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Adding to the queue", .serialized)
struct EnqueueTests {
    private func model(with names: [String], _ env: TestEnvironment) async throws -> AppModel {
        let model = env.makeModel()
        for name in names {
            await model.addSources([try await AppTestClip.make(in: env.root, .init(name: name))])
        }
        #expect(try await TestEnvironment.waitUntil { model.sources.count == names.count && model.sources.allSatisfy { $0.info != nil } })
        return model
    }

    @Test func enqueuedVideosLeaveTheListAndTheSelection() async throws {
        let env = try TestEnvironment()
        let model = try await model(with: ["a", "b", "c"], env)
        let ids = model.sources.map(\.id)
        model.selectedIDs = Set(ids)

        #expect(model.enqueue([ids[0]]) == 1)
        #expect(model.sources.map(\.id) == [ids[1], ids[2]])
        #expect(model.selectedIDs == [ids[1], ids[2]])
        #expect(model.queue.jobs.count == 1)
        // The queue row keeps the picture.
        #expect(model.ui.thumbnails[model.queue.jobs[0].source] != nil)
    }

    @Test func addToQueueThenConvertEncodesEachVideoOnce() async throws {
        let env = try TestEnvironment()
        let model = try await model(with: ["a", "b"], env)
        model.enqueue([model.sources[0].id])
        model.convertAll()
        #expect(model.queue.jobs.count == 2)
        #expect(Set(model.queue.jobs.map(\.source)).count == 2)
        #expect(model.sources.isEmpty)
        #expect(try await TestEnvironment.waitUntil(timeout: .seconds(60)) { model.queue.jobs.allSatisfy { $0.state.isFinished } })
        #expect(try FileManager.default.contentsOfDirectory(atPath: env.output.path).filter { !$0.hasPrefix(".") }.sorted()
            == ["a.mp4", "b.mp4"])
    }

    @Test func addAllToQueueEmptiesTheList() async throws {
        let env = try TestEnvironment()
        let model = try await model(with: ["a", "b"], env)
        model.selectedIDs = [model.sources[0].id]
        model.enqueueAll()
        #expect(model.sources.isEmpty)
        #expect(model.selectedIDs.isEmpty)
        #expect(model.queue.jobs.count == 2)
    }

    @Test func importingManyFilesInspectsEveryOne() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(name: "base"))
        let folder = env.root.appendingPathComponent("many")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<14 { try FileManager.default.copyItem(at: clip, to: folder.appendingPathComponent("v\(index).mov")) }
        try Data("1\n00:00:00,000 --> 00:00:00,500\nHi\n".utf8).write(to: folder.appendingPathComponent("v3.en.srt"))

        let model = env.makeModel()
        await model.addSources([folder])
        #expect(model.pendingFolderImport != nil)
        await model.confirmFolderImport(preset: model.defaultPreset)
        #expect(model.sources.count == 14)
        #expect(try await TestEnvironment.waitUntil { model.sources.allSatisfy { $0.info != nil } })
        let withSubtitles = model.sources.filter { !$0.subtitleFiles.isEmpty }
        #expect(withSubtitles.map(\.name) == ["v3.mov"])
        // List thumbnails are small (about twice their on-screen size), not the video's full frame.
        let width = try #require(model.sources.first?.thumbnail?.size.width)
        #expect(width <= AppModel.thumbnailSize.width)
    }

    @Test func thumbnailsAreReleasedWhenTheirJobsLeaveTheQueue() async throws {
        let env = try TestEnvironment()
        let model = try await model(with: ["a", "b"], env)
        model.enqueueAll()
        let first = model.queue.jobs[0]
        #expect(model.ui.thumbnails.count == 2)
        model.queue.remove([first.id])
        #expect(model.ui.thumbnails[first.source] == nil)
        #expect(model.ui.thumbnails.count == 1)
        model.queue.cancelAll()
        model.queue.clearFinished()
        #expect(model.ui.thumbnails.isEmpty)
    }
}
