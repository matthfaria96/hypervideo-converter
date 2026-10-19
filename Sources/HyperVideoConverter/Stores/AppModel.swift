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
    /// External SRT/WebVTT files: found next to the video, or added by the user.
    var subtitleFiles: [SubtitleFile] = []

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
    let presets: PresetStore
    let queue: QueueStore
    private let defaults: UserDefaults
    let ui = UIState()

    private(set) var sources: [SourceItem] = []
    var selection: SidebarItem?
    var showsPresetInspector = true
    var isImporting = false
    var alertMessage: String?

    var destinationFolder: URL {
        didSet { defaults.set(destinationFolder.path, forKey: PreferenceKey.destinationPath) }
    }

    /// `directory` and `defaults` override persistence and preferences (tests).
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        presets = PresetStore(directory: directory)
        queue = QueueStore(directory: directory, defaults: defaults)
        self.defaults = defaults
        let saved = defaults.string(forKey: PreferenceKey.destinationPath)
        destinationFolder = saved.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        if queue.jobs.contains(where: { !$0.state.isFinished }) { selection = .queue }
        SystemIntegration.requestNotificationPermission()
    }

    var defaultPreset: Preset {
        let id = defaults.string(forKey: PreferenceKey.defaultPresetID).flatMap(UUID.init(uuidString:))
        return presets.preset(id: id) ?? BuiltInPresets.default
    }

    var selectedSource: SourceItem? {
        guard case .source(let id) = selection else { return nil }
        return sources.first { $0.id == id }
    }

    // MARK: Sources

    /// Adds files, and every video or audio file inside dropped or opened folders.
    func addSources(_ urls: [URL]) {
        let existing = Set(sources.map(\.url))
        let media = MediaDiscovery.mediaFiles(in: urls)
        let accepted = media.filter { !existing.contains($0) }
        guard !accepted.isEmpty else {
            if !urls.isEmpty && media.isEmpty { alertMessage = "No video or audio files found there." }
            return
        }
        let preset = defaultPreset
        let items = accepted.map { SourceItem(url: $0, settings: preset.settings.presetSettings, presetID: preset.id) }
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
            let sidecars = SubtitleFile.sidecars(for: item.url).filter(Self.isReadable)
            update(item.id) { source in
                source.info = info
                source.thumbnail = thumbnail
                // The user may have added files while inspection ran; keep them.
                let known = Set(sidecars.map(\.url))
                source.subtitleFiles = sidecars + source.subtitleFiles.filter { !known.contains($0.url) }
            }
        } catch {
            update(item.id) { $0.errorMessage = error.localizedDescription }
        }
    }

    private static func isReadable(_ file: SubtitleFile) -> Bool {
        guard let data = try? Data(contentsOf: file.url) else { return false }
        return (try? SubtitleParser.cues(from: data)) != nil
    }

    // MARK: Subtitle files

    func chooseSubtitleFiles(for id: UUID) {
        guard let item = sources.first(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SubtitleFile.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.directoryURL = item.url.deletingLastPathComponent()
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        addSubtitleFiles(panel.urls, to: id)
    }

    func addSubtitleFiles(_ urls: [URL], to id: UUID) {
        guard let item = sources.first(where: { $0.id == id }) else { return }
        let base = item.url.deletingPathExtension().lastPathComponent
        let candidates = urls.map { SubtitleFile(url: $0, language: SubtitleFile.language(for: $0, video: base)) }
        let readable = candidates.filter(Self.isReadable)
        let rejected = candidates.count - readable.count
        if rejected > 0 {
            alertMessage = rejected == 1 ? "That file has no subtitles HyperVideo can read." : "\(rejected) files had no subtitles HyperVideo can read."
        }
        update(id) { source in
            let known = Set(source.subtitleFiles.map(\.url))
            source.subtitleFiles += readable.filter { !known.contains($0.url) }
        }
    }

    func removeSubtitleFile(_ file: SubtitleFile, from id: UUID) {
        update(id) { item in
            item.subtitleFiles.removeAll { $0.url == file.url }
            if item.settings.burnIn == .file(file.url) { item.settings.burnIn = nil }
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
            item.settings = item.settings.adopting(preset.settings)
            item.presetID = preset.id
        }
    }

    func applyToAll(from id: UUID) {
        guard let template = sources.first(where: { $0.id == id }) else { return }
        sources = sources.map { item in
            var copy = item
            copy.settings = item.settings.adopting(template.settings)
            copy.presetID = template.presetID
            return copy
        }
    }

    func presetName(for item: SourceItem) -> String {
        guard let preset = presets.preset(id: item.presetID) else { return "Custom" }
        return preset.settings.presetSettings == item.settings.presetSettings ? preset.name : "\(preset.name) (modified)"
    }

    // MARK: Queue

    /// Returns how many jobs were added.
    @discardableResult
    func enqueue(_ ids: [UUID]) -> Int {
        let suffix = defaults.string(forKey: PreferenceKey.outputSuffix) ?? ""
        var taken = queue.takenDestinations
        var jobs: [EncodeJob] = []
        var skipped: [String] = []
        for item in sources where ids.contains(item.id) {
            guard let info = item.info, item.settings.isValid else {
                skipped.append(item.name)
                continue
            }
            let destination = OutputNaming.destination(
                for: item.url, in: destinationFolder, container: item.settings.container, suffix: suffix, taken: taken
            )
            taken.insert(destination)
            jobs.append(EncodeJob(
                source: item.url, destination: destination, settings: item.settings, presetName: presetName(for: item),
                mediaDuration: item.settings.outputDuration(sourceDuration: info.duration),
                frameRate: item.settings.outputFrameRate(sourceFrameRate: info.frameRate),
                subtitleFiles: item.subtitleFiles
            ))
        }
        if !skipped.isEmpty { alertMessage = "Skipped (not ready or invalid settings): \(skipped.joined(separator: ", "))" }
        guard !jobs.isEmpty else { return 0 }
        queue.add(jobs)
        return jobs.count
    }

    func enqueueAll() { enqueue(sources.map(\.id)) }

    func encodeNow(_ id: UUID) {
        guard enqueue([id]) > 0 else { return }
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
