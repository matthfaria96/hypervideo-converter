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

    static func apply(_ buffer: CMSampleBuffer, factor: Float) -> CMSampleBuffer? {
        guard let source = CMSampleBufferGetDataBuffer(buffer),
              let format = CMSampleBufferGetFormatDescription(buffer) else { return nil }
        let length = CMBlockBufferGetDataLength(source)
        let count = length / MemoryLayout<Float>.size
        guard count > 0 else { return nil }
        var samples = [Float](repeating: 0, count: count)
        let copied = samples.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(source, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                       destination: $0.baseAddress!)
        }
        guard copied == noErr else { return nil }
        let output = scaled(samples, factor: factor)
        return makeBuffer(output, format: format, sampleCount: CMSampleBufferGetNumSamples(buffer),
                          pts: CMSampleBufferGetPresentationTimeStamp(buffer))
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
        let filled = samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: size)
        }
        guard filled == noErr else { return nil }
        var result: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: sampleCount,
            presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &result
        ) == noErr else { return nil }
        return result
    }

    static func transform(gainDb: Double) -> SampleTransform? {
        let gain = factor(db: gainDb)
        guard gain != 1 else { return nil }
        return { buffer in apply(buffer, factor: gain) ?? buffer }
    }
}
