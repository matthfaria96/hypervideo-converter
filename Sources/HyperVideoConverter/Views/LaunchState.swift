import SwiftUI

/// Launch argument `-LaunchState advanced|converting|settings` puts the window in that
/// state once the opened videos are analysed, like `-InitialSettingsTab` and
/// `-InitialSection` (used for screenshots).
enum LaunchState: String {
    case advanced, converting, settings

    static var requested: LaunchState? {
        UserDefaults.standard.string(forKey: "LaunchState").flatMap(LaunchState.init(rawValue:))
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
            guard let state = LaunchState.requested, !applied else { return }
            // Waits up to 20 s for the opened videos to be analysed.
            for _ in 0..<200 where !LaunchState.isReady(state, model: model) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            applied = true
            apply(state)
        }
    }

    private func apply(_ state: LaunchState) {
        switch state {
        case .advanced: model.ui.advancedSourceID = model.sources.first?.id
        case .converting: model.convertAll()
        case .settings: openSettings()
        }
    }
}
