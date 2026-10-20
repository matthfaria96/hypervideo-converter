import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Queue background I/O", .serialized)
struct QueueBackgroundIOTests {
    private func job(_ env: TestEnvironment, _ name: String, state: JobState = .cancelled) -> EncodeJob {
        EncodeJob(source: env.root.appendingPathComponent("\(name).mov"),
                  destination: env.output.appendingPathComponent("\(name).mp4"),
                  settings: EncodeSettings(), presetName: "Test").with(state: state)
    }

    /// Saves finished jobs (they need no source file) through a synchronous queue.
    private func saveJobs(_ env: TestEnvironment, _ names: [String]) -> [EncodeJob] {
        let saved = names.map { job(env, $0) }
        let queue = env.makeQueue()
        queue.add(saved)
        queue.flushPersistence()
        return queue.jobs
    }

    private func background(_ env: TestEnvironment) -> QueueStore {
        QueueStore(directory: env.support, defaults: env.defaults, saveDelay: 0, resolvesInBackground: true)
    }

    private func savedIDs(_ env: TestEnvironment) throws -> [UUID] {
        let data = try Data(contentsOf: env.support.appendingPathComponent("queue.json"))
        return try JSONDecoder().decode([EncodeJob].self, from: data).map(\.id)
    }

    @Test func queueFileLoadsInTheBackground() async throws {
        let env = try TestEnvironment()
        let saved = saveJobs(env, ["a", "b"])
        let queue = background(env)
        #expect(queue.isReady == false)
        #expect(queue.jobs.isEmpty)
        await queue.whenReady()
        #expect(queue.jobs.map(\.id) == saved.map(\.id))
        #expect(queue.jobs.map(\.state) == saved.map(\.state))
    }

    @Test func jobsAddedBeforeLoadAreKeptAfterTheSavedOnes() async throws {
        let env = try TestEnvironment()
        let saved = saveJobs(env, ["a", "b"])
        let queue = background(env)
        let added = job(env, "new", state: .queued)
        queue.add([added])
        await queue.whenReady()
        #expect(queue.jobs.map(\.id) == saved.map(\.id) + [added.id])
    }

    @Test func flushBeforeLoadNeverWritesAPartialList() async throws {
        let env = try TestEnvironment()
        let saved = saveJobs(env, ["a", "b"])
        let queue = background(env)
        let added = job(env, "new", state: .queued)
        queue.add([added])
        queue.flushPersistence()
        #expect(try savedIDs(env) == saved.map(\.id))
        await queue.whenReady()
        queue.flushPersistence()
        #expect(try savedIDs(env) == saved.map(\.id) + [added.id])
    }

    @Test func stopForQuitBeforeLoadWritesTheMergedList() async throws {
        let env = try TestEnvironment()
        let saved = saveJobs(env, ["a"])
        let queue = background(env)
        let added = job(env, "new", state: .queued)
        queue.add([added])
        await queue.stopForQuit()
        #expect(queue.isReady)
        #expect(try savedIDs(env) == saved.map(\.id) + [added.id])
    }

    @Test func cancelBeforeLoadAppliesToNewJobsOnly() async throws {
        let env = try TestEnvironment()
        let saved = saveJobs(env, ["a"])
        let queue = background(env)
        let added = job(env, "new", state: .queued)
        queue.add([added])
        queue.cancel(added.id)
        queue.remove([saved[0].id])
        #expect(queue.jobs.first?.state == .cancelled)
        await queue.whenReady()
        #expect(queue.jobs.map(\.id) == [saved[0].id, added.id])
    }

    @Test func retryRenamesWhenTheDestinationExists() async throws {
        let env = try TestEnvironment()
        let queue = env.makeQueue()
        let failed = job(env, "clip", state: .failed(message: "x"))
        queue.add([failed])
        try Data("x".utf8).write(to: failed.destination)
        await queue.retry(failed.id).value
        let retried = try #require(queue.jobs.first)
        #expect(retried.state == .queued)
        #expect(retried.destination.lastPathComponent == "clip 2.mp4")
    }

    @Test func retryKeepsAFreeDestination() async throws {
        let env = try TestEnvironment()
        let queue = env.makeQueue()
        let failed = job(env, "clip", state: .failed(message: "x"))
        queue.add([failed])
        await queue.retry(failed.id).value
        #expect(queue.jobs.first?.destination == failed.destination)
        #expect(queue.jobs.first?.state == .queued)
    }
}
