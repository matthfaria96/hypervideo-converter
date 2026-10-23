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
    /// Selected rows of the conversion list (IDs of videos on the editing list; queued jobs
    /// can't be selected). The output inspector edits the selected sources, or every
    /// source when none is selected.
    var selectedIDs: Set<UUID> = []
    /// What the inspector set while the list was empty; the next loose videos get it.
    var draftSettings: EncodeSettings?
    var draftPresetID: UUID?
    /// Every video's settings and the draft as they were in Convert mode, restored when
    /// Compress mode is left.
    var convertSnapshot: ModeSnapshot?
    var isImporting = false
    var alertMessage: String?
    /// The alert's title: what went wrong, rather than the app's name.
    var alertTitle: String?
    /// Set when an import includes folders, until a preset is chosen for them.
    var pendingFolderImport: FolderImport?

    var destinationFolder: URL {
        didSet { defaults.set(destinationFolder.path, forKey: PreferenceKey.destinationPath) }
    }

    /// `directory` and `defaults` override persistence and preferences (tests).
    init(directory: URL? = nil, defaults: UserDefaults = .standard, notifier: (any QueueNotifying)? = nil,
         saveDelay: TimeInterval = 0.5, resolvesInBackground: Bool = true) {
        presets = PresetStore(directory: directory)
        queue = QueueStore(directory: directory, defaults: defaults, notifier: notifier, saveDelay: saveDelay,
                           resolvesInBackground: resolvesInBackground)
        self.defaults = defaults
        let saved = defaults.string(forKey: PreferenceKey.destinationPath)
        destinationFolder = saved.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        queue.onJobsRemoved = { [weak self] removed in self?.releaseThumbnails(of: removed) }
        // Launch argument `-InitialSection history` opens on that page (used for screenshots).
        if let name = defaults.string(forKey: "InitialSection"), let page = AppSection(launchName: name) {
            section = page
            mode = name == "compress" ? .compress : .convert
        }
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

    // MARK: Subtitle files

    func chooseSubtitleFiles(for id: UUID) {
        guard let item = sources.first(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SubtitleFile.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.directoryURL = item.url.deletingLastPathComponent()
        panel.prompt = String(localized: "Add")
        PanelPresenter.present(panel) { [weak self] response in
            guard response == .OK else { return }
            self?.addSubtitleFiles(panel.urls, to: id)
        }
    }

    func addSubtitleFiles(_ urls: [URL], to id: UUID) {
        guard let item = sources.first(where: { $0.id == id }) else { return }
        let base = item.url.deletingPathExtension().lastPathComponent
        let candidates = urls.map { SubtitleFile(url: $0, language: SubtitleFile.language(for: $0, video: base)) }
        let readable = candidates.filter(Self.isReadable)
        let rejected = candidates.count - readable.count
        if rejected > 0 {
            alertTitle = String(localized: "Subtitles not added")
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
            copy.settings = item.settings.copyingAll(from: template.settings)
            copy.presetID = template.presetID
            return copy
        }
    }

    func presetName(for item: SourceItem) -> String {
        guard let preset = presets.preset(id: item.presetID) else { return String(localized: "Custom") }
        let name = preset.displayName
        return Self.matches(item.settings, preset: preset) ? name : String(localized: "\(name) (personalized)")
    }

    /// Whether `settings` still are what `preset` gives: for quality profiles only the
    /// fields a profile decides count, for other presets every shared setting.
    static func matches(_ settings: EncodeSettings, preset: Preset) -> Bool {
        if QualityProfile.profile(presetID: preset.id) != nil { return settings.matchesProfile(preset.settings) }
        return preset.settings.presetSettings == settings.presetSettings
    }

    /// The translated name of the preset a job was made with.
    func presetName(for job: EncodeJob) -> String {
        presets.preset(id: job.presetID)?.displayName ?? String(localized: String.LocalizationValue(job.presetName))
    }

    func showAlert(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
    }

    // MARK: Queue

    /// Queues the ready videos among `ids`, takes them off the editing list (they are jobs
    /// now) and returns how many were queued.
    @discardableResult
    func enqueue(_ ids: [UUID]) -> Int {
        let queued = Set(enqueueSources(ids))
        takeOffList(queued)
        return queued.count
    }

    func enqueueAll() { enqueue(sources.map(\.id)) }

    /// Removes sources that became jobs from the list and the selection, keeping their
    /// thumbnails for the queue rows.
    private func takeOffList(_ queued: Set<UUID>) {
        guard !queued.isEmpty else { return }
        for item in sources where queued.contains(item.id) {
            if let image = item.thumbnail { ui.thumbnails[item.url] = image }
        }
        setSources(sources.filter { !queued.contains($0.id) })
        selectedIDs.subtract(queued)
    }

    /// Creates jobs for the ready sources among `ids` and returns the IDs of those queued.
    private func enqueueSources(_ ids: [UUID]) -> [UUID] {
        let wanted = Set(ids)
        let suffix = defaults.string(forKey: PreferenceKey.outputSuffix) ?? ""
        var taken = queue.takenDestinations
        var jobs: [EncodeJob] = []
        var queued: [UUID] = []
        var skipped: [String] = []
        for item in sources where wanted.contains(item.id) {
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
                subtitleFiles: item.subtitleFiles, presetID: item.presetID
            ))
        }
        if !skipped.isEmpty {
            showAlert(String(localized: "Some videos weren't converted"),
                      String(localized: "Skipped (not ready or invalid settings): \(skipped.joined(separator: ", "))"))
        }
        if !jobs.isEmpty { queue.add(jobs) }
        return queued
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destinationFolder
        panel.prompt = String(localized: "Choose")
        PanelPresenter.present(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.destinationFolder = url
        }
    }
}
