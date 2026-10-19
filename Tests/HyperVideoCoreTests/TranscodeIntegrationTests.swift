@preconcurrency import AVFoundation
import VideoToolbox
import Testing
@testable import HyperVideoCore

/// End-to-end: synthesize a short clip with audio, then convert it with real encoders.
@Suite("Transcode integration", .serialized)
struct TranscodeIntegrationTests {
    @Test func h264DownscaleAndTrim() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 1280, height: 720), seconds: 3)
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.maxResolution = .sd480
        settings.trim = TrimRange(start: 1, end: 2.5)

        let out = dir.appendingPathComponent("out.mp4")
        let bytes = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        #expect(bytes > 0)

        let info = try await MediaInspector.inspect(out)
        #expect(info.displaySize == CGSize(width: 854, height: 480))
        #expect(info.videoCodec == "H.264")
        #expect(abs(info.duration - 1.5) < 0.2)
        #expect(info.audioTracks.count == 1)
    }

    @Test func hevcCropRotateWithProgress() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 640, height: 360), seconds: 2)
        var settings = EncodeSettings()
        settings.videoCodec = .hevc
        settings.container = .mov
        settings.rotation = .cw90
        settings.crop = Crop(top: 0, bottom: 0, left: 20, right: 20)
        settings.audioMixdown = .mono

        let reported = ProgressLog()
        let out = dir.appendingPathComponent("out.mov")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { reported.add($0) }

        let info = try await MediaInspector.inspect(out)
        #expect(info.displaySize == CGSize(width: 360 - 40, height: 640))
        #expect(info.videoCodec == "HEVC")
        #expect(info.audioTracks.first?.channels == 1)
        #expect(reported.last == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("source") }
        #expect(files == ["out.mov"])
    }

    @Test func cancellationRemovesPartialOutput() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 1920, height: 1080), seconds: 6)
        var settings = EncodeSettings()
        settings.videoCodec = .proRes422HQ
        settings.container = .mov
        let out = dir.appendingPathComponent("cancel.mov")

        let task = Task {
            try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("source") }
        #expect(leftovers.isEmpty, "\(leftovers)")
    }

    @Test func subtitlesPassThroughWithLanguages() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 640, height: 360), seconds: 2,
                                                  subtitleLanguages: ["en", "pt-BR"])
        let sourceInfo = try await MediaInspector.inspect(source)
        #expect(sourceInfo.subtitleTracks.map(\.language) == ["en", "pt-BR"])
        #expect(sourceInfo.subtitleTracks.first?.format == "Timed Text")

        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.trim = TrimRange(start: 0.5, end: nil)
        for (selection, expected) in [(SubtitleSelection.all, ["en", "pt-BR"]), (.first, ["en"]), (.none, [])] {
            settings.subtitles = selection
            let out = dir.appendingPathComponent("subs-\(selection.rawValue).mp4")
            _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
            let info = try await MediaInspector.inspect(out)
            #expect(info.subtitleTracks.map(\.language) == expected, "\(selection)")
            #expect(info.audioTracks.count == 1)
        }
    }

    @Test func chaptersFollowTrimAndMetadataSetting() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 640, height: 360), seconds: 3,
                                                  chapters: ["One", "Two", "Three"])
        let sourceInfo = try await MediaInspector.inspect(source)
        #expect(sourceInfo.chapters.map(\.title) == ["One", "Two", "Three"])

        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.trim = TrimRange(start: 0.5, end: 2.5)
        let out = dir.appendingPathComponent("chapters.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        let chapters = try await MediaInspector.inspect(out).chapters
        #expect(chapters.map(\.title) == ["One", "Two", "Three"])
        #expect(zip(chapters.map(\.start), [0, 0.5, 1.5]).allSatisfy { abs($0 - $1) < 0.05 }, "\(chapters)")

        settings.keepMetadata = false
        let bare = dir.appendingPathComponent("bare.mov")
        settings.container = .mov
        _ = try await TranscodeEngine().run(source: source, destination: bare, settings: settings) { _ in }
        #expect(try await MediaInspector.inspect(bare).chapters.isEmpty)
    }

    @Test func subtitleFilesAreAddedAfterSourceTracks() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 640, height: 360), seconds: 3,
                                                  subtitleLanguages: ["en"])
        let srt = dir.appendingPathComponent("source-640.pt-BR.srt")
        try "1\n00:00:00,200 --> 00:00:01,000\nUm\n\n2\n00:00:01,500 --> 00:00:02,500\nDois\n".write(to: srt, atomically: true, encoding: .utf8)
        let files = SubtitleFile.sidecars(for: source)
        #expect(files == [SubtitleFile(url: srt, language: "pt-BR")])

        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.trim = TrimRange(start: 1, end: 3)
        let out = dir.appendingPathComponent("with-srt.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings, subtitleFiles: files) { _ in }
        #expect(try await MediaInspector.inspect(out).subtitleTracks.map(\.language) == ["en", "pt-BR"])
        let cues = try await Self.textSamples(in: out, trackIndex: 1).filter { !$0.text.isEmpty }
        #expect(cues.map(\.text) == ["Dois"])
        #expect(abs((cues.first?.start ?? -1) - 0.5) < 0.02, "\(cues)")

        settings.subtitles = .first
        let first = dir.appendingPathComponent("first.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: first, settings: settings, subtitleFiles: files) { _ in }
        #expect(try await MediaInspector.inspect(first).subtitleTracks.map(\.language) == ["en", "pt-BR"])

        settings.subtitles = .none
        let none = dir.appendingPathComponent("none.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: none, settings: settings, subtitleFiles: files) { _ in }
        #expect(try await MediaInspector.inspect(none).subtitleTracks.map(\.language) == ["pt-BR"])
    }

    @Test func unreadableSubtitleFileFailsTheEncode() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 1)
        let bad = dir.appendingPathComponent("bad.srt")
        try "not a subtitle".write(to: bad, atomically: true, encoding: .utf8)
        let missing = dir.appendingPathComponent("missing.srt")
        for file in [bad, missing] {
            await #expect(throws: TranscodeError.self) {
                _ = try await TranscodeEngine().run(source: source, destination: dir.appendingPathComponent("o.mp4"),
                                                    settings: EncodeSettings(), subtitleFiles: [SubtitleFile(url: file, language: nil)]) { _ in }
            }
        }
    }

    @Test func nearZeroTrimIsRejected() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 1)
        var settings = EncodeSettings()
        settings.trim = TrimRange(start: 0.5, end: 0.5)
        await #expect(throws: TranscodeError.self) {
            _ = try await TranscodeEngine().run(source: source, destination: dir.appendingPathComponent("z.mp4"), settings: settings) { _ in }
        }
    }

    /// Decodes tx3g samples of the `trackIndex`-th subtitle track, with output-timeline start times.
    static func textSamples(in url: URL, trackIndex: Int) async throws -> [SubtitleCue] {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .subtitle)[trackIndex]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var cues: [SubtitleCue] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var bytes = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: &bytes)
            let length = bytes.count >= 2 ? Int(bytes[0]) << 8 | Int(bytes[1]) : 0
            let text = String(decoding: bytes.dropFirst(2).prefix(length), as: UTF8.self)
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            cues.append(SubtitleCue(start: start, end: start + CMSampleBufferGetDuration(sample).seconds, text: text))
        }
        return cues
    }

    @Test func stalledEncodeFailsInsteadOfHanging() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 1920, height: 1080), seconds: 6)
        var settings = EncodeSettings()
        settings.videoCodec = .proRes422HQ
        settings.container = .mov
        let out = dir.appendingPathComponent("stalled.mov")
        // A limit far below the gap between two frames makes the watchdog fire right away.
        let engine = TranscodeEngine(stallTimeout: .milliseconds(1))
        let started = ContinuousClock.now
        await #expect(throws: TranscodeError.self) {
            try await engine.run(source: source, destination: out, settings: settings) { _ in }
        }
        #expect(ContinuousClock.now - started < .seconds(5))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("source") }
        #expect(leftovers.isEmpty, "\(leftovers)")
    }

    @Test func alternateTracksPlayOneAtATime() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 640, height: 360), seconds: 2,
                                                  audioLanguages: ["en", "fr"], subtitleLanguages: ["en", "fr"])
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.audioTracks = .all
        let out = dir.appendingPathComponent("alternates.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }

        let asset = AVURLAsset(url: out)
        #expect(try await Self.enabled(asset, .audio) == [true, false])
        #expect(try await Self.enabled(asset, .subtitle) == [false, false])
        #expect(try await asset.loadMediaSelectionGroup(for: .audible)?.options.count == 2)
        // Each tx3g track is offered twice (all text and forced-only), and macOS may add
        // a machine-translated option in the system language, so check containment.
        let legible = try #require(try await asset.loadMediaSelectionGroup(for: .legible))
        #expect(Set(["en", "fr"]).isSubset(of: legible.options.compactMap(\.extendedLanguageTag)))
    }

    @Test func extraAudioEncodingAddsASecondVersionOfEachTrack() async throws {
        let dir = try Self.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 640, height: 360), seconds: 2,
                                                  audioLanguages: ["pt-BR"])
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.audioMixdown = .stereo
        settings.extraAudio = AudioEncoding(codec: .aac, mixdown: .mono, bitrateKbps: 64)
        let out = dir.appendingPathComponent("two-versions.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }

        let info = try await MediaInspector.inspect(out)
        #expect(info.audioTracks.map(\.channels) == [2, 1])
        #expect(info.audioTracks.map(\.language) == ["pt-BR", "pt-BR"])
        #expect(try await Self.enabled(AVURLAsset(url: out), .audio) == [true, false])
    }

    static func enabled(_ asset: AVAsset, _ type: AVMediaType) async throws -> [Bool] {
        var flags: [Bool] = []
        for track in try await asset.loadTracks(withMediaType: type) { flags.append(try await track.load(.isEnabled)) }
        return flags
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HVCTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ value: Double) { lock.withLock { values.append(value) } }
    var last: Double? { lock.withLock { values.last } }
}

enum SyntheticClip {
    /// Writes an H.264 clip with moving gradient frames and one stereo AAC sine-tone
    /// track per entry in `audioLanguages`, plus one tx3g subtitle track (one cue per
    /// second) per entry in `subtitleLanguages` and a one-second chapter per entry in `chapters`.
    static func make(
        in dir: URL, size: CGSize, seconds: Int, audioLanguages: [String?] = [nil],
        subtitleLanguages: [String] = [], chapters: [String] = []
    ) async throws -> URL {
        let url = dir.appendingPathComponent("source-\(Int(size.width)).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        let audios = audioLanguages.map { language in
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000
            ])
            input.extendedLanguageTag = language
            input.expectsMediaDataInRealTime = false
            return input
        }
        video.expectsMediaDataInRealTime = false
        writer.add(video)
        audios.forEach(writer.add)
        let subtitleFormat = SyntheticSubtitles.format()
        let subtitles = subtitleLanguages.map { language in
            let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: subtitleFormat)
            input.extendedLanguageTag = language
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            return input
        }
        var cues = Array(repeating: 0, count: subtitles.count)
        let chapterFormat = SyntheticSubtitles.format(mediaType: kCMMediaType_Text)
        let chapterInput = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: chapterFormat)
        if !chapters.isEmpty {
            chapterInput.marksOutputTrackAsEnabled = false
            writer.add(chapterInput)
            video.addTrackAssociation(withTrackOf: chapterInput, type: AVAssetTrack.AssociationType.chapterList.rawValue)
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        if !chapters.isEmpty {
            for (index, title) in chapters.enumerated() {
                while !chapterInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
                chapterInput.append(try SyntheticSubtitles.cue(title, at: Double(index), format: chapterFormat))
            }
            chapterInput.markAsFinished()
        }

        let fps = 30, chunk = 1_024
        let totalFrames = fps * seconds, totalAudio = 48_000 * seconds
        var frame = 0
        var audioPositions = Array(repeating: 0, count: audios.count)
        // Interleave all inputs; the writer stalls one if another falls behind.
        while frame < totalFrames || audioPositions.contains(where: { $0 < totalAudio }) || cues.contains(where: { $0 < seconds }) {
            var progressed = false
            for (index, input) in subtitles.enumerated() where cues[index] < seconds && input.isReadyForMoreMediaData {
                let cue = cues[index]
                input.append(try SyntheticSubtitles.cue("Line \(cue + 1)", at: Double(cue), format: subtitleFormat))
                cues[index] += 1
                if cues[index] == seconds { input.markAsFinished() }
                progressed = true
            }
            if frame < totalFrames, video.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool {
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                if let buffer {
                    fill(buffer, shade: UInt8(frame * 4 % 255))
                    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
                }
                frame += 1
                if frame == totalFrames { video.markAsFinished() }
                progressed = true
            }
            for (index, audio) in audios.enumerated() where audioPositions[index] < totalAudio && audio.isReadyForMoreMediaData {
                if let sample = try sineBuffer(start: audioPositions[index], frames: chunk) { audio.append(sample) }
                audioPositions[index] += chunk
                if audioPositions[index] >= totalAudio { audio.markAsFinished() }
                progressed = true
            }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? TranscodeError.noTracks }
        return url
    }

    /// One second of interlaced ProRes 720×480 whose two fields are different
    /// (even lines light, odd lines dark), which looks like heavy combing.
    static func makeInterlacedComb(in dir: URL) async throws -> URL {
        let url = dir.appendingPathComponent("source-interlaced.mov")
        let size = (width: 720, height: 480)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes422, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                kVTCompressionPropertyKey_FieldCount as String: 2,
                kVTCompressionPropertyKey_FieldDetail as String: kCMFormatDescriptionFieldDetail_TemporalTopFirst as String
            ]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height
        ])
        writer.add(video)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !video.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
            guard let buffer else { throw TranscodeError.noTracks }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
                for row in 0..<size.height { memset(base + row * rowBytes, row % 2 == 0 ? 220 : 30, rowBytes) }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        video.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? TranscodeError.noTracks }
        return url
    }

    private static func fill(_ buffer: CVPixelBuffer, shade: UInt8) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            memset(base + row * rowBytes, Int32(shade &+ UInt8(row % 255)), rowBytes)
        }
    }

    private static func sineBuffer(start: Int, frames: Int) throws -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { return nil }

        let samples = (0..<frames).flatMap { i -> [Float] in
            let value = Float(sin(2 * Double.pi * 440 * Double(start + i) / 48_000) * 0.2)
            return [value, value]
        }
        let data = samples.withUnsafeBytes { Data($0) }
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: 0, blockBufferOut: &block)
        guard let block else { return nil }
        data.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count) }

        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 48_000),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        return sample
    }
}

/// Subtitle and chapter samples for synthetic clips, built with the engine's tx3g writer.
enum SyntheticSubtitles {
    static func format(mediaType: CMMediaType = kCMMediaType_Subtitle) -> CMFormatDescription {
        TimedText.format(mediaType: mediaType)!
    }

    static func cue(_ text: String, at seconds: Double, format: CMFormatDescription) throws -> CMSampleBuffer {
        guard let sample = TimedText.sample(text, start: seconds, duration: 1, format: format) else { throw TranscodeError.noTracks }
        return sample
    }
}
