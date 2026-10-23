import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Moves frames between pixel buffers and the PNG files the backend reads and writes.
/// The bytes go through untouched: every image is tagged with one colour space and drawn
/// into the same one, so no colour management shifts the picture on the round trip.
enum FrameFiles {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    /// BGRA in memory, as the reader and the writer use it.
    private static let bitmapInfo = CGBitmapInfo(rawValue:
        CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

    static func name(_ index: Int) -> String { String(format: "%06d.png", index) }

    static func writePNG(_ buffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo,
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw UpscaleError.failed("couldn't write frame \(url.lastPathComponent)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw UpscaleError.failed("couldn't write frame \(url.lastPathComponent)")
        }
    }

    /// Draws the PNG at `url` into a buffer from `pool` (BGRA, the writer's size).
    static func readPNG(_ url: URL, pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw UpscaleError.failed("the upscaled frame \(url.lastPathComponent) is missing")
        }
        // The backend writes untagged PNGs; give them the space the frames left in.
        let image = decoded.copy(colorSpace: colorSpace) ?? decoded
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { throw UpscaleError.failed("out of frame buffers") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { throw UpscaleError.failed("couldn't draw frame \(url.lastPathComponent)") }
        // A backend that rounded the size differently is stretched to the exact output.
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
