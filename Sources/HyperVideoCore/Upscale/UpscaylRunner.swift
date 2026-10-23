import Foundation

/// Runs `upscayl-bin` over a folder of PNG frames. Cancelling the calling task
/// terminates the process; `progress` gets how many output frames exist so far.
struct UpscaylRunner: Sendable {
    let backend: UpscaleBackend

    func upscale(folder input: URL, into output: URL, model: UpscaleModel, scale: UpscaleScale,
                 size: CGSize, progress: @escaping @Sendable (Int) -> Void) async throws {
        let arguments = [
            "-i", input.path, "-o", output.path,
            "-m", backend.modelsFolder.path, "-n", model.rawValue,
            "-s", String(scale.rawValue),
            "-r", "\(Int(size.width))x\(Int(size.height))",
            "-f", "png",
        ]
        let watcher = Task {
            while !Task.isCancelled {
                progress(Self.count(in: output))
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer { watcher.cancel() }
        try await run(arguments)
        progress(Self.count(in: output))
    }

    static func count(in folder: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".png") }.count) ?? 0
    }

    private func run(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = backend.executable
        process.arguments = arguments
        let log = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = log
        let tail = LogTail()
        log.fileHandleForReading.readabilityHandler = { handle in tail.append(handle.availableData) }
        defer { log.fileHandleForReading.readabilityHandler = nil }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                    if Task.isCancelled { process.terminate() }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: UpscaleError.failed(error.localizedDescription))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw UpscaleError.failed(tail.text.isEmpty ? "exit code \(process.terminationStatus)" : tail.text)
        }
    }
}

/// The last lines the backend printed, for error messages.
private final class LogTail: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock { buffer = String((buffer + String(decoding: data, as: UTF8.self)).suffix(2000)) }
    }

    var text: String {
        lock.withLock {
            buffer.split(whereSeparator: \.isNewline).suffix(3).joined(separator: " ")
        }
    }
}
