@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

/// ENG-04 (engine half): free space is checked before any work starts.
@Suite("Disk space", .serialized)
struct DiskSpaceTests {
    @Test func requiredBytesDependsOnContainer() {
        #expect(DiskSpace.requiredBytes(sourceBytes: 1_000, container: .mkv) == 2_000)
        #expect(DiskSpace.requiredBytes(sourceBytes: 1_000, container: .mp4) == 1_000)
        #expect(DiskSpace.requiredBytes(sourceBytes: 1_000, container: .mov) == 1_000)
        #expect(DiskSpace.requiredBytes(sourceBytes: .max, container: .mkv) == .max)
    }

    @Test func availableCapacityReadsTheVolume() {
        let capacity = DiskSpace.availableCapacity(at: FileManager.default.temporaryDirectory)
        #expect((capacity ?? 0) > 0)
    }

    @Test func failsBeforeEncodingWhenSpaceIsShort() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 240), seconds: 1)
        let engine = TranscodeEngine(availableCapacity: { _ in 10 })
        await #expect {
            _ = try await engine.run(source: source, destination: dir.appendingPathComponent("out.mp4"),
                                     settings: EncodeSettings()) { _ in }
        } throws: { error in
            guard case TranscodeError.insufficientSpace(let required, let available) = error else { return false }
            return available == 10 && required > 10
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".hypervideo-") }
        #expect(leftovers.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("out.mp4").path))
    }

    @Test func unknownCapacityDoesNotBlock() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 240), seconds: 1)
        let engine = TranscodeEngine(availableCapacity: { _ in nil })
        let bytes = try await engine.run(source: source, destination: dir.appendingPathComponent("out.mp4"),
                                         settings: EncodeSettings()) { _ in }
        #expect(bytes > 0)
    }
}
