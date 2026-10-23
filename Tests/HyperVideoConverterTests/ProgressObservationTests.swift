import Foundation
import HyperVideoCore
import Observation
import Testing
@testable import HyperVideoConverter

/// A view that reads a job's progress before the job starts must be told when the
/// real progress box appears, or it keeps showing the placeholder's 0%.
@Suite("Progress observation")
@MainActor
struct ProgressObservationTests {
    final class Flag: @unchecked Sendable { var fired = false }

    @Test func readingProgressBeforeLaunchIsNotifiedWhenTheJobStarts() throws {
        let env = try TestEnvironment()
        let queue = env.makeQueue()
        // The source doesn't exist: the job fails later, but it launches (and gets its box) first.
        let job = EncodeJob(source: env.root.appendingPathComponent("missing.mov"),
                            destination: env.output.appendingPathComponent("o.mp4"),
                            settings: EncodeSettings(), presetName: "Test")
        queue.add([job])

        let flag = Flag()
        withObservationTracking {
            // What JobRowView reads while the job is still waiting.
            _ = queue.progress(for: job.id).fraction
        } onChange: {
            flag.fired = true
        }
        #expect(!flag.fired)
        queue.start()
        #expect(flag.fired)
    }
}
