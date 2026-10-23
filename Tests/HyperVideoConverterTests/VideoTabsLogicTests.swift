import CoreGraphics
import Foundation
import HyperVideoCore
import Testing
@testable import HyperVideoConverter

@Suite("Video tabs logic")
struct VideoTabsLogicTests {
    private func info(_ width: CGFloat, _ height: CGFloat) -> MediaInfo {
        MediaInfo(
            url: URL(fileURLWithPath: "/tmp/a.mov"), duration: 10, displaySize: CGSize(width: width, height: height),
            frameRate: 30, videoCodec: "avc1", videoBitrate: nil, dynamicRange: .sdr, audioTracks: [], fileBytes: 1)
    }

    @Test func denoiseChoiceDefaultsToOff() {
        #expect(VideoFilters().denoiseChoice == .off)
    }

    @Test func choosingDenoiseSetsFilterAndStrength() {
        let result = VideoFilters().choosingDenoise(.hqdn3d)
        #expect(result.denoise == .medium)
        #expect(result.denoiseFilter == .hqdn3d)
        #expect(result.denoiseChoice == .hqdn3d)
    }

    @Test func choosingDenoiseKeepsExistingStrength() {
        var filters = VideoFilters()
        filters.denoise = .strong
        #expect(filters.choosingDenoise(.nlmeans).denoise == .strong)
    }

    @Test func choosingDenoiseOffKeepsOtherFields() {
        var filters = VideoFilters()
        filters.denoise = .strong
        filters.sharpen = .light
        let result = filters.choosingDenoise(.off)
        #expect(result.denoise == .off)
        #expect(result.sharpen == .light)
    }

    @Test func choosingSharpenResolvesTune() {
        var filters = VideoFilters()
        filters.sharpenFilter = .lapsharp
        filters.sharpenTune = .film
        let result = filters.choosingSharpen(.unsharp)
        #expect(result.sharpenFilter == .unsharp)
        #expect(result.sharpenTune == .none)
        #expect(result.sharpen == .medium)
        #expect(result.sharpenChoice == .unsharp)
    }

    @Test func choosingSharpenOffClearsStrength() {
        var filters = VideoFilters()
        filters.sharpen = .strong
        #expect(filters.choosingSharpen(.off).sharpenChoice == .off)
    }

    @Test func finalDimensionsDefault() {
        let result = FinalDimensions.compute(info: info(1920, 1080), settings: EncodeSettings(), detectedCrop: nil)
        #expect(result?.storage == CGSize(width: 1920, height: 1080))
        #expect(result?.display == CGSize(width: 1920, height: 1080))
    }

    @Test func finalDimensionsRespectLimit() {
        var settings = EncodeSettings()
        settings.maxResolution = .hd720
        let result = FinalDimensions.compute(info: info(1920, 1080), settings: settings, detectedCrop: nil)
        #expect(result?.storage == CGSize(width: 1280, height: 720))
    }

    @Test func finalDimensionsLetterbox() {
        var settings = EncodeSettings()
        settings.maxResolution = .fhd1080
        settings.pictureOptions.padding.mode = .letterbox
        let result = FinalDimensions.compute(info: info(1920, 800), settings: settings, detectedCrop: nil)
        #expect(result?.storage == CGSize(width: 1920, height: 1080))
    }

    @Test func finalDimensionsUseDetectedCrop() {
        var settings = EncodeSettings()
        settings.pictureOptions.cropMode = .automatic
        let crop = Crop(top: 140, bottom: 140)
        let result = FinalDimensions.compute(info: info(1920, 1080), settings: settings, detectedCrop: crop)
        #expect(result?.storage == CGSize(width: 1920, height: 800))
    }

    @Test func finalDimensionsNoneIgnoresCustomCrop() {
        var settings = EncodeSettings()
        settings.pictureOptions.cropMode = .none
        settings.crop = Crop(top: 100, bottom: 100)
        let result = FinalDimensions.compute(info: info(1920, 1080), settings: settings, detectedCrop: nil)
        #expect(result?.storage == CGSize(width: 1920, height: 1080))
    }

    @Test func finalDimensionsNilWithoutVideo() {
        var media = info(10, 10)
        media.displaySize = nil
        #expect(FinalDimensions.compute(info: media, settings: EncodeSettings(), detectedCrop: nil) == nil)
    }

    @Test func padColorHexRoundTrip() {
        #expect(PadColorHex.hex(red: 1, green: 0.5, blue: 0) == "FF8000")
        let parts = PadColorHex.components("00FF00")
        #expect(parts?.red == 0 && parts?.green == 1 && parts?.blue == 0)
        #expect(PadColorHex.components("xyz") == nil)
    }
}
