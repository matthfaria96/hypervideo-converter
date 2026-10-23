@preconcurrency import AVFoundation
import Foundation

/// Upscales a video's frames with Real-ESRGAN in batches, so the work folder never holds
/// more than one batch of PNGs, encodes them at the plan's average bitrate (a predictable
/// size) and finally adds the source's audio back, untouched.
struct VideoUpscaler: Sendable {
    let backend: UpscaleBackend
    /// Frames per batch: a few hundred MB of PNGs at most.
    static let batchSize = 48
    /// Share of the progress bar for the final mux.
    static let muxShare = 0.03

    struct Job: Sendable {
        let asset: AVURLAsset
        let range: CMTimeRange
        let upscale: UpscaleSettings
        let plan: UpscalePlan
        let workDir: URL
        let output: URL
        let fileType: AVFileType
    }

    func run(_ job: Job, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let track = try await job.asset.loadTracks(withMediaType: .video).first else { throw UpscaleError.noVideo }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let size = Self.encodedSize(plan: job.plan, natural: natural, transform: transform)
        let video = job.workDir.appendingPathComponent("upscaled.mov")
        let total = max(1, job.plan.frameCount)

        let colors = Self.colorProperties(try await track.load(.formatDescriptions).first, height: natural.height)
        let pass = try FramePass(track: track, asset: job.asset, range: job.range, size: size, transform: transform,
                                 upscale: job.upscale, plan: job.plan, colors: colors, output: video)
        try await pass.run(runner: UpscaylRunner(backend: backend), workDir: job.workDir) { done in
            progress(min(1, Double(done) / Double(total)) * (1 - Self.muxShare))
        }
        try await Self.mux(video: video, source: job.asset, range: job.range, to: job.output, fileType: job.fileType)
        progress(1)
    }

    /// The source's colour tags, so the encoder converts the frames back to YCbCr the way
    /// they were decoded; untagged sources get what AVFoundation assumes for them
    /// (BT.709 for HD, BT.601 below 720 lines).
    static func colorProperties(_ format: CMFormatDescription?, height: CGFloat) -> [String: String] {
        let hd = height >= 720
        func tag(_ key: CFString, _ fallback: String) -> String {
            format.flatMap { CMFormatDescriptionGetExtension($0, extensionKey: key) as? String } ?? fallback
        }
        return [
            AVVideoColorPrimariesKey: tag(kCMFormatDescriptionExtension_ColorPrimaries,
                                          hd ? AVVideoColorPrimaries_ITU_R_709_2 : AVVideoColorPrimaries_SMPTE_C),
            AVVideoTransferFunctionKey: tag(kCMFormatDescriptionExtension_TransferFunction, AVVideoTransferFunction_ITU_R_709_2),
            AVVideoYCbCrMatrixKey: tag(kCMFormatDescriptionExtension_YCbCrMatrix,
                                       hd ? AVVideoYCbCrMatrix_ITU_R_709_2 : AVVideoYCbCrMatrix_ITU_R_601_4),
        ]
    }

    /// The writer's size: the plan's display size, swapped back when the track is rotated.
    static func encodedSize(plan: UpscalePlan, natural: CGSize, transform: CGAffineTransform) -> CGSize {
        let rotated = abs(transform.b) == 1 && abs(transform.c) == 1
        return rotated ? CGSize(width: plan.outputSize.height, height: plan.outputSize.width) : plan.outputSize
    }

    /// The upscaled picture plus every audio track of the source over the same range, copied as is.
    static func mux(video: URL, source: AVURLAsset, range: CMTimeRange, to output: URL, fileType: AVFileType) async throws {
        let composition = AVMutableComposition()
        let upscaled = AVURLAsset(url: video)
        guard let picture = try await upscaled.loadTracks(withMediaType: .video).first,
              let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw UpscaleError.failed("the upscaled video is empty") }
        let pictureRange = try await picture.load(.timeRange)
        try target.insertTimeRange(pictureRange, of: picture, at: .zero)
        target.preferredTransform = try await picture.load(.preferredTransform)
        for audio in try await source.loadTracks(withMediaType: .audio) {
            guard let lane = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            try lane.insertTimeRange(range, of: audio, at: .zero)
            lane.languageCode = try await audio.load(.languageCode)
            lane.extendedLanguageTag = try await audio.load(.extendedLanguageTag)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw UpscaleError.failed("couldn't prepare the final file")
        }
        try await session.export(to: output, as: fileType)
    }
}

/// Reads, upscales and encodes the frames, batch by batch.
private final class FramePass: @unchecked Sendable {
    private let reader: AVAssetReader
    private let readerOutput: AVAssetReaderTrackOutput
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let range: CMTimeRange
    private let upscale: UpscaleSettings
    private let size: CGSize

    init(track: AVAssetTrack, asset: AVURLAsset, range: CMTimeRange, size: CGSize, transform: CGAffineTransform,
         upscale: UpscaleSettings, plan: UpscalePlan, colors: [String: String], output: URL) throws {
        reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)
        writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(
            size: size, upscale: upscale, plan: plan, colors: colors))
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        self.range = range
        self.upscale = upscale
        self.size = size
    }

    static func videoSettings(size: CGSize, upscale: UpscaleSettings, plan: UpscalePlan,
                              colors: [String: String]) -> [String: Any] {
        [
            AVVideoColorPropertiesKey: colors,
            AVVideoCodecKey: upscale.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(plan.videoBitrate),
                AVVideoExpectedSourceFrameRateKey: plan.frameRate,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ],
        ]
    }

    func run(runner: UpscaylRunner, workDir: URL, progress: @escaping @Sendable (Int) -> Void) async throws {
        guard reader.startReading() else { throw TranscodeError.readerFailed(reader.error?.localizedDescription ?? "") }
        guard writer.startWriting() else { throw TranscodeError.writerFailed(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)
        defer { if reader.status == .reading { reader.cancelReading() } }
        var done = 0
        var batch = 0
        while true {
            try Task.checkCancellation()
            let folders = try Self.batchFolders(in: workDir, batch: batch)
            let times = try readBatch(into: folders.input)
            guard !times.isEmpty else { break }
            let before = done
            try await runner.upscale(folder: folders.input, into: folders.output, model: upscale.model,
                                     scale: upscale.scale, size: size) { progress(before + $0) }
            try await appendBatch(from: folders.output, times: times)
            done += times.count
            progress(done)
            try? FileManager.default.removeItem(at: folders.input.deletingLastPathComponent())
            batch += 1
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TranscodeError.writerFailed(writer.error?.localizedDescription ?? "the upscaled video wasn't finished")
        }
    }

    private static func batchFolders(in workDir: URL, batch: Int) throws -> (input: URL, output: URL) {
        let root = workDir.appendingPathComponent("frames-\(batch)", isDirectory: true)
        let input = root.appendingPathComponent("in", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return (input, output)
    }

    /// Writes up to one batch of decoded frames as PNGs, returning their times from the range start.
    private func readBatch(into folder: URL) throws -> [CMTime] {
        var times: [CMTime] = []
        while times.count < VideoUpscaler.batchSize, let sample = readerOutput.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            try FrameFiles.writePNG(buffer, to: folder.appendingPathComponent(FrameFiles.name(times.count)))
            times.append(CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample), range.start))
        }
        if times.isEmpty, reader.status == .failed {
            throw TranscodeError.readerFailed(reader.error?.localizedDescription ?? "")
        }
        return times
    }

    private func appendBatch(from folder: URL, times: [CMTime]) async throws {
        guard let pool = adaptor.pixelBufferPool else { throw UpscaleError.failed("the encoder didn't start") }
        for (index, time) in times.enumerated() {
            let buffer = try FrameFiles.readPNG(folder.appendingPathComponent(FrameFiles.name(index)), pool: pool)
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            }
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw TranscodeError.writerFailed(writer.error?.localizedDescription ?? "couldn't add an upscaled frame")
            }
        }
    }
}
