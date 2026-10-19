import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("App model", .serialized)
struct AppModelTests {
    @Test func encodeNowDoesNotStartQueueWhenNothingWasAdded() throws {
        let env = try TestEnvironment()
        let broken = env.root.appendingPathComponent("broken.mov")
        try Data("nope".utf8).write(to: broken)
        let model = env.makeModel()
        model.addSources([broken])
        let id = try #require(model.sources.first?.id)
        // Not inspected yet (info == nil), so enqueue skips it.
        model.encodeNow(id)
        #expect(model.queue.jobs.isEmpty)
        #expect(model.queue.isProcessing == false)
        #expect(model.selection == .source(id))
        #expect(model.alertMessage != nil)
    }

    @Test func encodeNowStartsQueueAndSelectsIt() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(name: "now"))
        let model = env.makeModel()
        model.addSources([clip])
        let id = try #require(model.sources.first?.id)
        #expect(try await TestEnvironment.waitUntil { model.sources.first?.info != nil })
        model.encodeNow(id)
        #expect(model.queue.jobs.count == 1)
        #expect(model.selection == .queue)
        #expect(try await TestEnvironment.waitUntil(timeout: .seconds(60)) {
            model.queue.jobs.first.map { $0.state.isFinished } ?? false
        })
        if case .completed = model.queue.jobs.first?.state {} else {
            Issue.record("job did not complete: \(String(describing: model.queue.jobs.first?.state))")
        }
        #expect(FileManager.default.fileExists(atPath: env.output.appendingPathComponent("now.mp4").path))
    }

    @Test func inspectMergesSidecarsWithUserAddedSubtitles() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(name: "movie"))
        let srt = "1\n00:00:00,000 --> 00:00:00,500\nHello\n"
        let sidecar = env.root.appendingPathComponent("movie.en.srt")
        try Data(srt.utf8).write(to: sidecar)
        let extras = env.root.appendingPathComponent("extras")
        try FileManager.default.createDirectory(at: extras, withIntermediateDirectories: true)
        let userFile = extras.appendingPathComponent("commentary.srt")
        try Data(srt.utf8).write(to: userFile)

        let model = env.makeModel()
        model.addSources([clip])
        let id = try #require(model.sources.first?.id)
        // Added before inspection finishes (it runs in a later main-actor task).
        model.addSubtitleFiles([userFile, sidecar], to: id)
        #expect(model.sources.first?.info == nil)
        #expect(try await TestEnvironment.waitUntil { model.sources.first?.info != nil })

        let urls = model.sources.first?.subtitleFiles.map(\.url.standardizedFileURL) ?? []
        #expect(urls == [sidecar.standardizedFileURL, userFile.standardizedFileURL])
    }
}
