import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralPreferences() }
            Tab("Queue", systemImage: "list.bullet.rectangle") { QueuePreferences() }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

private struct GeneralPreferences: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PreferenceKey.outputSuffix) private var suffix = ""
    @AppStorage(PreferenceKey.notifyOnCompletion) private var notify = true
    @AppStorage(PreferenceKey.notifyEachJob) private var notifyEachJob = false
    @AppStorage(PreferenceKey.bounceDockOnCompletion) private var bounceDock = false
    @AppStorage(PreferenceKey.playSoundOnCompletion) private var playSound = false
    @AppStorage(PreferenceKey.revealOnCompletion) private var reveal = false

    var body: some View {
        Form {
            LabeledContent("Save converted files to") {
                Button(model.destinationFolder.lastPathComponent, systemImage: "folder") { model.chooseDestination() }
                    .help(model.destinationFolder.path)
            }
            TextField("File name suffix", text: $suffix, prompt: Text("e.g. -converted"))
            LabeledContent("Default preset", value: model.defaultPreset.name)
            Toggle("Notify when the queue finishes", isOn: $notify)
            Toggle("Also notify for each conversion", isOn: $notifyEachJob)
            Toggle("Bounce the Dock icon when the queue finishes", isOn: $bounceDock)
            Toggle("Play a sound when the queue finishes", isOn: $playSound)
            Toggle("Show finished files in Finder", isOn: $reveal)
        }
        .formStyle(.grouped)
    }
}

private struct QueuePreferences: View {
    @AppStorage(PreferenceKey.maxConcurrentJobs) private var maxConcurrent = 1
    @AppStorage(PreferenceKey.autoStartQueue) private var autoStart = false

    var body: some View {
        Form {
            Picker("Simultaneous encodes", selection: $maxConcurrent) {
                ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
            }
            Text("Apple Silicon Pro, Max and Ultra chips have several media engines; 2 or more speeds up batch work.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Start encoding as soon as a job is added", isOn: $autoStart)
        }
        .formStyle(.grouped)
    }
}
