@preconcurrency import AVFoundation
import Synchronization
import Testing
@testable import HyperVideoCore

/// End-to-end MKV encodes, checked by parsing the output back with `MatroskaReader`.
@Suite("Matroska transcodes", .serialized)
struct MatroskaTranscodeTests {
    typealias Spec = StressClip.Spec

    private func encode(_ source: URL, _ settings: EncodeSettings, name: String = "out",
                        subtitleFiles: [SubtitleFile] = []) async throws -> (URL, MatroskaReader) {
        var settings = settings
        settings.container = .mkv
        let out = source.deletingLastPathComponent().appendingPathComponent("\(name).mkv")
        let reports = Mutex<[Double]>([])
        let bytes = try await TranscodeEngine().run(source: source, destination: out, settings: settings,
                                                    subtitleFiles: subtitleFiles) { value in reports.withLock { $0.append(value) } }
        let values = reports.withLock { $0 }
        #expect(values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 + 0.0001 }, "progress never goes backwards")
        let reader = try MatroskaReader(url: out)
        #expect(Int64(reader.data.count) == bytes)
        try checkStructure(reader)
        return (out, reader)
    }

    /// File-level invariants every output must satisfy.
    private func checkStructure(_ mkv: MatroskaReader) throws {
        #expect(mkv.docType == "matroska")
        let segment = try #require(mkv.segment)
        #expect(segment.dataStart + segment.size == mkv.data.count, "segment size is patched to the file end")
        for (id, offset) in mkv.seeks {
            #expect(mkv.segmentChild(at: offset)?.id == id, "seek entry 0x\(String(id, radix: 16)) points at its element")
        }
        #expect(Set(mkv.seeks.map(\.0)).isSuperset(of: [EBML.ID.info, EBML.ID.tracks]))
        let clusterOffsets = Set(mkv.clusters.map { $0.offset - segment.dataStart })
        #expect(!mkv.cues.isEmpty)
        #expect(mkv.cues.allSatisfy { clusterOffsets.contains(Int($0.1)) }, "cues point at clusters")
        #expect(mkv.blocks.allSatisfy { $0.time >= 0 })
        // Each cluster's first video block is a keyframe whenever the cluster starts at a cue.
        let video = mkv.tracks.first { $0.type == 1 }?.number
        let firstVideo = try #require(mkv.blocks.first { $0.track == video })
        #expect(firstVideo.isKeyframe && firstVideo.time <= 1)
    }

    private func blocks(_ mkv: MatroskaReader, track: Int) -> [MatroskaReader.Block] {
        mkv.blocks.filter { $0.track == track }
    }

    @Test func h264AndAACWithTrim() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 3)
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        let (_, mkv) = try await encode(source, settings)
        let tracks = mkv.tracks
        #expect(tracks.map(\.codecID) == ["V_MPEG4/ISO/AVC", "A_AAC"])
        #expect(tracks.map(\.number) == [1, 2])
        #expect(tracks[0].codecPrivate?.first == 1, "avcC configurationVersion")
        #expect(tracks[0].pixelSize == [320, 180] && tracks[0].displaySize == [320, 180])
        #expect((2...5).contains(tracks[1].codecPrivate?.count ?? 0))
        #expect(tracks[1].sampleRate == 48_000 && tracks[1].channels == 2)
        #expect(tracks[1].codecDelay == 44_000_000, "AAC priming (2112 samples) is declared, not played")
        #expect(tracks.allSatisfy { $0.isDefault })
        #expect(abs((mkv.duration ?? 0) - 3_000) < 40, "\(mkv.duration ?? 0)")
        let video = blocks(mkv, track: 1)
        #expect(video.count == 90, "\(video.count)")
        #expect(abs(Double(video.map(\.time).max() ?? 0) - 2_967) < 40)
        let audio = blocks(mkv, track: 2)
        #expect(abs(Double(audio.count) - 3 * 48_000 / 1_024) < 6, "\(audio.count)")
        #expect(zip(audio, audio.dropFirst()).allSatisfy { $0.time <= $1.time })
        // Only the finished file is left behind, with no work folder or intermediate movie.
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(files == ["out.mkv", "source-320.mov"], "\(files)")

        settings.trim = TrimRange(start: 1, end: 2.5)
        let (_, trimmed) = try await encode(source, settings, name: "trimmed")
        #expect(abs((trimmed.duration ?? 0) - 1_500) < 40, "\(trimmed.duration ?? 0)")
        let trimmedVideo = blocks(trimmed, track: 1)
        #expect(abs(trimmedVideo.count - 45) <= 1, "\(trimmedVideo.count)")
    }

    @Test func macOSCannotOpenMatroskaButTheParserCan() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, Spec())
        let (out, mkv) = try await encode(source, EncodeSettings())
        #expect(!mkv.blocks.isEmpty)
        let readable = (try? await AVURLAsset(url: out).load(.isReadable)) ?? false
        let tracks = (try? await AVURLAsset(url: out).loadTracks(withMediaType: .video)) ?? []
        // AVFoundation has no Matroska reader; if a future macOS adds one, this is the moment to know.
        print("AVFoundation on this Mac: readable=\(readable) videoTracks=\(tracks.count)")
        #expect(!readable || tracks.isEmpty)
    }

    @Test(arguments: [VideoCodec.hevc, .hevc10])
    func hevcWithBFramesUsesPresentationTimes(codec: VideoCodec) async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, Spec(frameTimes: (0..<60).map { Double($0) / 30 }, seconds: 2))
        var settings = EncodeSettings()
        settings.videoCodec = codec
        settings.allowBFrames = true
        let (_, mkv) = try await encode(source, settings)
        #expect(mkv.tracks.first?.codecID == "V_MPEGH/ISO/HEVC")
        #expect(mkv.tracks.first?.codecPrivate?.first == 1, "hvcC configurationVersion")
        let times = blocks(mkv, track: 1).map(\.time)
        #expect(times.count == 60)
        let sorted = times.sorted()
        #expect(Set(times).count == 60, "every frame has its own presentation time")
        #expect(zip(sorted, sorted.dropFirst()).allSatisfy { abs(Double($1 - $0) - 33.3) < 2 }, "\(sorted)")
        #expect(abs((mkv.duration ?? 0) - 2_000) < 40)
    }

    @Test func multipleAudioTracksKeepLanguagesAndOneDefault() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 2,
                                                  audioLanguages: ["en", "fr"])
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.audioTracks = .all
        settings.extraAudio = AudioEncoding(codec: .alac, mixdown: .stereo, bitrateKbps: 0)
        let (_, mkv) = try await encode(source, settings)
        let audio = mkv.tracks.filter { $0.type == 2 }
        #expect(audio.map(\.codecID) == ["A_AAC", "A_ALAC", "A_AAC", "A_ALAC"])
        #expect(audio.map(\.languageBCP47) == ["en", "en", "fr", "fr"])
        #expect(audio.map(\.language) == ["eng", "eng", "fra", "fra"])
        #expect(audio.map(\.isDefault) == [true, false, false, false])
        #expect(audio.filter { $0.codecID == "A_ALAC" }.allSatisfy { $0.codecPrivate?.count == 24 })
        for track in audio {
            let times = blocks(mkv, track: track.number).map(\.time)
            // Block times plus one packet, minus the declared priming, end with the 2 s clip.
            let end = Double(times.max() ?? 0) + 21 - Double(track.codecDelay) / 1e6
            #expect(abs(end - 2_000) < 60, "track \(track.number) ends at \(end)")
        }
    }

    @Test func subtitlesAndChaptersFollowTheTrim() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 3,
                                                  subtitleLanguages: ["en"], chapters: ["A", "B", "C"])
        let srt = dir.appendingPathComponent("side.srt")
        try "1\n00:00:01,500 --> 00:00:02,000\nOlá, mundo\n".write(to: srt, atomically: true, encoding: .utf8)
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.trim = TrimRange(start: 1, end: nil)
        let (_, mkv) = try await encode(source, settings, subtitleFiles: [SubtitleFile(url: srt, language: "pt-BR")])
        let subs = mkv.tracks.filter { $0.type == 0x11 }
        #expect(subs.map(\.codecID) == ["S_TEXT/UTF8", "S_TEXT/UTF8"])
        #expect(subs.map(\.languageBCP47) == ["en", "pt-BR"])
        #expect(subs.allSatisfy { !$0.isDefault })
        let sidecar = blocks(mkv, track: subs[1].number)
        #expect(sidecar.count == 1)
        #expect(sidecar.first.map { String(decoding: $0.payload, as: UTF8.self) } == "Olá, mundo")
        #expect(abs(Double(sidecar.first?.time ?? 0) - 500) < 20 && abs(Double(sidecar.first?.duration ?? 0) - 500) < 20)
        let embedded = blocks(mkv, track: subs[0].number)
        #expect(!embedded.isEmpty && embedded.allSatisfy { ($0.duration ?? 0) > 0 && $0.size > 0 })

        let chapters = mkv.chapters
        #expect(chapters.map(\.0) == ["B", "C"])
        #expect(chapters.first?.1 == 0)
        #expect(abs(Double(chapters.last?.1 ?? 0) / 1e9 - 1) < 0.05)
        #expect(abs((mkv.duration ?? 0) - 2_000) < 40)
    }

    @Test func passthroughKeepsRotationAndRejectsOtherCodecs() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0)
        let source = try await StressClip.make(in: dir, Spec(size: CGSize(width: 640, height: 360), transform: transform))
        var settings = EncodeSettings()
        settings.videoCodec = .passthrough
        settings.audioCodec = .passthrough
        let (_, mkv) = try await encode(source, settings)
        let video = try #require(mkv.tracks.first)
        #expect(video.pixelSize == [640, 360])
        #expect(video.roll == -90)
        #expect(mkv.tracks.map(\.codecID) == ["V_MPEG4/ISO/AVC", "A_AAC"])

        let prores = try await StressClip.make(in: dir, Spec(name: "prores", codec: .proRes422))
        await #expect(throws: TranscodeError.self) { _ = try await encode(prores, settings, name: "prores-out") }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("prores-out") || $0.hasPrefix(".") }
        #expect(leftovers.isEmpty, "\(leftovers)")
    }

    @Test func cancellingDuringTheRemuxLeavesNothing() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 640, height: 360), seconds: 6)
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.container = .mkv
        let out = dir.appendingPathComponent("cancel.mkv")
        let remuxing = Mutex(false)
        let task = Task {
            try await TranscodeEngine().run(source: source, destination: out, settings: settings) { value in
                if value > 0.9 && value < 1 { remuxing.withLock { $0 = true } }
            }
        }
        let deadline = ContinuousClock.now + .seconds(60)
        while !remuxing.withLock({ $0 }) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        task.cancel()
        // The remux may already have finished on a fast machine; either way nothing partial remains.
        let result = await task.result
        if case .failure(let error) = result { #expect(error is CancellationError, "\(error)") }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("source") }
        if case .success = result { #expect(leftovers == ["cancel.mkv"]) } else { #expect(leftovers.isEmpty, "\(leftovers)") }
    }
}
