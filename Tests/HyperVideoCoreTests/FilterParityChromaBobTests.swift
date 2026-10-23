import CoreImage
import Testing
@testable import HyperVideoCore

@Suite("Filter parity chroma and bob")
struct FilterParityChromaBobTests {
    let helper = FilterParityTests()

    func colorColumns() -> CIImage {
        helper.image(width: 32, height: 16) { x, _ in x % 2 == 0 ? [220, 40, 40, 255] : [40, 100, 200, 255] }
    }

    func columnContrast(_ image: CIImage) -> Double {
        let p = helper.pixels(image)
        var total = 0.0
        for x in 8..<24 { total += abs(Double(p[(8 * 32 + x) * 4]) - Double(p[(8 * 32 + x + 1) * 4])) }
        return total / 16
    }

    func meanLuma(_ image: CIImage) -> Double {
        let p = helper.pixels(image)
        return stride(from: 0, to: p.count, by: 4)
            .map { 0.299 * Double(p[$0]) + 0.587 * Double(p[$0 + 1]) + 0.114 * Double(p[$0 + 2]) }
            .reduce(0, +) / Double(p.count / 4)
    }

    func smoothed(_ strength: FilterStrength, _ tune: ChromaSmoothTune) -> CIImage {
        FrameFilter.chromaSmooth(colorColumns(), strength: strength, tune: tune)
    }

    @Test func chromaSmoothSoftensColourKeepsLuma() {
        let source = colorColumns()
        let out = smoothed(.medium, .medium)
        #expect(columnContrast(out) < columnContrast(source))
        #expect(abs(meanLuma(out) - meanLuma(source)) <= 4)
        #expect(helper.pixels(smoothed(.off, .medium)) == helper.pixels(source))
        #expect(columnContrast(smoothed(.ultralight, .verywide)) < columnContrast(smoothed(.ultralight, .tiny)))
    }

    func comb() -> CIImage {
        helper.image(width: 8, height: 8) { _, y in y % 2 == 0 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
    }

    @Test func bobRemovesCombing() {
        let out = FrameFilter.bob(comb())
        #expect(out.extent == comb().extent)
        let p = helper.pixels(out)
        for y in 1..<6 {
            #expect(abs(Int(p[(y * 8 + 4) * 4]) - Int(p[((y + 1) * 8 + 4) * 4])) < 40, "row \(y)")
        }
    }

    @Test func renderPicksDeinterlaceMethod() {
        let size = comb().extent.size
        let plan = GeometryPlanner.plan(naturalSize: size, preferredTransform: .identity, crop: Crop(),
                                        rotation: .none, flipHorizontal: false, maxResolution: .source)
        var filters = VideoFilters()
        filters.deinterlaceMethod = .blend
        let blend = FrameFilter.render(comb(), sourceSize: size, plan: plan, filters: filters, deinterlace: true)
        #expect(helper.pixels(blend) == helper.pixels(FrameFilter.blendFields(comb())))
        filters.deinterlaceMethod = .bob
        let bob = FrameFilter.render(comb(), sourceSize: size, plan: plan, filters: filters, deinterlace: true)
        #expect(helper.pixels(bob) == helper.pixels(FrameFilter.bob(comb())))
    }
}
