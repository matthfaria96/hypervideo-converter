import Foundation

extension HandBrakePresets {
    /// HandBrake applies each entry of AudioList to every selected track; HyperVideo
    /// keeps the first entry as the main version and the second as the extra one.
    static func applyAudio(_ p: Fields, to s: inout EncodeSettings, notes: inout [String]) {
        let behavior = p.string("AudioTrackSelectionBehavior") ?? "first"
        let list = (p.raw["AudioList"] as? [[String: Any]] ?? []).map(Fields.init)
        s.audioOptions.languages = p.strings("AudioLanguageList").filter { $0 != "any" }
        s.audioOptions.allowedPassthru = allowedPassthru(p)
        s.audioOptions.fallback = fallback(p.string("AudioEncoderFallback"), notes: &notes)
        s.audioOptions.extraFirstTrackOnly = p.bool("AudioSecondaryEncoderMode") ?? false
        s.audioOptions.automaticNaming = ["unnamed", "all"].contains(p.string("AudioAutomaticNamingBehavior") ?? "none")
        if behavior == "none" { s.audioTracks = .none }
        guard behavior != "none", let main = list.first else {
            s.audioCodec = .none
            return
        }
        s.audioTracks = behavior == "all" ? .all : .first
        let encoding = audioEncoding(main, notes: &notes)
        s.audioCodec = encoding.codec
        s.audioMixdown = encoding.mixdown
        s.audioBitrateKbps = encoding.bitrateKbps
        s.audioOptions.sampleRate = encoding.sampleRate
        s.audioOptions.gainDb = encoding.gainDb
        s.audioOptions.trackName = encoding.trackName
        if list.count > 1 { s.extraAudio = audioEncoding(list[1], notes: &notes) }
        if list.count > 2 {
            notes.append("Only the first two of its \(list.count) audio encoders are used.")
        }
    }

    static func audioEncoding(_ audio: Fields, notes: inout [String]) -> AudioEncoding {
        let bitrate = audio.int("AudioBitrate")
        let name = audio.string("AudioTrackName").flatMap { $0.isEmpty ? nil : $0 }
        if (audio.double("AudioTrackDRCSlider") ?? 0) > 0 { notes.append("Dynamic range compression isn't available.") }
        if audio.bool("AudioTrackQualityEnable") == true {
            notes.append("Quality-based audio isn't available, so it uses the bitrate.")
        }
        return AudioEncoding(
            codec: audioCodec(audio.string("AudioEncoder") ?? "aac", notes: &notes),
            mixdown: audioMixdown(audio.string("AudioMixdown"), notes: &notes),
            bitrateKbps: bitrate > 0 ? bitrate : 160,
            sampleRate: audioSampleRate(audio),
            gainDb: min(max(audio.double("AudioTrackGainSlider") ?? 0, -20), 20),
            trackName: name
        )
    }

    static func audioCodec(_ encoder: String, notes: inout [String]) -> AudioCodec {
        switch encoder {
        case "copy": return .autoPassthru
        case _ where encoder.hasPrefix("copy:"): return .passthrough
        case "ca_haac", "fdk_haac", "haac": return .heAAC
        case _ where encoder.contains("aac"): return .aac
        case "alac", "alac16", "alac24": return .alac
        default:
            notes.append("\(encoder) audio isn't available, so it uses AAC.")
            return .aac
        }
    }

    static func audioMixdown(_ value: String?, notes: inout [String]) -> AudioMixdown {
        switch value {
        case "mono", "left_only", "right_only": return .mono
        case "5point1", "6point1", "5_2_lfe": return .surround51
        case "7point1": return .surround71
        case "dpl1", "dpl2":
            notes.append("Dolby Surround mixdowns aren't available, so it uses Stereo.")
            return .stereo
        default: return .stereo
        }
    }

    /// Missing keeps today's 48 kHz; kHz values (< 1000) are scaled; the nearest supported rate wins.
    static func audioSampleRate(_ audio: Fields) -> AudioSampleRate {
        guard let value = audio.looseDouble("AudioSamplerate") else {
            return audio.string("AudioSamplerate") == "auto" ? .auto : .hz48000
        }
        guard value > 0 else { return .auto }
        let hertz = value < 1000 ? value * 1000 : value
        let rates = AudioSampleRate.allCases.filter { $0 != .auto }
        return rates.min { abs(Double($0.rawValue) - hertz) < abs(Double($1.rawValue) - hertz) } ?? .hz48000
    }

    static func fallback(_ value: String?, notes: inout [String]) -> AudioCodec {
        switch value {
        case nil, "aac", "ca_aac", "av_aac", "none": return .aac
        case "ca_haac", "fdk_haac": return .heAAC
        case "alac", "alac16", "alac24": return .alac
        case let other?:
            notes.append("\(other) audio isn't available as a fallback, so it uses AAC.")
            return .aac
        }
    }

    static func allowedPassthru(_ p: Fields) -> Set<PassthruCodec> {
        let mask = p.strings("AudioCopyMask")
        if !mask.isEmpty {
            return Set(mask.compactMap { PassthruCodec(rawValue: $0.replacingOccurrences(of: "copy:", with: "")) })
        }
        let flags = PassthruCodec.allCases.map { ($0, p.bool("AudioAllow\($0.rawValue.uppercased())Pass")) }
        guard flags.contains(where: { $0.1 != nil }) else { return Set(PassthruCodec.allCases) }
        return Set(flags.filter { $0.1 == true }.map(\.0))
    }
}
