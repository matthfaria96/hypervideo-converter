@preconcurrency import AVFoundation

/// Wires reader outputs to writer inputs for every track the settings keep.
struct PipelineFactory {
    let asset: AVURLAsset
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let settings: EncodeSettings
    let subtitleFiles: [SubtitleFile]

    /// A text track to keep: one of the source's own, or an external file.
    enum SubtitleSource {
        case track(AVAssetTrack, SubtitleTrackInfo.Kind)
        case file(SubtitleFile)

        var kind: SubtitleTrackInfo.Kind {
            switch self {
            case .track(_, let kind): kind
            case .file: .subtitle
            }
        }
    }

    func makePumps() async throws -> [SamplePump] {
        var pumps = try await videoPumps()
        pumps += try await audioPumps(firstReportsProgress: pumps.isEmpty)
        pumps += try await subtitlePumps()
        if let main = pumps.first?.input, let pump = try await chapterPump(attachedTo: main) {
            pumps.append(pump)
        }
        return pumps
    }

    /// Puts tracks of one kind in an alternate group so players offer them as choices
    /// and play only the default (the first audio track; no subtitles until picked),
    /// rather than mixing every enabled audio track together.
    func groupAlternates(_ inputs: [AVAssetWriterInput], defaultInput: AVAssetWriterInput?) {
        guard inputs.count > 1 || (defaultInput == nil && !inputs.isEmpty) else { return }
        for input in inputs where input !== defaultInput { input.marksOutputTrackAsEnabled = false }
        let group = AVAssetWriterInputGroup(inputs: inputs, defaultInput: defaultInput)
        if writer.canAdd(group) { writer.add(group) }
    }

    // MARK: Plumbing

    func attach(
        output: AVAssetReaderOutput, input: AVAssetWriterInput, label: String, reportsProgress: Bool,
        transform: SampleTransform? = nil
    ) throws -> SamplePump {
        output.alwaysCopiesSampleData = false
        input.expectsMediaDataInRealTime = false
        guard reader.canAdd(output) else { throw TranscodeError.cannotConfigure("\(label) decoding") }
        guard writer.canAdd(input) else { throw TranscodeError.cannotConfigure("\(label) encoding in \(settings.container.displayName)") }
        reader.add(output)
        writer.add(input)
        return SamplePump(output: output, input: input, label: label, reportsProgress: reportsProgress, transform: transform)
    }
}
