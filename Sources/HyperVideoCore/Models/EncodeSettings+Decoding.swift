import Foundation

// Decodes every field leniently, so presets and queues saved by older versions
// keep loading after new settings are added.
extension EncodeSettings {
    enum CodingKeys: String, CodingKey {
        case container, videoCodec, rateControl, frameRate, maxResolution, crop, rotation, flipHorizontal
        case allowBFrames, keyframeIntervalSeconds, filters
        case audioCodec, audioMixdown, audioBitrateKbps, audioTracks, extraAudio, subtitles, burnIn
        case trim, optimizeForWeb, keepMetadata
        case videoOptions, pictureOptions, audioOptions, subtitleOptions, chapterOptions, tags, alignAVStart
    }

    private enum LegacyKeys: String, CodingKey { case prioritizeSpeed }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        try decodeVideo(c)
        try decodeAudio(c)
        try decodeParity(c, legacy: legacy)
    }

    private mutating func decodeVideo(_ c: KeyedDecodingContainer<CodingKeys>) throws {
        let d = EncodeSettings()
        container = try c.decodeIfPresent(ContainerFormat.self, forKey: .container) ?? d.container
        videoCodec = try c.decodeIfPresent(VideoCodec.self, forKey: .videoCodec) ?? d.videoCodec
        rateControl = try c.decodeIfPresent(RateControl.self, forKey: .rateControl) ?? d.rateControl
        frameRate = try c.decodeIfPresent(FrameRate.self, forKey: .frameRate) ?? d.frameRate
        maxResolution = try c.decodeIfPresent(MaxResolution.self, forKey: .maxResolution) ?? d.maxResolution
        crop = try c.decodeIfPresent(Crop.self, forKey: .crop) ?? d.crop
        rotation = try c.decodeIfPresent(Rotation.self, forKey: .rotation) ?? d.rotation
        flipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? d.flipHorizontal
        allowBFrames = try c.decodeIfPresent(Bool.self, forKey: .allowBFrames) ?? d.allowBFrames
        keyframeIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .keyframeIntervalSeconds) ?? d.keyframeIntervalSeconds
        filters = try c.decodeIfPresent(VideoFilters.self, forKey: .filters) ?? d.filters
        trim = try c.decodeIfPresent(TrimRange.self, forKey: .trim)
        optimizeForWeb = try c.decodeIfPresent(Bool.self, forKey: .optimizeForWeb) ?? d.optimizeForWeb
        keepMetadata = try c.decodeIfPresent(Bool.self, forKey: .keepMetadata) ?? d.keepMetadata
    }

    private mutating func decodeAudio(_ c: KeyedDecodingContainer<CodingKeys>) throws {
        let d = EncodeSettings()
        audioCodec = try c.decodeIfPresent(AudioCodec.self, forKey: .audioCodec) ?? d.audioCodec
        audioMixdown = try c.decodeIfPresent(AudioMixdown.self, forKey: .audioMixdown) ?? d.audioMixdown
        audioBitrateKbps = try c.decodeIfPresent(Int.self, forKey: .audioBitrateKbps) ?? d.audioBitrateKbps
        audioTracks = try c.decodeIfPresent(AudioTrackSelection.self, forKey: .audioTracks) ?? d.audioTracks
        extraAudio = try c.decodeIfPresent(AudioEncoding.self, forKey: .extraAudio)
        subtitles = try c.decodeIfPresent(SubtitleSelection.self, forKey: .subtitles) ?? d.subtitles
        burnIn = try c.decodeIfPresent(SubtitleBurnIn.self, forKey: .burnIn)
    }

    private mutating func decodeParity(
        _ c: KeyedDecodingContainer<CodingKeys>, legacy: KeyedDecodingContainer<LegacyKeys>
    ) throws {
        let d = EncodeSettings()
        if let options = try c.decodeIfPresent(VideoEncoderOptions.self, forKey: .videoOptions) {
            videoOptions = options
        } else if try legacy.decodeIfPresent(Bool.self, forKey: .prioritizeSpeed) == true {
            videoOptions.speed = .speed
        }
        pictureOptions = try c.decodeIfPresent(PictureOptions.self, forKey: .pictureOptions) ?? d.pictureOptions
        audioOptions = try c.decodeIfPresent(AudioOptions.self, forKey: .audioOptions) ?? d.audioOptions
        subtitleOptions = try c.decodeIfPresent(SubtitleOptions.self, forKey: .subtitleOptions) ?? d.subtitleOptions
        chapterOptions = try c.decodeIfPresent(ChapterOptions.self, forKey: .chapterOptions) ?? d.chapterOptions
        tags = try c.decodeIfPresent(MetadataTags.self, forKey: .tags) ?? d.tags
        alignAVStart = try c.decodeIfPresent(Bool.self, forKey: .alignAVStart) ?? d.alignAVStart
    }
}
