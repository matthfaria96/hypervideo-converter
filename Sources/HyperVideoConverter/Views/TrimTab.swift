import AVKit
import HyperVideoCore
import SwiftUI

/// Built-in player with In/Out marking, so trimming needs no guesswork.
struct TrimTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings
    @Environment(AppModel.self) private var model

    /// The shared preview player, only while it shows this video.
    private var player: AVPlayer? {
        guard let player = model.ui.previewPlayer,
              (player.currentItem?.asset as? AVURLAsset)?.url == info.url else { return nil }
        return player
    }

    private var start: Double { settings.trim?.start ?? 0 }
    private var end: Double { settings.trim?.end ?? info.duration }

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(title: "Preview", symbol: "play.rectangle") {
                PlayerView(player: player)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxHeight: 380)
                    .clipShape(.rect(cornerRadius: 14))
            }

            SettingsSection(title: "Trim", symbol: "timeline.selection") {
                HStack(spacing: 16) {
                    marker("Start", value: start)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    marker("End", value: end)
                    Spacer()
                    Text("Length \(Format.duration(max(0, end - start)))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Group {
                    HStack(spacing: 8) {
                        Button("Set Start", systemImage: "chevron.left.to.line") { setStart(currentTime) }
                        Button("Set End", systemImage: "chevron.right.to.line") { setEnd(currentTime) }
                        Button("Play Selection", systemImage: "play.fill") { playSelection() }
                        Spacer()
                        Button("Clear", systemImage: "xmark") {
                            resetSelectionPlayback()
                            settings.trim = nil
                        }
                            .disabled(settings.trim == nil)
                    }
                    .compatGlassButtonStyle()
                }
            }
        }
        .onAppear { _ = model.ui.player(for: info.url) }
        .onChange(of: info.url) { _, url in _ = model.ui.player(for: url) }
        .onReceive(
            NotificationCenter.default.publisher(for: AVPlayer.rateDidChangeNotification).receive(on: RunLoop.main)
        ) { note in
            // A pause (by the user or at the selection's end) ends the Play Selection run, so
            // resuming with the player's own controls plays past the selection.
            if let changed = note.object as? AVPlayer, changed === player, changed.rate == 0 {
                resetSelectionPlayback()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            if let item = note.object as? AVPlayerItem, item === player?.currentItem { resetSelectionPlayback() }
        }
        .onDisappear {
            player?.pause()
            resetSelectionPlayback()
        }
    }

    private var aspectRatio: CGFloat {
        guard let size = info.displaySize, size.height > 0 else { return 16 / 9 }
        return size.width / size.height
    }

    private var currentTime: Double { player?.currentTime().seconds ?? 0 }

    private func marker(_ title: LocalizedStringKey, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Format.duration(value)).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

    private func setStart(_ time: Double) {
        resetSelectionPlayback()
        let clamped = min(max(0, time), end - 0.1)
        settings.trim = TrimRange(start: clamped, end: settings.trim?.end)
    }

    private func setEnd(_ time: Double) {
        resetSelectionPlayback()
        let clamped = max(min(info.duration, time), start + 0.1)
        settings.trim = TrimRange(start: start, end: clamped >= info.duration ? nil : clamped)
    }

    private func playSelection() {
        guard let player else { return }
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    /// Lifts the Play Selection stop point so normal playback runs to the end again.
    private func resetSelectionPlayback() {
        player?.currentItem?.forwardPlaybackEndTime = .invalid
    }
}

/// AppKit's player view. SwiftUI's `VideoPlayer` lives in a cross-import overlay that
/// doesn't link AVKit itself, so with a SwiftPM build its AVPlayerView superclass
/// can't be resolved at runtime and the app aborts when the view appears.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    /// Takes exactly the offered size. AVPlayerView's own fitting size changes with its
    /// controls layout, which can feed back into SwiftUI layout and loop on constraint
    /// updates until AppKit throws when the player or its video changes.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVPlayerView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 640, height: 360))
    }
}
