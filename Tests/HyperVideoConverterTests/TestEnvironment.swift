import Foundation
import Testing
@testable import HyperVideoConverter

/// Isolated persistence folder and preferences so tests never touch the user's real ones.
@MainActor
struct TestEnvironment {
    let root: URL
    let support: URL
    let output: URL
    let defaults: UserDefaults

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hvc-app-\(UUID().uuidString)")
        support = root.appendingPathComponent("support")
        output = root.appendingPathComponent("out")
        for dir in [support, output] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let suite = "hvc-tests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(false, forKey: PreferenceKey.autoStartQueue)
        defaults.set(1, forKey: PreferenceKey.maxConcurrentJobs)
        defaults.set(false, forKey: PreferenceKey.revealOnCompletion)
        defaults.set(false, forKey: PreferenceKey.notifyOnCompletion)
        defaults.set("", forKey: PreferenceKey.outputSuffix)
        defaults.set(output.path, forKey: PreferenceKey.destinationPath)
    }

    /// Saves at once and resolves the saved queue inline, so tests can read the file back.
    func makeModel() -> AppModel {
        AppModel(directory: support, defaults: defaults, saveDelay: 0, resolvesInBackground: false)
    }
    func makeQueue() -> QueueStore {
        QueueStore(directory: support, defaults: defaults, saveDelay: 0, resolvesInBackground: false)
    }

    func workDirectories() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: output.path).filter { $0.hasPrefix(".hypervideo-") }
    }

    /// Polls the main actor until `condition` holds or the timeout passes.
    static func waitUntil(timeout: Duration = .seconds(30), _ condition: @MainActor () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
