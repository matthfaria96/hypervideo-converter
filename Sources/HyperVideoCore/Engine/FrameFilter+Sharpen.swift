import CoreImage
import CoreImage.CIFilterBuiltins

extension FrameFilter {
    /// HandBrake-style sharpen: Unsharp or Lapsharp at one of six strengths, shaped by a tune.
    static func sharpen(_ image: CIImage, filters: VideoFilters) -> CIImage {
        guard filters.sharpen != .off else { return image }
        let tune = filters.sharpenTune.resolved(for: filters.sharpenFilter)
        let amount = filters.sharpen.amount
        switch filters.sharpenFilter {
        case .unsharp: return unsharp(image, amount: amount, tune: tune)
        case .lapsharp: return sharpen(image, amount: amount * lapsharpIntensity(tune))
        }
    }

    static func sharpen(_ image: CIImage, amount: Double) -> CIImage {
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image.clampedToExtent()
        filter.sharpness = Float(0.2 + 0.6 * amount)
        filter.radius = 1.5
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    static func unsharp(_ image: CIImage, amount: Double, tune: SharpenTune) -> CIImage {
        let filter = CIFilter.unsharpMask()
        filter.inputImage = image.clampedToExtent()
        filter.radius = unsharpRadius(tune)
        filter.intensity = Float(0.25 + 0.75 * amount)
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    private static func lapsharpIntensity(_ tune: SharpenTune) -> Double {
        switch tune {
        case .grain: 0.6
        case .animation: 1.2
        case .sprite: 0.8
        default: 1
        }
    }

    private static func unsharpRadius(_ tune: SharpenTune) -> Float {
        switch tune {
        case .ultrafine: 0.5
        case .fine: 1.0
        case .coarse: 2.5
        case .verycoarse: 4.0
        default: 1.5
        }
    }
}
