import AppKit
@preconcurrency import AVFoundation
import HyperVideoCore

/// Adding videos: files, folders and drops are listed and inspected away from the main
/// thread, so opening hundreds of files doesn't freeze the window.
extension AppModel {
    /// Videos inspected at the same time.
    static let inspectionWidth = 4
    /// Size, in pixels, of the list thumbnails (about twice their 46 × 34 point slot).
    static let thumbnailSize = CGSize(width: 96, height: 72)
    /// Size of the Analyze page's header picture.
    static let heroSize = CGSize(width: 1280, height: 1280)

    /// Adds files right away; when folders are included, first asks (through
    /// `pendingFolderImport`) which preset their videos should get.
    func addSources(_ urls: [URL]) async {
        let folders = await Task.detached(priority: .userInitiated) { urls.filter(Self.isDirectory) }.value
        guard folders.isEmpty else {
            pendingFolderImport = FolderImport(urls: urls, folders: folders, presetID: defaultPreset.id)
            return
        }
        await addSources(urls, folderPreset: nil)
    }

    /// Adds the pending import, giving every video found in its folders `preset`.
    func confirmFolderImport(preset: Preset) async {
        guard let pending = pendingFolderImport else { return }
        pendingFolderImport = nil
        await addSources(pending.urls, folderPreset: preset)
    }

    func cancelFolderImport() { pendingFolderImport = nil }

    /// Adds files, and every video or audio file inside folders. Files found in folders
    /// get `folderPreset` (the default preset when nil); loose files get the default.
    func addSources(_ urls: [URL], folderPreset: Preset?) async {
        let (media, sidecars) = await Task.detached(priority: .userInitiated) {
            let media = MediaDiscovery.mediaFiles(in: urls)
            return (media, SubtitleFile.sidecars(for: media))
        }.value
        let existing = Set(sources.map(\.url))
        let fallback = defaultPreset
        let loose = Set(urls.map(\.standardizedFileURL))
        let accepted = media.filter { !existing.contains($0) }
        guard !accepted.isEmpty else {
            if !urls.isEmpty && media.isEmpty {
                showAlert(String(localized: "No videos found"), String(localized: "No video or audio files found there."))
            }
            return
        }
        let items = accepted.map { url in
            let isLoose = loose.contains(url.standardizedFileURL) || folderPreset == nil
            return newSource(url: url, preset: isLoose ? fallback : (folderPreset ?? fallback), usesDraft: isLoose)
        }
        setSources(sources + items)
        Task { await inspectAll(items, sidecars: sidecars) }
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    // MARK: Inspection

    /// Inspects `items` a few at a time, so a big import doesn't open hundreds of files at once.
    func inspectAll(_ items: [SourceItem], sidecars: [URL: [SubtitleFile]] = [:]) async {
        await withTaskGroup(of: Void.self) { group in
            var remaining = items.makeIterator()
            for _ in 0..<Self.inspectionWidth {
                guard let item = remaining.next() else { break }
                group.addTask { await self.inspect(item, sidecars: sidecars[item.url]) }
            }
            while await group.next() != nil {
                guard let item = remaining.next() else { continue }
                group.addTask { await self.inspect(item, sidecars: sidecars[item.url]) }
            }
        }
    }

    /// Reads the video's facts, thumbnail and subtitle files. `sidecars` are the candidates
    /// already found beside the video (looked up when nil).
    func inspect(_ item: SourceItem, sidecars: [SubtitleFile]? = nil) async {
        do {
            let info = try await MediaInspector.inspect(item.url)
            let thumbnail = await Self.thumbnail(for: item.url, duration: info.duration, size: Self.thumbnailSize)
            let url = item.url
            let found = await Task.detached(priority: .utility) {
                (sidecars ?? SubtitleFile.sidecars(for: url)).filter(Self.isReadable)
            }.value
            update(item.id) { source in
                source.info = info
                source.thumbnail = thumbnail
                // The user may have added files while inspection ran; keep them.
                let known = Set(found.map(\.url))
                source.subtitleFiles = found + source.subtitleFiles.filter { !known.contains($0.url) }
            }
        } catch {
            update(item.id) { $0.errorMessage = error.localizedDescription }
        }
    }

    /// Whether the file parses as subtitles (reads the whole file; keep off the main thread).
    nonisolated static func isReadable(_ file: SubtitleFile) -> Bool {
        guard let data = try? Data(contentsOf: file.url) else { return false }
        return (try? SubtitleParser.cues(from: data)) != nil
    }

    nonisolated static func thumbnail(for url: URL, duration: Double, size: CGSize) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        let time = CMTime(seconds: min(duration * 0.1, 5), preferredTimescale: 600)
        guard let (image, _) = try? await generator.image(at: time) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    // MARK: Pictures

    /// Loads the large picture the Analyze header shows (one at a time is kept).
    func loadHero(for source: SourceItem) async {
        guard ui.hero?.url != source.url, let info = source.info else { return }
        guard let image = await Self.thumbnail(for: source.url, duration: info.duration, size: Self.heroSize) else { return }
        ui.hero = HeroPicture(url: source.url, image: image)
    }

    /// Gives a queued job its picture when it has none (jobs restored after a relaunch).
    func loadQueueThumbnail(for job: EncodeJob) async {
        guard ui.thumbnails[job.source] == nil,
              let image = await Self.thumbnail(for: job.source, duration: job.mediaDuration ?? 10, size: Self.thumbnailSize)
        else { return }
        ui.thumbnails[job.source] = image
    }

    /// Forgets queue thumbnails of videos that are no longer in the queue or on the list.
    func releaseThumbnails(of removed: [EncodeJob]) {
        let inUse = Set(queue.jobs.map(\.source) + sources.map(\.url))
        for job in removed where !inUse.contains(job.source) {
            ui.thumbnails[job.source] = nil
        }
    }
}
