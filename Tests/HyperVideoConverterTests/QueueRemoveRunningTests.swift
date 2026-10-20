import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Removing running jobs", .serialized)
struct QueueRemoveRunningTests {
    private func longJobs(_ env: TestEnvironment, names: [String]) async throws -> [EncodeJob] {
        let clip = try await AppTestClip.make(in: env.root, .init(
            name: "long", size: CGSize(width: 1920, height: 1080),
            frameTimes: (0..<180).map { Double($0) / 30 }, seconds: 6
        ))
        var settings = EncodeSettings()
        settings.videoCodec = .proRes422HQ
        settings.container = .mov
        return names.map { name in
            EncodeJob(source: clip, destination: env.output.appendingPathComponent("\(name).mov"),
                      settings: settings, presetName: "Test")
        }
    }

    @Test func removeRunningJobRemovesIt() async throws {
        let env = try TestEnvironment()
        let jobs = try await longJobs(env, names: ["a"])
        let queue = env.makeQueue()
        var removed: [UUID] = []
        queue.onJobsRemoved = { removed += $0.map(\.id) }
        queue.add(jobs)
        queue.start()
        #expect(queue.runningCount == 1)
        #expect(try await TestEnvironment.waitUntil { (try? env.workDirectories().count) == 1 })

        queue.remove([jobs[0].id])

        #expect(try await TestEnvironment.waitUntil { queue.jobs.isEmpty })
        #expect(queue.runningCount == 0)
        #expect(try env.workDirectories().isEmpty)
        #expect(env.makeQueue().jobs.isEmpty)
        #expect(removed == [jobs[0].id])
    }

    @Test func removeRunningAndQueuedRemovesBoth() async throws {
        let env = try TestEnvironment()
        let jobs = try await longJobs(env, names: ["a", "b"])
        let queue = env.makeQueue()
        queue.add(jobs)
        queue.start()
        #expect(queue.runningCount == 1)

        queue.remove(Set(jobs.map(\.id)))

        #expect(try await TestEnvironment.waitUntil { queue.jobs.isEmpty })
        #expect(queue.runningCount == 0)
        #expect(env.makeQueue().jobs.isEmpty)
    }

    @Test func sweepSkipsRunningJobsFolders() throws {
        let env = try TestEnvironment()
        let job = EncodeJob(source: env.root.appendingPathComponent("s.mov"),
                            destination: env.output.appendingPathComponent("s.mp4"),
                            settings: EncodeSettings(), presetName: "Test")
        let runningID = UUID()
        let kept = env.output.appendingPathComponent(WorkFolder.name(jobID: runningID))
        let swept = env.output.appendingPathComponent(WorkFolder.name(jobID: UUID()))
        for dir in [kept, swept] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        QueueStore.sweepStaleWorkDirectories(in: [job], skipping: [runningID])

        #expect(FileManager.default.fileExists(atPath: kept.path))
        #expect(!FileManager.default.fileExists(atPath: swept.path))
    }

    @Test func stopForQuitDropsJobPendingRemoval() async throws {
        let env = try TestEnvironment()
        let jobs = try await longJobs(env, names: ["a"])
        let queue = env.makeQueue()
        queue.add(jobs)
        queue.start()
        #expect(try await TestEnvironment.waitUntil { (try? env.workDirectories().count) == 1 })

        queue.remove([jobs[0].id])
        await queue.stopForQuit()

        #expect(queue.jobs.isEmpty)
        #expect(env.makeQueue().jobs.isEmpty)
    }

    @Test func stopImmediatelyDropsJobPendingRemoval() async throws {
        let env = try TestEnvironment()
        let jobs = try await longJobs(env, names: ["a"])
        let queue = env.makeQueue()
        queue.add(jobs)
        queue.start()
        #expect(try await TestEnvironment.waitUntil { (try? env.workDirectories().count) == 1 })

        queue.remove([jobs[0].id])
        queue.stopImmediately()

        #expect(queue.jobs.isEmpty)
        #expect(env.makeQueue().jobs.isEmpty)
        #expect(try env.workDirectories().isEmpty)
        #expect(try await TestEnvironment.waitUntil { queue.runningCount == 0 })
    }
}
