import AudioToolbox
import AVFoundation
import CoreMedia
import Testing
@testable import HyperVideoCore

@Suite("Audio parity")
struct AudioParityTests {
    private let aac = AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 160)

    @Test func defaultDictionariesUnchanged() {
        let reader = OutputSettingsBuilder.audioReaderPCM(channels: 2)
        #expect(reader[AVSampleRateKey] as? Int == 48_000)
        let writer = OutputSettingsBuilder.audioWriter(encoding: aac, channels: 2)
        #expect(writer[AVSampleRateKey] as? Int == 48_000)
        #expect(writer[AVFormatIDKey] as? UInt32 == kAudioFormatMPEG4AAC)
        #expect(writer[AVEncoderBitRateKey] as? Int == 160_000)
    }

    @Test func heAACAndSampleRates() {
        let he = AudioEncoding(codec: .heAAC, mixdown: .stereo, bitrateKbps: 64)
        let writer = OutputSettingsBuilder.audioWriter(encoding: he, channels: 2, sampleRate: 44_100)
        #expect(writer[AVFormatIDKey] as? UInt32 == kAudioFormatMPEG4AAC_HE)
        #expect(writer[AVSampleRateKey] as? Int == 44_100)
        let reader = OutputSettingsBuilder.audioReaderPCM(channels: 8, sampleRate: 22_050)
        #expect(reader[AVNumberOfChannelsKey] as? Int == 8)
        #expect(reader[AVSampleRateKey] as? Int == 22_050)
    }

    @Test func layoutAndBitrates() {
        let data = OutputSettingsBuilder.channelLayoutData(channels: 8)
        let tag = data.withUnsafeBytes { $0.load(as: AudioChannelLayout.self).mChannelLayoutTag }
        #expect(tag == kAudioChannelLayoutTag_MPEG_7_1_B)
        #expect(OutputSettingsBuilder.clampedAACBitrate(160, channels: 2) == 160)
        #expect(OutputSettingsBuilder.clampedAACBitrate(320, channels: 2, sampleRate: 8_000) <= 96)
        #expect(OutputSettingsBuilder.clampedAACBitrate(640, channels: 8) == 640)
    }

    // MARK: Planner

    private func sources(_ languages: [String?]) -> [AudioSourceTrack] {
        languages.enumerated().map { AudioSourceTrack(id: $0.offset + 1, language: $0.element) }
    }

    @Test func defaultPlan() {
        let jobs = AudioTrackPlanner.plan(sources: sources(["eng", "por"]), settings: EncodeSettings())
        #expect(jobs == [AudioJob(sourceTrackID: 1, encoding: EncodeSettings().audioEncodings[0], label: "audio0.0")])
    }

    @Test func noAudioOverridesExplicitList() {
        var settings = EncodeSettings()
        settings.audioOptions.tracks = [AudioTrackSetting(sourceTrackID: 1, encoding: aac)]
        #expect(AudioTrackPlanner.plan(sources: sources(["eng"]), settings: settings).count == 1)
        var noCodec = settings
        noCodec.audioCodec = .none
        #expect(AudioTrackPlanner.plan(sources: sources(["eng"]), settings: noCodec).isEmpty)
        var noTracks = settings
        noTracks.audioTracks = .none
        #expect(AudioTrackPlanner.plan(sources: sources(["eng"]), settings: noTracks).isEmpty)
    }

    @Test func languageSelection() {
        var settings = EncodeSettings()
        settings.audioTracks = .all
        settings.audioOptions.languages = ["por", "spa"]
        let src = sources(["eng", "por", "spa"])
        #expect(AudioTrackPlanner.plan(sources: src, settings: settings).map(\.sourceTrackID) == [2, 3])
        settings.audioOptions.languages = ["fra"]
        #expect(AudioTrackPlanner.plan(sources: src, settings: settings).map(\.sourceTrackID) == [1])
        settings.audioTracks = .none
        #expect(AudioTrackPlanner.plan(sources: src, settings: settings).isEmpty)
    }

    @Test func extraVersionLimits() {
        var settings = EncodeSettings()
        settings.audioTracks = .all
        settings.extraAudio = AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 128)
        let src = sources(["eng", "por"])
        #expect(AudioTrackPlanner.plan(sources: src, settings: settings).count == 4)
        settings.audioOptions.extraFirstTrackOnly = true
        #expect(AudioTrackPlanner.plan(sources: src, settings: settings).map(\.label) == ["audio0.0", "audio0.1", "audio1.0"])
    }

    @Test func explicitList() {
        var settings = EncodeSettings()
        let alac = AudioEncoding(codec: .alac, mixdown: .stereo, bitrateKbps: 160)
        let mono = AudioEncoding(codec: .aac, mixdown: .mono, bitrateKbps: 96)
        let none = AudioEncoding(codec: .none, mixdown: .stereo, bitrateKbps: 96)
        settings.audioOptions.tracks = [
            AudioTrackSetting(sourceTrackID: 2, encoding: alac),
            AudioTrackSetting(sourceTrackID: 9, encoding: mono),
            AudioTrackSetting(sourceTrackID: 1, encoding: none),
            AudioTrackSetting(sourceTrackID: 1, encoding: mono)
        ]
        settings.audioOptions.languages = ["xxx"]
        let jobs = AudioTrackPlanner.plan(sources: sources(["eng", "por"]), settings: settings)
        #expect(jobs.map(\.sourceTrackID) == [2, 1])
        #expect(jobs.map(\.encoding) == [alac, mono])
        #expect(jobs.map(\.label) == ["audio0.0", "audio1.0"])
    }

    @Test func autoPassthruRules() {
        let all = Set(PassthruCodec.allCases)
        #expect(AutoPassthru.copies(formatID: kAudioFormatMPEG4AAC, allowed: all, container: .mp4))
        #expect(!AutoPassthru.copies(formatID: kAudioFormatMPEG4AAC, allowed: [], container: .mp4))
        #expect(!AutoPassthru.copies(formatID: kAudioFormatAppleLossless, allowed: all, container: .mp4))
        #expect(AutoPassthru.copies(formatID: kAudioFormatAppleLossless, allowed: all, container: .mov))
        #expect(!AutoPassthru.copies(formatID: kAudioFormatOpus, allowed: all, container: .mkv))
        #expect(!AutoPassthru.copies(formatID: kAudioFormatLinearPCM, allowed: all, container: .mov))
    }

    @Test func fallbackEncoding() {
        let base = AudioEncoding(codec: .autoPassthru, mixdown: .surround51, bitrateKbps: 192,
                                 sampleRate: .hz44100, gainDb: 3, trackName: "x")
        let alac = AutoPassthru.fallbackEncoding(for: base, fallback: .alac, container: .mp4)
        #expect(alac.codec == .aac)
        #expect(AutoPassthru.fallbackEncoding(for: base, fallback: .alac, container: .mov).codec == .alac)
        #expect(AutoPassthru.fallbackEncoding(for: base, fallback: .heAAC, container: .mp4).codec == .heAAC)
        for fb in [AudioCodec.passthrough, .autoPassthru, .none] {
            #expect(AutoPassthru.fallbackEncoding(for: base, fallback: fb, container: .mov).codec == .aac)
        }
        #expect(alac.mixdown == .surround51 && alac.bitrateKbps == 192 && alac.sampleRate == .hz44100)
        #expect(alac.gainDb == 3 && alac.trackName == "x")
    }

    // MARK: Gain

    @Test func gainMath() {
        #expect(abs(AudioGain.factor(db: 6) - 1.995) < 0.01)
        #expect(abs(AudioGain.factor(db: -6) - 0.501) < 0.01)
        #expect(AudioGain.factor(db: 40) == AudioGain.factor(db: 20))
        #expect(AudioGain.scaled([0.5, -0.9], factor: 2) == [1.0, -1.0])
        #expect(AudioGain.transform(gainDb: 0) == nil)
    }

    @Test func gainOnSampleBuffer() throws {
        let frames = 1024
        let samples = (0..<(frames * 2)).map { Float($0 % 10) / 20 }
        let buffer = try Self.makeBuffer(samples, frames: frames)
        let scaled = try #require(AudioGain.apply(buffer, factor: 0.5))
        #expect(CMSampleBufferGetNumSamples(scaled) == frames)
        #expect(CMSampleBufferGetPresentationTimeStamp(scaled) == CMTime(value: 480, timescale: 48_000))
        let block = try #require(CMSampleBufferGetDataBuffer(scaled))
        var out = [Float](repeating: 0, count: samples.count)
        let status = out.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        }
        #expect(status == noErr)
        #expect(zip(out, samples).allSatisfy { abs($0 - $1 * 0.5) < 1e-6 })
    }

    @Test func gainRejectsOtherPCMLayouts() throws {
        let frames = 1024
        let samples = [Float](repeating: 0.25, count: frames * 2)
        let integer = try Self.makeBuffer(samples, frames: frames, flags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked)
        #expect(AudioGain.apply(integer, factor: 0.5) == nil)
        let short = try Self.makeBuffer(samples, frames: frames * 2)
        #expect(AudioGain.apply(short, factor: 0.5) == nil)
        let transform = try #require(AudioGain.transform(gainDb: 6))
        #expect(throws: TranscodeError.self) { try transform(integer) }
    }

    static func makeBuffer(
        _ samples: [Float], frames: Int, flags: AudioFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
    ) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format)
        try #require(formatStatus == noErr)
        var block: CMBlockBuffer?
        let size = samples.count * 4
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: size, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        try #require(blockStatus == noErr)
        let dataBlock = try #require(block)
        let fill = samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: dataBlock,
                                          offsetIntoDestination: 0, dataLength: size)
        }
        try #require(fill == noErr)
        var sample: CMSampleBuffer?
        let sampleStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: dataBlock, formatDescription: try #require(format), sampleCount: frames,
            presentationTimeStamp: CMTime(value: 480, timescale: 48_000), packetDescriptions: nil,
            sampleBufferOut: &sample)
        try #require(sampleStatus == noErr)
        return try #require(sample)
    }
}
