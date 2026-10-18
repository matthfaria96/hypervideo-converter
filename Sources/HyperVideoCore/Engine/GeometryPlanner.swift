import CoreGraphics

/// Turns orientation, crop, rotation, flip and resolution limits into a single
/// affine transform plus render size for the video compositor.
/// Coordinates follow AVFoundation's top-left origin convention.
public struct GeometryPlan: Equatable, Sendable {
    public var transform: CGAffineTransform
    public var renderSize: CGSize
}

public enum GeometryPlanner {
    public static func plan(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        crop: Crop,
        rotation: Rotation,
        flipHorizontal: Bool,
        maxResolution: MaxResolution
    ) -> GeometryPlan {
        var transform = normalized(preferredTransform, size: naturalSize)
        var size = orientedSize(naturalSize, preferredTransform)

        if rotation != .none {
            let radians = CGFloat(rotation.rawValue) * .pi / 180
            transform = normalized(transform.concatenating(CGAffineTransform(rotationAngle: radians)), size: naturalSize)
            size = orientedSize(naturalSize, transform)
        }

        if flipHorizontal {
            transform = transform
                .concatenating(CGAffineTransform(scaleX: -1, y: 1))
                .concatenating(CGAffineTransform(translationX: size.width, y: 0))
        }

        let cropped = clampedCrop(crop, in: size)
        transform = transform.concatenating(CGAffineTransform(translationX: -CGFloat(cropped.left), y: -CGFloat(cropped.top)))
        let croppedSize = CGSize(
            width: size.width - CGFloat(cropped.left + cropped.right),
            height: size.height - CGFloat(cropped.top + cropped.bottom)
        )

        let output = scaledSize(croppedSize, limit: maxResolution)
        let scale = CGAffineTransform(scaleX: output.width / croppedSize.width, y: output.height / croppedSize.height)
        return GeometryPlan(transform: transform.concatenating(scale), renderSize: output)
    }

    public static func orientedSize(_ size: CGSize, _ transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width).rounded(), height: abs(rect.height).rounded())
    }

    /// Re-anchors a transform so the transformed frame starts at the origin.
    private static func normalized(_ transform: CGAffineTransform, size: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    /// Keeps at least 16 px in each dimension so a typo can't produce an empty frame.
    static func clampedCrop(_ crop: Crop, in size: CGSize) -> Crop {
        let maxHorizontal = max(0, Int(size.width) - 16)
        let maxVertical = max(0, Int(size.height) - 16)
        let left = min(max(0, crop.left), maxHorizontal)
        let right = min(max(0, crop.right), maxHorizontal - left)
        let top = min(max(0, crop.top), maxVertical)
        let bottom = min(max(0, crop.bottom), maxVertical - top)
        return Crop(top: top, bottom: bottom, left: left, right: right)
    }

    static func scaledSize(_ size: CGSize, limit: MaxResolution) -> CGSize {
        var factor: CGFloat = 1
        if let box = limit.boundingBox(portrait: size.height > size.width) {
            factor = min(1, box.width / size.width, box.height / size.height)
        }
        return CGSize(width: even(size.width * factor), height: even(size.height * factor))
    }

    /// Encoders require even dimensions for 4:2:0 chroma.
    static func even(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded() * 2)
    }
}
