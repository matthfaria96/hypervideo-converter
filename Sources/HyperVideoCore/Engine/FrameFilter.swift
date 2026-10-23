import CoreImage
import CoreImage.CIFilterBuiltins

/// The Core Image pipeline for one frame: filters in the source's own orientation,
/// then the geometry plan's transform and crop.
enum FrameFilter {
    /// `image` is a decoded frame of `sourceSize`; the result fills `plan.renderSize`.
    /// `overlay` (burned-in subtitles) is drawn over the finished picture, in output pixels.
    static func render(
        _ image: CIImage, sourceSize: CGSize, plan: GeometryPlan, filters: VideoFilters, deinterlace: Bool,
        overlay: CIImage? = nil, canvas: CIColor = .black
    ) -> CIImage {
        var frame = image
        // Field lines run horizontally in the stored frame, so deinterlace before any rotation or scaling.
        if deinterlace { frame = filters.deinterlaceMethod == .bob ? bob(frame) : blendFields(frame) }
        if filters.denoise != .off { frame = denoise(frame, filters: filters) }
        if filters.chromaSmooth != .off {
            frame = chromaSmooth(frame, strength: filters.chromaSmooth, tune: filters.chromaSmoothTune)
        }
        if filters.sharpen != .off { frame = sharpen(frame, filters: filters) }
        if filters.grayscale { frame = grayscale(frame) }

        let output = CGRect(origin: .zero, size: plan.renderSize)
        let picture = toSourceSize(frame, extent: image.extent, sourceSize: sourceSize)
            .transformed(by: coreImageTransform(plan.transform, sourceHeight: sourceSize.height, renderHeight: plan.renderSize.height))
            .composited(over: CIImage(color: canvas).cropped(to: output))
            .cropped(to: output)
        return overlay.map { $0.composited(over: picture).cropped(to: output) } ?? picture
    }

    /// Decoded frames arrive at their storage size; the plan works in `sourceSize` (the track's
    /// natural size, which is the display size for pixel-aspect-tagged video), so stretch to it.
    static func toSourceSize(_ image: CIImage, extent: CGRect, sourceSize: CGSize) -> CIImage {
        guard extent.width > 0, extent.height > 0, sourceSize.width > 0, sourceSize.height > 0,
              extent.size != sourceSize else { return image }
        let scale = CGAffineTransform(scaleX: sourceSize.width / extent.width, y: sourceSize.height / extent.height)
        return image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY).concatenating(scale))
    }

    /// `plan.transform` uses AVFoundation's top-left origin; Core Image's origin is
    /// bottom-left, so flip in, apply, and flip back out.
    static func coreImageTransform(_ transform: CGAffineTransform, sourceHeight: CGFloat, renderHeight: CGFloat) -> CGAffineTransform {
        let flipIn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
        let flipOut = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderHeight)
        return flipIn.concatenating(transform).concatenating(flipOut)
    }

    /// Blend deinterlacing: each line becomes ¼ above + ½ itself + ¼ below, which
    /// merges the two fields and removes combing at a small cost in vertical detail.
    static func blendFields(_ image: CIImage) -> CIImage {
        let filter = CIFilter.convolution3X3()
        filter.inputImage = image.clampedToExtent()
        filter.weights = CIVector(values: [0, 0.25, 0, 0, 0.5, 0, 0, 0.25, 0], count: 9)
        filter.bias = 0
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    static func grayscale(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = 0
        filter.brightness = 0
        filter.contrast = 1
        return filter.outputImage ?? image
    }
}
