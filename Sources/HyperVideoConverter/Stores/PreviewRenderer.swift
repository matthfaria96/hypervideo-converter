import AppKit
import AVFoundation
import HyperVideoCore

/// A short real conversion of one video with its current settings: the same frame
/// before and after, and the clip's size projected to the whole video.
struct ConversionPreview {
    let original: NSImage
    let converted: NSImage
    let clipSeconds: Double
    let clipBytes: Int64
    /// The clip's bytes per second times the output's length; nil for very short videos.
    let projectedBytes: Int64?
    let outputSize: CGSize?
}

enum PreviewRenderer {
    /// Long enough to measure the bitrate, short enough to wait for.
    static let clipSeconds = 2.0
    /// AI Upscale runs a model per frame, so its preview is a handful of frames.
    static let upscaleClipSeconds = 0.3

    /// Where the clip is taken: about 30% in (past intros and fades), inside the trim.
    static func clipRange(duration: Double, trim: TrimRange?, upscaling: Bool) -> (start: Double, end: Double) {
        let lower = max(0, trim?.start ?? 0)
        let upper = min(duration, trim?.end ?? duration)
        let length = min(upscaling ? upscaleClipSeconds : clipSeconds, max(0, upper - lower))
        let start = min(lower + (upper - lower) * 0.3, upper - length)
        return (max(lower, start), max(lower, start) + length)
    }

    static func render(source: URL, info: MediaInfo, settings: EncodeSettings, workRoot: URL,
                       engine: TranscodeEngine = TranscodeEngine()) async throws -> ConversionPreview {
        let range = clipRange(duration: info.duration, trim: settings.trim, upscaling: settings.upscale != nil)
        var clipSettings = settings
        clipSettings.trim = TrimRange(start: range.start, end: range.end)
        let folder = workRoot.appendingPathComponent(".hypervideo-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let output = try await engine.transcode(
            source: source, destination: folder.appendingPathComponent("preview.\(settings.container.fileExtension)"),
            settings: clipSettings) { _ in }
        let clip = range.end - range.start
        let middle = clip / 2
        let original = try await frame(of: source, at: range.start + middle)
        let converted = try await frame(of: output.url, at: middle)
        let outputDuration = settings.outputDuration(sourceDuration: info.duration)
        let projected = clip >= 0.25 ? Int64(Double(output.bytes) / clip * outputDuration) : nil
        let track = try? await AVURLAsset(url: output.url).loadTracks(withMediaType: .video).first
        let size = try? await track?.load(.naturalSize)
        return ConversionPreview(original: original, converted: converted, clipSeconds: clip,
                                 clipBytes: output.bytes, projectedBytes: projected, outputSize: size)
    }

    private static func frame(of url: URL, at seconds: Double) async throws -> NSImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        return NSImage(cgImage: image, size: .zero)
    }
}
