import Foundation

public enum CropMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, conservative, none, custom

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .conservative: "Conservative"
        case .none: "None"
        case .custom: "Custom"
        }
    }
    /// Whether black borders are detected from the picture.
    public var detects: Bool { self == .automatic || self == .conservative }
}

public enum Anamorphic: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, automatic

    public var id: String { rawValue }
    public var displayName: String { self == .none ? "None" : "Automatic" }
}

public enum PaddingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, letterbox, pillarbox, both

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "None"
        case .letterbox: "Height (Letterbox)"
        case .pillarbox: "Width (Pillarbox)"
        case .both: "Width & Height"
        }
    }
}

public enum PadColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case black, white, gray, darkGray, custom

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .black: "Black"
        case .white: "White"
        case .gray: "Gray"
        case .darkGray: "Dark Gray"
        case .custom: "Custom"
        }
    }
}

public struct Padding: Codable, Hashable, Sendable {
    public var mode: PaddingMode = .none
    public var color: PadColor = .black
    /// RRGGBB without the leading '#'.
    public var customHex = "000000"

    public init(mode: PaddingMode = .none, color: PadColor = .black, customHex: String = "000000") {
        self.mode = mode
        self.color = color
        self.customHex = customHex
    }

    public var isActive: Bool { mode != .none }
    public var red: Double { components.0 }
    public var green: Double { components.1 }
    public var blue: Double { components.2 }

    private var components: (Double, Double, Double) {
        switch color {
        case .black: (0, 0, 0)
        case .white: (1, 1, 1)
        case .gray: (112 / 255, 128 / 255, 144 / 255)
        case .darkGray: (47 / 255, 79 / 255, 79 / 255)
        case .custom: customComponents
        }
    }

    private var customComponents: (Double, Double, Double) {
        var hex = customHex.trimmingCharacters(in: .whitespaces)
        for prefix in ["#", "0x", "0X"] where hex.hasPrefix(prefix) {
            hex = String(hex.dropFirst(prefix.count))
            break
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return (0, 0, 0) }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    private enum CodingKeys: String, CodingKey { case mode, color, customHex }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(PaddingMode.self, forKey: .mode) ?? .none
        color = try c.decodeIfPresent(PadColor.self, forKey: .color) ?? .black
        customHex = try c.decodeIfPresent(String.self, forKey: .customHex) ?? "000000"
    }
}

public struct PictureOptions: Codable, Hashable, Sendable {
    /// `.custom` with a zero crop is today's "no crop".
    public var cropMode: CropMode = .custom
    public var allowUpscaling = false
    public var anamorphic: Anamorphic = .none
    public var padding = Padding()

    public init() {}

    private enum CodingKeys: String, CodingKey { case cropMode, allowUpscaling, anamorphic, padding }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PictureOptions()
        cropMode = try c.decodeIfPresent(CropMode.self, forKey: .cropMode) ?? d.cropMode
        allowUpscaling = try c.decodeIfPresent(Bool.self, forKey: .allowUpscaling) ?? d.allowUpscaling
        anamorphic = try c.decodeIfPresent(Anamorphic.self, forKey: .anamorphic) ?? d.anamorphic
        padding = try c.decodeIfPresent(Padding.self, forKey: .padding) ?? d.padding
    }
}
