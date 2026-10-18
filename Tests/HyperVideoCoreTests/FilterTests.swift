@preconcurrency import AVFoundation
import CoreImage
import Testing
@testable import HyperVideoCore

@Suite("Frame filters")
struct FrameFilterTests {
    /// Unmanaged color so pixel values pass through exactly.
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    /// A source where every pixel's color encodes its own position.
    func positionImage(width: Int, height: Int) -> CIImage {
        var bytes = [UInt8]()
        for y in 0..<height { for x in 0..<width { bytes += [UInt8(x * 20), UInt8(y * 20), 200, 255] } }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: width * 4,
                       size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: nil)
    }

    func pixels(_ image: CIImage, size: CGSize) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: Int(size.width * size.height) * 4)
        context.render(image, toBitmap: &out, rowBytes: Int(size.width) * 4,
                       bounds: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: nil)
        return out
    }

    @Test(arguments: [Rotation.none, .cw90, .cw180, .cw270])
    func coreImageGeometryMatchesThePlan(rotation: Rotation) {
        let size = CGSize(width: 8, height: 6)
        let plan = GeometryPlanner.plan(naturalSize: size, preferredTransform: .identity,
                                        crop: Crop(top: 2, bottom: 0, left: 2, right: 0), rotation: rotation,
                                        flipHorizontal: rotation == .cw90, maxResolution: .source)
        let output = pixels(FrameFilter.render(positionImage(width: 8, height: 6), sourceSize: size, plan: plan,
                                               filters: VideoFilters(), deinterlace: false), size: plan.renderSize)
        let toSource = plan.transform.inverted()
        for oy in 0..<Int(plan.renderSize.height) {
            for ox in 0..<Int(plan.renderSize.width) {
                let source = CGPoint(x: Double(ox) + 0.5, y: Double(oy) + 0.5).applying(toSource)
                let expected = [UInt8(Int(source.x) * 20), UInt8(Int(source.y) * 20)]
                let index = (oy * Int(plan.renderSize.width) + ox) * 4
                #expect(Array(output[index..<index + 2]) == expected, "\(rotation) at \(ox),\(oy)")
            }
        }
    }

    @Test func blendRemovesCombing() {
        let comb = (0..<8).flatMap { y in [UInt8](repeating: y % 2 == 0 ? 240 : 16, count: 8 * 4) }
        let image = CIImage(bitmapData: Data(comb), bytesPerRow: 32, size: CGSize(width: 8, height: 8),
                            format: .RGBA8, colorSpace: nil)
        let rows = pixels(FrameFilter.blendFields(image), size: CGSize(width: 8, height: 8))
        for y in 1..<7 {
            #expect(abs(Int(rows[y * 32]) - 128) <= 1, "row \(y): \(rows[y * 32])")
        }
    }

    @Test func filtersNeverBlockPassthrough() {
        var settings = EncodeSettings()
        settings.filters.deinterlace = .always
        settings.filters.denoise = .strong
        settings.videoCodec = .passthrough
        #expect(settings.isValid, "the filter controls are hidden for passthrough")
    }

    @Test func denoiseAndSharpenKeepFrameEdges() {
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        for filtered in [FrameFilter.denoise(gray, amount: 1), FrameFilter.sharpen(gray, amount: 1)] {
            let edge = pixels(filtered.composited(over: CIImage(color: .black)).cropped(to: gray.extent), size: gray.extent.size)
            #expect(abs(Int(edge[0]) - 128) <= 2, "corner \(edge[0])")
        }
    }
}

@Suite("Deinterlace integration", .serialized)
struct DeinterlaceIntegrationTests {
    @Test func interlacedSourceIsDetectedAndCleaned() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.makeInterlacedComb(in: dir)
        #expect(try await MediaInspector.inspect(source).isInterlaced)

        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.audioCodec = .none
        let cleaned = dir.appendingPathComponent("auto.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: cleaned, settings: settings) { _ in }
        #expect(try await Self.combing(in: cleaned) < 20)

        settings.filters.deinterlace = .off
        let raw = dir.appendingPathComponent("off.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: raw, settings: settings) { _ in }
        #expect(try await Self.combing(in: raw) > 120)

        settings.filters = VideoFilters()
        settings.filters.grayscale = true
        settings.rotation = .cw90
        let rotated = dir.appendingPathComponent("rotated.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: rotated, settings: settings) { _ in }
        #expect(try await MediaInspector.inspect(rotated).displaySize == CGSize(width: 480, height: 720))
    }

    /// Mean luma difference between neighbouring rows of a middle frame.
    static func combing(in url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ])
        reader.add(output)
        reader.startReading()
        var frame: CVPixelBuffer?
        for _ in 0..<5 { if let sample = output.copyNextSampleBuffer() { frame = CMSampleBufferGetImageBuffer(sample) } }
        let buffer = try #require(frame)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let luma = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        var total = 0.0, count = 0.0
        for y in 8..<(height - 8) {
            for x in stride(from: 8, to: width - 8, by: 8) {
                total += abs(Double(luma[y * rowBytes + x]) - Double(luma[(y + 1) * rowBytes + x]))
                count += 1
            }
        }
        reader.cancelReading()
        return total / count
    }
}
