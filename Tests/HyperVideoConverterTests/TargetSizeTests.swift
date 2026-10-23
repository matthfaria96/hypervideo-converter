import CoreGraphics
import Foundation
import HyperVideoCore
import Testing
@testable import HyperVideoConverter

@Suite("Compress to a target size", .serialized)
@MainActor
struct TargetSizeTests {
    static func info(seconds: Double = 60, width: Double = 1920, height: Double = 1080) -> MediaInfo {
        MediaInfo(url: URL(fileURLWithPath: "/tmp/a.mov"), duration: seconds,
                  displaySize: CGSize(width: width, height: height), frameRate: 30, videoCodec: "H.264",
                  videoBitrate: 10_000_000, dynamicRange: .sdr,
                  audioTracks: [AudioTrackInfo(id: 2, codec: "AAC", channels: 2, sampleRate: 48_000, language: "en")],
                  fileBytes: 80_000_000)
    }

    @Test func bitrateFillsTheTargetWithTheAudio() {
        let plan = TargetSizePlan(bytes: 25_000_000, info: Self.info(), settings: EncodeSettings())
        // 25 MB over 60 s ≈ 3.2 Mbit/s in total, minus 128 kbit/s of audio and the container margin.
        let total = Double(plan.videoKbps + plan.audioKbps) * 1000 * 60 / 8
        #expect(total <= 25_000_000 && total > 23_000_000)
        #expect(plan.settings.rateControl == .averageBitrate(plan.videoKbps))
        #expect(plan.settings.videoCodec == .hevc)
        #expect(plan.fits)
    }

    @Test func smallTargetsLowerTheResolutionInsteadOfBlurring() {
        let roomy = TargetSizePlan(bytes: 60_000_000, info: Self.info(), settings: EncodeSettings())
        #expect(roomy.settings.maxResolution == .source)
        let tight = TargetSizePlan(bytes: 8_000_000, info: Self.info(), settings: EncodeSettings())
        #expect(tight.settings.maxResolution != .source)
        #expect(tight.settings.maxResolution.rawValue < 1080)
    }

    @Test func impossibleTargetsSayTheyWontFit() {
        let plan = TargetSizePlan(bytes: 500_000, info: Self.info(seconds: 600), settings: EncodeSettings())
        #expect(!plan.fits)
        #expect(plan.videoKbps == TargetSizePlan.minimumVideoKbps)
    }

    @Test func trimShortensTheDurationItPlansFor() {
        var settings = EncodeSettings()
        settings.trim = TrimRange(start: 0, end: 30)
        let trimmed = TargetSizePlan(bytes: 10_000_000, info: Self.info(), settings: settings)
        let whole = TargetSizePlan(bytes: 10_000_000, info: Self.info(), settings: EncodeSettings())
        #expect(trimmed.videoKbps > whole.videoKbps)
    }

    @Test func compressModeWithATargetQueuesBitrateJobs() throws {
        let model = try TestEnvironment().makeModel()
        model.setSources([WorkspaceTests.source("a.mov")])
        model.setMode(.compress)
        model.compressTargetMB = 10
        model.enqueue([model.sources[0].id])
        let job = try #require(model.queue.jobs.first)
        guard case .averageBitrate = job.settings.rateControl else {
            Issue.record("expected an average bitrate job")
            return
        }
        model.queue.cancelAll()
    }

    @Test func estimateShowsTheTargetAsAnUpperBound() throws {
        let model = try TestEnvironment().makeModel()
        model.setSources([WorkspaceTests.source("a.mov"), WorkspaceTests.source("b.mov")])
        model.setMode(.compress)
        model.compressTargetMB = 10
        let estimate = model.compressEstimate
        #expect(estimate.kind == .upTo)
        #expect((estimate.estimatedBytes ?? .max) <= 2 * 10_000_000)
    }

    @Test func targetIsRememberedAndClearable() throws {
        let env = try TestEnvironment()
        env.makeModel().compressTargetMB = 16
        #expect(env.makeModel().compressTargetMB == 16)
        let model = env.makeModel()
        model.compressTargetMB = nil
        #expect(env.makeModel().compressTargetMB == nil)
    }
}
