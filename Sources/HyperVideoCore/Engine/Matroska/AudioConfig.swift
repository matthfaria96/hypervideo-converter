import CoreAudioTypes
import Foundation

/// Decoder configuration blobs Matroska wants in CodecPrivate, pulled out of the
/// magic cookies CoreAudio attaches to compressed audio.
enum AudioConfig {
    /// The AAC AudioSpecificConfig. CoreAudio cookies are usually an MPEG-4 ES_Descriptor
    /// (as in an `esds` box), with the config in its DecoderSpecificInfo; a short cookie
    /// that isn't one is taken to be the bare config.
    static func aacSpecificConfig(fromCookie cookie: Data) -> Data? {
        let bytes = [UInt8](cookie)
        guard bytes.first == 0x03 else { return (2...5).contains(bytes.count) ? cookie : nil }
        return decoderSpecificInfo(in: bytes)
    }

    /// Walks ES_Descriptor (0x03) → DecoderConfigDescriptor (0x04) → DecoderSpecificInfo (0x05).
    private static func decoderSpecificInfo(in bytes: [UInt8]) -> Data? {
        var index = 0
        func descriptor(_ tag: UInt8) -> Int? {
            guard index < bytes.count, bytes[index] == tag else { return nil }
            index += 1
            var length = 0
            for _ in 0..<4 {
                guard index < bytes.count else { return nil }
                let byte = bytes[index]
                index += 1
                length = length << 7 | Int(byte & 0x7F)
                if byte & 0x80 == 0 { break }
            }
            return length
        }
        guard descriptor(0x03) != nil, index + 3 <= bytes.count else { return nil }
        let flags = bytes[index + 2]
        index += 3
        if flags & 0x80 != 0 { index += 2 }                                   // dependsOn_ES_ID
        if flags & 0x40 != 0, index < bytes.count { index += 1 + Int(bytes[index]) } // URL
        if flags & 0x20 != 0 { index += 2 }                                   // OCR_ES_ID
        guard descriptor(0x04) != nil else { return nil }
        index += 13                                                           // object type … avg bitrate
        guard let length = descriptor(0x05), length > 0, index + length <= bytes.count else { return nil }
        return Data(bytes[index..<index + length])
    }

    /// A two-byte AAC-LC config built from the stream format, for when there's no usable cookie.
    static func aacLCConfig(_ asbd: AudioStreamBasicDescription) -> Data {
        let rates: [Double] = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]
        let rateIndex = UInt16(rates.firstIndex(of: asbd.mSampleRate) ?? 3)
        let channels = UInt16(min(asbd.mChannelsPerFrame == 8 ? 7 : asbd.mChannelsPerFrame, 7))
        let value: UInt16 = 2 << 11 | rateIndex << 7 | channels << 3
        return Data([UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// The 24-byte ALACSpecificConfig. CoreAudio may wrap it in `frma` and `alac`
    /// atoms (the latter adding a 4-byte version); a bare 24-byte cookie is the config.
    static func alacSpecificConfig(fromCookie cookie: Data) -> Data? {
        let bytes = [UInt8](cookie)
        if bytes.count == 24 { return cookie }
        let tag: [UInt8] = Array("alac".utf8)
        var index = 4
        while index + 4 <= bytes.count {
            if Array(bytes[index..<index + 4]) == tag {
                let size = Int(bytes[index - 4]) << 24 | Int(bytes[index - 3]) << 16 | Int(bytes[index - 2]) << 8 | Int(bytes[index - 1])
                let start = index + 8
                if size == 36, start + 24 <= bytes.count { return Data(bytes[start..<start + 24]) }
            }
            index += 1
        }
        return nil
    }
}
