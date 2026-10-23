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
        if name.contains("prores") {
            if name.contains("lt") { return .proRes422LT }
            if name.contains("proxy") { return .proRes422Proxy }
            if name.contains("hq") { return .proRes422HQ }
            return name.contains("4444") ? .proRes4444 : .proRes422
        }
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

    /// Nearest supported rate for a HandBrake rate string; "auto" or junk keeps the source rate.
    static func nearestFrameRate(_ value: String?) -> FrameRate {
        guard let fps = value.flatMap(Double.init), fps > 0 else { return .source }
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

    /// A preset level; unknown names ("custom") become Medium.
    static func level(_ preset: String?) -> FilterStrength {
        guard let preset, let level = FilterStrength(rawValue: preset), level != .off else { return .medium }
        return level
    }
}

extension HandBrakePresets {
    static func applyVideo(_ p: Fields, to s: inout EncodeSettings, notes: inout [String]) {
        s.container = container(p.string("FileFormat"), notes: &notes)
        s.videoCodec = videoCodec(p.string("VideoEncoder"), notes: &notes)
        s.rateControl = rateControl(p, codec: p.string("VideoEncoder"))
        let (rate, mode) = framerate(p)
        s.frameRate = rate
        s.videoOptions.frameRateMode = mode
        s.videoOptions.speed = encoderSpeed(p.string("VideoPreset"))
        s.videoOptions.profile = profile(p.string("VideoProfile"), notes: &notes).resolved(for: s.videoCodec)
        s.videoOptions.level = videoLevel(p.string("VideoLevel"), codec: s.videoCodec, notes: &notes)
        if p.bool("VideoMultiPass") == true, p.int("VideoQualityType") != 2 {
            notes.append("Multi-pass encoding isn't available, so it encodes in one pass.")
        }
        if let tune = p.string("VideoTune"), !tune.isEmpty, tune != "none" {
            notes.append("Encoder tunes aren't available on VideoToolbox.")
        }
    }

    static func framerate(_ p: Fields) -> (FrameRate, FrameRateMode) {
        let rate = nearestFrameRate(p.string("VideoFramerate"))
        switch p.string("VideoFramerateMode") {
        case "pfr": return (rate, .peak)
        case "vfr": return (.source, .variable)
        default: return (rate, .constant)
        }
    }

    static func encoderSpeed(_ preset: String?) -> EncoderSpeed {
        switch preset {
        case "ultrafast", "superfast", "veryfast", "faster", "fast", "speed": .speed
        case "slow", "slower", "veryslow", "placebo", "quality", "preservation": .quality
        default: .balanced
        }
    }

    static func profile(_ value: String?, notes: inout [String]) -> VideoProfile {
        guard let value, !value.isEmpty, value != "auto" else { return .auto }
        if let known = VideoProfile(rawValue: value) { return known }
        notes.append("The \(value) profile isn't available, so it uses Auto.")
        return .auto
    }

    static func videoLevel(_ value: String?, codec: VideoCodec, notes: inout [String]) -> VideoLevel {
        guard let value, !value.isEmpty, value != "auto" else { return .auto }
        guard let known = VideoLevel(rawValue: value) else {
            notes.append("Level \(value) isn't available, so it uses Auto.")
            return .auto
        }
        guard codec == .h264 else {
            notes.append("HEVC levels aren't available, so it uses Auto.")
            return .auto
        }
        return known
    }
}
