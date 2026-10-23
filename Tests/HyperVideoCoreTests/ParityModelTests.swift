import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Parity model")
struct ParityModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: Video, picture, filters

    @Test func filterStrengthAmounts() {
        #expect(FilterStrength.off.amount == 0)
        #expect(FilterStrength.ultralight.amount == 1.0 / 6)
        #expect(FilterStrength.light.amount == 1.0 / 3)
        #expect(FilterStrength.medium.amount == 2.0 / 3)
        #expect(FilterStrength.strong.amount == 1)
        #expect(FilterStrength.stronger.amount == 4.0 / 3)
        #expect(FilterStrength.verystrong.amount == 5.0 / 3)
        #expect(FilterStrength.allCases.map(\.displayName)
            == ["Off", "Ultralight", "Light", "Medium", "Strong", "Stronger", "Very Strong"])
    }

    @Test func legacyFiltersDecodeWithDefaults() throws {
        let f = try decode(VideoFilters.self, #"{"deinterlace":"auto","denoise":"light","sharpen":"strong","grayscale":false}"#)
        #expect(f.deinterlaceMethod == .blend)
        #expect(f.denoiseFilter == .nlmeans)
        #expect(f.denoiseTune == .none)
        #expect(f.chromaSmooth == .off)
        #expect(f.chromaSmoothTune == .none)
        #expect(f.sharpenFilter == .lapsharp)
        #expect(f.sharpenTune == .none)
        #expect(f.colorspace == .off)
        #expect(f.denoise == .light)
        #expect(f.sharpen == .strong)
    }

    @Test func filterActivity() {
        var f = VideoFilters()
        f.chromaSmooth = .light
        #expect(f.isActive(sourceIsInterlaced: false))
        var g = VideoFilters()
        g.colorspace = .bt709
        #expect(!g.isActive(sourceIsInterlaced: false))
    }

    @Test func sharpenTuneOptions() {
        #expect(SharpenTune.options(for: .unsharp) == [.none, .ultrafine, .fine, .medium, .coarse, .verycoarse])
        #expect(SharpenTune.options(for: .lapsharp) == [.none, .film, .grain, .animation, .sprite])
        #expect(SharpenTune.film.resolved(for: .unsharp) == .none)
    }

    @Test func profileAndLevelOptions() {
        #expect(VideoProfile.options(for: .h264) == [.auto, .baseline, .main, .high])
        #expect(VideoProfile.options(for: .hevc10) == [.auto, .main10])
        #expect(VideoProfile.high.resolved(for: .hevc) == .auto)
        #expect(VideoLevel.options(for: .hevc) == [.auto])
        #expect(VideoLevel.options(for: .h264).count == 10)
    }

    private func close(_ p: Padding, _ r: Double, _ g: Double, _ b: Double) -> Bool {
        abs(p.red - r) < 1e-9 && abs(p.green - g) < 1e-9 && abs(p.blue - b) < 1e-9
    }

    @Test func paddingColors() {
        let k: Double = 255
        #expect(close(Padding(color: .gray), 112 / k, 128 / k, 144 / k))
        #expect(close(Padding(color: .darkGray), 47 / k, 79 / k, 79 / k))
        #expect(close(Padding(color: .white), 1, 1, 1))
        #expect(close(Padding(color: .custom, customHex: "FF8000"), 1, 128 / k, 0))
        #expect(close(Padding(color: .custom, customHex: "zz"), 0, 0, 0))
    }

    @Test func cropModeDetects() {
        #expect(CropMode.automatic.detects && CropMode.conservative.detects)
        #expect(!CropMode.custom.detects && !CropMode.none.detects)
    }

    @Test func emptyJSONGivesDefaults() throws {
        #expect(try decode(VideoEncoderOptions.self, "{}") == VideoEncoderOptions())
        #expect(try decode(PictureOptions.self, "{}") == PictureOptions())
    }
}
