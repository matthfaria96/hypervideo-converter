import AppKit
import AVFoundation
import HyperVideoCore
import Observation

/// Transient view state kept in an observable object instead of `@State`,
/// so the app also builds with the Command Line Tools toolchain (no SwiftUI macro plugin).
@Observable
@MainActor
final class UIState {
    var isDropTargeted = false
    var detailTab: SettingsTab = .summary
    var isSavingPreset = false
    var presetName = ""
    var renamingPreset: Preset?
    var isSidebarCollapsed = false
    /// The video whose Advanced settings sheet is open.
    var advancedSourceID: UUID?
    /// Thumbnails of videos that moved from the editing list into the queue.
    var thumbnails: [URL: NSImage] = [:]
    /// When the user last pressed Convert; the finished-run banner counts from here.
    var batchStartedAt: Date?
    /// Confirmations of destructive actions.
    var confirmingClearList = false
    var confirmingClearHistory = false
    var confirmingApplyToAll = false
    /// The file shown in Quick Look (Space on a selected row).
    var quickLookURL: URL?

    private(set) var previewPlayer: AVPlayer?

    func player(for url: URL) -> AVPlayer {
        if let player = previewPlayer, (player.currentItem?.asset as? AVURLAsset)?.url == url { return player }
        previewPlayer?.pause()
        let player = AVPlayer(url: url)
        previewPlayer = player
        return player
    }
}
