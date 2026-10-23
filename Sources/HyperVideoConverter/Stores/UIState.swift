import AppKit
import AVFoundation
import HyperVideoCore
import Observation
import SwiftUI

/// A video's big picture, for the Analyze header.
struct HeroPicture {
    let url: URL
    let image: NSImage
}

/// Transient view state kept in an observable object instead of `@State`,
/// so the app also builds with the Command Line Tools toolchain (no SwiftUI macro plugin).
@Observable
@MainActor
final class UIState {
    var isDropTargeted = false
    /// Launch argument `-InitialSettingsTab filters` picks the first tab (used for screenshots).
    var detailTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "InitialSettingsTab") ?? "") ?? .summary
    /// A lone video whose panel the user closed; selecting it again reopens the panel.
    var dismissedPanelSourceID: UUID?
    var presetName = ""
    var renamingPreset: Preset?
    /// Thumbnails of videos that moved from the editing list into the queue.
    var thumbnails: [URL: NSImage] = [:]
    /// The large picture of the Analyze header: the video last shown there.
    var hero: HeroPicture?
    /// When the user last pressed Convert; the finished-run banner counts from here.
    var batchStartedAt: Date?
    /// When the last run started; History marks its results "New" even after the banner is dismissed.
    var lastRunStartedAt: Date?
    /// Compress mode's target, in MB per video (stored by AppModel).
    var compressTargetMB: Double?
    /// A run finished since History was last opened (the footer's badge turns green).
    var hasUnseenResults = false
    /// Confirmations of destructive actions.
    var confirmingClearList = false
    var confirmingClearHistory = false
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
