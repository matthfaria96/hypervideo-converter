import AppKit

/// Dock badge and Finder reveal; notifications are in `SystemNotifier`.
@MainActor
enum SystemIntegration {
    private static var currentBadge: String?

    /// The Dock badge text: the overall percentage, else the number of waiting jobs.
    static func badge(progress: Double?, pendingCount: Int) -> String? {
        if let progress { return "\(Int((progress * 100).rounded()))%" }
        return pendingCount > 0 ? "\(pendingCount)" : nil
    }

    /// Touches the Dock tile only when the text changes (progress ticks mostly don't change it).
    static func updateDock(progress: Double?, pendingCount: Int) {
        let badge = badge(progress: progress, pendingCount: pendingCount)
        guard badge != currentBadge else { return }
        currentBadge = badge
        NSApp?.dockTile.badgeLabel = badge
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
