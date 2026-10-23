import CoreImage
import CoreImage.CIFilterBuiltins

extension FrameFilter {
    /// HandBrake-style denoise: NLMeans or HQDN3D at one of six strengths, shaped by a tune.
    static func denoise(_ image: CIImage, filters: VideoFilters) -> CIImage {
        guard filters.denoise != .off else { return image }
        let amount = filters.denoise.amount * filters.denoiseTune.multiplier
        if filters.denoiseTune == .sprite { return median(image) }
        let base = filters.denoiseFilter == .nlmeans ? denoise(image, amount: amount) : hqdn3d(image, amount: amount)
        guard filters.denoiseTune == .grain else { return base }
        // Keep the original luma, take the denoised chroma: grain survives, colour noise goes.
        let blend = CIFilter.luminosityBlendMode()
        blend.inputImage = image
        blend.backgroundImage = base
        return (blend.outputImage ?? base).cropped(to: image.extent)
    }

    static func denoise(_ image: CIImage, amount: Double) -> CIImage {
        let filter = CIFilter.noiseReduction()
        filter.inputImage = image.clampedToExtent()
        filter.noiseLevel = Float(0.01 + 0.03 * amount)
        filter.sharpness = 0.4
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    /// Spatial approximation of HQDN3D: median, soft blur, then a mix with the original.
    static func hqdn3d(_ image: CIImage, amount: Double) -> CIImage {
        let blurred = median(image).clampedToExtent()
            .applyingGaussianBlur(sigma: 0.3 + 0.6 * amount)
            .cropped(to: image.extent)
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = image
        mix.targetImage = blurred
        mix.time = Float(min(1, 0.2 + 0.5 * amount))
        return (mix.outputImage ?? image).cropped(to: image.extent)
    }

    static func median(_ image: CIImage) -> CIImage {
        let filter = CIFilter.median()
        filter.inputImage = image.clampedToExtent()
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }
}
