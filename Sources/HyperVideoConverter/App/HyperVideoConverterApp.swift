import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct HyperVideoConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel()

    init() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.maxConcurrentJobs: 1,
            PreferenceKey.notifyOnCompletion: true,
            PreferenceKey.notifyEachJob: false,
            PreferenceKey.bounceDockOnCompletion: false,
            PreferenceKey.playSoundOnCompletion: false,
            PreferenceKey.revealOnCompletion: false,
            PreferenceKey.autoStartQueue: false,
            PreferenceKey.outputSuffix: ""
        ])
    }

    var body: some Scene {
        Window("HyperVideo Converter", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 680)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .onAppear { appDelegate.model = model }
        }
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Settings {
            PreferencesView()
                .environment(model)
        }
    }
}

/// Lets Finder "Open With" and Dock drops reach the model.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var model: AppModel?
    @MainActor private lazy var sessionEnd = SessionEndMonitor()
    @MainActor private lazy var quitCoordinator = QuitCoordinator(isSessionEnding: { [unowned self] in sessionEnd.isSessionEnding })

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in model?.addSources(urls) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // Lets cancelled encodes remove their hidden work folders before the process exits.
            quitCoordinator.shouldTerminate(queue: model?.queue)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start watching for logout/shutdown before any quit can arrive.
        MainActor.assumeIsolated { _ = sessionEnd }
        // Needed when launched as a bare SwiftPM executable rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Choose Videos…") {
                model.section = .conversion
                model.isImporting = true
            }
            .keyboardShortcut("o")
        }
        CommandMenu("Encode") {
            Button(model.mode == .compress ? "Compress Videos" : "Convert Videos") { model.convertAll() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.readySourceCount == 0 && model.queue.pendingCount == 0)

            Button("Add Selected to Queue") { model.enqueue(Array(model.selectedIDs)) }
                .keyboardShortcut("b")
                .disabled(model.selectedIDs.isEmpty)

            Button("Add All to Queue") { model.enqueueAll() }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(model.sources.isEmpty)

            Divider()

            Button("Start Queue") { model.queue.start() }
                .keyboardShortcut("r")
                .disabled(model.queue.pendingCount == 0)
            Button("Pause Queue") { model.queue.pause() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(!model.queue.isProcessing)
            Button("Cancel All") { model.queue.cancelAll() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.queue.runningCount == 0 && model.queue.pendingCount == 0)

            Divider()

            Button("Advanced Settings…") { model.ui.advancedSourceID = model.selectedSource?.id }
                .keyboardShortcut("e")
                .disabled(model.selectedSource?.info == nil)
            Button(model.allSourcesSelected ? "Deselect All" : "Select All Videos") { model.toggleSelectAll() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.sources.isEmpty)
            Button("Deselect All") { model.selectedIDs = [] }
                .keyboardShortcut("d")
            Button("Remove Selected Videos") { model.removeSelectedSources() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedIDs.isEmpty)
        }
        CommandGroup(after: .sidebar) {
            Button("Conversion") { model.setMode(.convert) }
                .keyboardShortcut("1")
            Button("History") { model.section = .history }
                .keyboardShortcut("2")
            Button("Favorites") { model.section = .favorites }
                .keyboardShortcut("3")
            Button("Compress") { model.setMode(.compress) }
                .keyboardShortcut("4")
            Button("Analyze Video") { model.section = .analyze }
                .keyboardShortcut("5")
            Divider()
            Button(model.ui.isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar") {
                model.ui.isSidebarCollapsed.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
    }
}
