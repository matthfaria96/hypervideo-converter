@preconcurrency import AVFoundation

/// HandBrake's "Forced only" for a 3GPP text track that mixes forced and normal lines:
/// keep the cues flagged forced (a `frcd` sample modifier box), blank the rest, and
/// flag the output track as holding only forced subtitles.
enum ForcedSubtitles {
    private static let forcedBox: UInt32 = 0x6672_6364 // "frcd"

    /// True when the tx3g sample carries a `frcd` modifier box after its text.
    static func isForced(_ sample: CMSampleBuffer) -> Bool {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return false }
        let length = CMBlockBufferGetDataLength(block)
        guard length >= 2 else { return false }
        var bytes = [UInt8](repeating: 0, count: length)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        guard status == noErr else { return false }
        return hasForcedBox(bytes)
    }

    /// Walks the modifier boxes that follow the 16-bit length and the text.
    static func hasForcedBox(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2 else { return false }
        var offset = 2 + (Int(bytes[0]) << 8 | Int(bytes[1]))
        while offset + 8 <= bytes.count {
            let size = Int(bigEndian(bytes, offset))
            if bigEndian(bytes, offset + 4) == forcedBox { return true }
            guard size >= 8 else { return false }
            offset += size
        }
        return false
    }

    private static func bigEndian(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    /// `format` with the "all subtitles forced" display flag added; nil if it can't be built.
    static func forcedFormat(from format: CMFormatDescription) -> CMFormatDescription? {
        let existing = CMFormatDescriptionGetExtensions(format) as? [CFString: Any] ?? [:]
        var extensions = existing
        let flags = (existing[kCMTextFormatDescriptionExtension_DisplayFlags] as? NSNumber)?.uint32Value ?? 0
        extensions[kCMTextFormatDescriptionExtension_DisplayFlags] = NSNumber(
            value: flags | UInt32(kCMTextDisplayFlag_allSubtitlesForced))
        var result: CMFormatDescription?
        let status = CMFormatDescriptionCreate(
            allocator: nil, mediaType: CMFormatDescriptionGetMediaType(format),
            mediaSubType: CMFormatDescriptionGetMediaSubType(format),
            extensions: extensions as CFDictionary, formatDescriptionOut: &result)
        return status == noErr ? result : nil
    }

    /// Keeps forced cues and replaces the others with empty ones of the same timing, all
    /// described by `format` (the forced-flagged description).
    static func transform(format: CMFormatDescription) -> SampleTransform {
        { sample in
            // Marker buffers (no samples, no data) pass through as the plain copy would.
            guard CMSampleBufferGetNumSamples(sample) > 0 else { return sample }
            let data = isForced(sample) ? CMSampleBufferGetDataBuffer(sample) : emptyCue()
            guard let data, let rebuilt = rebuilt(sample, data: data, format: format) else {
                throw TranscodeError.writerFailed("a forced subtitle couldn't be copied")
            }
            return rebuilt
        }
    }

    /// True when any sample in the first `limit` of the track is a forced cue.
    static func hasForcedCue(asset: AVAsset, track: AVAssetTrack, limit: Int = 10_000) -> Bool {
        guard let reader = try? AVAssetReader(asset: asset) else { return false }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }
        defer { reader.cancelReading() }
        for _ in 0..<limit {
            guard let sample = output.copyNextSampleBuffer() else { return false }
            if isForced(sample) { return true }
        }
        return false
    }

    private static func emptyCue() -> CMBlockBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: 2, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: 2, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        ) == noErr, let block, CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: 2) == noErr
        else { return nil }
        return block
    }

    private static func rebuilt(_ sample: CMSampleBuffer, data: CMBlockBuffer, format: CMFormatDescription) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing) == noErr else { return nil }
        var size = CMBlockBufferGetDataLength(data)
        var result: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: data, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &result)
        return status == noErr ? result : nil
    }
}
