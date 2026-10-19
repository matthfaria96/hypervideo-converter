import Foundation

/// Encoding of EBML, the binary format Matroska is built on: every element is an ID,
/// a variable-length size and a payload. Everything here is pure and returns new bytes.
enum EBML {
    /// The size value whose bytes are all ones means "unknown size", so each width
    /// holds one value fewer than its bits allow.
    static func sizeLength(_ value: UInt64) -> Int {
        var length = 1
        while length < 8 && value >= (UInt64(1) << (7 * UInt64(length))) - 1 { length += 1 }
        return length
    }

    /// A variable-length size: a leading marker bit tells the reader how many bytes follow.
    /// `width` forces a wider encoding, used for sizes that are patched later.
    static func size(_ value: UInt64, width: Int? = nil) -> Data {
        let length = width ?? sizeLength(value)
        precondition((1...8).contains(length), "EBML sizes are 1 to 8 bytes")
        let marked = value | (UInt64(1) << (7 * UInt64(length)))
        return Data((0..<length).reversed().map { UInt8(truncatingIfNeeded: marked >> (8 * UInt64($0))) })
    }

    /// Element IDs keep their marker bits, so they're written as their minimal big-endian bytes.
    static func id(_ id: UInt32) -> Data {
        let length = id > 0xFF_FFFF ? 4 : id > 0xFFFF ? 3 : id > 0xFF ? 2 : 1
        return Data((0..<length).reversed().map { UInt8(truncatingIfNeeded: id >> (8 * UInt32($0))) })
    }

    static func element(_ elementID: UInt32, _ payload: Data) -> Data {
        id(elementID) + size(UInt64(payload.count)) + payload
    }

    static func master(_ elementID: UInt32, _ children: [Data]) -> Data {
        element(elementID, children.reduce(Data(), +))
    }

    /// Big-endian unsigned integer in as few bytes as possible (at least one),
    /// or exactly `width` bytes when it must keep its size for patching.
    static func uintBytes(_ value: UInt64, width: Int? = nil) -> Data {
        var length = 1
        while length < 8 && value >> (8 * UInt64(length)) != 0 { length += 1 }
        let count = width ?? length
        return Data((0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) })
    }

    /// Big-endian two's complement in as few bytes as hold the sign.
    static func intBytes(_ value: Int64) -> Data {
        var length = 1
        while length < 8 {
            let bits = Int64(8 * length)
            let low = -(Int64(1) << (bits - 1)), high = (Int64(1) << (bits - 1)) - 1
            if value >= low && value <= high { break }
            length += 1
        }
        let raw = UInt64(bitPattern: value)
        return Data((0..<length).reversed().map { UInt8(truncatingIfNeeded: raw >> (8 * UInt64($0))) })
    }

    static func floatBytes(_ value: Double) -> Data {
        uintBytes(value.bitPattern, width: 8)
    }

    static func uint(_ elementID: UInt32, _ value: UInt64) -> Data { element(elementID, uintBytes(value)) }
    static func int(_ elementID: UInt32, _ value: Int64) -> Data { element(elementID, intBytes(value)) }
    static func float(_ elementID: UInt32, _ value: Double) -> Data { element(elementID, floatBytes(value)) }
    static func string(_ elementID: UInt32, _ value: String) -> Data { element(elementID, Data(value.utf8)) }

    /// A Void element filling exactly `count` bytes (at least 2), for reserved space.
    static func void(filling count: Int) -> Data {
        precondition(count >= 2, "a Void element needs at least two bytes")
        // One size byte holds up to 126; past that, use a fixed 8-byte size.
        let width = count - 2 <= 126 ? 1 : 8
        let payload = count - 1 - width
        return id(ID.void) + size(UInt64(payload), width: width) + Data(count: payload)
    }
}

/// Matroska element IDs used by the muxer (and the test reader).
extension EBML {
    enum ID {
        static let ebml: UInt32 = 0x1A45DFA3
        static let ebmlVersion: UInt32 = 0x4286
        static let ebmlReadVersion: UInt32 = 0x42F7
        static let ebmlMaxIDLength: UInt32 = 0x42F2
        static let ebmlMaxSizeLength: UInt32 = 0x42F3
        static let docType: UInt32 = 0x4282
        static let docTypeVersion: UInt32 = 0x4287
        static let docTypeReadVersion: UInt32 = 0x4285
        static let void: UInt32 = 0xEC

        static let segment: UInt32 = 0x18538067
        static let seekHead: UInt32 = 0x114D9B74
        static let seek: UInt32 = 0x4DBB
        static let seekID: UInt32 = 0x53AB
        static let seekPosition: UInt32 = 0x53AC

        static let info: UInt32 = 0x1549A966
        static let timestampScale: UInt32 = 0x2AD7B1
        static let duration: UInt32 = 0x4489
        static let title: UInt32 = 0x7BA9
        static let muxingApp: UInt32 = 0x4D80
        static let writingApp: UInt32 = 0x5741
        static let segmentUUID: UInt32 = 0x73A4

        static let tracks: UInt32 = 0x1654AE6B
        static let trackEntry: UInt32 = 0xAE
        static let trackNumber: UInt32 = 0xD7
        static let trackUID: UInt32 = 0x73C5
        static let trackType: UInt32 = 0x83
        static let flagDefault: UInt32 = 0x88
        static let flagForced: UInt32 = 0x55AA
        static let flagLacing: UInt32 = 0x9C
        static let defaultDuration: UInt32 = 0x23E383
        static let language: UInt32 = 0x22B59C
        static let languageBCP47: UInt32 = 0x22B59D
        static let codecID: UInt32 = 0x86
        static let codecPrivate: UInt32 = 0x63A2
        static let codecDelay: UInt32 = 0x56AA
        static let video: UInt32 = 0xE0
        static let pixelWidth: UInt32 = 0xB0
        static let pixelHeight: UInt32 = 0xBA
        static let displayWidth: UInt32 = 0x54B0
        static let displayHeight: UInt32 = 0x54BA
        static let projection: UInt32 = 0x7670
        static let projectionType: UInt32 = 0x7671
        static let projectionPoseRoll: UInt32 = 0x7675
        static let audio: UInt32 = 0xE1
        static let samplingFrequency: UInt32 = 0xB5
        static let channels: UInt32 = 0x9F
        static let bitDepth: UInt32 = 0x6264

        static let cluster: UInt32 = 0x1F43B675
        static let timestamp: UInt32 = 0xE7
        static let simpleBlock: UInt32 = 0xA3
        static let blockGroup: UInt32 = 0xA0
        static let block: UInt32 = 0xA1
        static let blockDuration: UInt32 = 0x9B

        static let cues: UInt32 = 0x1C53BB6B
        static let cuePoint: UInt32 = 0xBB
        static let cueTime: UInt32 = 0xB3
        static let cueTrackPositions: UInt32 = 0xB7
        static let cueTrack: UInt32 = 0xF7
        static let cueClusterPosition: UInt32 = 0xF1

        static let tags: UInt32 = 0x1254C367
        static let tag: UInt32 = 0x7373
        static let targets: UInt32 = 0x63C0
        static let targetTypeValue: UInt32 = 0x68CA
        static let simpleTag: UInt32 = 0x67C8
        static let tagName: UInt32 = 0x45A3
        static let tagString: UInt32 = 0x4487

        static let chapters: UInt32 = 0x1043A770
        static let editionEntry: UInt32 = 0x45B9
        static let editionUID: UInt32 = 0x45BC
        static let editionFlagDefault: UInt32 = 0x45DB
        static let chapterAtom: UInt32 = 0xB6
        static let chapterUID: UInt32 = 0x73C4
        static let chapterTimeStart: UInt32 = 0x91
        static let chapterTimeEnd: UInt32 = 0x92
        static let chapterDisplay: UInt32 = 0x80
        static let chapString: UInt32 = 0x85
        static let chapLanguage: UInt32 = 0x437C
    }
}
