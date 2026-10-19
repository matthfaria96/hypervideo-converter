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
            PreferenceKey.revealOnCompletion: false,
            PreferenceKey.autoStartQueue: false,
            PreferenceKey.outputSuffix: ""
        ])
    }

    var body: some Scene {
        Window("HyperVideo Converter", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 680)
                .tint(Color(red: 1.0, green: 0.68, blue: 0.08))
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

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in model?.addSources(urls) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let queue = model?.queue, queue.runningCount > 0 else { return .terminateNow }
            // Let cancelled encodes remove their hidden work folders before the process exits.
            Task { @MainActor in
                await queue.stopForQuit()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Video…") { model.isImporting = true }
                .keyboardShortcut("o")
        }
        CommandMenu("Encode") {
            Button("Add to Queue") {
                if let id = model.selectedSource?.id { model.enqueue([id]) }
            }
            .keyboardShortcut("b")
            .disabled(model.selectedSource == nil)

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

            Button("Show Queue") { model.selection = .queue }
                .keyboardShortcut("1", modifiers: [.command, .option])
        }
        CommandGroup(after: .sidebar) {
            Button(model.showsPresetInspector ? "Hide Presets" : "Show Presets") {
                model.showsPresetInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
