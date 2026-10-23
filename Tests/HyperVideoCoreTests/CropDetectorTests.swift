@preconcurrency import AVFoundation
import CoreMedia
import Testing
@testable import HyperVideoCore

@Suite("Crop detector")
struct CropDetectorTests {
    private func buffer(width: Int = 320, height: Int = 240, dark: (Int, Int) -> Bool) -> [UInt8] {
        (0..<height).flatMap { y in (0..<width).map { x in dark(x, y) ? UInt8(0) : UInt8(128) } }
    }

    @Test func detectsHorizontalBars() {
        let luma = buffer { _, y in y < 30 || y >= 210 }
        #expect(CropDetector.bars(luma: luma, width: 320, height: 240) == Crop(top: 30, bottom: 30, left: 0, right: 0))
    }

    @Test func detectsSideBarsToo() {
        let luma = buffer { x, y in y < 30 || y >= 210 || x < 40 }
        #expect(CropDetector.bars(luma: luma, width: 320, height: 240)?.left == 40)
    }

    @Test func oddBarsRoundDownToEven() {
        let luma = buffer { _, y in y < 31 }
        #expect(CropDetector.bars(luma: luma, width: 320, height: 240)?.top == 30)
    }

    @Test func allDarkFrameIsNil() {
        #expect(CropDetector.bars(luma: buffer { _, _ in true }, width: 320, height: 240) == nil)
    }

    @Test func combineAutomaticPicksMostFrequent() {
        let crops = [30, 30, 30, 0].map { Crop(top: $0) }
        #expect(CropDetector.combine(crops, mode: .automatic).top == 30)
        let tied = [10, 20].map { Crop(top: $0) }
        #expect(CropDetector.combine(tied, mode: .automatic).top == 10)
    }

    @Test func combineConservativePicksMinimum() {
        let crops = [30, 30, 30, 0].map { Crop(top: $0) }
        #expect(CropDetector.combine(crops, mode: .conservative).top == 0)
        #expect(CropDetector.combine([], mode: .automatic) == .zero)
    }

    @Test func rotationMovesBorders() {
        let crop = Crop(top: 1, bottom: 2, left: 3, right: 4)
        #expect(crop.rotated(by: .cw90, flipped: false) == Crop(top: 3, bottom: 4, left: 2, right: 1))
        #expect(crop.rotated(by: .cw180, flipped: false) == Crop(top: 2, bottom: 1, left: 4, right: 3))
        #expect(crop.rotated(by: .cw270, flipped: false) == Crop(top: 4, bottom: 3, left: 1, right: 2))
        #expect(crop.rotated(by: .none, flipped: true) == Crop(top: 1, bottom: 2, left: 4, right: 3))
    }

    @Test func peakLimiterThinsHighRates() {
        var limiter = PeakRateLimiter(peak: 30)
        let times = (0..<60).map { Double($0) / 60 }
        let admitted = times.filter { limiter.admits($0) }
        #expect(abs(admitted.count - 30) <= 1)
        for pair in zip(admitted, admitted.dropFirst()) { #expect(pair.1 - pair.0 >= 1.0 / 30 - 0.0005) }
    }

    /// HandBrake keeps close to the peak rather than snapping to a divisor of the source rate.
    @Test(arguments: [(50.0, 30.0), (120.0, 50.0), (60.0, 24.0)])
    func peakLimiterStaysNearThePeak(source: Double, peak: Double) {
        var limiter = PeakRateLimiter(peak: peak)
        let times = (0..<Int(source * 2)).map { Double($0) / source }
        let perSecond = Double(times.filter { limiter.admits($0) }.count) / 2
        #expect(abs(perSecond - peak) <= 1, "\(perSecond) fps from \(source) with peak \(peak)")
    }

    @Test func peakLimiterDoesNotBankTimeAcrossPauses() {
        var limiter = PeakRateLimiter(peak: 30)
        let results = [0, 1, 1.01, 1.02].map { limiter.admits($0) }
        #expect(results == [true, true, false, false])
    }

    @Test func peakLimiterKeepsLowerRates() {
        var limiter = PeakRateLimiter(peak: 30)
        let times = (0..<60).map { Double($0) / 29.97 }
        #expect(times.filter { limiter.admits($0) }.count == 60)
    }

    @Test func alignmentStartsAtFirstVideoFrame() {
        let zero = CMTime.zero
        #expect(AVAlignment.start(rangeStart: zero, firstVideo: CMTime(seconds: 0.5, preferredTimescale: 600)).seconds == 0.5)
        #expect(AVAlignment.start(rangeStart: zero, firstVideo: nil) == zero)
        #expect(AVAlignment.start(rangeStart: CMTime(seconds: 1, preferredTimescale: 600),
                                  firstVideo: CMTime(seconds: 0.5, preferredTimescale: 600)).seconds == 1)
    }
}

@Suite("AV alignment")
struct AVAlignmentSourceTests {
    @Test func sessionStartFollowsFirstVideoFrame() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, StressClip.Spec(frameTimes: (15..<45).map { Double($0) / 30 }, seconds: 2))
        let asset = AVURLAsset(url: source)
        var settings = EncodeSettings()
        let range = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        #expect(await AVAlignment.sessionStart(asset: asset, range: range, settings: settings) == .zero)
        settings.alignAVStart = true
        let start = await AVAlignment.sessionStart(asset: asset, range: range, settings: settings)
        #expect(abs(start.seconds - 0.5) < 0.02, "\(start.seconds)")
    }
}
