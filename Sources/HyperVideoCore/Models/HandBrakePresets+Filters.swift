import Foundation

extension HandBrakePresets {
    static func applyFilters(_ p: Fields, to s: inout EncodeSettings, notes: inout [String]) {
        applyDeinterlace(p, to: &s, notes: &notes)
        applyDenoise(p, to: &s)
        applyChromaSmooth(p, to: &s)
        applySharpen(p, to: &s)
        s.filters.colorspace = colorspace(p.string("PictureColorspacePreset"), notes: &notes)
        s.filters.grayscale = p.bool("VideoGrayScale") ?? false
        if isActive(p.string("PictureDeblockPreset")) {
            notes.append("Deblock isn't available on macOS's video engine.")
        }
        if isActive(p.string("PictureDetelecine")) {
            notes.append("Detelecine isn't available on macOS's video engine.")
        }
    }

    private static func isActive(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.isEmpty && value != "off"
    }

    private static func applyDeinterlace(_ p: Fields, to s: inout EncodeSettings, notes: inout [String]) {
        guard isActive(p.string("PictureDeinterlaceFilter")) else {
            s.filters.deinterlace = .off
            return
        }
        s.filters.deinterlace = p.string("PictureCombDetectPreset") == "off" ? .always : .auto
        switch p.string("PictureDeinterlacePreset") {
        case "bob", "eedi2bob": s.filters.deinterlaceMethod = .bob
        case "eedi2":
            s.filters.deinterlaceMethod = .blend
            notes.append("EEDI2 deinterlacing isn't available, so it blends.")
        default: s.filters.deinterlaceMethod = .blend
        }
    }

    private static func applyDenoise(_ p: Fields, to s: inout EncodeSettings) {
        guard let filter = p.string("PictureDenoiseFilter").flatMap(DenoiseFilter.init(rawValue:)) else {
            s.filters.denoise = .off
            return
        }
        s.filters.denoiseFilter = filter
        s.filters.denoise = level(p.string("PictureDenoisePreset"))
        s.filters.denoiseTune = p.string("PictureDenoiseTune").flatMap(DenoiseTune.init(rawValue:)) ?? .none
    }

    private static func applyChromaSmooth(_ p: Fields, to s: inout EncodeSettings) {
        guard isActive(p.string("PictureChromaSmoothPreset")) else {
            s.filters.chromaSmooth = .off
            return
        }
        s.filters.chromaSmooth = level(p.string("PictureChromaSmoothPreset"))
        s.filters.chromaSmoothTune = p.string("PictureChromaSmoothTune").flatMap(ChromaSmoothTune.init(rawValue:)) ?? .none
    }

    private static func applySharpen(_ p: Fields, to s: inout EncodeSettings) {
        guard let filter = p.string("PictureSharpenFilter").flatMap(SharpenFilter.init(rawValue:)) else {
            s.filters.sharpen = .off
            return
        }
        s.filters.sharpenFilter = filter
        s.filters.sharpen = level(p.string("PictureSharpenPreset"))
        let tune = p.string("PictureSharpenTune").flatMap(SharpenTune.init(rawValue:))
        s.filters.sharpenTune = tune?.resolved(for: filter) ?? .none
    }

    private static func colorspace(_ value: String?, notes: inout [String]) -> ColorspaceTarget {
        switch value {
        case nil, "off": return .off
        case "bt709": return .bt709
        case "bt601-6-525": return .bt601ntsc
        case "bt601-6-625": return .bt601pal
        case "bt2020": return .bt2020
        default:
            notes.append("Custom colorspace settings aren't available.")
            return .off
        }
    }
}
