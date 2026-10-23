import Foundation

/// AI models bundled from Upscayl (Real-ESRGAN family). Only models whose licences allow
/// redistribution are included, as in HyperImage.
public enum UpscaleModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case lite = "upscayl-lite-4x"
    case digitalArt = "digital-art-4x"
    case standard = "upscayl-standard-4x"
    case highFidelity = "high-fidelity-4x"

    public var id: String { rawValue }

    /// English names; the app's string tables translate them.
    public var displayName: String {
        switch self {
        case .lite: "Fast"
        case .digitalArt: "Animation & Art"
        case .standard: "Standard"
        case .highFidelity: "High Fidelity"
        }
    }

    public var summary: String {
        switch self {
        case .lite: "Good results in a reasonable time. Recommended for video."
        case .digitalArt: "Cartoons, anime and screen recordings."
        case .standard: "More detail on real footage, but very slow."
        case .highFidelity: "Finest textures, but very slow."
        }
    }

    /// Measured on an Apple M4 (720p frames, models always run at 4× before resizing),
    /// so time follows the source's pixels, not the chosen scale.
    public var secondsPerSourceMegapixel: Double {
        switch self {
        case .lite: 1.22
        case .digitalArt: 6.7
        case .standard: 21.9
        case .highFidelity: 21.9
        }
    }
}

public enum UpscaleScale: Int, Codable, CaseIterable, Identifiable, Sendable {
    case x2 = 2, x3 = 3, x4 = 4
    public var id: Int { rawValue }
    public var displayName: String { "\(rawValue)×" }
}

/// How heavy the upscaled file may get: bits spent per pixel and frame.
/// Upscaled frames are clean (the model removes noise), so they compress well at low rates.
public enum UpscaleWeight: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact, balanced, high

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compact: "Light"
        case .balanced: "Balanced"
        case .high: "High Quality"
        }
    }

    public func bitsPerPixel(for codec: UpscaleCodec) -> Double {
        let hevc: Double = switch self {
        case .compact: 0.035
        case .balanced: 0.055
        case .high: 0.09
        }
        // H.264 needs roughly 60% more bits for the same picture.
        return codec == .h264 ? hevc * 1.6 : hevc
    }
}

public enum UpscaleCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case hevc, h264
    public var id: String { rawValue }
    public var displayName: String { self == .hevc ? "HEVC (H.265)" : "H.264" }
}

public struct UpscaleSettings: Codable, Hashable, Sendable {
    public var model = UpscaleModel.lite
    public var scale = UpscaleScale.x2
    public var weight = UpscaleWeight.balanced
    public var codec = UpscaleCodec.hevc
    /// Keeps the result inside 3840 × 2160 (or its portrait version).
    public var limitTo4K = true

    public init() {}

    enum CodingKeys: String, CodingKey { case model, scale, weight, codec, limitTo4K }

    /// Lenient, like EncodeSettings: fields added later fall back to their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UpscaleSettings()
        model = (try? c.decodeIfPresent(UpscaleModel.self, forKey: .model)) ?? d.model
        scale = (try? c.decodeIfPresent(UpscaleScale.self, forKey: .scale)) ?? d.scale
        weight = (try? c.decodeIfPresent(UpscaleWeight.self, forKey: .weight)) ?? d.weight
        codec = (try? c.decodeIfPresent(UpscaleCodec.self, forKey: .codec)) ?? d.codec
        limitTo4K = (try? c.decodeIfPresent(Bool.self, forKey: .limitTo4K)) ?? d.limitTo4K
    }
}

public enum UpscaleError: LocalizedError, Equatable {
    case backendMissing
    case failed(String)
    case noVideo

    public var errorDescription: String? {
        switch self {
        case .backendMissing: "The AI engine (Upscayl) wasn't found in the app."
        case .failed(let message): "AI Upscale failed: \(message)"
        case .noVideo: "This file has no video to upscale."
        }
    }
}
