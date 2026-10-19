import AppKit
import HyperVideoCore
import UserNotifications

/// What the queue tells the user about finished work.
@MainActor
protocol QueueNotifying: AnyObject {
    func jobFinished(_ job: EncodeJob, succeeded: Bool)
    /// Every pending job has run; `done` and `failed` count this run's jobs.
    func queueFinished(done: Int, failed: Int)
}

/// The text of the notification posted when the whole queue is done.
struct QueueSummary: Equatable {
    let title: String
    let body: String

    init(done: Int, failed: Int) {
        title = failed == 0 ? String(localized: "Queue finished") : String(localized: "Queue finished with errors")
        let converted = done == 1 ? String(localized: "1 video converted") : String(localized: "\(done) videos converted")
        let failures = failed == 1 ? String(localized: "1 failed") : String(localized: "\(failed) failed")
        body = failed == 0 ? converted : "\(converted), \(failures)"
    }
}

/// Posts notifications through Notification Center (asking for permission the first
/// time one is needed), and optionally bounces the Dock icon and plays a sound.
@MainActor
final class SystemNotifier: QueueNotifying {
    private let defaults: UserDefaults
    private var authorization: Task<Bool, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `UNUserNotificationCenter` traps without an app bundle, e.g. under `swift run`
    /// or in a test runner, so only a real `.app` with a bundle ID posts.
    static var canNotify: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private func enabled(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    func jobFinished(_ job: EncodeJob, succeeded: Bool) {
        if succeeded && enabled(PreferenceKey.revealOnCompletion, default: false) {
            SystemIntegration.reveal([job.destination])
        }
        guard enabled(PreferenceKey.notifyEachJob, default: false) else { return }
        post(title: succeeded ? String(localized: "Conversion finished") : String(localized: "Conversion failed"),
             body: succeeded ? job.destination.lastPathComponent : job.source.lastPathComponent)
    }

    func queueFinished(done: Int, failed: Int) {
        if enabled(PreferenceKey.notifyOnCompletion, default: true) {
            let summary = QueueSummary(done: done, failed: failed)
            post(title: summary.title, body: summary.body)
        }
        if enabled(PreferenceKey.bounceDockOnCompletion, default: false), let app = NSApp, !app.isActive {
            app.requestUserAttention(.informationalRequest)
        }
        if enabled(PreferenceKey.playSoundOnCompletion, default: false) {
            NSSound(named: "Glass")?.play()
        }
    }

    private func post(title: String, body: String) {
        guard Self.canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let authorization = authorization ?? Task {
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                appLog.error("Notification permission failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        self.authorization = authorization
        Task {
            guard await authorization.value else { return }
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                appLog.error("Couldn't post a notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
