import CoreImage
import CoreImage.CIFilterBuiltins

extension FrameFilter {
    /// Softens colour only: the blurred copy supplies hue and saturation, the original its luminance.
    static func chromaSmooth(_ image: CIImage, strength: FilterStrength, tune: ChromaSmoothTune) -> CIImage {
        guard strength != .off else { return image }
        let sigma = (1 + 4 * strength.amount) * tune.widthFactor
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: image.extent)
        let blend = CIFilter.colorBlendMode()
        blend.inputImage = blurred
        blend.backgroundImage = image
        return (blend.outputImage ?? image).cropped(to: image.extent)
    }

    /// Bob deinterlacing: keep one field and line-double it back to full height.
    static func bob(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let origin = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        let half = image.samplingNearest()
            .transformed(by: origin)
            .transformed(by: CGAffineTransform(scaleX: 1, y: 0.5))
        let doubled = half.samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: 1, y: 2))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        return doubled.clampedToExtent().cropped(to: extent)
    }
}
