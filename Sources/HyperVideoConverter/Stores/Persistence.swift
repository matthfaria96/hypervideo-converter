import Foundation
import OSLog

let appLog = Logger(subsystem: "com.hypervideo.converter", category: "app")

/// Small JSON documents stored in Application Support.
struct JSONStore<Value: Codable>: Sendable {
    let fileName: String

    private var url: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("HyperVideo Converter", isDirectory: true).appendingPathComponent(fileName)
    }

    func load() -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            appLog.error("Couldn't decode \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ value: Value) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            appLog.error("Couldn't save \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum PreferenceKey {
    static let maxConcurrentJobs = "maxConcurrentJobs"
    static let notifyOnCompletion = "notifyOnCompletion"
    static let revealOnCompletion = "revealOnCompletion"
    static let outputSuffix = "outputSuffix"
    static let destinationPath = "destinationPath"
    static let defaultPresetID = "defaultPresetID"
    static let autoStartQueue = "autoStartQueue"
}
