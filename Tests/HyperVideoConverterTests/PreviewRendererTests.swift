import Foundation
import HyperVideoCore
import Testing
@testable import HyperVideoConverter

@Suite("Conversion preview", .serialized)
@MainActor
struct PreviewRendererTests {
    @Test func rendersAShortClipWithBeforeAndAfterFrames() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(
            name: "four", frameTimes: (0..<120).map { Double($0) / 30 }, seconds: 4))
        let info = try await MediaInspector.inspect(clip)
        var settings = EncodeSettings()
        settings.container = .mp4
        let preview = try await PreviewRenderer.render(source: clip, info: info, settings: settings,
                                                      workRoot: env.output)
        #expect(preview.clipSeconds == PreviewRenderer.clipSeconds)
        #expect(preview.clipBytes > 0)
        #expect(preview.original.size.width > 0 && preview.converted.size.width > 0)
        // 2 s measured out of 4 s: the projection is about twice the clip.
        let projected = try #require(preview.projectedBytes)
        #expect(projected > preview.clipBytes)
        // The preview cleans up after itself.
        #expect(try FileManager.default.contentsOfDirectory(atPath: env.output.path).isEmpty)
    }

    @Test func clipStartsAFewSecondsInAndFitsInsideTheVideo() {
        #expect(PreviewRenderer.clipRange(duration: 60, trim: nil, upscaling: false) == (18, 20))
        let short = PreviewRenderer.clipRange(duration: 1, trim: nil, upscaling: false)
        #expect(short.start == 0 && short.end == 1)
        let trimmed = PreviewRenderer.clipRange(duration: 60, trim: TrimRange(start: 40, end: 50), upscaling: false)
        #expect(trimmed.start >= 40 && trimmed.end <= 50)
        let upscale = PreviewRenderer.clipRange(duration: 60, trim: nil, upscaling: true)
        #expect(upscale.end - upscale.start <= PreviewRenderer.upscaleClipSeconds + 0.001)
    }
}
