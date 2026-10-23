@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import CoreText
import Synchronization

/// Draws timed subtitle cues into frames: white text with a dark outline and shadow,
/// bottom-centered, sized to the output height and wrapped to fit its width.
/// Cue times are on the source timeline, which is what the compositor is asked to render.
final class SubtitleBurner: @unchecked Sendable {
    let cues: [SubtitleCue]
    /// The last rendered cue; a cue spans many frames, so this saves redrawing each one.
    private let cache = Mutex<(text: String, size: CGSize, image: CIImage)?>(nil)

    /// `cues` are cut to `start..<end`; overlapping cues show together, one per line.
    init(cues: [SubtitleCue], start: Double, end: Double) {
        self.cues = SubtitleParser.timeline(cues, start: start, end: end).filter { !$0.text.isEmpty }
    }

    /// The text overlay for the frame at `seconds`, or nil when no cue is showing.
    func overlay(at seconds: Double, size: CGSize) -> CIImage? {
        guard let cue = cues.first(where: { $0.start <= seconds && seconds < $0.end }) else { return nil }
        if let cached = cache.withLock({ $0 }), cached.text == cue.text, cached.size == size { return cached.image }
        guard let image = Self.render(cue.text, size: size).map(CIImage.init(cgImage:)) else { return nil }
        cache.withLock { $0 = (cue.text, size, image) }
        return image
    }

    /// A transparent `size` image with `text` drawn near the bottom.
    static func render(_ text: String, size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let fontSize = max(10, size.height * 0.055)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafeBytes(of: &alignment) { bytes in
            bytes.baseAddress.map {
                [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: $0)]
            } ?? []
        }.withUnsafeBufferPointer { CTParagraphStyleCreate($0.baseAddress, $0.count) }
        let base: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ]
        let fill = base.merging([
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]) { $1 }
        // A positive stroke width draws only the outline, as a percentage of the font size.
        let outline = base.merging([
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): 18.0
        ]) { $1 }

        let box = textBox(text, attributes: fill, size: size)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -fontSize * 0.08), blur: fontSize * 0.25,
                          color: CGColor(gray: 0, alpha: 0.85))
        draw(text, attributes: outline, in: box, context: context)
        context.restoreGState()
        draw(text, attributes: fill, in: box, context: context)
        return context.makeImage()
    }

    /// The wrapped text's frame: 90% of the width, its bottom 6% of the height above the edge.
    static func textBox(_ text: String, attributes: [NSAttributedString.Key: Any], size: CGSize) -> CGRect {
        let width = size.width * 0.9
        let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil
        )
        let height = min(fitted.height.rounded(.up) + 2, size.height * 0.9)
        return CGRect(x: (size.width - width) / 2, y: size.height * 0.06, width: width, height: height)
    }

    private static func draw(_ text: String, attributes: [NSAttributedString.Key: Any], in box: CGRect, context: CGContext) {
        let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: box, transform: nil), nil)
        CTFrameDraw(frame, context)
    }

    // MARK: Loading

    /// The cues `burnIn` points at: an external file, or a source tx3g text track.
    static func cues(for burnIn: SubtitleBurnIn, asset: AVAsset) async throws -> [SubtitleCue] {
        switch burnIn {
        case .file(let url):
            do {
                return try SubtitleParser.cues(from: Data(contentsOf: url))
            } catch {
                throw TranscodeError.cannotConfigure(
                    "the subtitle file \(url.lastPathComponent) couldn't be read (\(error.localizedDescription))"
                )
            }
        case .track(let id):
            let tracks = try await MediaInspector.subtitleTracks(in: asset).map(\.0)
            guard let track = tracks.first(where: { Int($0.trackID) == id }) else {
                throw TranscodeError.cannotConfigure("the subtitle track to burn in is missing from the source")
            }
            return try await textCues(of: track, asset: asset)
        }
    }

    /// Decodes a 3GPP timed-text track: each sample is a 16-bit length then UTF-8 text.
    private static func textCues(of track: AVAssetTrack, asset: AVAsset) async throws -> [SubtitleCue] {
        let formats = try await track.load(.formatDescriptions)
        guard let format = formats.first, CMFormatDescriptionGetMediaSubType(format) == kCMTextFormatType_3GText else {
            let name = formats.first.map { FourCC.string(CMFormatDescriptionGetMediaSubType($0)) } ?? "unknown"
            throw TranscodeError.cannotConfigure("burning in \(name) subtitles (only Timed Text tracks can be burned in)")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { throw TranscodeError.cannotConfigure("reading the subtitle track") }
        reader.add(output)
        guard reader.startReading() else { throw TranscodeError.readerFailed(reader.error?.localizedDescription ?? "subtitle track") }
        var cues: [SubtitleCue] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let text = timedText(in: sample), !text.isEmpty else { continue }
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let duration = CMSampleBufferGetDuration(sample).seconds
            guard start.isFinite, duration.isFinite, duration > 0 else { continue }
            cues.append(SubtitleCue(start: start, end: start + duration, text: text))
        }
        return cues
    }

    static func timedText(in sample: CMSampleBuffer) -> String? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var bytes = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
        guard bytes.count >= 2,
              CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: &bytes) == noErr
        else { return nil }
        let length = Int(bytes[0]) << 8 | Int(bytes[1])
        return String(decoding: bytes.dropFirst(2).prefix(length), as: UTF8.self)
    }
}
