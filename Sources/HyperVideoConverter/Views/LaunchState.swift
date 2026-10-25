import SwiftUI

/// Launch argument `-LaunchState converting|settings|preview|select|targetSize` puts the window in that
/// state once the opened videos are analysed, like `-InitialSettingsTab` and
/// `-InitialSection` (used for screenshots). `-OpenOnLaunch '(a.mov, b.mp4)'` adds those files
/// without bringing the app to the front, so screenshots can be taken in the background.
enum LaunchState: String {
    case converting, settings, preview, select, targetSize

    static var requested: LaunchState? {
        UserDefaults.standard.string(forKey: "LaunchState").flatMap(LaunchState.init(rawValue:))
    }

    static var filesToOpen: [URL] {
        (UserDefaults.standard.stringArray(forKey: "OpenOnLaunch") ?? []).map { URL(fileURLWithPath: $0) }
    }

    /// Whether the window is ready to enter the state: settings need nothing, the
    /// others an analysed video.
    @MainActor
    static func isReady(_ state: LaunchState, model: AppModel) -> Bool {
        state == .settings || model.sources.contains { $0.info != nil }
    }
}

struct LaunchStateModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var applied = false

    func body(content: Content) -> some View {
        content.task {
            guard !applied else { return }
            applied = true
            let files = LaunchState.filesToOpen
            if !files.isEmpty { await model.addSources(files, folderPreset: nil) }
            guard let state = LaunchState.requested else { return }
            // Waits up to 20 s for the opened videos to be analysed.
            for _ in 0..<200 where !LaunchState.isReady(state, model: model) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            apply(state)
        }
    }

    private func apply(_ state: LaunchState) {
        switch state {
        case .converting: model.convertAll()
        case .settings: openSettings()
        case .preview: model.ui.previewSourceID = model.sources.first?.id
        case .select: model.selectedIDs = Set(model.sources.prefix(1).map(\.id))
        case .targetSize: model.compressTargetMB = 25
        }
    }
}

/// Launch argument `-ScreenshotActiveLook YES` draws the controls as in the frontmost window even when
/// the app stays in the background (screenshots taken without taking the focus from other apps).
struct ScreenshotLookModifier: ViewModifier {
    private let forced = UserDefaults.standard.bool(forKey: "ScreenshotActiveLook")

    func body(content: Content) -> some View {
        if forced {
            content.environment(\.controlActiveState, .key)
        } else {
            content
        }
    }
}
