import Foundation
@testable import HyperVideoCore

/// A small independent EBML/Matroska parser for checking the muxer's output.
/// It walks the whole file, failing on any element whose size overruns its parent.
struct MatroskaReader {
    struct ParseError: Error, CustomStringConvertible { let description: String }

    struct Element {
        let id: UInt32
        let offset: Int
        let dataStart: Int
        let size: Int
        var children: [Element] = []

        func child(_ id: UInt32) -> Element? { children.first { $0.id == id } }
        func all(_ id: UInt32) -> [Element] { children.filter { $0.id == id } }
    }

    struct Track {
        var number: Int, type: Int, codecID: String
        var language: String?, languageBCP47: String?, isDefault: Bool
        var codecPrivate: Data?
        var codecDelay: UInt64 = 0
        var pixelSize: [Int]?, displaySize: [Int]?
        var roll: Double?
        var sampleRate: Double?, channels: Int?
    }

    struct Block {
        var track: Int, time: Int64, isKeyframe: Bool, size: Int, duration: Int64?, payload: Data
    }

    let data: [UInt8]
    let top: [Element]

    init(url: URL) throws {
        data = [UInt8](try Data(contentsOf: url))
        top = try Self.parse(data, from: 0, to: data.count)
    }

    static let masters: Set<UInt32> = [
        EBML.ID.ebml, EBML.ID.segment, EBML.ID.seekHead, EBML.ID.seek, EBML.ID.info, EBML.ID.tracks, EBML.ID.trackEntry,
        EBML.ID.video, EBML.ID.audio, EBML.ID.projection, EBML.ID.cluster, EBML.ID.blockGroup, EBML.ID.cues,
        EBML.ID.cuePoint, EBML.ID.cueTrackPositions, EBML.ID.chapters, EBML.ID.editionEntry, EBML.ID.chapterAtom,
        EBML.ID.chapterDisplay, EBML.ID.tags, EBML.ID.tag, EBML.ID.targets, EBML.ID.simpleTag
    ]

    /// Reads a variable-length size or ID; returns (value with or without marker, length).
    static func vint(_ bytes: [UInt8], at index: Int, keepMarker: Bool) throws -> (UInt64, Int) {
        guard index < bytes.count, bytes[index] != 0 else { throw ParseError(description: "bad vint at \(index)") }
        let length = bytes[index].leadingZeroBitCount + 1
        guard index + length <= bytes.count else { throw ParseError(description: "vint past end at \(index)") }
        var value: UInt64 = keepMarker ? UInt64(bytes[index]) : UInt64(bytes[index] & (0xFF >> length))
        for i in 1..<length { value = value << 8 | UInt64(bytes[index + i]) }
        return (value, length)
    }

    static func parse(_ bytes: [UInt8], from start: Int, to end: Int) throws -> [Element] {
        var elements: [Element] = []
        var index = start
        while index < end {
            let (id, idLength) = try vint(bytes, at: index, keepMarker: true)
            let (size, sizeLength) = try vint(bytes, at: index + idLength, keepMarker: false)
            let dataStart = index + idLength + sizeLength
            guard dataStart + Int(size) <= end else {
                throw ParseError(description: String(format: "element 0x%X at %d overruns its parent", id, index))
            }
            var element = Element(id: UInt32(id), offset: index, dataStart: dataStart, size: Int(size))
            if masters.contains(element.id) {
                element.children = try parse(bytes, from: dataStart, to: dataStart + Int(size))
            }
            elements.append(element)
            index = dataStart + Int(size)
        }
        return elements
    }

    func bytes(_ element: Element) -> [UInt8] { Array(data[element.dataStart..<element.dataStart + element.size]) }
    func uint(_ element: Element?) -> UInt64? { element.map { bytes($0).reduce(0) { $0 << 8 | UInt64($1) } } }
    func string(_ element: Element?) -> String? { element.map { String(decoding: bytes($0), as: UTF8.self) } }
    func float(_ element: Element?) -> Double? {
        guard let element else { return nil }
        let raw = bytes(element).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return element.size == 4 ? Double(Float(bitPattern: UInt32(raw))) : Double(bitPattern: raw)
    }

    var header: Element? { top.first { $0.id == EBML.ID.ebml } }
    var segment: Element? { top.first { $0.id == EBML.ID.segment } }
    var docType: String? { string(header?.child(EBML.ID.docType)) }

    /// Duration in milliseconds.
    var duration: Double? { float(segment?.child(EBML.ID.info)?.child(EBML.ID.duration)) }

    /// Info/Title.
    var title: String? { string(segment?.child(EBML.ID.info)?.child(EBML.ID.title)) }

    /// Every SimpleTag in the Tags element, by name.
    var tagValues: [String: String] {
        var result: [String: String] = [:]
        for tag in segment?.child(EBML.ID.tags)?.all(EBML.ID.tag) ?? [] {
            for simple in tag.all(EBML.ID.simpleTag) {
                if let name = string(simple.child(EBML.ID.tagName)), let value = string(simple.child(EBML.ID.tagString)) {
                    result[name] = value
                }
            }
        }
        return result
    }

    var tracks: [Track] {
        (segment?.child(EBML.ID.tracks)?.all(EBML.ID.trackEntry) ?? []).map { entry in
            let video = entry.child(EBML.ID.video), audio = entry.child(EBML.ID.audio)
            var track = Track(
                number: Int(uint(entry.child(EBML.ID.trackNumber)) ?? 0), type: Int(uint(entry.child(EBML.ID.trackType)) ?? 0),
                codecID: string(entry.child(EBML.ID.codecID)) ?? "",
                language: string(entry.child(EBML.ID.language)), languageBCP47: string(entry.child(EBML.ID.languageBCP47)),
                isDefault: (uint(entry.child(EBML.ID.flagDefault)) ?? 1) == 1,
                codecPrivate: entry.child(EBML.ID.codecPrivate).map { Data(bytes($0)) }
            )
            track.codecDelay = uint(entry.child(EBML.ID.codecDelay)) ?? 0
            if let video {
                track.pixelSize = [Int(uint(video.child(EBML.ID.pixelWidth)) ?? 0), Int(uint(video.child(EBML.ID.pixelHeight)) ?? 0)]
                track.displaySize = [Int(uint(video.child(EBML.ID.displayWidth)) ?? 0), Int(uint(video.child(EBML.ID.displayHeight)) ?? 0)]
                track.roll = float(video.child(EBML.ID.projection)?.child(EBML.ID.projectionPoseRoll))
            }
            if let audio {
                track.sampleRate = float(audio.child(EBML.ID.samplingFrequency))
                track.channels = uint(audio.child(EBML.ID.channels)).map(Int.init)
            }
            return track
        }
    }

    var clusters: [Element] { segment?.all(EBML.ID.cluster) ?? [] }

    var blocks: [Block] {
        clusters.flatMap { cluster -> [Block] in
            let base = Int64(uint(cluster.child(EBML.ID.timestamp)) ?? 0)
            return cluster.children.compactMap { child -> Block? in
                switch child.id {
                case EBML.ID.simpleBlock: return block(child, base: base, duration: nil)
                case EBML.ID.blockGroup:
                    guard let inner = child.child(EBML.ID.block) else { return nil }
                    return block(inner, base: base, duration: uint(child.child(EBML.ID.blockDuration)).map(Int64.init))
                default: return nil
                }
            }
        }
    }

    private func block(_ element: Element, base: Int64, duration: Int64?) -> Block? {
        let raw = bytes(element)
        guard let (track, length) = try? Self.vint(raw, at: 0, keepMarker: false), raw.count >= length + 3 else { return nil }
        let relative = Int16(bitPattern: UInt16(raw[length]) << 8 | UInt16(raw[length + 1]))
        let flags = raw[length + 2]
        let payload = Data(raw[(length + 3)...])
        return Block(track: Int(track), time: base + Int64(relative), isKeyframe: flags & 0x80 != 0,
                     size: payload.count, duration: duration, payload: payload)
    }

    /// (time ms, cluster offset from segment data) per cue point.
    var cues: [(UInt64, UInt64)] {
        (segment?.child(EBML.ID.cues)?.all(EBML.ID.cuePoint) ?? []).map { point in
            (uint(point.child(EBML.ID.cueTime)) ?? 0,
             uint(point.child(EBML.ID.cueTrackPositions)?.child(EBML.ID.cueClusterPosition)) ?? 0)
        }
    }

    /// SeekHead entries as (target ID, absolute offset).
    var seeks: [(UInt32, Int)] {
        guard let segment else { return [] }
        return (segment.child(EBML.ID.seekHead)?.all(EBML.ID.seek) ?? []).map { seek in
            (UInt32(uint(seek.child(EBML.ID.seekID)) ?? 0), segment.dataStart + Int(uint(seek.child(EBML.ID.seekPosition)) ?? 0))
        }
    }

    /// (title, start ns, end ns) per chapter.
    var chapters: [(String, UInt64, UInt64)] {
        let atoms = segment?.child(EBML.ID.chapters)?.child(EBML.ID.editionEntry)?.all(EBML.ID.chapterAtom) ?? []
        return atoms.map {
            (string($0.child(EBML.ID.chapterDisplay)?.child(EBML.ID.chapString)) ?? "",
             uint($0.child(EBML.ID.chapterTimeStart)) ?? 0, uint($0.child(EBML.ID.chapterTimeEnd)) ?? 0)
        }
    }

    /// The element starting at `offset` anywhere in the segment's top level.
    func segmentChild(at offset: Int) -> Element? {
        segment?.children.first { $0.offset == offset }
    }
}
