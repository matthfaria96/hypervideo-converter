import Foundation

public enum DeinterlaceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Only when the source is flagged as interlaced.
    case auto
    case off
    case always

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .auto: "Automatic"
        case .off: "Off"
        case .always: "Always"
        }
    }
}

public enum FilterStrength: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, ultralight, light, medium, strong, stronger, verystrong

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .off: "Off"
        case .ultralight: "Ultralight"
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        case .stronger: "Stronger"
        case .verystrong: "Very Strong"
        }
    }
    /// 0 when off, 1 for strong, rising above 1 for the stronger presets.
    public var amount: Double {
        switch self {
        case .off: 0
        case .ultralight: 1 / 6
        case .light: 1 / 3
        case .medium: 2 / 3
        case .strong: 1
        case .stronger: 4 / 3
        case .verystrong: 5 / 3
        }
    }
}

public enum DeinterlaceMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case blend, bob

    public var id: String { rawValue }
    public var displayName: String { self == .blend ? "Blend" : "Bob" }
}

public enum DenoiseFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case nlmeans, hqdn3d

    public var id: String { rawValue }
    public var displayName: String { self == .nlmeans ? "NLMeans" : "HQDN3D" }
}

public enum DenoiseTune: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, film, grain, highMotion = "highmotion", animation, tape, sprite

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "None"
        case .film: "Film"
        case .grain: "Grain"
        case .highMotion: "High Motion"
        case .animation: "Animation"
        case .tape: "Tape"
        case .sprite: "Sprite"
        }
    }
    public var multiplier: Double {
        switch self {
        case .highMotion, .tape: 1.2
        case .animation: 0.8
        default: 1
        }
    }
}

public enum ChromaSmoothTune: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, tiny, small, medium, wide, verywide

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "None"
        case .tiny: "Tiny"
        case .small: "Small"
        case .medium: "Medium"
        case .wide: "Wide"
        case .verywide: "Very Wide"
        }
    }
    public var widthFactor: Double {
        switch self {
        case .none, .medium: 1
        case .tiny: 0.5
        case .small: 0.75
        case .wide: 1.5
        case .verywide: 2
        }
    }
}

public enum SharpenFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case unsharp, lapsharp

    public var id: String { rawValue }
    public var displayName: String { self == .unsharp ? "Unsharp" : "Lapsharp" }
}

public enum SharpenTune: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, ultrafine, fine, medium, coarse, verycoarse, film, grain, animation, sprite

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "None"
        case .ultrafine: "Ultrafine"
        case .fine: "Fine"
        case .medium: "Medium"
        case .coarse: "Coarse"
        case .verycoarse: "Very Coarse"
        case .film: "Film"
        case .grain: "Grain"
        case .animation: "Animation"
        case .sprite: "Sprite"
        }
    }

    public static func options(for filter: SharpenFilter) -> [SharpenTune] {
        switch filter {
        case .unsharp: [.none, .ultrafine, .fine, .medium, .coarse, .verycoarse]
        case .lapsharp: [.none, .film, .grain, .animation, .sprite]
        }
    }

    public func resolved(for filter: SharpenFilter) -> SharpenTune {
        Self.options(for: filter).contains(self) ? self : .none
    }
}

public enum ColorspaceTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, bt709, bt601ntsc = "bt601_525", bt601pal = "bt601_625", bt2020

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .off: "Off"
        case .bt709: "BT.709"
        case .bt601ntsc: "BT.601 NTSC"
        case .bt601pal: "BT.601 PAL"
        case .bt2020: "BT.2020"
        }
    }
}

/// Picture filters applied after decoding, before scaling.
public struct VideoFilters: Codable, Hashable, Sendable {
    public var deinterlace: DeinterlaceMode = .auto
    public var deinterlaceMethod: DeinterlaceMethod = .blend
    public var denoise: FilterStrength = .off
    public var denoiseFilter: DenoiseFilter = .nlmeans
    public var denoiseTune: DenoiseTune = .none
    public var chromaSmooth: FilterStrength = .off
    public var chromaSmoothTune: ChromaSmoothTune = .none
    public var sharpen: FilterStrength = .off
    public var sharpenFilter: SharpenFilter = .lapsharp
    public var sharpenTune: SharpenTune = .none
    public var colorspace: ColorspaceTarget = .off
    public var grayscale = false

    public init() {}

    /// Whether any filter will run on a source with the given interlacing.
    public func isActive(sourceIsInterlaced: Bool) -> Bool {
        deinterlaces(sourceIsInterlaced: sourceIsInterlaced) || denoise != .off
            || chromaSmooth != .off || sharpen != .off || grayscale
    }

    public func deinterlaces(sourceIsInterlaced: Bool) -> Bool {
        deinterlace == .always || (deinterlace == .auto && sourceIsInterlaced)
    }

    private enum CodingKeys: String, CodingKey {
        case deinterlace, deinterlaceMethod, denoise, denoiseFilter, denoiseTune
        case chromaSmooth, chromaSmoothTune, sharpen, sharpenFilter, sharpenTune, colorspace, grayscale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoFilters()
        deinterlace = try c.decodeIfPresent(DeinterlaceMode.self, forKey: .deinterlace) ?? d.deinterlace
        deinterlaceMethod = try c.decodeIfPresent(DeinterlaceMethod.self, forKey: .deinterlaceMethod) ?? d.deinterlaceMethod
        denoise = try c.decodeIfPresent(FilterStrength.self, forKey: .denoise) ?? d.denoise
        denoiseFilter = try c.decodeIfPresent(DenoiseFilter.self, forKey: .denoiseFilter) ?? d.denoiseFilter
        denoiseTune = try c.decodeIfPresent(DenoiseTune.self, forKey: .denoiseTune) ?? d.denoiseTune
        chromaSmooth = try c.decodeIfPresent(FilterStrength.self, forKey: .chromaSmooth) ?? d.chromaSmooth
        chromaSmoothTune = try c.decodeIfPresent(ChromaSmoothTune.self, forKey: .chromaSmoothTune) ?? d.chromaSmoothTune
        sharpen = try c.decodeIfPresent(FilterStrength.self, forKey: .sharpen) ?? d.sharpen
        sharpenFilter = try c.decodeIfPresent(SharpenFilter.self, forKey: .sharpenFilter) ?? d.sharpenFilter
        sharpenTune = try c.decodeIfPresent(SharpenTune.self, forKey: .sharpenTune) ?? d.sharpenTune
        colorspace = try c.decodeIfPresent(ColorspaceTarget.self, forKey: .colorspace) ?? d.colorspace
        grayscale = try c.decodeIfPresent(Bool.self, forKey: .grayscale) ?? d.grayscale
    }
}
