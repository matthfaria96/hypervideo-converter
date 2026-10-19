import Foundation
import HyperVideoCore

/// How settings from a profile, a preset or another video combine with a video's own.
extension EncodeSettings {
    /// Settings with the per-video values (trim, crop and burned-in subtitle, which only
    /// make sense for one source) reset, as stored in and applied from presets.
    var presetSettings: EncodeSettings {
        var copy = self
        copy.trim = nil
        copy.crop = .zero
        copy.burnIn = nil
        return copy
    }

    /// Takes only what a quality profile decides (codec, rate control, resolution,
    /// frame rate, audio codec and bitrate) from `profile`; everything else stays.
    func applyingProfile(_ profile: EncodeSettings) -> EncodeSettings {
        var copy = self
        copy.videoCodec = profile.videoCodec
        copy.rateControl = profile.rateControl
        copy.maxResolution = profile.maxResolution
        copy.frameRate = profile.frameRate
        copy.audioCodec = profile.audioCodec
        copy.audioBitrateKbps = profile.audioBitrateKbps
        if profile.audioCodec == .passthrough { copy.audioTracks = profile.audioTracks }
        return copy.fixingCodecForContainer()
    }

    /// Whether the fields a quality profile decides still equal `profile`'s.
    func matchesProfile(_ profile: EncodeSettings) -> Bool {
        applyingProfile(profile) == self
    }

    /// Applies a preset: its settings win, except this video's trim, crop and burned-in
    /// subtitle, and the advanced choices (filters, rotation, flip, extra audio, track
    /// selection) that the preset leaves at their defaults.
    func adopting(_ template: EncodeSettings) -> EncodeSettings {
        let defaults = EncodeSettings()
        var settings = template
        settings.trim = trim
        settings.crop = crop
        settings.burnIn = burnIn
        if template.filters == defaults.filters { settings.filters = filters }
        if template.rotation == defaults.rotation { settings.rotation = rotation }
        if template.flipHorizontal == defaults.flipHorizontal { settings.flipHorizontal = flipHorizontal }
        if template.extraAudio == nil { settings.extraAudio = extraAudio }
        if template.audioTracks == defaults.audioTracks { settings.audioTracks = audioTracks }
        if template.subtitles == defaults.subtitles { settings.subtitles = subtitles }
        return settings
    }

    /// Copies every setting of another video ("Apply to All"), keeping only this
    /// video's trim, crop and burned-in subtitle.
    func copyingAll(from template: EncodeSettings) -> EncodeSettings {
        var settings = template
        settings.trim = trim
        settings.crop = crop
        settings.burnIn = burnIn
        return settings
    }
}
