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

/// Folders waiting for the user to pick the preset their videos get.
struct FolderImport: Identifiable, Equatable {
    let id = UUID()
    /// Everything that was dropped or opened; loose files keep the default preset.
    let urls: [URL]
    let folders: [URL]
    /// The preset chosen for the folders' videos.
    var presetID: UUID?
}

/// The pages of the sidebar.
enum AppSection: Hashable, CaseIterable {
    case conversion, history, favorites, analyze
}

/// The workspace's two flavours: Compress also resets the targets to a compact MP4.
enum WorkMode: Hashable {
    case convert, compress
}

@Observable
@MainActor
final class AppModel {
    let presets: PresetStore
    let queue: QueueStore
    private let defaults: UserDefaults
    let ui = UIState()

    private(set) var sources: [SourceItem] = []
    var section: AppSection = .conversion
    var mode: WorkMode = .convert
    /// Selected rows of the conversion list (source or job IDs). The output inspector
    /// edits the selected sources, or every source when none is selected.
    var selectedIDs: Set<UUID> = []
    /// What the inspector set while the list was empty; the next loose videos get it.
    var draftSettings: EncodeSettings?
    var draftPresetID: UUID?
    var isImporting = false
    var alertMessage: String?
    /// Set when an import includes folders, until a preset is chosen for them.
    var pendingFolderImport: FolderImport?

    var destinationFolder: URL {
        didSet { defaults.set(destinationFolder.path, forKey: PreferenceKey.destinationPath) }
    }

    /// `directory` and `defaults` override persistence and preferences (tests).
    init(directory: URL? = nil, defaults: UserDefaults = .standard, notifier: (any QueueNotifying)? = nil) {
        presets = PresetStore(directory: directory)
        queue = QueueStore(directory: directory, defaults: defaults, notifier: notifier)
        self.defaults = defaults
        let saved = defaults.string(forKey: PreferenceKey.destinationPath)
        destinationFolder = saved.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    var defaultPreset: Preset {
        let id = defaults.string(forKey: PreferenceKey.defaultPresetID).flatMap(UUID.init(uuidString:))
        return presets.preset(id: id) ?? QualityProfile.balanced.preset
    }

    /// The one source a per-video view (Advanced, Analyze) works on: the single selected
    /// source, or the only source in the list.
    var selectedSource: SourceItem? {
        let selected = sources.filter { selectedIDs.contains($0.id) }
        if selected.count == 1 { return selected[0] }
        return selected.isEmpty && sources.count == 1 ? sources[0] : nil
    }

    // MARK: Sources

    /// Adds files right away; when folders are included, first asks (through
    /// `pendingFolderImport`) which preset their videos should get.
    func addSources(_ urls: [URL]) {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard folders.isEmpty else {
            pendingFolderImport = FolderImport(urls: urls, folders: folders, presetID: defaultPreset.id)
            return
        }
        addSources(urls, folderPreset: nil)
    }

    /// Adds the pending import, giving every video found in its folders `preset`.
    func confirmFolderImport(preset: Preset) {
        guard let pending = pendingFolderImport else { return }
        pendingFolderImport = nil
        addSources(pending.urls, folderPreset: preset)
    }

    func cancelFolderImport() { pendingFolderImport = nil }

    /// Adds files, and every video or audio file inside folders. Files found in folders
    /// get `folderPreset` (the default preset when nil); loose files get the default.
    func addSources(_ urls: [URL], folderPreset: Preset?) {
        let existing = Set(sources.map(\.url))
        let fallback = defaultPreset
        let loose = Set(urls.map(\.standardizedFileURL))
        let media = MediaDiscovery.mediaFiles(in: urls)
        let accepted = media.filter { !existing.contains($0) }
        guard !accepted.isEmpty else {
            if !urls.isEmpty && media.isEmpty { alertMessage = String(localized: "No video or audio files found there.") }
            return
        }
        let items = accepted.map { url in
            let isLoose = loose.contains(url.standardizedFileURL) || folderPreset == nil
            return newSource(url: url, preset: isLoose ? fallback : (folderPreset ?? fallback), usesDraft: isLoose)
        }
        sources = sources + items
        items.forEach { item in Task { await inspect(item) } }
    }

    func removeSource(_ id: UUID) {
        sources = sources.filter { $0.id != id }
        selectedIDs.remove(id)
    }

    func clearSources() {
        sources = []
        selectedIDs = []
    }

    /// Replaces the whole list (reordering keeps every item and its settings).
    func setSources(_ items: [SourceItem]) { sources = items }

    func inspect(_ item: SourceItem) async {
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
        panel.prompt = String(localized: "Add")
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
            alertMessage = rejected == 1
                ? String(localized: "That file has no subtitles HyperVideo can read.")
                : String(localized: "\(rejected) files had no subtitles HyperVideo can read.")
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
        guard let preset = presets.preset(id: item.presetID) else { return String(localized: "Custom") }
        let name = preset.displayName
        return preset.settings.presetSettings == item.settings.presetSettings ? name : String(localized: "\(name) (modified)")
    }

    // MARK: Queue

    /// Returns how many jobs were added.
    @discardableResult
    func enqueue(_ ids: [UUID]) -> Int { enqueueSources(ids).count }

    /// Queues the ready sources among `ids` and returns the IDs of those queued.
    func enqueueSources(_ ids: [UUID]) -> [UUID] {
        let suffix = defaults.string(forKey: PreferenceKey.outputSuffix) ?? ""
        var taken = queue.takenDestinations
        var jobs: [EncodeJob] = []
        var queued: [UUID] = []
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
            queued.append(item.id)
            jobs.append(EncodeJob(
                source: item.url, destination: destination, settings: item.settings, presetName: presetName(for: item),
                mediaDuration: item.settings.outputDuration(sourceDuration: info.duration),
                frameRate: item.settings.outputFrameRate(sourceFrameRate: info.frameRate),
                subtitleFiles: item.subtitleFiles
            ))
        }
        if !skipped.isEmpty {
            alertMessage = String(localized: "Skipped (not ready or invalid settings): \(skipped.joined(separator: ", "))")
        }
        if !jobs.isEmpty { queue.add(jobs) }
        return queued
    }

    func enqueueAll() { enqueue(sources.map(\.id)) }

    func encodeNow(_ id: UUID) {
        guard enqueue([id]) > 0 else { return }
        queue.start()
        section = .conversion
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destinationFolder
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK, let url = panel.url { destinationFolder = url }
    }
}
