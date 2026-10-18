import AppKit
import UserNotifications

/// Dock badge, completion notifications and Finder reveal.
@MainActor
enum SystemIntegration {
    private static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    static func updateDock(progress: Double?, pendingCount: Int) {
        if let progress {
            NSApp.dockTile.badgeLabel = "\(Int((progress * 100).rounded()))%"
        } else {
            NSApp.dockTile.badgeLabel = pendingCount > 0 ? "\(pendingCount)" : nil
        }
    }

    static func requestNotificationPermission() {
        guard canNotify else { return }
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                appLog.error("Notification permission failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func notify(title: String, body: String) {
        guard canNotify, UserDefaults.standard.object(forKey: PreferenceKey.notifyOnCompletion) as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
