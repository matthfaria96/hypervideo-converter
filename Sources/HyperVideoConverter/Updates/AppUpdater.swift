import AppKit
import Sparkle
import SwiftUI

/// In-app updates through Sparkle, like Sirena and Wineup. The feed (SUFeedURL), the EdDSA public key
/// (SUPublicEDKey) and the daily automatic check live in Resources/Info.plist; updates are signed with
/// the witchmymac EdDSA key and the app with the witchmymac certificate.
@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    /// The real app's bundle id. Test copies (another bundle id) don't check, unless HYPERVIDEO_UPDATES=1.
    private static let releaseBundleID = "com.hypervideo.converter"

    /// False while a check or an install is already under way.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private init() {}

    /// Starts Sparkle's scheduler (daily check, from Info.plist). Call once at launch.
    func start() {
        guard controller == nil else { return }
        let env = ProcessInfo.processInfo.environment
        guard Bundle.main.bundleIdentifier == Self.releaseBundleID || env["HYPERVIDEO_UPDATES"] != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            MainActor.assumeIsolated { self?.canCheckForUpdates = canCheck }
        }
        controller.startUpdater()
    }

    /// "Check for Updates…": always shows a result, even "You're up to date".
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// The app menu item and the About button: disabled while a check is already under way.
struct CheckForUpdatesButton: View {
    private let updater = AppUpdater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
