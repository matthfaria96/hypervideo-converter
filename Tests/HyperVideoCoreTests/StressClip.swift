@preconcurrency import AVFoundation
import VideoToolbox
@testable import HyperVideoCore

/// Builds small, unusual source files at test time (no ffmpeg needed): odd sizes,
/// rotation metadata, variable frame rate, 10-bit HEVC, ProRes, odd audio layouts.
enum StressClip {
    struct Audio {
        var channels = 2
        var sampleRate = 48_000
        var language: String?
        /// The ISO 639-2 `mdhd` code alone, as HandBrake and ffmpeg write it.
        var languageCode: String?
    }

    struct Spec {
        var name = "source"
        var fileType: AVFileType = .mov
        var size: CGSize? = CGSize(width: 320, height: 180)
        var codec: AVVideoCodecType = .h264
        var tenBit = false
        var transform: CGAffineTransform = .identity
        /// Presentation times of the video frames, in seconds.
        var frameTimes: [Double] = (0..<30).map { Double($0) / 30 }
        var seconds = 1.0
        var audio: [Audio] = [Audio()]
        var metadata: [AVMetadataItem] = []
    }

    static func make(in dir: URL, _ spec: Spec) async throws -> URL {
        let url = dir.appendingPathComponent("\(spec.name).\(spec.fileType == .mp4 ? "mp4" : "mov")")
        let writer = try AVAssetWriter(outputURL: url, fileType: spec.fileType)
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        if let size = spec.size {
            var settings: [String: Any] = [
                AVVideoCodecKey: spec.codec, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
            ]
            if spec.tenBit {
                settings[AVVideoCompressionPropertiesKey] = [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String]
            }
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            video.transform = spec.transform
            video.expectsMediaDataInRealTime = false
            writer.add(video)
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)
            ])
        }
        let audios = spec.audio.map { audio in
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: audio.sampleRate,
                AVNumberOfChannelsKey: audio.channels,
                AVChannelLayoutKey: OutputSettingsBuilder.channelLayoutData(channels: audio.channels)
            ])
            input.extendedLanguageTag = audio.language
            input.languageCode = audio.languageCode
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            return input
        }
        writer.metadata = spec.metadata
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var frame = 0
        let chunk = 1_024
        var positions = Array(repeating: 0, count: audios.count)
        let totals = spec.audio.map { Int(Double($0.sampleRate) * spec.seconds) }
        let frames = adaptor == nil ? 0 : spec.frameTimes.count
        while frame < frames || zip(positions, totals).contains(where: { $0 < $1 }) {
            var progressed = false
            if let adaptor, frame < frames, adaptor.assetWriterInput.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool {
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                if let buffer {
                    shade(buffer, frame)
                    adaptor.append(buffer, withPresentationTime: CMTime(seconds: spec.frameTimes[frame], preferredTimescale: 6_000))
                }
                frame += 1
                if frame == frames { adaptor.assetWriterInput.markAsFinished() }
                progressed = true
            }
            for (index, input) in audios.enumerated() where positions[index] < totals[index] && input.isReadyForMoreMediaData {
                let count = min(chunk, totals[index] - positions[index])
                if let sample = pcm(spec.audio[index], start: positions[index], frames: count) { input.append(sample) }
                positions[index] += count
                if positions[index] >= totals[index] { input.markAsFinished() }
                progressed = true
            }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? TranscodeError.noTracks }
        return url
    }

    private static func shade(_ buffer: CVPixelBuffer, _ frame: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            memset(base + row * rowBytes, Int32((frame * 5 + row) % 255), rowBytes)
        }
    }

    private static func pcm(_ audio: Audio, start: Int, frames: Int) -> CMSampleBuffer? {
        let channels = UInt32(audio.channels)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(audio.sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels,
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0
        )
        let layoutData = OutputSettingsBuilder.channelLayoutData(channels: audio.channels)
        var format: CMAudioFormatDescription?
        layoutData.withUnsafeBytes { layout in
            _ = CMAudioFormatDescriptionCreate(
                allocator: nil, asbd: &asbd, layoutSize: layoutData.count,
                layout: layout.baseAddress?.assumingMemoryBound(to: AudioChannelLayout.self),
                magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        }
        guard let format else { return nil }
        let samples = (0..<frames).flatMap { i -> [Float] in
            let value = Float(sin(2 * Double.pi * 440 * Double(start + i) / Double(audio.sampleRate)) * 0.2)
            return Array(repeating: value, count: audio.channels)
        }
        let data = samples.withUnsafeBytes { Data($0) }
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: 0, blockBufferOut: &block)
        guard let block else { return nil }
        data.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count) }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(audio.sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        return sample
    }
}
