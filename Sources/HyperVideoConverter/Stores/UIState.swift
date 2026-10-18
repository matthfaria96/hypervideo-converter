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

    private(set) var previewPlayer: AVPlayer?

    func player(for url: URL) -> AVPlayer {
        if let player = previewPlayer, (player.currentItem?.asset as? AVURLAsset)?.url == url { return player }
        previewPlayer?.pause()
        let player = AVPlayer(url: url)
        previewPlayer = player
        return player
    }
}
