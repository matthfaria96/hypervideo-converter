import CoreMedia
import Foundation

/// Gain applied to Float32 PCM between the reader and the writer.
enum AudioGain {
    static let maxDb = 20.0

    static func factor(db: Double) -> Float {
        guard db.isFinite else { return 1 }
        return Float(pow(10, min(max(db, -maxDb), maxDb) / 20))
    }

    static func scaled(_ samples: [Float], factor: Float) -> [Float] {
        samples.map { min(max($0 * factor, -1), 1) }
    }

    /// The gained copy of `buffer`, or nil when it isn't the packed, interleaved Float32 PCM
    /// `OutputSettingsBuilder.audioReaderPCM` asks for, or a Core Media call fails.
    static func apply(_ buffer: CMSampleBuffer, factor: Float) -> CMSampleBuffer? {
        guard let source = CMSampleBufferGetDataBuffer(buffer),
              let format = CMSampleBufferGetFormatDescription(buffer),
              let channels = floatChannels(format) else { return nil }
        let count = CMSampleBufferGetNumSamples(buffer) * channels
        let size = count * MemoryLayout<Float>.size
        guard count > 0, CMBlockBufferGetDataLength(source) == size else { return nil }
        var samples = [Float](repeating: 0, count: count)
        let copied = samples.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferCopyDataBytes(source, atOffset: 0, dataLength: size, destination: base)
        }
        guard copied == noErr else { return nil }
        let output = scaled(samples, factor: factor)
        return makeBuffer(output, format: format, sampleCount: CMSampleBufferGetNumSamples(buffer),
                          pts: CMSampleBufferGetPresentationTimeStamp(buffer))
    }

    /// Channel count of native-endian, interleaved 32-bit float PCM; nil for any other layout.
    static func floatChannels(_ format: CMFormatDescription) -> Int? {
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM, asbd.mBitsPerChannel == 32,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
              asbd.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              asbd.mChannelsPerFrame > 0 else { return nil }
        return Int(asbd.mChannelsPerFrame)
    }

    private static func makeBuffer(
        _ samples: [Float], format: CMFormatDescription, sampleCount: Int, pts: CMTime
    ) -> CMSampleBuffer? {
        let size = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: size, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        ) == noErr, let block else { return nil }
        let filled = samples.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: size)
        }
        guard filled == noErr else { return nil }
        var result: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: sampleCount,
            presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &result
        ) == noErr else { return nil }
        return result
    }

    /// Fails the encode rather than passing un-gained audio through, so the output never
    /// mixes gained and un-gained packets.
    static func transform(gainDb: Double) -> SampleTransform? {
        let gain = factor(db: gainDb)
        guard gain != 1 else { return nil }
        return { buffer in
            guard let gained = apply(buffer, factor: gain) else {
                throw TranscodeError.writerFailed("the audio gain couldn't be applied")
            }
            return gained
        }
    }
}
