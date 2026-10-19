import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Queue destinations")
struct QueueStoreTests {
    private func job(_ env: TestEnvironment, name: String = "clip") -> EncodeJob {
        EncodeJob(
            source: env.root.appendingPathComponent("\(name).mov"),
            destination: env.output.appendingPathComponent("\(name).mp4"),
            settings: EncodeSettings(), presetName: "Test"
        )
    }

    @Test func cancelledAndFailedJobsKeepTheirDestinationReserved() throws {
        let env = try TestEnvironment()
        let queue = env.makeQueue()
        let first = job(env)
        queue.add([first])
        queue.cancel(first.id)
        #expect(queue.jobs.first?.state == .cancelled)
        #expect(queue.takenDestinations.contains(first.destination))
    }

    @Test func completedJobsReleaseTheirDestination() throws {
        let env = try TestEnvironment()
        var done = job(env)
        done.state = .completed(outputBytes: 1, elapsed: 1)
        try JSONEncoder().encode([done]).write(to: env.support.appendingPathComponent("queue.json"))
        let queue = env.makeQueue()
        #expect(queue.jobs.count == 1)
        #expect(queue.takenDestinations.isEmpty)
    }

    @Test func enqueueAvoidsDestinationOfCancelledJob() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(name: "clip"))
        let model = env.makeModel()
        model.addSources([clip])
        let id = try #require(model.sources.first?.id)
        #expect(try await TestEnvironment.waitUntil { model.sources.first?.info != nil })

        #expect(model.enqueue([id]) == 1)
        let first = try #require(model.queue.jobs.first)
        model.queue.cancel(first.id)
        #expect(model.enqueue([id]) == 1)
        let second = try #require(model.queue.jobs.last)
        #expect(second.destination != first.destination)
        #expect(second.destination.lastPathComponent == "clip 2.mp4")
    }

    @Test func retryPicksNewDestinationWhenAnotherJobHoldsIt() throws {
        let env = try TestEnvironment()
        let queue = env.makeQueue()
        let first = job(env)
        var second = job(env)
        second.destination = first.destination
        queue.add([first])
        queue.cancel(first.id)
        queue.add([second])
        queue.retry(first.id)
        let retried = try #require(queue.jobs.first { $0.id == first.id })
        #expect(retried.state == .queued)
        #expect(retried.destination.lastPathComponent == "clip 2.mp4")
        #expect(Set(queue.jobs.map(\.destination)).count == 2)
    }

    @Test func retryPicksNewDestinationWhenFileExists() throws {
        let env = try TestEnvironment()
        let queue = env.makeQueue()
        let failed = job(env)
        queue.add([failed])
        queue.cancel(failed.id)
        try Data("x".utf8).write(to: failed.destination)
        queue.retry(failed.id)
        let retried = try #require(queue.jobs.first)
        #expect(retried.destination.lastPathComponent == "clip 2.mp4")
    }

    @Test func retryKeepsDestinationWhenFree() throws {
        let env = try TestEnvironment()
        let queue = env.makeQueue()
        let cancelled = job(env)
        queue.add([cancelled])
        queue.cancel(cancelled.id)
        queue.retry(cancelled.id)
        #expect(queue.jobs.first?.destination == cancelled.destination)
        #expect(queue.jobs.first?.state == .queued)
    }

    @Test func retryHonoursOutputSuffix() throws {
        let env = try TestEnvironment()
        env.defaults.set("-hv", forKey: PreferenceKey.outputSuffix)
        let queue = env.makeQueue()
        let cancelled = job(env)
        queue.add([cancelled])
        queue.cancel(cancelled.id)
        try Data("x".utf8).write(to: cancelled.destination)
        queue.retry(cancelled.id)
        #expect(queue.jobs.first?.destination.lastPathComponent == "clip-hv.mp4")
    }
}
