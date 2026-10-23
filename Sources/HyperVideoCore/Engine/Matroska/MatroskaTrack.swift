import CoreMedia
import Foundation

/// One Matroska track, described from the CoreMedia format of the samples it will carry.
struct MatroskaTrack: Equatable {
    enum Kind: UInt64 {
        case video = 1, audio = 2, subtitle = 0x11
    }

    struct Video: Equatable {
        var pixelWidth: Int
        var pixelHeight: Int
        var displayWidth: Int
        var displayHeight: Int
        /// Clockwise rotation players should apply, in degrees (0, 90, 180 or 270).
        var rotation: Int
    }

    struct Audio: Equatable {
        var sampleRate: Double
        var channels: Int
        var bitDepth: Int?
    }

    var number: Int
    var uid: UInt64
    var kind: Kind
    var codecID: String
    var codecPrivate: Data?
    var language: String?
    var isDefault: Bool
    var isForced = false
    var name: String?
    var defaultDurationNs: UInt64?
    /// Decoder priming the timestamps include, such as AAC's leading samples.
    var codecDelayNs: UInt64 = 0
    var video: Video?
    var audio: Audio?

    /// The TrackEntry element.
    var element: Data {
        var children = [
            EBML.uint(EBML.ID.trackNumber, UInt64(number)),
            EBML.uint(EBML.ID.trackUID, uid),
            EBML.uint(EBML.ID.trackType, kind.rawValue),
            EBML.uint(EBML.ID.flagDefault, isDefault ? 1 : 0),
            EBML.uint(EBML.ID.flagForced, isForced ? 1 : 0),
            EBML.uint(EBML.ID.flagLacing, 0),
            EBML.string(EBML.ID.language, Self.legacyLanguage(language)),
            EBML.string(EBML.ID.codecID, codecID)
        ]
        if let language { children.append(EBML.string(EBML.ID.languageBCP47, language)) }
        if let name, !name.isEmpty { children.append(EBML.string(EBML.ID.name, name)) }
        if let codecPrivate { children.append(EBML.element(EBML.ID.codecPrivate, codecPrivate)) }
        if codecDelayNs > 0 { children.append(EBML.uint(EBML.ID.codecDelay, codecDelayNs)) }
        if let defaultDurationNs { children.append(EBML.uint(EBML.ID.defaultDuration, defaultDurationNs)) }
        if let video { children.append(Self.videoElement(video)) }
        if let audio { children.append(Self.audioElement(audio)) }
        return EBML.master(EBML.ID.trackEntry, children)
    }

    private static func videoElement(_ video: Video) -> Data {
        var children = [
            EBML.uint(EBML.ID.pixelWidth, UInt64(video.pixelWidth)),
            EBML.uint(EBML.ID.pixelHeight, UInt64(video.pixelHeight)),
            EBML.uint(EBML.ID.displayWidth, UInt64(video.displayWidth)),
            EBML.uint(EBML.ID.displayHeight, UInt64(video.displayHeight))
        ]
        if video.rotation != 0 {
            // A rectangular projection whose roll is counter-clockwise, as FFmpeg and mpv read it.
            children.append(EBML.master(EBML.ID.projection, [
                EBML.uint(EBML.ID.projectionType, 0),
                EBML.float(EBML.ID.projectionPoseRoll, Double(-video.rotation))
            ]))
        }
        return EBML.master(EBML.ID.video, children)
    }

    private static func audioElement(_ audio: Audio) -> Data {
        var children = [
            EBML.float(EBML.ID.samplingFrequency, audio.sampleRate),
            EBML.uint(EBML.ID.channels, UInt64(audio.channels))
        ]
        if let bits = audio.bitDepth, bits > 0 { children.append(EBML.uint(EBML.ID.bitDepth, UInt64(bits))) }
        return EBML.master(EBML.ID.audio, children)
    }

    /// The pre-BCP 47 Language element wants an ISO 639-2 code; "und" when unknown.
    static func legacyLanguage(_ tag: String?) -> String {
        guard let tag else { return "und" }
        return Locale(identifier: tag).language.languageCode?.identifier(.alpha3) ?? "und"
    }
}

// MARK: Building from CoreMedia

extension MatroskaTrack {
    enum UnsupportedFormat: Error, Equatable {
        case codec(String)
    }

    /// Video track for H.264 or HEVC samples; other codecs can't be copied into MKV here.
    static func video(
        format: CMFormatDescription, number: Int, transform: CGAffineTransform, frameRate: Float, language: String?
    ) throws -> MatroskaTrack {
        let subtype = CMFormatDescriptionGetMediaSubType(format)
        let codecID: String, atom: String
        switch subtype {
        case kCMVideoCodecType_H264: (codecID, atom) = ("V_MPEG4/ISO/AVC", "avcC")
        case kCMVideoCodecType_HEVC: (codecID, atom) = ("V_MPEGH/ISO/HEVC", "hvcC")
        default: throw UnsupportedFormat.codec(FourCC.string(subtype))
        }
        guard let config = sampleDescriptionAtom(atom, in: format) else { throw UnsupportedFormat.codec(FourCC.string(subtype)) }

        let dims = CMVideoFormatDescriptionGetDimensions(format)
        let aspect = pixelAspect(of: format)
        let width = Int(dims.width), height = Int(dims.height)
        let video = Video(
            pixelWidth: width, pixelHeight: height,
            displayWidth: max(1, Int((Double(width) * aspect).rounded())), displayHeight: height,
            rotation: rotation(of: transform)
        )
        let duration = frameRate > 0 ? UInt64((1_000_000_000 / Double(frameRate)).rounded()) : nil
        return MatroskaTrack(number: number, uid: uid(for: number), kind: .video, codecID: codecID, codecPrivate: config,
                             language: language, isDefault: true, defaultDurationNs: duration, video: video)
    }

    /// Audio track for AAC, ALAC, AC-3, E-AC-3 or MP3 samples.
    static func audio(format: CMFormatDescription, number: Int, language: String?, isDefault: Bool, name: String? = nil) throws -> MatroskaTrack {
        let subtype = CMFormatDescriptionGetMediaSubType(format)
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
            throw UnsupportedFormat.codec(FourCC.string(subtype))
        }
        let cookie = magicCookie(of: format)
        let codecID: String
        var codecPrivate: Data?
        var bitDepth: Int?
        switch subtype {
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_LD:
            codecID = "A_AAC"
            codecPrivate = cookie.flatMap(AudioConfig.aacSpecificConfig(fromCookie:)) ?? AudioConfig.aacLCConfig(asbd)
        case kAudioFormatAppleLossless:
            codecID = "A_ALAC"
            guard let config = cookie.flatMap(AudioConfig.alacSpecificConfig(fromCookie:)) else { throw UnsupportedFormat.codec("alac") }
            codecPrivate = config
            bitDepth = Int(config[5])
        case kAudioFormatAC3: codecID = "A_AC3"
        case kAudioFormatEnhancedAC3: codecID = "A_EAC3"
        case kAudioFormatMPEGLayer3: codecID = "A_MPEG/L3"
        default: throw UnsupportedFormat.codec(FourCC.string(subtype))
        }
        let audio = Audio(sampleRate: asbd.mSampleRate, channels: Int(asbd.mChannelsPerFrame), bitDepth: bitDepth)
        return MatroskaTrack(number: number, uid: uid(for: number), kind: .audio, codecID: codecID, codecPrivate: codecPrivate,
                             language: language, isDefault: isDefault, isForced: false, name: name, defaultDurationNs: nil, audio: audio)
    }

    /// Plain UTF-8 text subtitles (converted from 3GPP timed text).
    static func subtitle(
        number: Int, language: String?, isDefault: Bool = false, isForced: Bool = false, name: String? = nil
    ) -> MatroskaTrack {
        MatroskaTrack(number: number, uid: uid(for: number), kind: .subtitle, codecID: "S_TEXT/UTF8", codecPrivate: nil,
                      language: language, isDefault: isDefault, isForced: isForced, name: name, defaultDurationNs: nil)
    }

    /// Stable, non-zero UIDs that differ per file and per track.
    static func uid(for number: Int) -> UInt64 {
        UInt64.random(in: 1...UInt64.max >> 8) << 8 | UInt64(number & 0xFF)
    }

    static func rotation(of transform: CGAffineTransform) -> Int {
        let degrees = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
        return ((degrees % 360) + 360) % 360
    }

    private static func pixelAspect(of format: CMFormatDescription) -> Double {
        let ext = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio)
        guard let dict = ext as? [String: Any],
              let h = (dict[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String] as? NSNumber)?.doubleValue,
              let v = (dict[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String] as? NSNumber)?.doubleValue,
              h > 0, v > 0
        else { return 1 }
        return h / v
    }

    private static func sampleDescriptionAtom(_ name: String, in format: CMFormatDescription) -> Data? {
        let atoms = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
        return (atoms as? [String: Any])?[name] as? Data
    }

    private static func magicCookie(of format: CMFormatDescription) -> Data? {
        var size = 0
        guard let pointer = CMAudioFormatDescriptionGetMagicCookie(format, sizeOut: &size), size > 0 else { return nil }
        return Data(bytes: pointer, count: size)
    }
}
