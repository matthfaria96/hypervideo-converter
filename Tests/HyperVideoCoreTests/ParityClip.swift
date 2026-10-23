@preconcurrency import AVFoundation
@testable import HyperVideoCore

/// Small video-only sources for the parity transcodes: optional black bars and pixel aspect.
enum ParityClip {
    struct Spec {
        var name = "parity"
        var size = CGSize(width: 320, height: 180)
        var frameTimes: [Double] = (0..<30).map { Double($0) / 30 }
        /// Rows painted black at the top and bottom of every frame.
        var blackBars = 0
        var pixelAspect: CGSize?
        /// 8-bit gray level of the picture.
        var level: UInt8 = 120
    }

    static func make(in dir: URL, _ spec: Spec) async throws -> URL {
        let url = dir.appendingPathComponent("\(spec.name).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(spec.size.width), AVVideoHeightKey: Int(spec.size.height)
        ]
        if let par = spec.pixelAspect {
            settings[AVVideoPixelAspectRatioKey] = [
                AVVideoPixelAspectRatioHorizontalSpacingKey: Int(par.width),
                AVVideoPixelAspectRatioVerticalSpacingKey: Int(par.height)
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(spec.size.width), kCVPixelBufferHeightKey as String: Int(spec.size.height)
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var index = 0
        while index < spec.frameTimes.count {
            if input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool {
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                if let buffer {
                    paint(buffer, spec: spec)
                    adaptor.append(buffer, withPresentationTime: CMTime(seconds: spec.frameTimes[index], preferredTimescale: 6_000))
                }
                index += 1
            } else {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    private static func paint(_ buffer: CVPixelBuffer, spec: Spec) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer), width = CVPixelBufferGetWidth(buffer)
        for y in 0..<height {
            let black = y < spec.blackBars || y >= height - spec.blackBars
            for x in 0..<width {
                let value = black ? UInt8(0) : spec.level
                let pixel = base + y * stride + x * 4
                pixel[0] = value; pixel[1] = value; pixel[2] = value; pixel[3] = 255
            }
        }
    }
}

/// Reads back what the parity tests assert on.
enum OutputProbe {
    static func presentationTimes(_ url: URL, _ type: AVMediaType = .video) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: type).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any]? = type == .video ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA] : nil
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        reader.startReading()
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            if time.isNumeric { times.append(time.seconds) }
        }
        return times.sorted()
    }

    static func format(_ url: URL) async throws -> CMFormatDescription? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        return try await track.load(.formatDescriptions).first
    }

    static func pixelAspect(_ format: CMFormatDescription) -> CGSize? {
        let value = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio)
        guard let dict = value as? [String: Any],
              let h = dict[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String] as? NSNumber,
              let v = dict[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String] as? NSNumber else { return nil }
        return CGSize(width: h.doubleValue, height: v.doubleValue)
    }

    /// Mean luma of one row of the frame at `time`.
    static func rowLuma(_ url: URL, time: Double, rowFraction: Double) async throws -> Double {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        guard let luma = CropDetector.luma(of: image) else { return 0 }
        let row = min(image.height - 1, Int(Double(image.height) * rowFraction))
        let slice = luma[(row * image.width)..<((row + 1) * image.width)]
        return Double(slice.reduce(0) { $0 + Int($1) }) / Double(image.width)
    }
}
