import Foundation

/// Where the Upscayl executable and its models live: inside the app bundle, or in
/// Vendor/Upscayl for tests and `swift run`.
public struct UpscaleBackend: Sendable, Equatable {
    public let executable: URL
    public let modelsFolder: URL

    /// A folder holding `upscayl-bin` and `models/`; nil when either is missing.
    public init?(folder: URL) {
        let executable = folder.appendingPathComponent("upscayl-bin")
        let models = folder.appendingPathComponent("models", isDirectory: true)
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.fileExists(atPath: models.path) else { return nil }
        self.executable = executable
        self.modelsFolder = models
    }

    /// The copy in the app bundle (Contents/MacOS/upscayl-bin, Resources/Upscayl/models).
    /// Debug builds also look for the repository's Vendor/Upscayl, so `swift run` works.
    public static func bundled() -> UpscaleBackend? {
        if let exec = Bundle.main.executableURL?.deletingLastPathComponent(),
           let resources = Bundle.main.resourceURL {
            let executable = exec.appendingPathComponent("upscayl-bin")
            let models = resources.appendingPathComponent("Upscayl/models", isDirectory: true)
            if FileManager.default.isExecutableFile(atPath: executable.path),
               FileManager.default.fileExists(atPath: models.path) {
                return UpscaleBackend(executable: executable, modelsFolder: models)
            }
        }
        #if DEBUG
        let vendor = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/Upscayl")
        return UpscaleBackend(folder: vendor)
        #else
        return nil
        #endif
    }

    init(executable: URL, modelsFolder: URL) {
        self.executable = executable
        self.modelsFolder = modelsFolder
    }
}
