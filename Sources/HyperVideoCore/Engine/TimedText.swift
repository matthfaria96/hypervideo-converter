import CoreMedia

/// Builds 3GPP timed text (tx3g) samples, used for chapter title tracks.
enum TimedText {
    /// A plain white-on-transparent tx3g description for `mediaType` (text or subtitle).
    static func format(mediaType: CMMediaType) -> CMFormatDescription? {
        let white: [CFString: Any] = [
            kCMTextFormatDescriptionColor_Red: 255, kCMTextFormatDescriptionColor_Green: 255,
            kCMTextFormatDescriptionColor_Blue: 255, kCMTextFormatDescriptionColor_Alpha: 255
        ]
        let extensions: [CFString: Any] = [
            kCMTextFormatDescriptionExtension_DisplayFlags: 0,
            kCMTextFormatDescriptionExtension_HorizontalJustification: 1,
            kCMTextFormatDescriptionExtension_VerticalJustification: -1,
            kCMTextFormatDescriptionExtension_BackgroundColor: [
                kCMTextFormatDescriptionColor_Red: 0, kCMTextFormatDescriptionColor_Green: 0,
                kCMTextFormatDescriptionColor_Blue: 0, kCMTextFormatDescriptionColor_Alpha: 0
            ],
            kCMTextFormatDescriptionExtension_DefaultTextBox: [
                kCMTextFormatDescriptionRect_Top: 0, kCMTextFormatDescriptionRect_Left: 0,
                kCMTextFormatDescriptionRect_Bottom: 0, kCMTextFormatDescriptionRect_Right: 0
            ],
            kCMTextFormatDescriptionExtension_DefaultStyle: [
                kCMTextFormatDescriptionStyle_StartChar: 0, kCMTextFormatDescriptionStyle_EndChar: 0,
                kCMTextFormatDescriptionStyle_Font: 1, kCMTextFormatDescriptionStyle_FontFace: 0,
                kCMTextFormatDescriptionStyle_FontSize: 18, kCMTextFormatDescriptionStyle_ForegroundColor: white
            ],
            kCMTextFormatDescriptionExtension_FontTable: ["1": "Sans-Serif"]
        ]
        var format: CMFormatDescription?
        let status = CMFormatDescriptionCreate(
            allocator: nil, mediaType: mediaType, mediaSubType: kCMTextFormatType_3GText,
            extensions: extensions as CFDictionary, formatDescriptionOut: &format
        )
        return status == noErr ? format : nil
    }

    /// One sample: a 16-bit big-endian length followed by the UTF-8 text.
    static func sample(_ text: String, start: Double, duration: Double, format: CMFormatDescription) -> CMSampleBuffer? {
        let utf8 = Array(text.utf8.prefix(Int(UInt16.max)))
        let bytes = [UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)] + utf8
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block
        ) == noErr, let block else { return nil }
        let copied = bytes.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count)
        }
        guard copied == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            presentationTimeStamp: CMTime(seconds: start, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        var size = bytes.count
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        )
        return sample
    }
}
