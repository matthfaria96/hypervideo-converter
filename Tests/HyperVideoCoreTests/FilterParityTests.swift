import CoreImage
import CoreImage.CIFilterBuiltins
import Testing
@testable import HyperVideoCore

@Suite("Filter parity")
struct FilterParityTests {
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    func image(width: Int, height: Int, _ pixel: (Int, Int) -> [UInt8]) -> CIImage {
        var bytes = [UInt8]()
        for y in 0..<height { for x in 0..<width { bytes += pixel(x, y) } }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: width * 4,
                       size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: nil)
    }

    func pixels(_ image: CIImage) -> [UInt8] {
        let size = image.extent.size
        var out = [UInt8](repeating: 0, count: Int(size.width * size.height) * 4)
        context.render(image, toBitmap: &out, rowBytes: Int(size.width) * 4,
                       bounds: image.extent, format: .RGBA8, colorSpace: nil)
        return out
    }

    func noisy() -> CIImage {
        var seed: UInt32 = 12345
        return image(width: 32, height: 32) { _, _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let n = Int(seed >> 24) % 81 - 40
            return [UInt8(128 + n), UInt8(128 + n), UInt8(128 + n), 255]
        }
    }

    func deviation(_ image: CIImage) -> Double {
        let values = pixels(image).enumerated().filter { $0.offset % 4 == 0 }.map { Double($0.element) }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }

    func difference(_ a: CIImage, _ b: CIImage) -> Double {
        zip(pixels(a), pixels(b)).map { abs(Double($0) - Double($1)) }.reduce(0, +)
    }

    func edge() -> CIImage { image(width: 32, height: 16) { x, _ in x < 16 ? [60, 60, 60, 255] : [190, 190, 190, 255] } }

    @Test(arguments: [FilterStrength.light, .medium, .strong])
    func legacyDenoiseIsPixelIdentical(strength: FilterStrength) {
        let source = noisy()
        let filter = CIFilter.noiseReduction()
        filter.inputImage = source.clampedToExtent()
        filter.noiseLevel = Float(0.01 + 0.03 * strength.amount)
        filter.sharpness = 0.4
        let reference = (filter.outputImage ?? source).cropped(to: source.extent)
        var filters = VideoFilters()
        filters.denoise = strength
        #expect(pixels(FrameFilter.denoise(source, filters: filters)) == pixels(reference))
    }

    @Test(arguments: [FilterStrength.light, .medium, .strong])
    func legacySharpenIsPixelIdentical(strength: FilterStrength) {
        let source = edge()
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = source.clampedToExtent()
        filter.sharpness = Float(0.2 + 0.6 * strength.amount)
        filter.radius = 1.5
        let reference = (filter.outputImage ?? source).cropped(to: source.extent)
        var filters = VideoFilters()
        filters.sharpen = strength
        filters.sharpenFilter = .lapsharp
        #expect(pixels(FrameFilter.sharpen(source, filters: filters)) == pixels(reference))
    }

    @Test func denoiseKeepsExtentForEveryCombination() {
        let source = noisy()
        for strength in FilterStrength.allCases {
            for method in DenoiseFilter.allCases {
                for tune in DenoiseTune.allCases {
                    var filters = VideoFilters()
                    filters.denoise = strength
                    filters.denoiseFilter = method
                    filters.denoiseTune = tune
                    #expect(FrameFilter.denoise(source, filters: filters).extent == source.extent)
                }
            }
        }
    }

    @Test func hqdn3dLowersNoiseMoreWhenStronger() {
        let source = noisy()
        func run(_ strength: FilterStrength) -> Double {
            var filters = VideoFilters()
            filters.denoise = strength
            filters.denoiseFilter = .hqdn3d
            return deviation(FrameFilter.denoise(source, filters: filters))
        }
        #expect(run(.ultralight) < deviation(source))
        #expect(run(.verystrong) < run(.ultralight))
    }

    @Test func grainTuneKeepsLuma() {
        let source = image(width: 32, height: 32) { x, y in
            let n = (x * 7 + y * 13) % 2 == 0 ? 30 : -30
            return [UInt8(128 + n), UInt8(128 - n), 128, 255]
        }
        var filters = VideoFilters()
        filters.denoise = .strong
        filters.denoiseFilter = .hqdn3d
        filters.denoiseTune = .grain
        let before = pixels(source), after = pixels(FrameFilter.denoise(source, filters: filters))
        var total = 0.0
        for i in stride(from: 0, to: before.count, by: 4) {
            func luma(_ p: [UInt8]) -> Double { 0.299 * Double(p[i]) + 0.587 * Double(p[i + 1]) + 0.114 * Double(p[i + 2]) }
            total += abs(luma(before) - luma(after))
        }
        #expect(total / Double(before.count / 4) <= 3)
    }

    @Test func spriteTuneRemovesIsolatedPixel() {
        let source = image(width: 16, height: 16) { x, y in x == 8 && y == 8 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
        var filters = VideoFilters()
        filters.denoise = .medium
        filters.denoiseTune = .sprite
        let out = pixels(FrameFilter.denoise(source, filters: filters))
        #expect(out[(8 * 16 + 8) * 4] < 10)
    }

    func sharpened(_ filter: SharpenFilter, _ tune: SharpenTune) -> VideoFilters {
        var filters = VideoFilters()
        filters.sharpen = .strong
        filters.sharpenFilter = filter
        filters.sharpenTune = tune
        return filters
    }

    @Test func sharpenTunesScale() {
        func change(_ filters: VideoFilters) -> Double { difference(edge(), FrameFilter.sharpen(edge(), filters: filters)) }
        #expect(change(sharpened(.unsharp, .verycoarse)) > change(sharpened(.unsharp, .ultrafine)))
        #expect(change(sharpened(.lapsharp, .grain)) < change(sharpened(.lapsharp, .animation)))
    }

    @Test func invalidSharpenTuneActsLikeNone() {
        let film = sharpened(.unsharp, .film), none = sharpened(.unsharp, .none)
        #expect(pixels(FrameFilter.sharpen(edge(), filters: film)) == pixels(FrameFilter.sharpen(edge(), filters: none)))
    }
}
