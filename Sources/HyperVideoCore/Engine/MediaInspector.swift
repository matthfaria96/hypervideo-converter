import AVFoundation
import CoreMedia

public enum MediaInspectorError: LocalizedError {
    case unreadable(URL)
    case noPlayableTracks(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "“\(url.lastPathComponent)” can't be read by macOS media frameworks."
        case .noPlayableTracks(let url): "“\(url.lastPathComponent)” has no video or audio tracks."
        }
    }
}

public enum MediaInspector {
    public static func inspect(_ url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url)
        let (isReadable, duration) = try await asset.load(.isReadable, .duration)
        guard isReadable else { throw MediaInspectorError.unreadable(url) }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !videoTracks.isEmpty || !audioTracks.isEmpty else { throw MediaInspectorError.noPlayableTracks(url) }

        var info = MediaInfo(
            url: url, duration: duration.seconds.isFinite ? duration.seconds : 0,
            displaySize: nil, frameRate: nil, videoCodec: nil, videoBitrate: nil,
            dynamicRange: .sdr, audioTracks: [], fileBytes: fileSize(url)
        )

        if let video = videoTracks.first {
            let (size, transform, fps, rate, formats) = try await video.load(
                .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .formatDescriptions
            )
            info.displaySize = GeometryPlanner.orientedSize(size, transform)
            info.frameRate = fps > 0 ? Double(fps) : nil
            info.videoBitrate = rate > 0 ? Double(rate) : nil
            if let format = formats.first {
                info.videoCodec = FourCC.string(CMFormatDescriptionGetMediaSubType(format))
                info.dynamicRange = dynamicRange(of: format)
            }
        }

        var audioInfos: [AudioTrackInfo] = []
        for track in audioTracks {
            audioInfos.append(try await audioInfo(for: track))
        }
        info.audioTracks = audioInfos
        info.subtitleTracks = try await subtitleInfos(in: asset)
        return info
    }

    /// Text subtitles first, then closed captions, each in track order.
    static func subtitleTracks(in asset: AVAsset) async throws -> [(AVAssetTrack, SubtitleTrackInfo.Kind)] {
        let subtitles = try await asset.loadTracks(withMediaType: .subtitle)
        let captions = try await asset.loadTracks(withMediaType: .closedCaption)
        return subtitles.map { ($0, .subtitle) } + captions.map { ($0, .closedCaption) }
    }

    private static func subtitleInfos(in asset: AVAsset) async throws -> [SubtitleTrackInfo] {
        var infos: [SubtitleTrackInfo] = []
        for (track, kind) in try await subtitleTracks(in: asset) {
            let (formats, language, code) = try await track.load(.formatDescriptions, .extendedLanguageTag, .languageCode)
            let format = formats.first.map { FourCC.string(CMFormatDescriptionGetMediaSubType($0)) } ?? "Text"
            infos.append(SubtitleTrackInfo(id: Int(track.trackID), kind: kind, format: format, language: language ?? code))
        }
        return infos
    }

    public static func colorSpace(of format: CMFormatDescription) -> OutputSettingsBuilder.ColorSpace? {
        let ext = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        guard
            let primaries = ext[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String,
            let transfer = ext[kCMFormatDescriptionExtension_TransferFunction as String] as? String,
            let matrix = ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
        else { return nil }
        return .init(primaries: primaries, transfer: transfer, matrix: matrix)
    }

    static func dynamicRange(of format: CMFormatDescription) -> DynamicRange {
        if CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_DolbyVisionHEVC { return .dolbyVision }
        switch colorSpace(of: format)?.transfer {
        case AVVideoTransferFunction_SMPTE_ST_2084_PQ: return .hdr10
        case AVVideoTransferFunction_ITU_R_2100_HLG: return .hlg
        default: return .sdr
        }
    }

    private static func audioInfo(for track: AVAssetTrack) async throws -> AudioTrackInfo {
        let (formats, language) = try await track.load(.formatDescriptions, .extendedLanguageTag)
        var channels = 2
        var sampleRate = 48_000.0
        var codec = "Audio"
        if let format = formats.first {
            codec = FourCC.string(CMFormatDescriptionGetMediaSubType(format))
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                channels = Int(asbd.mChannelsPerFrame)
                sampleRate = asbd.mSampleRate
            }
        }
        return AudioTrackInfo(id: Int(track.trackID), codec: codec, channels: channels,
                              sampleRate: sampleRate, language: language)
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
