import Foundation

/// Streams a Matroska file to disk. Headers go first with room reserved for the
/// SeekHead and placeholders for the segment size and duration; clusters are written
/// as they fill up (each held in memory only until it closes); `finish` appends the
/// cues and patches the reserved spots, so the result is fully seekable.
final class MatroskaWriter {
    struct Frame {
        var track: Int
        /// Presentation time in milliseconds (the file's timestamp scale).
        var time: Int64
        /// Decode time in milliseconds, which orders blocks and anchors clusters.
        var decodeTime: Int64
        var isKeyframe: Bool
        /// Set for subtitles, which need an explicit duration.
        var duration: Int64?
        var data: Data
    }

    struct Chapter: Equatable {
        var title: String
        var startNs: UInt64
        var endNs: UInt64
    }

    static let timestampScale: UInt64 = 1_000_000
    /// Longest span a cluster covers before a new one starts, even without a keyframe.
    static let maxClusterSpan: Int64 = 5_000
    static let maxClusterBytes = 16 << 20
    /// Room kept for the SeekHead in front of Info; four entries need well under this.
    static let seekHeadReserve = 160

    private let handle: FileHandle
    private let cueTrack: Int?
    private var offset: UInt64 = 0
    private var segmentSizeOffset: UInt64 = 0
    private var segmentDataStart: UInt64 = 0
    private var durationOffset: UInt64 = 0
    private var seekEntries: [(UInt32, UInt64)] = []
    private var cluster = Data()
    private var clusterTime: Int64?
    private var cuePoints: [(time: Int64, position: UInt64)] = []
    private var endTime: Int64 = 0

    /// `cueTrack` is the track whose keyframes become cue points (the video track, if any).
    init(url: URL, tracks: [MatroskaTrack], chapters: [Chapter], cueTrack: Int?, appName: String) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        self.cueTrack = cueTrack
        try writeHeaders(tracks: tracks, chapters: chapters, appName: appName)
    }

    deinit { try? handle.close() }

    // MARK: Headers

    private func writeHeaders(tracks: [MatroskaTrack], chapters: [Chapter], appName: String) throws {
        try write(EBML.master(EBML.ID.ebml, [
            EBML.uint(EBML.ID.ebmlVersion, 1),
            EBML.uint(EBML.ID.ebmlReadVersion, 1),
            EBML.uint(EBML.ID.ebmlMaxIDLength, 4),
            EBML.uint(EBML.ID.ebmlMaxSizeLength, 8),
            EBML.string(EBML.ID.docType, "matroska"),
            EBML.uint(EBML.ID.docTypeVersion, 4),
            EBML.uint(EBML.ID.docTypeReadVersion, 2)
        ]))
        try write(EBML.id(EBML.ID.segment))
        segmentSizeOffset = offset
        try write(EBML.size(0, width: 8))
        segmentDataStart = offset
        try write(EBML.void(filling: Self.seekHeadReserve))

        let info = infoElement(appName: appName)
        seekEntries.append((EBML.ID.info, offset - segmentDataStart))
        // Duration is the last child, so its 8 value bytes end the element.
        durationOffset = offset + UInt64(info.count) - 8
        try write(info)

        seekEntries.append((EBML.ID.tracks, offset - segmentDataStart))
        try write(EBML.master(EBML.ID.tracks, tracks.map(\.element)))
        if !chapters.isEmpty {
            seekEntries.append((EBML.ID.chapters, offset - segmentDataStart))
            try write(Self.chaptersElement(chapters))
        }
    }

    private func infoElement(appName: String) -> Data {
        let uuid = withUnsafeBytes(of: UUID().uuid) { Data($0) }
        return EBML.master(EBML.ID.info, [
            EBML.uint(EBML.ID.timestampScale, Self.timestampScale),
            EBML.element(EBML.ID.segmentUUID, uuid),
            EBML.string(EBML.ID.muxingApp, appName),
            EBML.string(EBML.ID.writingApp, appName),
            EBML.float(EBML.ID.duration, 0)
        ])
    }

    static func chaptersElement(_ chapters: [Chapter]) -> Data {
        let atoms = chapters.enumerated().map { index, chapter in
            EBML.master(EBML.ID.chapterAtom, [
                EBML.uint(EBML.ID.chapterUID, UInt64(index + 1)),
                EBML.uint(EBML.ID.chapterTimeStart, chapter.startNs),
                EBML.uint(EBML.ID.chapterTimeEnd, chapter.endNs),
                EBML.master(EBML.ID.chapterDisplay, [
                    EBML.string(EBML.ID.chapString, chapter.title),
                    EBML.string(EBML.ID.chapLanguage, "und")
                ])
            ])
        }
        return EBML.master(EBML.ID.chapters, [
            EBML.master(EBML.ID.editionEntry, [
                EBML.uint(EBML.ID.editionUID, 1),
                EBML.uint(EBML.ID.editionFlagDefault, 1)
            ] + atoms)
        ])
    }

    // MARK: Blocks

    /// Adds one frame. Frames should arrive in decode order across all tracks.
    func add(_ frame: Frame) throws {
        let isCuePoint = frame.isKeyframe && frame.track == cueTrack
        if let start = clusterTime {
            let relative = frame.time - start
            let tooLong = frame.decodeTime - start >= Self.maxClusterSpan || cluster.count >= Self.maxClusterBytes
            if isCuePoint || tooLong || relative < Int64(Int16.min) || relative > Int64(Int16.max) {
                try flushCluster()
            }
        }
        if clusterTime == nil {
            // Anchor on the decode time so reordered frames that follow stay at or after it.
            clusterTime = max(0, min(frame.decodeTime, frame.time))
        }
        let start = clusterTime ?? 0
        if isCuePoint {
            cuePoints.append((max(0, frame.time), offset - segmentDataStart))
        }
        cluster.append(Self.block(frame, relativeTo: start))
    }

    /// Notes when a frame ends on the presentation timeline (without any codec delay),
    /// so the segment duration covers every track.
    func extend(to time: Int64) {
        endTime = max(endTime, time)
    }

    /// A SimpleBlock, or for frames with a duration a BlockGroup with BlockDuration.
    static func block(_ frame: Frame, relativeTo clusterTime: Int64) -> Data {
        let relative = Int16(clamping: max(frame.time, 0) - clusterTime)
        let header = EBML.size(UInt64(frame.track))
            + Data([UInt8(truncatingIfNeeded: UInt16(bitPattern: relative) >> 8), UInt8(truncatingIfNeeded: UInt16(bitPattern: relative))])
        guard let duration = frame.duration else {
            return EBML.element(EBML.ID.simpleBlock, header + Data([frame.isKeyframe ? 0x80 : 0x00]) + frame.data)
        }
        return EBML.master(EBML.ID.blockGroup, [
            EBML.element(EBML.ID.block, header + Data([0x00]) + frame.data),
            EBML.uint(EBML.ID.blockDuration, UInt64(max(duration, 0)))
        ])
    }

    private func flushCluster() throws {
        guard let start = clusterTime, !cluster.isEmpty else { return }
        let timestamp = EBML.uint(EBML.ID.timestamp, UInt64(start))
        let payload = UInt64(timestamp.count + cluster.count)
        try write(EBML.id(EBML.ID.cluster) + EBML.size(payload) + timestamp)
        try write(cluster)
        cluster = Data()
        clusterTime = nil
    }

    // MARK: Finishing

    /// Writes the last cluster and the cues, then patches the duration, SeekHead and segment size.
    func finish() throws {
        try flushCluster()
        if !cuePoints.isEmpty, let cueTrack {
            seekEntries.append((EBML.ID.cues, offset - segmentDataStart))
            try write(EBML.master(EBML.ID.cues, cuePoints.map { point in
                EBML.master(EBML.ID.cuePoint, [
                    EBML.uint(EBML.ID.cueTime, UInt64(point.time)),
                    EBML.master(EBML.ID.cueTrackPositions, [
                        EBML.uint(EBML.ID.cueTrack, UInt64(cueTrack)),
                        EBML.uint(EBML.ID.cueClusterPosition, point.position)
                    ])
                ])
            }))
        }
        let end = offset
        try patch(at: durationOffset, EBML.floatBytes(Double(endTime)))
        try patch(at: segmentDataStart, Self.seekHead(seekEntries, filling: Self.seekHeadReserve))
        try patch(at: segmentSizeOffset, EBML.size(end - segmentDataStart, width: 8))
        try handle.synchronize()
        try handle.close()
    }

    /// A SeekHead padded with a Void to exactly `count` bytes.
    static func seekHead(_ entries: [(UInt32, UInt64)], filling count: Int) -> Data {
        let head = EBML.master(EBML.ID.seekHead, entries.map { id, position in
            EBML.master(EBML.ID.seek, [
                EBML.element(EBML.ID.seekID, EBML.id(id)),
                EBML.element(EBML.ID.seekPosition, EBML.uintBytes(position, width: 8))
            ])
        })
        precondition(head.count + 2 <= count, "SeekHead outgrew its reserved space")
        return head + EBML.void(filling: count - head.count)
    }

    private func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        offset += UInt64(data.count)
    }

    private func patch(at position: UInt64, _ data: Data) throws {
        try handle.seek(toOffset: position)
        try handle.write(contentsOf: data)
        try handle.seek(toOffset: offset)
    }
}
