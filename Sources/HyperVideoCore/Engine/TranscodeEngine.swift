@preconcurrency import AVFoundation

public enum TranscodeError: LocalizedError {
    case invalidSettings([String])
    case noTracks
    case cannotConfigure(String)
    case readerFailed(String)
    case writerFailed(String)
    case stalled
    case insufficientSpace(required: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case .invalidSettings(let issues): issues.joined(separator: "\n")
        case .noTracks: "The source has no tracks that can be converted."
        case .cannotConfigure(let what): "These settings aren't supported for this source: \(what)."
        case .readerFailed(let detail): "Couldn't decode the source: \(detail)"
        case .writerFailed(let detail): "Couldn't write the output: \(detail)"
        case .stalled: "The conversion stopped making progress, so it was stopped. Try again, or choose fewer subtitle or audio tracks."
        case .insufficientSpace(let required, let available):
            "There isn't enough free space to save this video. It needs about \(Self.bytes(required)) but only \(Self.bytes(available)) is free."
        }
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

/// Where a finished encode ended up and how big it is.
public struct TranscodeOutput: Sendable, Equatable {
    public let url: URL
    public let bytes: Int64

    public init(url: URL, bytes: Int64) {
        self.url = url
        self.bytes = bytes
    }
}

/// Native transcoder built on AVAssetReader/AVAssetWriter with VideoToolbox hardware encoders.
public struct TranscodeEngine: Sendable {
    /// How long every track may go without writing a sample before the encode is
    /// treated as stuck. AVFoundation can deadlock when the reader and the writer's
    /// interleaving wait on each other; this turns a frozen queue into an error.
    let stallTimeout: Duration
    /// Free bytes on the volume holding a folder; nil when unknown (the check is skipped).
    let availableCapacity: @Sendable (URL) -> Int64?

    public init(
        stallTimeout: Duration = .seconds(60),
        availableCapacity: @escaping @Sendable (URL) -> Int64? = DiskSpace.availableCapacity(at:)
    ) {
        self.stallTimeout = stallTimeout
        self.availableCapacity = availableCapacity
    }

    /// Encodes `source` to `destination`, returning the output size in bytes.
    public func run(
        source: URL,
        destination: URL,
        settings: EncodeSettings,
        subtitleFiles: [SubtitleFile] = [],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        try await transcode(source: source, destination: destination, settings: settings,
                            subtitleFiles: subtitleFiles, progress: progress).bytes
    }

    /// Encodes `source` next to `destination`. If a file with that name appears while
    /// encoding, the result gets a unique name instead; the returned URL is the real one.
    /// `subtitleFiles` are external SRT/WebVTT files added after the source's own text tracks.
    public func transcode(
        source: URL,
        destination: URL,
        settings: EncodeSettings,
        subtitleFiles: [SubtitleFile] = [],
        workTag: UUID? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscodeOutput {
        guard settings.isValid else { throw TranscodeError.invalidSettings(settings.validationIssues) }

        let asset = AVURLAsset(url: source)
        let range = try Self.timeRange(settings.trim, duration: try await Self.readableDuration(of: asset))
        try precheckSpace(source: source, destination: destination, container: settings.container)
        // Work in a private folder next to the output so cleanup also catches AVFoundation's sidecar files.
        let workDir = destination.deletingLastPathComponent().appendingPathComponent(WorkFolder.name(jobID: workTag))
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let partial = workDir.appendingPathComponent(destination.lastPathComponent)
        // MKV goes through an intermediate movie that is then remuxed; the encode is most of the work.
        let remuxes = settings.container == .mkv
        let encoded = remuxes ? workDir.appendingPathComponent("intermediate.mov") : partial
        let encodeShare = remuxes ? 0.9 : 1

        try await encode(EncodePass(asset: asset, range: range, output: encoded, settings: settings,
                                    subtitleFiles: subtitleFiles)) { progress($0 * encodeShare) }
        if remuxes {
            try await remux(encoded, to: partial, tags: settings.tags) { progress(encodeShare + $0 * (1 - encodeShare)) }
        }

        let final = try Self.moveIntoPlace(partial, destination: destination, container: settings.container)
        progress(1)
        let size = try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return TranscodeOutput(url: final, bytes: Int64(size ?? 0))
    }

    /// The source's duration; a missing, truncated or non-media file fails here with a bare
    /// AVFoundation error, which becomes a readable one.
    static func readableDuration(of asset: AVURLAsset) async throws -> CMTime {
        do {
            let (readable, loaded) = try await asset.load(.isReadable, .duration)
            guard readable, loaded.isNumeric else { throw MediaInspectorError.unreadable(asset.url) }
            return loaded
        } catch {
            throw TranscodeError.readerFailed("“\(asset.url.lastPathComponent)” can't be opened (\(error.localizedDescription)).")
        }
    }

    /// Fails early when the destination volume can't hold the output (and, for MKV, the intermediate).
    private func precheckSpace(source: URL, destination: URL, container: ContainerFormat) throws {
        guard let sourceSize = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
        let required = DiskSpace.requiredBytes(sourceBytes: Int64(sourceSize), container: container)
        guard let available = availableCapacity(destination.deletingLastPathComponent()), available < required else { return }
        throw TranscodeError.insufficientSpace(required: required, available: available)
    }

    /// Moves the finished file to `destination`, or to a fresh unique name if something
    /// took that name meanwhile. Never overwrites; retries if a name is taken mid-move.
    static func moveIntoPlace(_ partial: URL, destination: URL, container: ContainerFormat) throws -> URL {
        let folder = destination.deletingLastPathComponent()
        var lastError: Error?
        for _ in 0..<4 {
            let target = FileManager.default.fileExists(atPath: destination.path)
                ? OutputNaming.destination(for: destination, in: folder, container: container)
                : destination
            do {
                try FileManager.default.moveItem(at: partial, to: target)
                return target
            } catch CocoaError.fileWriteFileExists {
                lastError = CocoaError(.fileWriteFileExists)
            } catch {
                lastError = error
                break
            }
        }
        let detail = lastError?.localizedDescription ?? "unknown error"
        throw TranscodeError.writerFailed("Couldn't move the finished file into place (\(detail)).")
    }

    /// Copies the finished intermediate movie into Matroska, stopping if the task is cancelled.
    private func remux(
        _ movie: URL, to output: URL, tags: MetadataTags, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let cancel = CancelFlag()
        try await withTaskCancellationHandler {
            try await MatroskaRemuxer(source: movie, destination: output, tags: tags).run(cancel: cancel, progress: progress)
        } onCancel: {
            cancel.set()
        }
        try? FileManager.default.removeItem(at: movie)
    }

    /// Shortest trim worth encoding: about one frame at 30 fps.
    static let minimumTrim = 1.0 / 30

    static func timeRange(_ trim: TrimRange?, duration: CMTime) throws -> CMTimeRange {
        guard let trim else { return CMTimeRange(start: .zero, duration: duration) }
        let total = duration.seconds
        let start = min(max(trim.start, 0), total)
        let end = min(trim.end ?? total, total)
        guard end - start >= minimumTrim else {
            throw TranscodeError.invalidSettings(["The trim range is too short to contain any video."])
        }
        return CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: max(end, start), preferredTimescale: 600)
        )
    }
}

/// Hands non-Sendable AVFoundation objects to a closure that runs while no pump uses them.
final class Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
