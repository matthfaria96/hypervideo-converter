import CoreMedia
import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Matroska empty samples")
struct MatroskaEmptySampleTests {
    /// A sample buffer with one sample per entry in `sizes`, backed by `bytes`.
    private func makeBuffer(bytes: [UInt8], sizes: [Int]) throws -> CMSampleBuffer {
        let length = max(bytes.count, 1)
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr)
        let blockBuffer = try #require(block)
        let payload = bytes.isEmpty ? [UInt8(0)] : bytes
        payload.withUnsafeBytes {
            _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: blockBuffer,
                                              offsetIntoDestination: 0, dataLength: payload.count)
        }
        var timings = sizes.indices.map {
            CMSampleTimingInfo(duration: CMTime(value: 1_000, timescale: 1_000),
                               presentationTimeStamp: CMTime(value: CMTimeValue($0 * 1_000), timescale: 1_000),
                               decodeTimeStamp: .invalid)
        }
        var sampleSizes = sizes
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: nil,
            sampleCount: sizes.count, sampleTimingEntryCount: timings.count, sampleTimingArray: &timings,
            sampleSizeEntryCount: sampleSizes.count, sampleSizeArray: &sampleSizes, sampleBufferOut: &sample)
        #expect(status == noErr)
        return try #require(sample)
    }

    @Test("Zero-byte sample between others becomes an empty packet")
    func emptySampleInMiddle() throws {
        let buffer = try makeBuffer(bytes: [1, 2, 3, 4, 5, 6, 7], sizes: [4, 0, 3])
        let packets = MatroskaRemuxer.packets(in: buffer, track: 1, isText: false)
        #expect(packets.count == 3)
        guard packets.count == 3 else { return }
        #expect(packets[0].data == Data([1, 2, 3, 4]))
        #expect(packets[1].data.isEmpty)
        #expect(packets[2].data == Data([5, 6, 7]))
        for (index, packet) in packets.enumerated() {
            #expect(packet.pts == CMTime(value: CMTimeValue(index * 1_000), timescale: 1_000))
        }
    }

    @Test("Single zero-byte text sample does not crash")
    func singleEmptyTextSample() throws {
        let buffer = try makeBuffer(bytes: [], sizes: [0])
        let packets = MatroskaRemuxer.packets(in: buffer, track: 3, isText: true)
        #expect(packets.count == 1)
        #expect(packets.first?.data.isEmpty == true)
    }
}
