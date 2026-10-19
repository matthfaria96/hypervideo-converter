import AppKit

/// Dock badge and Finder reveal; notifications are in `SystemNotifier`.
@MainActor
enum SystemIntegration {
    static func updateDock(progress: Double?, pendingCount: Int) {
        if let progress {
            NSApp?.dockTile.badgeLabel = "\(Int((progress * 100).rounded()))%"
        } else {
            NSApp?.dockTile.badgeLabel = pendingCount > 0 ? "\(pendingCount)" : nil
        }
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
