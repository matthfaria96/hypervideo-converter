import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Queue persistence", .serialized)
struct QueuePersistenceTests {
    private func job(_ env: TestEnvironment, _ name: String, state: JobState = .queued) -> EncodeJob {
        var job = EncodeJob(source: env.root.appendingPathComponent("\(name).mov"),
                            destination: env.output.appendingPathComponent("\(name).mp4"),
                            settings: EncodeSettings(), presetName: "Test")
        job.state = state
        return job
    }

    private func savedData(_ env: TestEnvironment) -> Data? {
        try? Data(contentsOf: env.support.appendingPathComponent("queue.json"))
    }

    @Test func burstsOfChangesBecomeOneWriteOfTheLatestState() async throws {
        let env = try TestEnvironment()
        let queue = QueueStore(directory: env.support, defaults: env.defaults, saveDelay: 0.3, resolvesInBackground: false)
        queue.add((0..<5).map { job(env, "j\($0)") })
        for _ in 0..<10 { queue.move(fromOffsets: [0], toOffset: 3) }
        // Nothing is written on the main thread right away.
        #expect(savedData(env) == nil)
        #expect(try await TestEnvironment.waitUntil(timeout: .seconds(5)) { savedData(env) != nil })
        let saved = try JSONDecoder().decode([EncodeJob].self, from: try #require(savedData(env)))
        #expect(saved.map(\.id) == queue.jobs.map(\.id))
    }

    @Test func flushWritesPendingChangesAtOnce() throws {
        let env = try TestEnvironment()
        let queue = QueueStore(directory: env.support, defaults: env.defaults, saveDelay: 60, resolvesInBackground: false)
        queue.add([job(env, "a")])
        #expect(savedData(env) == nil)
        queue.flushPersistence()
        #expect(savedData(env) != nil)
    }

    @Test func quittingFlushesTheQueue() async throws {
        let env = try TestEnvironment()
        let queue = QueueStore(directory: env.support, defaults: env.defaults, saveDelay: 60, resolvesInBackground: false)
        queue.add([job(env, "a"), job(env, "b")])
        await queue.stopForQuit()
        let saved = try JSONDecoder().decode([EncodeJob].self, from: try #require(savedData(env)))
        #expect(saved.count == 2)
    }

    @Test func savedFileIsCompactAndOldPrettyFilesStillLoad() throws {
        let env = try TestEnvironment()
        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
        let old = [job(env, "old")]
        try pretty.encode(old).write(to: env.support.appendingPathComponent("queue.json"))
        let queue = env.makeQueue()
        #expect(queue.jobs.map(\.id) == old.map(\.id))
        queue.add([job(env, "new")])
        let text = String(decoding: try #require(savedData(env)), as: UTF8.self)
        #expect(!text.contains("\n"))
    }

    @Test func historyKeepsTheNewestFinishedJobs() throws {
        let env = try TestEnvironment()
        var jobs = (0..<8).map { job(env, "f\($0)", state: .cancelled) }
        jobs.insert(job(env, "waiting"), at: 3)
        let kept = QueueStore.pruned(jobs, limit: 5)
        #expect(kept.count == 6)
        #expect(kept.map(\.source.lastPathComponent).contains("waiting.mov"))
        let finished = kept.filter { $0.state.isFinished }.map(\.source.lastPathComponent)
        #expect(finished == ["f3.mov", "f4.mov", "f5.mov", "f6.mov", "f7.mov"])
        #expect(QueueStore.pruned(jobs, limit: 100) == jobs)
    }

    @Test func loadingPrunesAHugeHistoryAndTellsWhoWasDropped() throws {
        let env = try TestEnvironment()
        let limit = QueueStore.historyLimit
        let history = (0..<(limit + 30)).map { job(env, "h\($0)", state: .completed(outputBytes: 1, elapsed: 1)) }
        try JSONEncoder().encode(history).write(to: env.support.appendingPathComponent("queue.json"))
        let queue = env.makeQueue()
        #expect(queue.jobs.count == limit)
        #expect(queue.jobs.first?.source.lastPathComponent == "h30.mov")
        var dropped: [EncodeJob] = []
        queue.onJobsRemoved = { dropped += $0 }
        queue.clearFinished()
        #expect(dropped.count == limit)
        #expect(queue.jobs.isEmpty)
    }

    @Test func launchWorkRunsInTheBackgroundWithoutTouchingNewJobs() async throws {
        let env = try TestEnvironment()
        let source = env.root.appendingPathComponent("gone.mov")
        try Data("x".utf8).write(to: source)
        let saved = job(env, "gone")
        env.makeQueue().add([saved])
        try FileManager.default.removeItem(at: env.root.appendingPathComponent("gone.mov"))

        let queue = QueueStore(directory: env.support, defaults: env.defaults, saveDelay: 0, resolvesInBackground: true)
        #expect(queue.isReady == false)
        let added = job(env, "added")
        queue.add([added])
        await queue.whenReady()
        #expect(queue.isReady)
        guard case .failed = queue.jobs.first(where: { $0.id == saved.id })?.state else {
            Issue.record("the saved job with a missing source should fail once launch work is done")
            return
        }
        // A job added while launch work ran keeps its state (its source doesn't exist either).
        #expect(queue.jobs.first { $0.id == added.id }?.state == .queued)
    }

    @Test func startingBeforeLaunchWorkFinishesWaitsForIt() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(name: "ok"))
        let model = env.makeModel()
        await model.addSources([clip])
        #expect(try await TestEnvironment.waitUntil { model.sources.first?.info != nil })
        model.enqueueAll()
        model.queue.flushPersistence()

        let queue = QueueStore(directory: env.support, defaults: env.defaults, saveDelay: 0, resolvesInBackground: true)
        queue.start()
        #expect(queue.runningCount == 0)
        await queue.whenReady()
        #expect(queue.runningCount == 1)
        await queue.stopForQuit()
    }
}

@MainActor
@Suite("Progress updates")
struct ProgressTests {
    @Test func throttleLimitsRateAndStep() {
        let throttle = ProgressThrottle(minInterval: 0.1, minStep: 0.01)
        #expect(throttle.accepts(0.0, at: 0))
        #expect(!throttle.accepts(0.5, at: 0.05))     // too soon
        #expect(!throttle.accepts(0.001, at: 0.2))    // moved less than 1%
        #expect(throttle.accepts(0.02, at: 0.2))
        #expect(throttle.accepts(1.0, at: 0.31))
    }

    @Test func fiveHundredTicksInOneSecondMakeAtMostTenUpdates() {
        let throttle = ProgressThrottle()
        let shown = (0..<500).filter { throttle.accepts(Double($0) / 500, at: Double($0) / 500) }
        #expect(shown.count <= 11)
        #expect(shown.count >= 9)
    }

    @Test func progressNeverMovesBackward() {
        let box = JobProgress()
        box.advance(to: 0.4)
        box.advance(to: 0.3)
        #expect(box.fraction == 0.4)
    }

    @Test func dockBadgeOnlyChangesWithItsText() {
        #expect(SystemIntegration.badge(progress: 0.504, pendingCount: 3) == "50%")
        #expect(SystemIntegration.badge(progress: 0.5049, pendingCount: 0) == "50%")
        #expect(SystemIntegration.badge(progress: nil, pendingCount: 3) == "3")
        #expect(SystemIntegration.badge(progress: nil, pendingCount: 0) == nil)
    }

    @Test func runningJobProgressIsKeptOutOfTheJobList() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(
            name: "long", size: CGSize(width: 1280, height: 720),
            frameTimes: (0..<120).map { Double($0) / 30 }, seconds: 4
        ))
        var settings = EncodeSettings()
        settings.videoCodec = .proRes422HQ
        settings.container = .mov
        let queue = env.makeQueue()
        let job = EncodeJob(source: clip, destination: env.output.appendingPathComponent("p.mov"),
                            settings: settings, presetName: "Test")
        queue.add([job])
        queue.start()
        let box = queue.progress(for: job.id)
        #expect(try await TestEnvironment.waitUntil(timeout: .seconds(60)) { box.fraction > 0 || queue.jobs[0].state.isFinished })
        // The list entry stays "running"; only the job's own progress object moves.
        if queue.jobs[0].state.isRunning { #expect(queue.jobs[0].state == .running(progress: 0)) }
        #expect(try await TestEnvironment.waitUntil(timeout: .seconds(60)) { queue.jobs[0].state.isFinished })
        #expect(queue.overallProgress == nil)
    }
}
