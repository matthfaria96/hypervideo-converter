import CoreGraphics
import Foundation
import HyperVideoCore

enum DenoiseChoice: String, CaseIterable, Identifiable {
    case off, nlmeans, hqdn3d

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .off: "Off"
        case .nlmeans: "NLMeans"
        case .hqdn3d: "HQDN3D"
        }
    }
}

enum SharpenChoice: String, CaseIterable, Identifiable {
    case off, unsharp, lapsharp

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .off: "Off"
        case .unsharp: "Unsharp"
        case .lapsharp: "Lapsharp"
        }
    }
}

extension VideoFilters {
    var denoiseChoice: DenoiseChoice {
        guard denoise != .off else { return .off }
        return denoiseFilter == .nlmeans ? .nlmeans : .hqdn3d
    }

    func choosingDenoise(_ choice: DenoiseChoice) -> VideoFilters {
        var copy = self
        switch choice {
        case .off:
            copy.denoise = .off
        case .nlmeans, .hqdn3d:
            copy.denoiseFilter = choice == .nlmeans ? .nlmeans : .hqdn3d
            if copy.denoise == .off { copy.denoise = .medium }
        }
        return copy
    }

    var sharpenChoice: SharpenChoice {
        guard sharpen != .off else { return .off }
        return sharpenFilter == .unsharp ? .unsharp : .lapsharp
    }

    func choosingSharpen(_ choice: SharpenChoice) -> VideoFilters {
        var copy = self
        switch choice {
        case .off:
            copy.sharpen = .off
        case .unsharp, .lapsharp:
            copy.sharpenFilter = choice == .unsharp ? .unsharp : .lapsharp
            copy.sharpenTune = copy.sharpenTune.resolved(for: copy.sharpenFilter)
            if copy.sharpen == .off { copy.sharpen = .medium }
        }
        return copy
    }
}

enum FinalDimensions {
    static func compute(
        info: MediaInfo, settings: EncodeSettings, detectedCrop: Crop?
    ) -> (storage: CGSize, display: CGSize)? {
        guard let size = info.displaySize else { return nil }
        let crop: Crop
        switch settings.pictureOptions.cropMode {
        case .custom: crop = settings.crop
        case .none: crop = .zero
        case .automatic, .conservative: crop = detectedCrop ?? .zero
        }
        let plan = GeometryPlanner.plan(
            naturalSize: size, preferredTransform: .identity, crop: crop, rotation: settings.rotation,
            flipHorizontal: settings.flipHorizontal, maxResolution: settings.maxResolution,
            picture: settings.pictureOptions)
        let storage = plan.renderSize
        guard let aspect = plan.pixelAspect, aspect.height > 0 else { return (storage, storage) }
        let display = CGSize(width: (storage.width * aspect.width / aspect.height).rounded(), height: storage.height)
        return (storage, display)
    }
}

enum PadColorHex {
    static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

/// The last value of each Quality mode, so switching Constant Quality ↔ Average Bitrate
/// and back restores what the user had instead of resetting it.
struct RateControlMemory: Equatable {
    static let defaultQuality = 0.62
    static let defaultBitrateKbps = 6_000

    private(set) var quality = Self.defaultQuality
    private(set) var bitrateKbps = Self.defaultBitrateKbps

    /// Remembers `current`'s value and returns the rate control for the chosen mode.
    mutating func switching(toQuality: Bool, from current: RateControl) -> RateControl {
        switch current {
        case .quality(let value):
            guard !toQuality else { return current }
            quality = value
            return .averageBitrate(bitrateKbps)
        case .averageBitrate(let kbps):
            guard toQuality else { return current }
            bitrateKbps = kbps
            return .quality(quality)
        }
    }
}
