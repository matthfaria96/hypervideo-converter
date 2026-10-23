@preconcurrency import AVFoundation
import AudioToolbox
import Testing
@testable import HyperVideoCore

@Suite("Audio parity transcodes", .serialized)
struct AudioParityTranscodeTests {
    private func convert(
        _ audio: [StressClip.Audio], container: ContainerFormat = .mov, seconds: Double = 1,
        configure: (inout EncodeSettings) -> Void
    ) async throws -> URL {
        let dir = try TranscodeIntegrationTests.tempDir()
        var spec = StressClip.Spec()
        spec.audio = audio
        spec.seconds = seconds
        let source = try await StressClip.make(in: dir, spec)
        var settings = EncodeSettings()
        settings.container = container
        configure(&settings)
        let out = dir.appendingPathComponent("out.\(container.fileExtension)")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        return out
    }

    private func formatIDs(of url: URL) async throws -> [UInt32] {
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        var ids: [UInt32] = []
        for track in tracks {
            let formats = try await track.load(.formatDescriptions)
            let asbd = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
            ids.append(asbd?.mFormatID ?? 0)
        }
        return ids
    }

    private func formatListIDs(of url: URL) async throws -> [UInt32] {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        var size = 0
        guard let items = CMAudioFormatDescriptionGetFormatList(format, sizeOut: &size) else { return [] }
        let list = Array(UnsafeBufferPointer(start: items, count: size / MemoryLayout<AudioFormatListItem>.size))
        return list.map(\.mASBD.mFormatID)
    }

    private func rms(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: OutputSettingsBuilder.audioReaderPCM(channels: 2))
        reader.add(output)
        reader.startReading()
        var sum = 0.0
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var data = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / 4)
            _ = data.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            }
            for value in data { sum += Double(value * value) }
            count += data.count
        }
        return count == 0 ? 0 : (sum / Double(count)).squareRoot()
    }

    @Test func defaultsUnchanged() async throws {
        let out = try await convert([.init(), .init()]) { _ in }
        let info = try await MediaInspector.inspect(out)
        #expect(info.audioTracks.count == 1)
        #expect(info.audioTracks.first?.channels == 2)
        #expect(info.audioTracks.first?.sampleRate == 48_000)
        #expect(try await formatIDs(of: out) == [kAudioFormatMPEG4AAC])
    }

    @Test func languageSelection() async throws {
        let audio = [StressClip.Audio(language: "eng"), .init(language: "por"), .init(language: "spa")]
        let out = try await convert(audio) {
            $0.audioTracks = .all
            $0.audioOptions.languages = ["por", "spa"]
        }
        let info = try await MediaInspector.inspect(out)
        #expect(info.audioTracks.compactMap { $0.language.flatMap(LanguageFilter.normalized) } == ["por", "spa"])
    }

    @Test func languageSelectionUsesISOCode() async throws {
        let audio = [StressClip.Audio(languageCode: "eng"), .init(languageCode: "fra")]
        let out = try await convert(audio) {
            $0.audioTracks = .all
            $0.audioOptions.languages = ["fra"]
        }
        let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        #expect(tracks.count == 1)
        let code = try await tracks.first?.load(.languageCode)
        #expect(code == "fra")
    }

    @Test func explicitList() async throws {
        let out = try await convert([.init(), .init()]) {
            $0.audioOptions.tracks = [
                AudioTrackSetting(sourceTrackID: 3, encoding: AudioEncoding(codec: .aac, mixdown: .mono, bitrateKbps: 96)),
                AudioTrackSetting(sourceTrackID: 2, encoding: AudioEncoding(codec: .alac, mixdown: .stereo, bitrateKbps: 160))
            ]
        }
        let info = try await MediaInspector.inspect(out)
        #expect(info.audioTracks.map(\.channels) == [1, 2])
        #expect(try await formatIDs(of: out) == [kAudioFormatMPEG4AAC, kAudioFormatAppleLossless])
    }

    @Test(arguments: [(AudioSampleRate.hz44100, 48_000, 44_100.0), (.hz22050, 48_000, 22_050), (.auto, 32_000, 32_000)])
    func sampleRates(rate: AudioSampleRate, source: Int, expected: Double) async throws {
        let out = try await convert([.init(sampleRate: source)]) { $0.audioOptions.sampleRate = rate }
        #expect(try await MediaInspector.inspect(out).audioTracks.first?.sampleRate == expected)
    }

    @Test(arguments: [(8, 8), (6, 6)])
    func surround71(sourceChannels: Int, expected: Int) async throws {
        let out = try await convert([.init(channels: sourceChannels)]) { $0.audioMixdown = .surround71 }
        #expect(try await MediaInspector.inspect(out).audioTracks.first?.channels == expected)
    }

    @Test func heAAC() async throws {
        let out = try await convert([.init()]) {
            $0.audioCodec = .heAAC
            $0.audioBitrateKbps = 64
            $0.audioOptions.sampleRate = .hz44100
        }
        // MOV reports the AAC base format; the SBR extension shows in the cookie's format list.
        let ids = try await formatIDs(of: out)
        #expect(ids == [kAudioFormatMPEG4AAC])
        let list = try await formatListIDs(of: out)
        #expect(list.contains(kAudioFormatMPEG4AAC_HE), "list \(list)")
    }

    @Test func autoPassthru() async throws {
        let copied = try await convert([.init(sampleRate: 44_100)], container: .mp4) { $0.audioCodec = .autoPassthru }
        #expect(try await MediaInspector.inspect(copied).audioTracks.first?.sampleRate == 44_100)
        let encoded = try await convert([.init(sampleRate: 44_100)], container: .mp4) {
            $0.audioCodec = .autoPassthru
            $0.audioOptions.allowedPassthru = []
        }
        #expect(try await MediaInspector.inspect(encoded).audioTracks.first?.sampleRate == 48_000)
        let lossless = try await convert([.init()], container: .mov) {
            $0.audioCodec = .autoPassthru
            $0.audioOptions.allowedPassthru = []
            $0.audioOptions.fallback = .alac
        }
        #expect(try await formatIDs(of: lossless) == [kAudioFormatAppleLossless])
    }

    @Test func passthruOnlyCopiesJustThatCodec() async throws {
        let copied = try await convert([.init(sampleRate: 44_100)], container: .mp4) {
            $0.audioCodec = .autoPassthru
            $0.audioOptions.passthruOnly = .aac
        }
        #expect(try await MediaInspector.inspect(copied).audioTracks.first?.sampleRate == 44_100)
        let fallback = try await convert([.init(sampleRate: 44_100)], container: .mp4) {
            $0.audioCodec = .autoPassthru
            $0.audioOptions.passthruOnly = .ac3
        }
        #expect(try await MediaInspector.inspect(fallback).audioTracks.first?.sampleRate == 48_000)
    }

    @Test(arguments: [(6.0, 1.85, 2.15), (-6.0, 0.45, 0.55)])
    func gain(db: Double, low: Double, high: Double) async throws {
        let base = try await rms(of: convert([.init()]) { _ in })
        let gained = try await rms(of: convert([.init()]) { $0.audioOptions.gainDb = db })
        let ratio = gained / max(base, 1e-9)
        #expect(base > 0)
        #expect(ratio > low && ratio < high)
    }

    @Test func names() async throws {
        let named = try await convert([.init()]) { $0.audioOptions.trackName = "Commentary" }
        let track = try #require(try await AVURLAsset(url: named).loadTracks(withMediaType: .audio).first)
        #expect(await TrackNames.name(of: track) == "Commentary")
        let auto = try await convert([.init()]) { $0.audioOptions.automaticNaming = true }
        let autoTrack = try #require(try await AVURLAsset(url: auto).loadTracks(withMediaType: .audio).first)
        #expect(await TrackNames.name(of: autoTrack) == "Stereo")
    }

    @Test func extraFirstTrackOnly() async throws {
        let extra = AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 128)
        let limited = try await convert([.init(), .init()]) {
            $0.audioTracks = .all
            $0.extraAudio = extra
            $0.audioOptions.extraFirstTrackOnly = true
        }
        #expect(try await MediaInspector.inspect(limited).audioTracks.count == 3)
        let full = try await convert([.init(), .init()]) {
            $0.audioTracks = .all
            $0.extraAudio = extra
        }
        #expect(try await MediaInspector.inspect(full).audioTracks.count == 4)
    }
}
