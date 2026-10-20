@preconcurrency import AVFoundation
import Synchronization
import Testing
@testable import HyperVideoCore

/// ENG-02: the output name is resolved again at the moment of the final move.
@Suite("Final move", .serialized)
struct FinalMoveTests {
    private func encodeWithCollision(container: ContainerFormat) async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 240), seconds: 1)
        var settings = EncodeSettings()
        settings.container = container
        let ext = container.fileExtension
        let destination = dir.appendingPathComponent("out.\(ext)")
        let foreign = Data("foreign".utf8)
        let wrote = Mutex(false)
        let output = try await TranscodeEngine().transcode(source: source, destination: destination, settings: settings) { _ in
            let first = wrote.withLock { done -> Bool in
                defer { done = true }
                return !done
            }
            if first { try? foreign.write(to: destination) }
        }
        #expect(output.url == dir.appendingPathComponent("out 2.\(ext)"))
        #expect(output.bytes > 0)
        _ = try await MediaInspector.inspect(output.url)
        #expect(try Data(contentsOf: destination) == foreign)
    }

    @Test func destinationCreatedMidEncodeGetsUniqueName() async throws {
        try await encodeWithCollision(container: .mp4)
    }

    @Test func destinationCreatedMidEncodeGetsUniqueNameMKV() async throws {
        try await encodeWithCollision(container: .mkv)
    }

    @Test func runStillReturnsBytes() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 240), seconds: 1)
        let bytes = try await TranscodeEngine().run(source: source, destination: dir.appendingPathComponent("plain.mp4"),
                                                    settings: EncodeSettings()) { _ in }
        #expect(bytes > 0)
    }
}
