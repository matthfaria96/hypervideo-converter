@preconcurrency import AVFoundation
import CoreGraphics

/// Finds black borders by sampling a few frames. Pure analysis lives in `bars` and `combine`.
public enum CropDetector {
    /// Samples `samples` frames of the file and returns the borders to remove.
    public static func detect(url: URL, mode: CropMode, samples: Int = 10) async throws -> Crop {
        try await detect(asset: AVURLAsset(url: url), mode: mode, range: nil, samples: samples)
    }

    static func detect(asset: AVAsset, mode: CropMode, range: CMTimeRange?, samples: Int) async throws -> Crop {
        guard mode.detects, samples > 0 else { return .zero }
        let span: CMTimeRange
        if let range, range.duration.isNumeric, range.duration.seconds > 0 {
            span = range
        } else {
            span = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        var found: [Crop] = []
        for index in 0..<samples {
            let fraction = Double(index + 1) / Double(samples + 1)
            let time = CMTimeAdd(span.start, CMTime(seconds: span.duration.seconds * fraction, preferredTimescale: 600))
            guard let image = try? await generator.image(at: time).image else { continue }
            guard let luma = luma(of: image),
                  let crop = bars(luma: luma, width: image.width, height: image.height) else { continue }
            found.append(crop)
        }
        return combine(found, mode: mode)
    }

    static func luma(of image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Borders whose rows/columns average at or below `threshold`. Edges are rounded down to
    /// even; nil when the picture would shrink below 16 px, which also covers all-dark frames.
    static func bars(luma: [UInt8], width: Int, height: Int, threshold: UInt8 = 24) -> Crop? {
        guard width > 0, height > 0, luma.count >= width * height else { return nil }
        let rows = (0..<height).map { rowMean(luma, row: $0, width: width) }
        let top = rows.prefix { $0 <= Double(threshold) }.count
        let bottom = rows.reversed().prefix { $0 <= Double(threshold) }.count
        guard top + bottom <= height - 16 else { return nil }
        let columns = (0..<width).map { columnMean(luma, column: $0, width: width, rows: top..<(height - bottom)) }
        let left = columns.prefix { $0 <= Double(threshold) }.count
        let right = columns.reversed().prefix { $0 <= Double(threshold) }.count
        guard left + right <= width - 16 else { return nil }
        return Crop(top: top & ~1, bottom: bottom & ~1, left: left & ~1, right: right & ~1)
    }

    private static func rowMean(_ luma: [UInt8], row: Int, width: Int) -> Double {
        var sum = 0
        for x in 0..<width { sum += Int(luma[row * width + x]) }
        return Double(sum) / Double(width)
    }

    private static func columnMean(_ luma: [UInt8], column: Int, width: Int, rows: Range<Int>) -> Double {
        guard !rows.isEmpty else { return 255 }
        var sum = 0
        for y in rows { sum += Int(luma[y * width + column]) }
        return Double(sum) / Double(rows.count)
    }

    /// Automatic: the most common value per edge (ties go to the smaller). Conservative: the smallest.
    static func combine(_ crops: [Crop], mode: CropMode) -> Crop {
        guard !crops.isEmpty else { return .zero }
        func pick(_ values: [Int]) -> Int {
            if mode == .conservative { return values.min() ?? 0 }
            let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
            return counts.max { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key }?.key ?? 0
        }
        return Crop(
            top: pick(crops.map(\.top)), bottom: pick(crops.map(\.bottom)),
            left: pick(crops.map(\.left)), right: pick(crops.map(\.right))
        )
    }
}

extension Crop {
    /// The same borders after the picture is rotated clockwise, then optionally mirrored.
    public func rotated(by rotation: Rotation, flipped: Bool) -> Crop {
        var result: Crop
        switch rotation {
        case .none: result = self
        case .cw90: result = Crop(top: left, bottom: right, left: bottom, right: top)
        case .cw180: result = Crop(top: bottom, bottom: top, left: right, right: left)
        case .cw270: result = Crop(top: right, bottom: left, left: top, right: bottom)
        }
        if flipped { result = Crop(top: result.top, bottom: result.bottom, left: result.right, right: result.left) }
        return result
    }
}
