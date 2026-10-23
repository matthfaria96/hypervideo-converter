import Foundation
import HyperVideoCore

/// The text shown for a failed job, translated where the engine's English text isn't enough.
enum JobErrorMessage {
    static func text(for error: Error) -> String {
        if case TranscodeError.insufficientSpace(let required, let available) = error {
            let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availableText = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return String(localized: "There isn't enough free space in the destination folder. This video needs about \(requiredText), but only \(availableText) is free.")
        }
        if let upscale = error as? UpscaleError {
            switch upscale {
            case .backendMissing: return String(localized: "The AI engine (Upscayl) wasn't found in the app.")
            case .noVideo: return String(localized: "This file has no video to upscale.")
            case .failed(let detail): return String(localized: "AI Upscale failed: \(detail)")
            }
        }
        return error.localizedDescription
    }
}
