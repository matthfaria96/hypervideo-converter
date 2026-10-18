@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

/// End-to-end: synthesize a short clip with audio, then convert it with real encoders.
@Suite("Transcode integration", .serialized)
struct TranscodeIntegrationTests {
    @Test func h264DownscaleAndTrim() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 1280, height: 720), seconds: 3)
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.maxResolution = .sd480
        settings.trim = TrimRange(start: 1, end: 2.5)

        let out = dir.appendingPathComponent("out.mp4")
        let bytes = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        #expect(bytes > 0)

        let info = try await MediaInspector.inspect(out)
        #expect(info.displaySize == CGSize(width: 854, height: 480))
        #expect(info.videoCodec == "H.264")
        #expect(abs(info.duration - 1.5) < 0.2)
        #expect(info.audioTracks.count == 1)
    }

    @Test func hevcCropRotateWithProgress() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 640, height: 360), seconds: 2)
        var settings = EncodeSettings()
        settings.videoCodec = .hevc
        settings.container = .mov
        settings.rotation = .cw90
        settings.crop = Crop(top: 0, bottom: 0, left: 20, right: 20)
        settings.audioMixdown = .mono

        let reported = ProgressLog()
        let out = dir.appendingPathComponent("out.mov")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { reported.add($0) }

        let info = try await MediaInspector.inspect(out)
        #expect(info.displaySize == CGSize(width: 360 - 40, height: 640))
        #expect(info.videoCodec == "HEVC")
        #expect(info.audioTracks.first?.channels == 1)
        #expect(reported.last == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("source") }
        #expect(files == ["out.mov"])
    }

    @Test func cancellationRemovesPartialOutput() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 1920, height: 1080), seconds: 6)
        var settings = EncodeSettings()
        settings.videoCodec = .proRes422HQ
        settings.container = .mov
        let out = dir.appendingPathComponent("cancel.mov")

        let task = Task {
            try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("source") }
        #expect(leftovers.isEmpty, "\(leftovers)")
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HVCTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ value: Double) { lock.withLock { values.append(value) } }
    var last: Double? { lock.withLock { values.last } }
}

enum SyntheticClip {
    /// Writes an H.264 + stereo AAC clip with moving gradient frames and a sine tone.
    static func make(in dir: URL, size: CGSize, seconds: Int) async throws -> URL {
        let url = dir.appendingPathComponent("source-\(Int(size.width)).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000
        ])
        video.expectsMediaDataInRealTime = false
        audio.expectsMediaDataInRealTime = false
        writer.add(video)
        writer.add(audio)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = 30, chunk = 1_024
        let totalFrames = fps * seconds, totalAudio = 48_000 * seconds
        var frame = 0, audioPos = 0
        // Interleave both inputs; the writer stalls one if the other falls behind.
        while frame < totalFrames || audioPos < totalAudio {
            var progressed = false
            if frame < totalFrames, video.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool {
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                if let buffer {
                    fill(buffer, shade: UInt8(frame * 4 % 255))
                    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
                }
                frame += 1
                if frame == totalFrames { video.markAsFinished() }
                progressed = true
            }
            if audioPos < totalAudio, audio.isReadyForMoreMediaData {
                if let sample = try sineBuffer(start: audioPos, frames: chunk) { audio.append(sample) }
                audioPos += chunk
                if audioPos >= totalAudio { audio.markAsFinished() }
                progressed = true
            }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? TranscodeError.noTracks }
        return url
    }

    private static func fill(_ buffer: CVPixelBuffer, shade: UInt8) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            memset(base + row * rowBytes, Int32(shade &+ UInt8(row % 255)), rowBytes)
        }
    }

    private static func sineBuffer(start: Int, frames: Int) throws -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { return nil }

        let samples = (0..<frames).flatMap { i -> [Float] in
            let value = Float(sin(2 * Double.pi * 440 * Double(start + i) / 48_000) * 0.2)
            return [value, value]
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
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 48_000),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        return sample
    }
}
