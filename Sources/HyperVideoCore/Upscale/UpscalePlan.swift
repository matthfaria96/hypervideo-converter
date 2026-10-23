import CoreGraphics
import Foundation

/// What an upscale will produce for one video: the output size, the bitrate the encoder
/// is held to, and from those the file size and processing time shown before starting.
public struct UpscalePlan: Equatable, Sendable {
    public let sourceSize: CGSize
    public let outputSize: CGSize
    /// True when "Limit to 4K" shrank the requested scale.
    public let isLimited: Bool
    public let frameRate: Double
    public let frameCount: Int
    /// Bits per second for the video track (average bitrate, so the size is predictable).
    public let videoBitrate: Double
    public let sourceBytes: Int64
    public let predictedBytes: Int64
    /// On an Apple M4; faster Macs finish sooner. The queue refines it once running.
    public let estimatedSeconds: Double

    /// MP4/MOV boxes and indexes on top of the media.
    static let containerOverhead = 1.01
    static let uhdBox = CGSize(width: 3840, height: 2160)
    static let fallbackSize = CGSize(width: 1280, height: 720)

    public init(info: MediaInfo, settings: UpscaleSettings) {
        let source = info.displaySize ?? Self.fallbackSize
        let scale = Double(settings.scale.rawValue)
        let requested = CGSize(width: source.width * scale, height: source.height * scale)
        let limited = settings.limitTo4K ? Self.fit(requested, in: Self.box(for: requested)) : requested
        sourceSize = source
        outputSize = Self.even(limited)
        isLimited = settings.limitTo4K && limited.width < requested.width - 1
        frameRate = info.frameRate.flatMap { $0 > 0 ? $0 : nil } ?? 30
        frameCount = Int((info.duration * frameRate).rounded(.up))
        videoBitrate = outputSize.width * outputSize.height * frameRate * settings.weight.bitsPerPixel(for: settings.codec)
        sourceBytes = info.fileBytes
        let audioBytes = Self.audioBytes(info: info)
        predictedBytes = Int64(((videoBitrate * info.duration / 8) + audioBytes) * Self.containerOverhead)
        let megapixels = source.width * source.height / 1_000_000
        estimatedSeconds = Double(frameCount) * megapixels * settings.model.secondsPerSourceMegapixel
    }

    /// Output size relative to the source: 0.5 = 50% larger.
    public var growth: Double {
        guard sourceBytes > 0 else { return 0 }
        return Double(predictedBytes) / Double(sourceBytes) - 1
    }

    /// The audio is copied as is: whatever the file holds besides the video track.
    static func audioBytes(info: MediaInfo) -> Double {
        guard !info.audioTracks.isEmpty else { return 0 }
        guard let video = info.videoBitrate else {
            // Unknown split: assume 160 kbit/s per track.
            return Double(info.audioTracks.count) * 160_000 * info.duration / 8
        }
        return max(0, Double(info.fileBytes) - video * info.duration / 8)
    }

    private static func box(for size: CGSize) -> CGSize {
        size.height > size.width ? CGSize(width: uhdBox.height, height: uhdBox.width) : uhdBox
    }

    private static func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        let factor = min(1, box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * factor, height: size.height * factor)
    }

    private static func even(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, (size.width / 2).rounded(.down) * 2), height: max(2, (size.height / 2).rounded(.down) * 2))
    }
}
