import CoreGraphics

/// Turns orientation, crop, rotation, flip and resolution limits into a single
/// affine transform plus render size for the video compositor.
/// Coordinates follow AVFoundation's top-left origin convention.
public struct GeometryPlan: Equatable, Sendable {
    public var transform: CGAffineTransform
    /// The whole output frame, padding included.
    public var renderSize: CGSize
    /// Where the picture sits inside `renderSize`.
    public var pictureRect: CGRect
    /// Pixel aspect to tag on the output; nil for square pixels.
    public var pixelAspect: CGSize?

    public init(transform: CGAffineTransform, renderSize: CGSize, pictureRect: CGRect? = nil, pixelAspect: CGSize? = nil) {
        self.transform = transform
        self.renderSize = renderSize
        self.pictureRect = pictureRect ?? CGRect(origin: .zero, size: renderSize)
        self.pixelAspect = pixelAspect
    }
}

public enum GeometryPlanner {
    public static func plan(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        crop: Crop,
        rotation: Rotation,
        flipHorizontal: Bool,
        maxResolution: MaxResolution,
        picture: PictureOptions = PictureOptions(),
        sourcePixelAspect: CGSize = CGSize(width: 1, height: 1)
    ) -> GeometryPlan {
        var (transform, size) = oriented(
            naturalSize: naturalSize, preferredTransform: preferredTransform, rotation: rotation, flip: flipHorizontal
        )
        let cropped = clampedCrop(crop, in: size)
        transform = transform.concatenating(CGAffineTransform(translationX: -CGFloat(cropped.left), y: -CGFloat(cropped.top)))
        let croppedSize = CGSize(
            width: size.width - CGFloat(cropped.left + cropped.right),
            height: size.height - CGFloat(cropped.top + cropped.bottom)
        )

        var output = scaledSize(croppedSize, limit: maxResolution, allowUpscaling: picture.allowUpscaling)
        var pixelAspect: CGSize?
        let netRotation = (rotation.rawValue + Self.rotationDegrees(of: preferredTransform)) % 180
        if picture.anamorphic == .automatic, !picture.padding.isActive, netRotation == 0,
           let reduced = reducedAspect(sourcePixelAspect) {
            output.width = even(output.width * reduced.height / reduced.width)
            pixelAspect = reduced
        }
        let scale = CGAffineTransform(scaleX: output.width / croppedSize.width, y: output.height / croppedSize.height)
        transform = transform.concatenating(scale)

        guard picture.padding.isActive else {
            return GeometryPlan(transform: transform, renderSize: output, pixelAspect: pixelAspect)
        }
        let padding = padded(output, mode: picture.padding.mode, limit: maxResolution)
        transform = transform.concatenating(CGAffineTransform(translationX: padding.origin.x, y: padding.origin.y))
        return GeometryPlan(
            transform: transform, renderSize: padding.canvas,
            pictureRect: CGRect(origin: padding.origin, size: output), pixelAspect: nil
        )
    }

    public static func orientedSize(_ size: CGSize, _ transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width).rounded(), height: abs(rect.height).rounded())
    }

    /// Applies the container's orientation, then the user's rotation and horizontal flip.
    private static func oriented(
        naturalSize: CGSize, preferredTransform: CGAffineTransform, rotation: Rotation, flip: Bool
    ) -> (CGAffineTransform, CGSize) {
        var transform = normalized(preferredTransform, size: naturalSize)
        var size = orientedSize(naturalSize, preferredTransform)
        if rotation != .none {
            let radians = CGFloat(rotation.rawValue) * .pi / 180
            transform = normalized(transform.concatenating(CGAffineTransform(rotationAngle: radians)), size: naturalSize)
            size = orientedSize(naturalSize, transform)
        }
        if flip {
            transform = transform
                .concatenating(CGAffineTransform(scaleX: -1, y: 1))
                .concatenating(CGAffineTransform(translationX: size.width, y: 0))
        }
        return (transform, size)
    }

    /// The container rotation in degrees (0, 90, 180, 270), snapped to the nearest right angle.
    private static func rotationDegrees(of transform: CGAffineTransform) -> Int {
        let degrees = atan2(transform.b, transform.a) * 180 / .pi
        let snapped = Int((degrees / 90).rounded()) * 90
        return ((snapped % 360) + 360) % 360
    }

    /// A positive, finite pixel aspect reduced to its smallest integer ratio; nil for square or invalid.
    private static func reducedAspect(_ aspect: CGSize) -> CGSize? {
        guard aspect.width.isFinite, aspect.height.isFinite, aspect.width > 0, aspect.height > 0 else { return nil }
        let width = Int(aspect.width.rounded()), height = Int(aspect.height.rounded())
        guard width > 0, height > 0, width != height else { return nil }
        let divisor = gcd(width, height)
        return CGSize(width: width / divisor, height: height / divisor)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

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

    static func scaledSize(_ size: CGSize, limit: MaxResolution, allowUpscaling: Bool = false) -> CGSize {
        var factor: CGFloat = 1
        var ceiling = size
        if let box = limit.boundingBox(portrait: size.height > size.width) {
            let fit = min(box.width / size.width, box.height / size.height)
            factor = allowUpscaling ? fit : min(1, fit)
            if allowUpscaling { ceiling = box }
        }
        return CGSize(width: evenFitting(size.width * factor, within: ceiling.width),
                      height: evenFitting(size.height * factor, within: ceiling.height))
    }

    /// The frame to write when the picture is centred on a letterbox/pillarbox canvas.
    /// Without a resolution limit the canvas is the 16:9 (9:16 for portrait) box around the picture.
    static func padded(_ picture: CGSize, mode: PaddingMode, limit: MaxResolution) -> (canvas: CGSize, origin: CGPoint) {
        guard mode != .none else { return (picture, .zero) }
        let portrait = picture.height > picture.width
        let box = limit.boundingBox(portrait: portrait) ?? aspectBox(around: picture, portrait: portrait)
        let width = (mode == .pillarbox || mode == .both) ? max(picture.width, box.width) : picture.width
        let height = (mode == .letterbox || mode == .both) ? max(picture.height, box.height) : picture.height
        let canvas = CGSize(width: even(width), height: even(height))
        let origin = CGPoint(x: floorEven((canvas.width - picture.width) / 2),
                             y: floorEven((canvas.height - picture.height) / 2))
        return (canvas, origin)
    }

    private static func floorEven(_ value: CGFloat) -> CGFloat {
        max(0, (value / 2).rounded(.down) * 2)
    }

    /// The smallest 16:9 (or 9:16) box that holds the picture.
    private static func aspectBox(around picture: CGSize, portrait: Bool) -> CGSize {
        if portrait {
            let height = max(picture.height, picture.width * 16 / 9)
            return CGSize(width: (height * 9 / 16).rounded(), height: height)
        }
        let width = max(picture.width, picture.height * 16 / 9)
        return CGSize(width: width, height: (width * 9 / 16).rounded())
    }

    /// Nearest even value, but never more than `limit` rounded down to even: downscales keep
    /// their aspect as closely as possible and nothing is ever stretched past its ceiling.
    static func evenFitting(_ value: CGFloat, within limit: CGFloat) -> CGFloat {
        min(max(2, (value / 2).rounded() * 2), even(limit))
    }

    /// Encoders require even dimensions for 4:2:0 chroma. Rounds down, so an odd crop
    /// loses a pixel instead of being stretched by one; the tolerance absorbs scaling noise.
    static func even(_ value: CGFloat) -> CGFloat {
        max(2, ((value + 1e-6) / 2).rounded(.down) * 2)
    }
}
