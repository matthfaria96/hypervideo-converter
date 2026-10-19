import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Queue order")
struct QueueOrderTests {
    /// Three queued jobs named a, b, c whose sources don't exist (they fail fast if started).
    private func queue(_ env: TestEnvironment) -> (QueueStore, [EncodeJob]) {
        let queue = env.makeQueue()
        let jobs = ["a", "b", "c"].map { name in
            EncodeJob(source: env.root.appendingPathComponent("\(name).mov"),
                      destination: env.output.appendingPathComponent("\(name).mp4"),
                      settings: EncodeSettings(), presetName: "Test")
        }
        queue.add(jobs)
        return (queue, jobs)
    }

    private func names(_ queue: QueueStore) -> [String] {
        queue.jobs.map { $0.source.deletingPathExtension().lastPathComponent }
    }

    @Test func moveUpDownAndToTop() throws {
        let env = try TestEnvironment()
        let (queue, jobs) = queue(env)
        queue.move(jobs[2].id, .up)
        #expect(names(queue) == ["a", "c", "b"])
        queue.move(jobs[0].id, .down)
        #expect(names(queue) == ["c", "a", "b"])
        queue.move(jobs[1].id, .top)
        #expect(names(queue) == ["b", "c", "a"])
    }

    @Test func movesPastTheEndsAreDisabledAndIgnored() throws {
        let env = try TestEnvironment()
        let (queue, jobs) = queue(env)
        #expect(!queue.canMove(jobs[0].id, .up))
        #expect(!queue.canMove(jobs[0].id, .top))
        #expect(!queue.canMove(jobs[2].id, .down))
        #expect(queue.canMove(jobs[1].id, .down))
        queue.move(jobs[0].id, .up)
        queue.move(jobs[2].id, .down)
        #expect(names(queue) == ["a", "b", "c"])
    }

    @Test func dragTakesTheTargetsPlace() throws {
        let env = try TestEnvironment()
        let (queue, jobs) = queue(env)
        queue.move(jobs[0].id, onto: jobs[2].id)
        #expect(names(queue) == ["b", "c", "a"])
        queue.move(jobs[0].id, onto: jobs[1].id)
        #expect(names(queue) == ["a", "b", "c"])
        queue.move(jobs[1].id, onto: jobs[1].id)
        #expect(names(queue) == ["a", "b", "c"])
    }

    @Test func orderIsPersisted() throws {
        let env = try TestEnvironment()
        let (queue, jobs) = queue(env)
        queue.move(jobs[2].id, .top)
        #expect(names(env.makeQueue()) == ["c", "a", "b"])
    }

    @Test func pendingJobsLaunchInListOrderUpToTheLimit() {
        let make = { (name: String, state: JobState) -> EncodeJob in
            EncodeJob(source: URL(fileURLWithPath: "/x/\(name).mov"), destination: URL(fileURLWithPath: "/y/\(name).mp4"),
                      settings: EncodeSettings(), presetName: "T").with(state: state)
        }
        let jobs = [make("done", .cancelled), make("run", .running(progress: 0.5)),
                    make("p1", .queued), make("p2", .queued), make("p3", .queued)]
        #expect(QueueStore.nextToLaunch(jobs, limit: 1).isEmpty)
        #expect(QueueStore.nextToLaunch(jobs, limit: 3).map(\.id) == [jobs[2].id, jobs[3].id])
    }

    @Test func startRunsTheTopPendingJobFirst() throws {
        let env = try TestEnvironment()
        let (queue, jobs) = queue(env)
        queue.move(jobs[2].id, .top)
        queue.start()
        #expect(queue.jobs.first { $0.id == jobs[2].id }?.state.isRunning == true)
        #expect(queue.jobs.filter(\.state.isRunning).count == 1)
    }
}
