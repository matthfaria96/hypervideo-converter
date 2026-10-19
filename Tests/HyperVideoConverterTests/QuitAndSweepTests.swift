import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Quit and stale work folders", .serialized)
struct QuitAndSweepTests {
    @Test func stopForQuitCancelsEncodesAndRemovesWorkFolders() async throws {
        let env = try TestEnvironment()
        env.defaults.set(2, forKey: PreferenceKey.maxConcurrentJobs)
        let clip = try await AppTestClip.make(in: env.root, .init(
            name: "long", size: CGSize(width: 1920, height: 1080),
            frameTimes: (0..<180).map { Double($0) / 30 }, seconds: 6
        ))
        var settings = EncodeSettings()
        settings.videoCodec = .proRes422HQ
        settings.container = .mov
        let jobs = ["a", "b"].map { name in
            EncodeJob(source: clip, destination: env.output.appendingPathComponent("\(name).mov"),
                      settings: settings, presetName: "Test")
        }
        let queue = env.makeQueue()
        queue.add(jobs)
        queue.start()
        #expect(queue.runningCount == 2)
        #expect(try await TestEnvironment.waitUntil { (try? env.workDirectories().count) == 2 })

        await queue.stopForQuit()

        #expect(try env.workDirectories().isEmpty)
        #expect(queue.runningCount == 0)
        #expect(queue.isProcessing == false)
        #expect(queue.jobs.allSatisfy { $0.state == .queued })
        let outputs = try FileManager.default.contentsOfDirectory(atPath: env.output.path)
        #expect(outputs.isEmpty)
        // Persisted as queued, so a relaunch resumes them.
        let relaunched = env.makeQueue()
        #expect(relaunched.jobs.map(\.state) == [.queued, .queued])
    }

    @Test func stopForQuitWithNothingRunningIsHarmless() async throws {
        let env = try TestEnvironment()
        let queue = env.makeQueue()
        await queue.stopForQuit()
        #expect(queue.jobs.isEmpty)
        #expect(queue.isProcessing == false)
    }

    @Test func launchSweepsStaleWorkFoldersNextToQueuedOutputs() throws {
        let env = try TestEnvironment()
        let job = EncodeJob(source: env.root.appendingPathComponent("s.mov"),
                            destination: env.output.appendingPathComponent("s.mp4"),
                            settings: EncodeSettings(), presetName: "Test")
        env.makeQueue().add([job])
        let stale = env.output.appendingPathComponent(".hypervideo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: stale.appendingPathComponent("s.mp4"))
        let keep = env.output.appendingPathComponent("keep.mp4")
        try Data("done".utf8).write(to: keep)

        let relaunched = env.makeQueue()

        #expect(relaunched.jobs.count == 1)
        #expect(try env.workDirectories().isEmpty)
        #expect(FileManager.default.fileExists(atPath: keep.path))
    }

    @Test func relaunchRequeuesJobsThatWereRunning() throws {
        let env = try TestEnvironment()
        try Data("x".utf8).write(to: env.root.appendingPathComponent("s.mov"))
        var running = EncodeJob(source: env.root.appendingPathComponent("s.mov"),
                                destination: env.output.appendingPathComponent("s.mp4"),
                                settings: EncodeSettings(), presetName: "Test")
        running.state = .running(progress: 0.4)
        try JSONEncoder().encode([running]).write(to: env.support.appendingPathComponent("queue.json"))
        #expect(env.makeQueue().jobs.first?.state == .queued)
    }
}

@MainActor
@Suite("Stop immediately for session end", .serialized)
struct StopImmediatelyTests {
    @Test func stopImmediatelyRequeuesAndRemovesWorkFolders() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(
            name: "long", size: CGSize(width: 1920, height: 1080),
            frameTimes: (0..<180).map { Double($0) / 30 }, seconds: 6
        ))
        var settings = EncodeSettings()
        settings.videoCodec = .proRes422HQ
        settings.container = .mov
        let job = EncodeJob(source: clip, destination: env.output.appendingPathComponent("a.mov"),
                            settings: settings, presetName: "Test")
        let queue = env.makeQueue()
        queue.add([job])
        queue.start()
        #expect(try await TestEnvironment.waitUntil { (try? env.workDirectories().count) == 1 })

        queue.stopImmediately()

        // Synchronous: by the time it returns, the job is requeued and persisted and the folder is gone.
        #expect(queue.isProcessing == false)
        #expect(queue.jobs.map(\.state) == [.queued])
        #expect(try env.workDirectories().isEmpty)
        #expect(env.makeQueue().jobs.map(\.state) == [.queued])
        // Let the cancelled task wind down before the temp folder goes away.
        #expect(try await TestEnvironment.waitUntil { queue.runningCount == 0 })
    }
}
