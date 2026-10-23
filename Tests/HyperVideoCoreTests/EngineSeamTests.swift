@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

@Suite("Engine seams")
struct EngineSeamTests {
    private func samples(_ count: Int) throws -> [CMSampleBuffer] {
        let format = try #require(TimedText.format(mediaType: kCMMediaType_Subtitle))
        return try (0..<count).map { index in
            try #require(TimedText.sample("cue \(index)", start: Double(index), duration: 1, format: format))
        }
    }

    @Test func transformDropsAndReplacesSamples() throws {
        let all = try samples(4)
        var iterator = all.makeIterator()
        var seen = 0
        let next = SamplePump.filtered({ iterator.next() }, { buffer in
            defer { seen += 1 }
            return seen == 1 ? nil : buffer
        })
        var out: [CMSampleBuffer] = []
        while let buffer = next() { out.append(buffer) }
        #expect(out.count == 3)
        #expect(out[0] === all[0])
        #expect(out[1] === all[2])
        #expect(out[2] === all[3])
    }

    @Test func nilTransformPassesEverything() throws {
        let all = try samples(4)
        var iterator = all.makeIterator()
        let next = SamplePump.filtered({ iterator.next() }, nil)
        var count = 0
        while next() != nil { count += 1 }
        #expect(count == 4)
    }
}
