@preconcurrency import AVFoundation
import CoreImage
import Synchronization

/// Composition instruction carrying what `FilterCompositor` needs for one track.
final class FilterInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let trackID: CMPersistentTrackID
    let sourceSize: CGSize
    let plan: GeometryPlan
    let filters: VideoFilters
    let deinterlace: Bool
    let subtitles: SubtitleBurner?

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, sourceSize: CGSize, plan: GeometryPlan,
         filters: VideoFilters, deinterlace: Bool, subtitles: SubtitleBurner? = nil) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.trackID = trackID
        self.sourceSize = sourceSize
        self.plan = plan
        self.filters = filters
        self.deinterlace = deinterlace
        self.subtitles = subtitles
    }
}

/// Renders each frame through `FrameFilter` on the GPU. AVFoundation creates the
/// compositor and calls it from its own queues; the render context is guarded by a lock.
final class FilterCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private let renderContext = Mutex<AVVideoCompositionRenderContext?>(nil)

    // Formats decoders produce natively, so frames rarely need converting before filtering.
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelFormatType_32BGRA
        ],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable]()
    ]

    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelFormatType_32BGRA
        ],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable]()
    ]

    let supportsWideColorSourceFrames = true
    let supportsHDRSourceFrames = true

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext.withLock { $0 = newRenderContext }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let context = renderContext.withLock { $0 }
        guard
            let instruction = request.videoCompositionInstruction as? FilterInstruction,
            let source = request.sourceFrame(byTrackID: instruction.trackID),
            let context, let output = context.newPixelBuffer()
        else {
            request.finish(with: NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue))
            return
        }
        let image = FrameFilter.render(
            CIImage(cvPixelBuffer: source), sourceSize: instruction.sourceSize, plan: instruction.plan,
            filters: instruction.filters, deinterlace: instruction.deinterlace,
            overlay: instruction.subtitles?.overlay(at: request.compositionTime.seconds, size: instruction.plan.renderSize)
        )
        Self.tag(output, like: context.videoComposition)
        Self.context.render(image, to: output, bounds: CGRect(origin: .zero, size: instruction.plan.renderSize),
                            colorSpace: Self.colorSpace(of: output))
        request.finish(withComposedVideoFrame: output)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    /// Tags the frame with the composition's output color so Core Image converts into it.
    private static func tag(_ buffer: CVPixelBuffer, like composition: AVVideoComposition) {
        let tags: [(CFString, String?)] = [
            (kCVImageBufferColorPrimariesKey, composition.colorPrimaries),
            (kCVImageBufferTransferFunctionKey, composition.colorTransferFunction),
            (kCVImageBufferYCbCrMatrixKey, composition.colorYCbCrMatrix)
        ]
        for case let (key, value?) in tags {
            CVBufferSetAttachment(buffer, key, value as CFString, .shouldPropagate)
        }
    }

    /// The output buffer's tagged color space.
    private static func colorSpace(of buffer: CVPixelBuffer) -> CGColorSpace? {
        guard let attachments = CVBufferCopyAttachments(buffer, .shouldPropagate) else { return nil }
        return CVImageBufferCreateColorSpaceFromAttachments(attachments)?.takeRetainedValue()
    }
}
