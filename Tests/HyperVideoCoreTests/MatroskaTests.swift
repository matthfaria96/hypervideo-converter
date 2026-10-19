import CoreAudioTypes
import Foundation
import Testing
@testable import HyperVideoCore

@Suite("EBML encoding")
struct EBMLEncodingTests {
    @Test func sizesUseTheShortestWidthAndAvoidTheUnknownMarker() {
        #expect(EBML.size(0) == Data([0x80]))
        #expect(EBML.size(126) == Data([0xFE]))
        // 127 in one byte would be all ones, which means "unknown size".
        #expect(EBML.size(127) == Data([0x40, 0x7F]))
        #expect(EBML.size(16_382) == Data([0x7F, 0xFE]))
        #expect(EBML.size(16_383) == Data([0x20, 0x3F, 0xFF]))
        #expect(EBML.size(0, width: 8) == Data([0x01, 0, 0, 0, 0, 0, 0, 0]))
        #expect(EBML.size(0x1234, width: 4) == Data([0x10, 0x00, 0x12, 0x34]))
        #expect(EBML.sizeLength((UInt64(1) << 56) - 2) == 8)
    }

    @Test func idsKeepTheirMarkerBits() {
        #expect(EBML.id(EBML.ID.simpleBlock) == Data([0xA3]))
        #expect(EBML.id(EBML.ID.ebmlVersion) == Data([0x42, 0x86]))
        #expect(EBML.id(EBML.ID.timestampScale) == Data([0x2A, 0xD7, 0xB1]))
        #expect(EBML.id(EBML.ID.segment) == Data([0x18, 0x53, 0x80, 0x67]))
    }

    @Test func integersAndFloats() {
        #expect(EBML.uintBytes(0) == Data([0x00]))
        #expect(EBML.uintBytes(255) == Data([0xFF]))
        #expect(EBML.uintBytes(256) == Data([0x01, 0x00]))
        #expect(EBML.uintBytes(5, width: 8) == Data([0, 0, 0, 0, 0, 0, 0, 5]))
        #expect(EBML.intBytes(-1) == Data([0xFF]))
        #expect(EBML.intBytes(127) == Data([0x7F]))
        #expect(EBML.intBytes(128) == Data([0x00, 0x80]))
        #expect(EBML.intBytes(-129) == Data([0xFF, 0x7F]))
        #expect(EBML.floatBytes(1) == Data([0x3F, 0xF0, 0, 0, 0, 0, 0, 0]))
        #expect(EBML.uint(EBML.ID.trackNumber, 1) == Data([0xD7, 0x81, 0x01]))
        #expect(EBML.string(EBML.ID.docType, "matroska") == Data([0x42, 0x82, 0x88]) + Data("matroska".utf8))
        #expect(EBML.master(EBML.ID.video, [EBML.uint(EBML.ID.pixelWidth, 2)]) == Data([0xE0, 0x83, 0xB0, 0x81, 0x02]))
    }

    @Test(arguments: [2, 3, 100, 128, 129, 500])
    func voidFillsExactly(count: Int) throws {
        let void = EBML.void(filling: count)
        #expect(void.count == count)
        let parsed = try MatroskaReader.parse([UInt8](void), from: 0, to: void.count)
        #expect(parsed.count == 1 && parsed[0].id == EBML.ID.void)
    }

    @Test func blocksCarryTrackTimeAndFlags() {
        let frame = MatroskaWriter.Frame(track: 2, time: 998, decodeTime: 990, isKeyframe: true, duration: nil, data: Data([9]))
        #expect(MatroskaWriter.block(frame, relativeTo: 1_000) == Data([0xA3, 0x85, 0x82, 0xFF, 0xFE, 0x80, 0x09]))
        var text = frame
        text.duration = 1_500
        let group = MatroskaWriter.block(text, relativeTo: 0)
        #expect(group.first == 0xA0)
        #expect(group.suffix(4) == Data([0x9B, 0x82, 0x05, 0xDC]))
    }

    @Test func seekHeadAlwaysFillsItsReserve() throws {
        let entries: [(UInt32, UInt64)] = [(EBML.ID.info, 160), (EBML.ID.tracks, 300), (EBML.ID.chapters, 900), (EBML.ID.cues, 1 << 40)]
        let head = MatroskaWriter.seekHead(entries, filling: MatroskaWriter.seekHeadReserve)
        #expect(head.count == MatroskaWriter.seekHeadReserve)
        let parsed = try MatroskaReader.parse([UInt8](head), from: 0, to: head.count)
        #expect(parsed.map(\.id) == [EBML.ID.seekHead, EBML.ID.void])
        #expect(parsed[0].all(EBML.ID.seek).count == 4)
    }
}

@Suite("Matroska tracks")
struct MatroskaTrackTests {
    @Test func aacConfigComesOutOfAnESDescriptorCookie() {
        // ES_Descriptor → DecoderConfigDescriptor → DecoderSpecificInfo [0x11, 0x90].
        let cookie = Data([0x03, 0x19, 0x00, 0x00, 0x00,
                           0x04, 0x11, 0x40, 0x15, 0x00, 0x00, 0x00, 0x00, 0x01, 0xF4, 0x00, 0x00, 0x01, 0xF4, 0x00,
                           0x05, 0x02, 0x11, 0x90, 0x06, 0x01, 0x02])
        #expect(AudioConfig.aacSpecificConfig(fromCookie: cookie) == Data([0x11, 0x90]))
        #expect(AudioConfig.aacSpecificConfig(fromCookie: Data([0x12, 0x10])) == Data([0x12, 0x10]))
        #expect(AudioConfig.aacSpecificConfig(fromCookie: Data([0x03, 0x01])) == nil)
    }

    @Test func aacLCConfigFromStreamFormat() {
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = 48_000
        asbd.mChannelsPerFrame = 2
        #expect(AudioConfig.aacLCConfig(asbd) == Data([0x11, 0x90]))
        asbd.mSampleRate = 44_100
        asbd.mChannelsPerFrame = 6
        #expect(AudioConfig.aacLCConfig(asbd) == Data([0x12, 0x30]))
    }

    @Test func alacConfigIsUnwrappedFromItsAtoms() {
        let config = Data((0..<24).map { UInt8($0) })
        let frma = Data([0, 0, 0, 12]) + Data("frma".utf8) + Data("alac".utf8)
        let alac = Data([0, 0, 0, 36]) + Data("alac".utf8) + Data(count: 4) + config
        #expect(AudioConfig.alacSpecificConfig(fromCookie: frma + alac + Data([0, 0, 0, 8, 0, 0, 0, 0])) == config)
        #expect(AudioConfig.alacSpecificConfig(fromCookie: config) == config)
        #expect(AudioConfig.alacSpecificConfig(fromCookie: Data(count: 10)) == nil)
    }

    @Test func rotationAndLanguages() {
        #expect(MatroskaTrack.rotation(of: .identity) == 0)
        #expect(MatroskaTrack.rotation(of: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0)) == 90)
        #expect(MatroskaTrack.rotation(of: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)) == 180)
        #expect(MatroskaTrack.rotation(of: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)) == 270)
        #expect(MatroskaTrack.legacyLanguage("pt-BR") == "por")
        #expect(MatroskaTrack.legacyLanguage(nil) == "und")
    }

    @Test func timedTextBecomesPlainText() {
        let utf8 = Array("Olá".utf8)
        #expect(MatroskaRemuxer.text(fromTimedText: Data([0, UInt8(utf8.count)] + utf8 + [0, 0, 0, 8, 0x73, 0x74, 0x79, 0x6C])) == "Olá")
        #expect(MatroskaRemuxer.text(fromTimedText: Data([0, 0])).isEmpty)
        #expect(MatroskaRemuxer.text(fromTimedText: Data([0, 9, 0x41])) == "A", "a bad length is clamped")
    }
}

@Suite("Matroska settings")
struct MatroskaSettingsTests {
    @Test func validationKeepsProResInMOVButAllowsALAC() {
        var settings = EncodeSettings()
        settings.container = .mkv
        #expect(settings.isValid)
        #expect(settings.container.fileExtension == "mkv" && settings.container.displayName == "Matroska (MKV)")
        settings.audioCodec = .alac
        #expect(settings.isValid)
        settings.videoCodec = .proRes422
        #expect(settings.validationIssues == ["Apple ProRes requires the QuickTime (MOV) container."])
        settings.videoCodec = .h264
        settings.container = .mp4
        #expect(settings.validationIssues == ["Apple Lossless audio requires the QuickTime (MOV) or Matroska (MKV) container."])
    }

    @Test func closedCaptionsStayMOVOnly() {
        #expect(SubtitleTrackInfo.Kind.subtitle.isSupported(in: .mkv))
        #expect(!SubtitleTrackInfo.Kind.closedCaption.isSupported(in: .mkv))
    }

    @Test func settingsRoundTripWithMKV() throws {
        var settings = EncodeSettings()
        settings.container = .mkv
        let decoded = try JSONDecoder().decode(EncodeSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.container == .mkv)
    }
}
