import Foundation

extension HandBrakePresets {
    static func container(_ format: String?, notes: inout [String]) -> ContainerFormat {
        switch format?.replacingOccurrences(of: "av_", with: "") {
        case "mp4", nil: return .mp4
        case "m4v": return .m4v
        case "mov": return .mov
        case "mkv": return .mkv
        case let other?:
            notes.append("\(other.uppercased()) output isn't available, so it saves as MP4.")
            return .mp4
        }
    }

    static func videoCodec(_ encoder: String?, notes: inout [String]) -> VideoCodec {
        let name = encoder ?? "x264"
        let tenBit = name.contains("10bit") || name.contains("12bit")
        if name.contains("264") { return .h264 }
        if name.contains("265") || name.contains("hevc") { return tenBit ? .hevc10 : .hevc }
        if name.contains("prores") { return .proRes422 }
        notes.append("The \(name) encoder isn't available, so it uses HEVC\(tenBit ? " 10-bit" : "").")
        return tenBit ? .hevc10 : .hevc
    }

    /// HandBrake's constant quality is a rate factor where lower is better (0–51 for
    /// x264/x265, 0–63 for AV1); VideoToolbox encoders use 0–100 where higher is better.
    static func rateControl(_ p: Fields, codec: String?) -> RateControl {
        guard p.int("VideoQualityType") == 2 else { return .averageBitrate(max(100, p.int("VideoAvgBitrate"))) }
        let slider = p.double("VideoQualitySlider") ?? 22
        let encoder = codec ?? ""
        let quality: Double
        if encoder.hasPrefix("vt_") {
            quality = slider / 100
        } else {
            quality = 1 - slider / (encoder.contains("av1") ? 63 : 51)
        }
        return .quality((min(max(quality, 0.2), 1) * 100).rounded() / 100)
    }

    /// "pfr" is a peak, which HyperVideo honours by keeping the source rate rather
    /// than duplicating frames to reach it.
    static func frameRate(_ value: String?, mode: String?) -> FrameRate {
        guard mode == "cfr", let fps = value.flatMap(Double.init) else { return .source }
        return FrameRate.allCases.filter { $0 != .source }.min { abs($0.rawValue - fps) < abs($1.rawValue - fps) } ?? .source
    }

    static func maxResolution(height: Int) -> MaxResolution {
        guard height > 0 else { return .source }
        let limits = MaxResolution.allCases.filter { $0 != .source }.sorted { $0.rawValue > $1.rawValue }
        return limits.first { $0.rawValue <= height } ?? .sd480
    }

    static func rotation(_ value: String?) -> (Rotation, Bool) {
        let parts = Dictionary(
            (value ?? "").split(separator: ":").compactMap { pair -> (String, Int)? in
                let kv = pair.split(separator: "=")
                guard kv.count == 2, let number = Int(kv[1]) else { return nil }
                return (String(kv[0]), number)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return (Rotation(rawValue: parts["angle"] ?? 0) ?? .none, parts["hflip"] == 1)
    }

    static func strength(filter: String?, preset: String?) -> FilterStrength {
        guard let filter, filter != "off" else { return .off }
        switch preset {
        case "ultralight", "light": return .light
        case "strong", "stronger", "verystrong": return .strong
        default: return .medium
        }
    }
}
