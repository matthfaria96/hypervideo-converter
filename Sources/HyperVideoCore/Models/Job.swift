import Foundation

public enum JobState: Codable, Hashable, Sendable {
    case queued
    case running(progress: Double)
    case completed(outputBytes: Int64, elapsed: TimeInterval)
    case failed(message: String)
    case cancelled

    public var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .queued, .running: false
        }
    }

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

public struct EncodeJob: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var source: URL
    public var destination: URL
    public var settings: EncodeSettings
    public var presetName: String
    public var state: JobState
    public var createdAt: Date
    /// Output length in seconds and frame rate, used to report encode speed.
    public var mediaDuration: Double?
    public var frameRate: Double?
    /// External subtitle files for this source; nil in queues saved before they existed.
    public var subtitleFiles: [SubtitleFile]?

    public init(
        source: URL, destination: URL, settings: EncodeSettings, presetName: String,
        mediaDuration: Double? = nil, frameRate: Double? = nil, subtitleFiles: [SubtitleFile] = []
    ) {
        self.id = UUID()
        self.source = source
        self.destination = destination
        self.settings = settings
        self.presetName = presetName
        self.state = .queued
        self.createdAt = Date()
        self.mediaDuration = mediaDuration
        self.frameRate = frameRate
        self.subtitleFiles = subtitleFiles
    }

    public func with(state: JobState) -> EncodeJob {
        var copy = self
        copy.state = state
        return copy
    }

    /// Jobs interrupted by quitting resume as queued.
    public func restoredAfterRelaunch() -> EncodeJob {
        state.isRunning ? with(state: .queued) : self
    }
}

public enum OutputNaming {
    /// Builds a destination that never overwrites an existing file or one reserved in `taken`.
    public static func destination(
        for source: URL,
        in folder: URL,
        container: ContainerFormat,
        suffix: String = "",
        taken: Set<URL> = [],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + suffix
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(container.fileExtension)
        var counter = 2
        while candidate == source || fileExists(candidate) || taken.contains(candidate) {
            candidate = folder
                .appendingPathComponent("\(base) \(counter)")
                .appendingPathExtension(container.fileExtension)
            counter += 1
        }
        return candidate
    }
}
