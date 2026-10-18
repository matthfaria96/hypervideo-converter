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
    case off, light, medium, strong

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
    /// 0 when off, rising to 1 for strong.
    public var amount: Double {
        switch self {
        case .off: 0
        case .light: 1 / 3
        case .medium: 2 / 3
        case .strong: 1
        }
    }
}

/// Picture filters applied after decoding, before scaling.
public struct VideoFilters: Codable, Hashable, Sendable {
    public var deinterlace: DeinterlaceMode = .auto
    public var denoise: FilterStrength = .off
    public var sharpen: FilterStrength = .off
    public var grayscale = false

    public init() {}

    /// Whether any filter will run on a source with the given interlacing.
    public func isActive(sourceIsInterlaced: Bool) -> Bool {
        deinterlaces(sourceIsInterlaced: sourceIsInterlaced) || denoise != .off || sharpen != .off || grayscale
    }

    public func deinterlaces(sourceIsInterlaced: Bool) -> Bool {
        deinterlace == .always || (deinterlace == .auto && sourceIsInterlaced)
    }

    private enum CodingKeys: String, CodingKey { case deinterlace, denoise, sharpen, grayscale }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deinterlace = try c.decodeIfPresent(DeinterlaceMode.self, forKey: .deinterlace) ?? .auto
        denoise = try c.decodeIfPresent(FilterStrength.self, forKey: .denoise) ?? .off
        sharpen = try c.decodeIfPresent(FilterStrength.self, forKey: .sharpen) ?? .off
        grayscale = try c.decodeIfPresent(Bool.self, forKey: .grayscale) ?? false
    }
}
