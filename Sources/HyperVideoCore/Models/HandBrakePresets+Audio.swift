import Foundation

extension HandBrakePresets {
    /// HandBrake applies each entry of AudioList to every selected track; HyperVideo
    /// keeps the first entry as the main version and the second as the extra one.
    static func applyAudio(_ p: Fields, to s: inout EncodeSettings, notes: inout [String]) {
        let behavior = p.string("AudioTrackSelectionBehavior") ?? "first"
        let list = (p.raw["AudioList"] as? [[String: Any]] ?? []).map(Fields.init)
        guard behavior != "none", let main = list.first else {
            s.audioCodec = .none
            return
        }
        s.audioTracks = behavior == "all" ? .all : .first
        let encoding = audioEncoding(main, notes: &notes)
        s.audioCodec = encoding.codec
        s.audioMixdown = encoding.mixdown
        s.audioBitrateKbps = encoding.bitrateKbps
        if list.count > 1 { s.extraAudio = audioEncoding(list[1], notes: &notes) }
        if list.count > 2 {
            notes.append("Only the first two of its \(list.count) audio encoders are used.")
        }
    }

    static func audioEncoding(_ audio: Fields, notes: inout [String]) -> AudioEncoding {
        let encoder = audio.string("AudioEncoder") ?? "aac"
        let codec: AudioCodec
        switch encoder {
        case _ where encoder.hasPrefix("copy"):
            codec = .passthrough
        case _ where encoder.contains("aac"):
            codec = .aac
        case "alac", "alac16", "alac24":
            codec = .alac
        default:
            codec = .aac
            notes.append("\(encoder) audio isn't available, so it uses AAC.")
        }
        let mixdown: AudioMixdown = switch audio.string("AudioMixdown") {
        case "mono", "left_only", "right_only": .mono
        case "5point1", "6point1", "7point1", "5_2_lfe": .surround51
        default: .stereo
        }
        let bitrate = audio.int("AudioBitrate")
        return AudioEncoding(codec: codec, mixdown: mixdown, bitrateKbps: bitrate > 0 ? bitrate : 160)
    }
}
