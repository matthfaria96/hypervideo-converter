@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

@Suite("Filter parity transcodes", .serialized)
struct FilterParityTranscodeTests {
    struct Case: Sendable, CustomStringConvertible {
        let description: String
        let configure: @Sendable (inout VideoFilters) -> Void
    }

    static let cases: [Case] = [
        Case(description: "bob") { $0.deinterlace = .always; $0.deinterlaceMethod = .bob },
        Case(description: "hqdn3d grain") { $0.denoise = .verystrong; $0.denoiseFilter = .hqdn3d; $0.denoiseTune = .grain },
        Case(description: "chroma smooth") { $0.chromaSmooth = .medium; $0.chromaSmoothTune = .wide },
        Case(description: "unsharp coarse") { $0.sharpen = .strong; $0.sharpenFilter = .unsharp; $0.sharpenTune = .coarse },
        Case(description: "lapsharp film") { $0.sharpen = .ultralight; $0.sharpenFilter = .lapsharp; $0.sharpenTune = .film }
    ]

    @Test(arguments: cases)
    func encodesWithFilter(_ item: Case) async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 1)
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.audioCodec = .none
        item.configure(&settings.filters)
        let output = dir.appendingPathComponent("out.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: output, settings: settings) { _ in }
        let info = try await MediaInspector.inspect(output)
        #expect(info.displaySize == CGSize(width: 320, height: 180))
        #expect(abs(info.duration - 1) < 0.3)
    }

    @Test func bobCleansInterlacedSource() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.makeInterlacedComb(in: dir)
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.audioCodec = .none
        settings.filters.deinterlace = .always
        settings.filters.deinterlaceMethod = .bob
        let output = dir.appendingPathComponent("bob.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: output, settings: settings) { _ in }
        #expect(try await DeinterlaceIntegrationTests.combing(in: output) < 20)
    }
}
