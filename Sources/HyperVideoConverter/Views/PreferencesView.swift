import SwiftUI

/// Settings (⌘,): grouped forms with icons, in the style of System Settings panes.
struct PreferencesView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralPreferences() }
            Tab("Queue", systemImage: "list.bullet.rectangle") { QueuePreferences() }
            Tab("About", systemImage: "info.circle") { AboutView() }
        }
        .frame(width: 560)
    }
}

/// A form row's label with a tinted symbol tile, like System Settings.
struct SettingIcon: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint.gradient, in: .rect(cornerRadius: 6))
        }
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
            Section("Output") {
                LabeledContent {
                    Button(model.destinationFolder.lastPathComponent, systemImage: "folder") { model.chooseDestination() }
                        .help(model.destinationFolder.path)
                } label: {
                    SettingIcon(title: "Save converted files to", symbol: "folder.fill", tint: .blue)
                }
                LabeledContent {
                    TextField("File name suffix", text: $suffix, prompt: Text("e.g. -converted"))
                        .labelsHidden()
                        .frame(maxWidth: 180)
                } label: {
                    SettingIcon(title: "File name suffix", symbol: "textformat", tint: .gray)
                }
                LabeledContent {
                    Text(verbatim: model.defaultPreset.displayName).foregroundStyle(.secondary)
                } label: {
                    SettingIcon(title: "Default preset", symbol: "star.fill", tint: Theme.accent)
                }
            }
            Section("When the queue finishes") {
                Toggle(isOn: $notify) { SettingIcon(title: "Notify when the queue finishes", symbol: "bell.badge.fill", tint: .red) }
                Toggle(isOn: $notifyEachJob) { SettingIcon(title: "Also notify for each conversion", symbol: "bell.fill", tint: .orange) }
                    .disabled(!notify)
                Toggle(isOn: $bounceDock) { SettingIcon(title: "Bounce the Dock icon when the queue finishes", symbol: "dock.rectangle", tint: .purple) }
                Toggle(isOn: $playSound) { SettingIcon(title: "Play a sound when the queue finishes", symbol: "speaker.wave.2.fill", tint: .pink) }
                Toggle(isOn: $reveal) { SettingIcon(title: "Show finished files in Finder", symbol: "magnifyingglass", tint: .teal) }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct QueuePreferences: View {
    @AppStorage(PreferenceKey.maxConcurrentJobs) private var maxConcurrent = 1
    @AppStorage(PreferenceKey.autoStartQueue) private var autoStart = false

    var body: some View {
        Form {
            Section {
                Picker(selection: $maxConcurrent) {
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                } label: {
                    SettingIcon(title: "Simultaneous encodes", symbol: "square.stack.3d.up.fill", tint: .indigo)
                }
                Toggle(isOn: $autoStart) {
                    SettingIcon(title: "Start encoding as soon as a job is added", symbol: "play.fill", tint: .green)
                }
            } footer: {
                Text("Apple Silicon Pro, Max and Ultra chips have several media engines; 2 or more speeds up batch work.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}
