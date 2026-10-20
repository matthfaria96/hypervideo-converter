import AppKit

/// Presents open and save panels as sheets on the key window instead of app-modal
/// dialogs. Falls back to a standalone panel when no window is available.
@MainActor
enum PanelPresenter {
    static func present(_ panel: NSSavePanel, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { completion(response) }
            }
        } else {
            panel.begin { response in
                MainActor.assumeIsolated { completion(response) }
            }
        }
    }
}
