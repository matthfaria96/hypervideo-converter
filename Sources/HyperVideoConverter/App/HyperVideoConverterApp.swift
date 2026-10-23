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
                .frame(minWidth: 1000, minHeight: 640)
                .onAppear { appDelegate.model = model }
                .modifier(WindowOpener(delegate: appDelegate))
        }
        // Opening files must not make SwiftUI re-activate the window with a full layout pass
        // (about a second with dozens of files); AppDelegate adds them to the list itself.
        .handlesExternalEvents(matching: [])
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Settings {
            PreferencesView()
                .environment(model)
        }
    }
}

/// Hands the delegate a way to open the main window again after it was closed.
private struct WindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let delegate: AppDelegate

    func body(content: Content) -> some View {
        content.onAppear { delegate.openMainWindow = { openWindow(id: "main") } }
    }
}

/// Lets Finder "Open With" and Dock drops reach the model.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var model: AppModel? {
        didSet { flushPendingURLs() }
    }
    /// Files opened before the window appeared and handed over the model (cold launch).
    @MainActor private var pendingURLs: [URL] = []
    @MainActor var openMainWindow: (() -> Void)?
    @MainActor private lazy var sessionEnd = SessionEndMonitor()
    @MainActor private lazy var quitCoordinator = QuitCoordinator(isSessionEnding: { [unowned self] in sessionEnd.isSessionEnding })

    func application(_ application: NSApplication, open urls: [URL]) {
        // Activate inside the event, while the system still counts it as the user's request.
        MainActor.assumeIsolated {
            showMainWindow()
            pendingURLs += urls
            flushPendingURLs()
        }
    }

    @MainActor private func flushPendingURLs() {
        guard let model, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        Task { await model.addSources(urls) }
    }

    /// Brings the window forward (SwiftUI no longer does it for opened files, see the scene).
    @MainActor private func showMainWindow() {
        // Opened files are the user's request, so take the focus even from another app.
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else {
            if let openMainWindow {
                openMainWindow()
            } else {
                // Cold launch from "Open With": the open event matches no scene (see
                // handlesExternalEvents), so SwiftUI never presents the window. Ask it the
                // way a Dock click does once launching has settled.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Self.reopenIfNoWindow() }
            }
            return
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    /// Sends this app the Apple Event a Dock click sends; SwiftUI answers it by
    /// presenting the main window.
    @MainActor private static func reopenIfNoWindow() {
        guard !NSApp.windows.contains(where: { $0.canBecomeMain }) else { return }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                           eventID: AEEventID(kAEReopenApplication),
                                           targetDescriptor: .currentProcess(),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        do {
            try event.sendEvent(options: [.noReply], timeout: 1)
        } catch {
            appLog.error("Could not reopen the main window: \(error.localizedDescription, privacy: .public)")
        }
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
            // ⌘1/⌘2 pick the mode like HyperImage (⌘3 stays free for AI Upscale).
            Button("Convert") { model.setMode(.convert) }
                .keyboardShortcut("1")
            Button("Compress") { model.setMode(.compress) }
                .keyboardShortcut("2")
            Divider()
            Button("History") { model.presentedPage = .history }
                .keyboardShortcut("y")
            Button("Favorites") { model.presentedPage = .favorites }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Analyze Video") { model.presentedPage = .analyze }
                .keyboardShortcut("i")
            Divider()
            ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                Button { model.ui.detailTab = tab } label: { Text(tab.title) }
                    .keyboardShortcut(SettingsTab.shortcutDigit(at: index).map {
                        KeyboardShortcut(KeyEquivalent($0), modifiers: [.command, .option])
                    })
                    .disabled(model.panelSource == nil && model.ui.advancedSourceID == nil)
            }
            Divider()
            Button(model.ui.isInspectorShown ? "Hide Output Settings" : "Show Output Settings") {
                model.ui.isInspectorShown.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
