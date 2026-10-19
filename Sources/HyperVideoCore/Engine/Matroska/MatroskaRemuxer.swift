@preconcurrency import AVFoundation

/// Copies the compressed tracks of a movie into a Matroska file without re-encoding:
/// the first video track (H.264/HEVC), every audio track (AAC, ALAC, AC-3, E-AC-3,
/// MP3), 3GPP text subtitles as UTF-8 text, and the movie's chapters. Samples stream
/// through one at a time, in decode order, with their presentation times.
struct MatroskaRemuxer {
    let source: URL
    let destination: URL
    var appName = "HyperVideo Converter"

    /// Remuxes on a private queue. `cancel` is polled between samples; progress runs 0...1.
    func run(cancel: CancelFlag, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let plan = try await Plan.make(asset: asset)
        let job = Unchecked((self, plan))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue(label: "HyperVideo.remux.mkv", qos: .userInitiated).async {
                do {
                    try job.value.0.copy(job.value.1, cancel: cancel, progress: progress)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Planning

    /// The tracks to copy, worked out before any sample is read.
    struct Plan {
        struct Source {
            let track: AVAssetTrack
            var entry: MatroskaTrack
            let isText: Bool
        }
        let asset: AVURLAsset
        var sources: [Source]
        let chapters: [MatroskaWriter.Chapter]
        let metadata: MatroskaWriter.Metadata
        let duration: Double

        static func make(asset: AVURLAsset) async throws -> Plan {
            var sources: [Source] = []
            do {
                if let video = try await asset.loadTracks(withMediaType: .video).first {
                    let (formats, transform, fps, language) = try await video.load(
                        .formatDescriptions, .preferredTransform, .nominalFrameRate, .extendedLanguageTag)
                    guard let format = formats.first else { throw TranscodeError.cannotConfigure("video in Matroska (MKV)") }
                    let entry = try MatroskaTrack.video(format: format, number: sources.count + 1, transform: transform,
                                                        frameRate: fps, language: language)
                    sources.append(Source(track: video, entry: entry, isText: false))
                }
                for (index, track) in try await asset.loadTracks(withMediaType: .audio).enumerated() {
                    let (formats, language) = try await track.load(.formatDescriptions, .extendedLanguageTag)
                    guard let format = formats.first else { continue }
                    let entry = try MatroskaTrack.audio(format: format, number: sources.count + 1,
                                                        language: language, isDefault: index == 0)
                    sources.append(Source(track: track, entry: entry, isText: false))
                }
                for track in try await asset.loadTracks(withMediaType: .subtitle) {
                    let (formats, language) = try await track.load(.formatDescriptions, .extendedLanguageTag)
                    guard formats.first.map(CMFormatDescriptionGetMediaSubType) == kCMTextFormatType_3GText else { continue }
                    sources.append(Source(track: track, entry: .subtitle(number: sources.count + 1, language: language), isText: true))
                }
            } catch MatroskaTrack.UnsupportedFormat.codec(let name) {
                throw TranscodeError.cannotConfigure("the \(name) codec in Matroska (MKV); choose H.264 or H.265 video and AAC audio")
            }
            let duration = try await asset.load(.duration).seconds
            let chapters = try await MediaInspector.chapters(of: asset).map {
                MatroskaWriter.Chapter(title: $0.title, startNs: nanoseconds($0.start), endNs: nanoseconds($0.end))
            }
            let metadata = await Self.metadata(of: asset)
            return Plan(asset: asset, sources: sources, chapters: chapters, metadata: metadata, duration: duration)
        }

        /// What the title, artist, dates and so on of `asset` become in Matroska. The movie
        /// the encoder wrote only has them when the job keeps metadata.
        static func metadata(of asset: AVAsset) async -> MatroskaWriter.Metadata {
            let items = (try? await asset.load(.metadata)) ?? []
            guard !items.isEmpty else { return MatroskaWriter.Metadata() }
            func text(_ identifier: AVMetadataIdentifier) async -> String? {
                for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                    if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
                    if let date = try? await item.load(.dateValue) { return date.formatted(.iso8601) }
                }
                return nil
            }
            var metadata = MatroskaWriter.Metadata()
            metadata.title = await text(.commonIdentifierTitle)
            var artist = await text(.commonIdentifierArtist)
            if artist == nil { artist = await text(.commonIdentifierCreator) }
            if artist == nil { artist = await text(.commonIdentifierAuthor) }
            let named: [(String, String?)] = [
                ("TITLE", metadata.title),
                ("ARTIST", artist),
                ("ALBUM", await text(.commonIdentifierAlbumName)),
                ("DATE_RELEASED", await text(.commonIdentifierCreationDate)),
                ("DESCRIPTION", await text(.commonIdentifierDescription)),
                ("COPYRIGHT", await text(.commonIdentifierCopyrights)),
                ("PUBLISHER", await text(.commonIdentifierPublisher)),
                ("SUBJECT", await text(.commonIdentifierSubject))
            ]
            metadata.tags = named.compactMap { name, value in value.map { .init(name: name, value: $0) } }
            return metadata
        }

        private static func nanoseconds(_ seconds: Double) -> UInt64 {
            UInt64((max(seconds, 0) * 1_000_000_000).rounded())
        }
    }

    // MARK: Copying

    /// One compressed frame split out of a sample buffer, which may hold several (audio).
    private struct Packet {
        var track: Int
        var pts: CMTime
        var dts: CMTime
        var duration: CMTime
        var isKeyframe: Bool
        var data: Data
        /// Priming to drop, carried by the first packet of a buffer that declares it.
        var trimStart: CMTime = .invalid
    }

    /// Reads one track's packets in order, one sample buffer at a time.
    private final class TrackFeed {
        let number: Int
        let isText: Bool
        let output: AVAssetReaderTrackOutput
        private var queued: [Packet] = []

        init(number: Int, isText: Bool, output: AVAssetReaderTrackOutput) {
            self.number = number
            self.isText = isText
            self.output = output
        }

        /// The next packet, without consuming it; nil once the track is done.
        func peek() -> Packet? {
            while queued.isEmpty {
                guard let buffer = output.copyNextSampleBuffer() else { return nil }
                queued = MatroskaRemuxer.packets(in: buffer, track: number, isText: isText)
            }
            return queued.first
        }

        func pop() { queued.removeFirst() }
    }

    private func copy(_ plan: Plan, cancel: CancelFlag, progress: @Sendable (Double) -> Void) throws {
        guard !plan.sources.isEmpty else { throw TranscodeError.noTracks }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: plan.asset) } catch {
            throw TranscodeError.readerFailed(error.localizedDescription)
        }
        let feeds = plan.sources.map { source in
            let output = AVAssetReaderTrackOutput(track: source.track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            return TrackFeed(number: source.entry.number, isText: source.isText, output: output)
        }
        guard reader.startReading() else {
            throw TranscodeError.readerFailed(reader.error?.localizedDescription ?? "unknown error")
        }
        defer { if reader.status == .reading { reader.cancelReading() } }

        let timing = Self.priming(entries: plan.sources.map(\.entry), feeds: feeds)
        let video = timing.entries.first { $0.kind == .video }?.number
        let writer: MatroskaWriter
        do {
            writer = try MatroskaWriter(url: destination, tracks: timing.entries, chapters: plan.chapters,
                                        cueTrack: video, appName: appName, metadata: plan.metadata)
        } catch {
            throw TranscodeError.writerFailed(error.localizedDescription)
        }
        try interleave(feeds, into: writer, timing: timing, duration: plan.duration, cancel: cancel, progress: progress)
        if reader.status == .failed {
            throw TranscodeError.readerFailed(reader.error?.localizedDescription ?? "unknown error")
        }
        do { try writer.finish() } catch { throw TranscodeError.writerFailed(error.localizedDescription) }
        progress(1)
    }

    /// Per-track timing fixes: entries with codec delays, millisecond shifts added to
    /// block times, and the delays in milliseconds.
    private struct Timing {
        var entries: [MatroskaTrack]
        var shifts: [Int64]
        var delays: [Int64]
    }

    /// Encoder priming (AAC's leading samples) becomes a codec delay that players skip:
    /// either flagged as trimmed on the first buffer, or given negative times, which
    /// are shifted up because block times can't go below zero.
    private static func priming(entries: [MatroskaTrack], feeds: [TrackFeed]) -> Timing {
        var entries = entries
        var shifts = Array(repeating: Int64(0), count: feeds.count)
        for (index, feed) in feeds.enumerated() where entries[index].kind == .audio {
            guard let first = feed.peek() else { continue }
            let ahead = first.pts.seconds < 0 ? -first.pts.seconds : 0
            let delay = max(ahead, first.trimStart.isNumeric ? first.trimStart.seconds : 0)
            entries[index].codecDelayNs = UInt64((delay * 1_000_000_000).rounded())
            shifts[index] = Int64((ahead * 1_000).rounded())
        }
        let delays = entries.map { Int64(($0.codecDelayNs + 500_000) / 1_000_000) }
        return Timing(entries: entries, shifts: shifts, delays: delays)
    }

    /// Writes every packet, always taking the one with the earliest decode time next.
    private func interleave(
        _ feeds: [TrackFeed], into writer: MatroskaWriter, timing: Timing, duration: Double,
        cancel: CancelFlag, progress: @Sendable (Double) -> Void
    ) throws {
        var lastReported = -1.0
        while true {
            if cancel.isSet { throw CancellationError() }
            let pending = feeds.enumerated().compactMap { index, feed in feed.peek().map { (index, $0) } }
            guard let (index, packet) = pending.min(by: { Self.order($0.1) < Self.order($1.1) }) else { return }
            feeds[index].pop()
            if feeds[index].isText && packet.data.isEmpty { continue }
            let frame = Self.frame(packet, shift: timing.shifts[index], isText: feeds[index].isText)
            let end = frame.time + (packet.duration.isNumeric ? Self.milliseconds(packet.duration) : 0)
            do {
                try writer.add(frame)
                writer.extend(to: end - timing.delays[index])
            } catch {
                throw TranscodeError.writerFailed(error.localizedDescription)
            }
            let fraction = duration > 0 ? min(max(packet.pts.seconds / duration, 0), 1) : 0
            if fraction - lastReported >= 0.01 {
                lastReported = fraction
                progress(fraction)
            }
        }
    }

    private static func order(_ packet: Packet) -> Double {
        packet.dts.isNumeric ? packet.dts.seconds : packet.pts.seconds
    }

    private static func milliseconds(_ time: CMTime) -> Int64 {
        time.isNumeric ? CMTimeConvertScale(time, timescale: 1_000, method: .roundHalfAwayFromZero).value : 0
    }

    private static func frame(_ packet: Packet, shift: Int64, isText: Bool) -> MatroskaWriter.Frame {
        let pts = milliseconds(packet.pts) + shift
        let dts = packet.dts.isNumeric ? milliseconds(packet.dts) + shift : pts
        return MatroskaWriter.Frame(
            track: packet.track, time: pts, decodeTime: dts, isKeyframe: packet.isKeyframe,
            duration: isText ? milliseconds(packet.duration) : nil, data: packet.data
        )
    }
}

// MARK: Sample buffers

extension MatroskaRemuxer {
    /// Splits a sample buffer into its frames. Text samples become plain UTF-8.
    private static func packets(in buffer: CMSampleBuffer, track: Int, isText: Bool) -> [Packet] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        let count = CMSampleBufferGetNumSamples(buffer)
        guard count > 0 else { return [] }
        let notSync = notSyncFlags(buffer)
        let trim = CMGetAttachment(buffer, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart, attachmentModeOut: nil)
            .flatMap { $0 as? [String: Any] }.map { CMTimeMakeFromDictionary($0 as CFDictionary) } ?? .invalid
        var packets: [Packet] = []
        var position = 0
        for index in 0..<count {
            let size = CMSampleBufferGetSampleSize(buffer, at: index)
            var timing = CMSampleTimingInfo()
            CMSampleBufferGetSampleTimingInfo(buffer, at: index, timingInfoOut: &timing)
            var bytes = Data(count: size)
            let status = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: position, dataLength: size, destination: $0.baseAddress!)
            }
            position += size
            guard status == noErr else { continue }
            let data = isText ? Data(text(fromTimedText: bytes).utf8) : bytes
            packets.append(Packet(track: track, pts: timing.presentationTimeStamp, dts: timing.decodeTimeStamp,
                                  duration: timing.duration, isKeyframe: index < notSync.count ? !notSync[index] : true,
                                  data: data, trimStart: index == 0 ? trim : .invalid))
        }
        return packets
    }

    /// Per-sample "not a sync sample" flags; samples without attachments are keyframes.
    private static func notSyncFlags(_ buffer: CMSampleBuffer) -> [Bool] {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[CFString: Any]] else {
            return []
        }
        return attachments.map { ($0[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false }
    }

    /// The text of a 3GPP timed text sample: a 16-bit length, then the UTF-8 text
    /// (or UTF-16 with a byte-order mark), then optional style boxes, which are dropped.
    static func text(fromTimedText sample: Data) -> String {
        let bytes = [UInt8](sample)
        guard bytes.count >= 2 else { return "" }
        let length = min(Int(bytes[0]) << 8 | Int(bytes[1]), bytes.count - 2)
        let body = Data(bytes[2..<2 + length])
        if body.starts(with: [0xFE, 0xFF]) { return String(data: body, encoding: .utf16) ?? "" }
        return String(decoding: body, as: UTF8.self)
    }
}
