import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
final class RecordingNotifier: QueueNotifying {
    private(set) var jobs: [(name: String, succeeded: Bool)] = []
    private(set) var summaries: [(done: Int, failed: Int)] = []

    func jobFinished(_ job: EncodeJob, succeeded: Bool) {
        jobs.append((job.source.deletingPathExtension().lastPathComponent, succeeded))
    }

    func queueFinished(done: Int, failed: Int) { summaries.append((done, failed)) }
}

@MainActor
@Suite("Completion notifications", .serialized)
struct NotificationTests {
    private func bogusJob(_ env: TestEnvironment, _ name: String) -> EncodeJob {
        EncodeJob(source: env.root.appendingPathComponent("\(name).mov"),
                  destination: env.output.appendingPathComponent("\(name).mp4"),
                  settings: EncodeSettings(), presetName: "Test")
    }

    @Test func summaryCountsDoneAndFailed() {
        #expect(QueueSummary(done: 3, failed: 0) == QueueSummary(done: 3, failed: 0))
        #expect(QueueSummary(done: 3, failed: 0).title == "Queue finished")
        #expect(QueueSummary(done: 3, failed: 0).body == "3 videos converted")
        #expect(QueueSummary(done: 1, failed: 2).title == "Queue finished with errors")
        #expect(QueueSummary(done: 1, failed: 2).body == "1 video converted, 2 failed")
    }

    @Test func testProcessNeverReachesNotificationCenter() throws {
        #expect(!SystemNotifier.canNotify)
        let env = try TestEnvironment()
        for key in [PreferenceKey.notifyOnCompletion, PreferenceKey.notifyEachJob, PreferenceKey.bounceDockOnCompletion] {
            env.defaults.set(true, forKey: key)
        }
        let notifier = SystemNotifier(defaults: env.defaults)
        notifier.jobFinished(bogusJob(env, "a"), succeeded: false)
        notifier.queueFinished(done: 1, failed: 1)
    }

    @Test func oneSummaryWhenTheQueueRunsDry() async throws {
        let env = try TestEnvironment()
        let recorder = RecordingNotifier()
        let queue = QueueStore(directory: env.support, defaults: env.defaults, notifier: recorder)
        queue.add(["a", "b", "c"].map { bogusJob(env, $0) })
        queue.start()
        #expect(try await TestEnvironment.waitUntil { queue.jobs.allSatisfy(\.state.isFinished) })
        #expect(recorder.jobs.map(\.name) == ["a", "b", "c"])
        #expect(recorder.jobs.allSatisfy { !$0.succeeded })
        #expect(recorder.summaries.count == 1)
        #expect(recorder.summaries.first?.done == 0)
        #expect(recorder.summaries.first?.failed == 3)
    }

    @Test func successesAreCounted() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(name: "good"))
        let recorder = RecordingNotifier()
        let model = AppModel(directory: env.support, defaults: env.defaults, notifier: recorder)
        model.addSources([clip])
        #expect(try await TestEnvironment.waitUntil { model.sources.first?.info != nil })
        model.enqueueAll()
        model.queue.add([bogusJob(env, "bad")])
        model.queue.start()
        #expect(try await TestEnvironment.waitUntil(timeout: .seconds(60)) { recorder.summaries.count == 1 })
        #expect(recorder.summaries.first?.done == 1)
        #expect(recorder.summaries.first?.failed == 1)
    }

    @Test func cancellingEverythingPostsNoSummary() async throws {
        let env = try TestEnvironment()
        let recorder = RecordingNotifier()
        let queue = QueueStore(directory: env.support, defaults: env.defaults, notifier: recorder)
        queue.add([bogusJob(env, "a"), bogusJob(env, "b")])
        queue.cancelAll()
        #expect(queue.jobs.allSatisfy { $0.state == .cancelled })
        #expect(recorder.summaries.isEmpty)
    }
}
