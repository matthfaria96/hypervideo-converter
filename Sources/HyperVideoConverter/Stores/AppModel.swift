import AppKit
@preconcurrency import AVFoundation
import HyperVideoCore
import Observation
import UniformTypeIdentifiers

struct SourceItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var info: MediaInfo?
    var errorMessage: String?
    var thumbnail: NSImage?
    var settings: EncodeSettings
    var presetID: UUID?

    var isLoading: Bool { info == nil && errorMessage == nil }
    var name: String { url.lastPathComponent }
}

enum SidebarItem: Hashable {
    case source(UUID)
    case queue
}

@Observable
@MainActor
final class AppModel {
    let presets = PresetStore()
    let queue = QueueStore()
    let ui = UIState()

    private(set) var sources: [SourceItem] = []
    var selection: SidebarItem?
    var showsPresetInspector = true
    var isImporting = false
    var alertMessage: String?

    var destinationFolder: URL {
        didSet { UserDefaults.standard.set(destinationFolder.path, forKey: PreferenceKey.destinationPath) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: PreferenceKey.destinationPath)
        destinationFolder = saved.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        if queue.jobs.contains(where: { !$0.state.isFinished }) { selection = .queue }
        SystemIntegration.requestNotificationPermission()
    }

    var defaultPreset: Preset {
        let id = UserDefaults.standard.string(forKey: PreferenceKey.defaultPresetID).flatMap(UUID.init(uuidString:))
        return presets.preset(id: id) ?? BuiltInPresets.default
    }

    var selectedSource: SourceItem? {
        guard case .source(let id) = selection else { return nil }
        return sources.first { $0.id == id }
    }

    // MARK: Sources

    func addSources(_ urls: [URL]) {
        let existing = Set(sources.map(\.url))
        let accepted = urls.filter(Self.isMedia).filter { !existing.contains($0) }
        guard !accepted.isEmpty else {
            if !urls.isEmpty && existing.isDisjoint(with: urls) { alertMessage = "None of those files are video or audio." }
            return
        }
        let preset = defaultPreset
        let items = accepted.map { SourceItem(url: $0, settings: preset.settings, presetID: preset.id) }
        sources = sources + items
        selection = .source(items[0].id)
        items.forEach { item in Task { await inspect(item) } }
    }

    func removeSource(_ id: UUID) {
        sources = sources.filter { $0.id != id }
        if selection == .source(id) { selection = sources.first.map { .source($0.id) } }
    }

    func clearSources() {
        sources = []
        selection = queue.jobs.isEmpty ? nil : .queue
    }

    private func inspect(_ item: SourceItem) async {
        do {
            let info = try await MediaInspector.inspect(item.url)
            let thumbnail = await Self.thumbnail(for: item.url, duration: info.duration)
            update(item.id) { $0.info = info; $0.thumbnail = thumbnail }
        } catch {
            update(item.id) { $0.errorMessage = error.localizedDescription }
        }
    }

    private static func thumbnail(for url: URL, duration: Double) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let time = CMTime(seconds: min(duration * 0.1, 5), preferredTimescale: 600)
        guard let (image, _) = try? await generator.image(at: time) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    private static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audiovisualContent)
    }

    // MARK: Settings

    func update(_ id: UUID, _ change: (inout SourceItem) -> Void) {
        sources = sources.map { item in
            guard item.id == id else { return item }
            var copy = item
            change(&copy)
            return copy
        }
    }

    func applyPreset(_ preset: Preset, to id: UUID) {
        update(id) { item in
            var settings = preset.settings
            settings.trim = item.settings.trim
            item.settings = settings
            item.presetID = preset.id
        }
    }

    func applyToAll(from id: UUID) {
        guard let template = sources.first(where: { $0.id == id }) else { return }
        sources = sources.map { item in
            var copy = item
            var settings = template.settings
            settings.trim = item.settings.trim
            copy.settings = settings
            copy.presetID = template.presetID
            return copy
        }
    }

    func presetName(for item: SourceItem) -> String {
        guard let preset = presets.preset(id: item.presetID) else { return "Custom" }
        return preset.settings == item.settings ? preset.name : "\(preset.name) (modified)"
    }

    // MARK: Queue

    func enqueue(_ ids: [UUID]) {
        let suffix = UserDefaults.standard.string(forKey: PreferenceKey.outputSuffix) ?? ""
        var taken = queue.takenDestinations
        var jobs: [EncodeJob] = []
        var skipped: [String] = []
        for item in sources where ids.contains(item.id) {
            guard item.info != nil, item.settings.isValid else {
                skipped.append(item.name)
                continue
            }
            let destination = OutputNaming.destination(
                for: item.url, in: destinationFolder, container: item.settings.container, suffix: suffix, taken: taken
            )
            taken.insert(destination)
            jobs.append(EncodeJob(source: item.url, destination: destination, settings: item.settings,
                                  presetName: presetName(for: item)))
        }
        if !skipped.isEmpty { alertMessage = "Skipped (not ready or invalid settings): \(skipped.joined(separator: ", "))" }
        guard !jobs.isEmpty else { return }
        queue.add(jobs)
    }

    func enqueueAll() { enqueue(sources.map(\.id)) }

    func encodeNow(_ id: UUID) {
        enqueue([id])
        queue.start()
        selection = .queue
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destinationFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { destinationFolder = url }
    }
}
