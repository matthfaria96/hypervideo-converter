import Foundation
import HyperVideoCore

/// How settings from a profile, a preset or another video combine with a video's own.
extension EncodeSettings {
    /// Settings with the per-video values reset, as stored in and applied from presets:
    /// trim, crop, burned-in subtitle, audio and subtitle track lists, chapter titles and
    /// the title tag only make sense for one source.
    var presetSettings: EncodeSettings {
        var copy = self
        copy.trim = nil
        copy.crop = .zero
        copy.burnIn = nil
        copy.audioOptions.tracks = []
        copy.subtitleOptions.tracks = []
        copy.chapterOptions.titles = []
        copy.tags.title = nil
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
        return copy.retuningAudioTracks().fixingCodecForContainer()
    }

    /// Whether the fields a quality profile decides still equal `profile`'s.
    func matchesProfile(_ profile: EncodeSettings) -> Bool {
        applyingProfile(profile) == self
    }

    /// Applies a preset: its settings win, except this video's trim, crop, burned-in
    /// subtitle, track lists, chapter titles and title tag, and the advanced choices
    /// (filters, picture, video encoder tuning, audio and subtitle options, chapter
    /// markers, other tags, rotation, flip, extra audio, track selection) that the
    /// preset leaves at their defaults.
    func adopting(_ template: EncodeSettings) -> EncodeSettings {
        template.keepingPerVideo(from: self).keepingAdvanced(from: self, template: template).retuningAudioTracks()
    }

    /// The Audio tab's explicit tracks with the main audio encoder and bitrate, so a
    /// profile, preset or inspector change to the audio reaches them too; each track
    /// keeps its mixdown, sample rate, gain and name.
    func retuningAudioTracks() -> EncodeSettings {
        var copy = self
        copy.audioOptions.tracks = audioOptions.tracks.map { track in
            var retuned = track
            retuned.encoding.codec = audioCodec
            retuned.encoding.bitrateKbps = audioBitrateKbps
            return retuned
        }
        return copy
    }

    /// Copies every setting of another video ("Apply to All"), keeping only this
    /// video's trim, crop, burned-in subtitle, track lists, chapter titles and title tag.
    func copyingAll(from template: EncodeSettings) -> EncodeSettings {
        template.keepingPerVideo(from: self)
    }

    /// This value with the per-video fields taken from `source`.
    private func keepingPerVideo(from source: EncodeSettings) -> EncodeSettings {
        var settings = self
        settings.trim = source.trim
        settings.crop = source.crop
        settings.burnIn = source.burnIn
        settings.audioOptions.tracks = source.audioOptions.tracks
        settings.subtitleOptions.tracks = source.subtitleOptions.tracks
        settings.chapterOptions.titles = source.chapterOptions.titles
        settings.tags.title = source.tags.title
        return settings
    }

    /// Keeps `current`'s advanced choices wherever `template` leaves them at the defaults.
    private func keepingAdvanced(from current: EncodeSettings, template: EncodeSettings) -> EncodeSettings {
        let defaults = EncodeSettings()
        var settings = self
        if template.filters == defaults.filters { settings.filters = current.filters }
        if template.rotation == defaults.rotation { settings.rotation = current.rotation }
        if template.flipHorizontal == defaults.flipHorizontal { settings.flipHorizontal = current.flipHorizontal }
        if template.extraAudio == nil { settings.extraAudio = current.extraAudio }
        if template.audioTracks == defaults.audioTracks { settings.audioTracks = current.audioTracks }
        if template.subtitles == defaults.subtitles { settings.subtitles = current.subtitles }
        if template.pictureOptions == defaults.pictureOptions { settings.pictureOptions = current.pictureOptions }
        let video = template.videoOptions
        if video.frameRateMode == defaults.videoOptions.frameRateMode {
            settings.videoOptions.frameRateMode = current.videoOptions.frameRateMode
        }
        if video.speed == defaults.videoOptions.speed { settings.videoOptions.speed = current.videoOptions.speed }
        if video.profile == defaults.videoOptions.profile { settings.videoOptions.profile = current.videoOptions.profile }
        if video.level == defaults.videoOptions.level { settings.videoOptions.level = current.videoOptions.level }
        keepGeneric(from: current, template: template, defaults: defaults, into: &settings)
        return settings
    }

    private func keepGeneric(
        from current: EncodeSettings, template: EncodeSettings, defaults: EncodeSettings, into settings: inout EncodeSettings
    ) {
        var audio = template.audioOptions
        audio.tracks = defaults.audioOptions.tracks
        var defaultAudio = defaults.audioOptions
        defaultAudio.tracks = []
        if audio == defaultAudio {
            settings.audioOptions.languages = current.audioOptions.languages
            settings.audioOptions.allowedPassthru = current.audioOptions.allowedPassthru
            settings.audioOptions.fallback = current.audioOptions.fallback
            settings.audioOptions.extraFirstTrackOnly = current.audioOptions.extraFirstTrackOnly
            settings.audioOptions.sampleRate = current.audioOptions.sampleRate
            settings.audioOptions.gainDb = current.audioOptions.gainDb
            settings.audioOptions.trackName = current.audioOptions.trackName
            settings.audioOptions.automaticNaming = current.audioOptions.automaticNaming
        }
        if template.subtitleOptions.languages.isEmpty { settings.subtitleOptions.languages = current.subtitleOptions.languages }
        if template.chapterOptions.markers == nil { settings.chapterOptions.markers = current.chapterOptions.markers }
        var otherTags = template.tags
        otherTags.title = nil
        if otherTags == MetadataTags() {
            var tags = current.tags
            tags.title = settings.tags.title
            settings.tags = tags
        }
        if !template.alignAVStart { settings.alignAVStart = current.alignAVStart }
    }
}
