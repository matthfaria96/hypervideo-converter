import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Media discovery")
struct MediaDiscoveryTests {
    /// Builds a folder tree of empty files; discovery only looks at names and types.
    private func makeTree(_ paths: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HVCScan-\(UUID().uuidString)")
        for path in paths {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return root
    }

    @Test func foldersExpandRecursivelyInFinderOrder() throws {
        let root = try makeTree([
            "Trip/Day 10.mp4", "Trip/Day 2.mov", "Trip/notes.txt", "Trip/.hidden.mov",
            "Trip/Audio/interview.m4a", "Trip/Audio/cover.jpg", "Trip/Bundle.app/Contents/clip.mov"
        ])
        let found = MediaDiscovery.mediaFiles(in: [root.appendingPathComponent("Trip")])
        #expect(found.map(\.lastPathComponent) == ["interview.m4a", "Day 2.mov", "Day 10.mp4"])
    }

    @Test func filesPassThroughAndDuplicatesCollapse() throws {
        let root = try makeTree(["a.mov", "b.txt", "Folder/a2.mp4"])
        let movie = root.appendingPathComponent("a.mov")
        let found = MediaDiscovery.mediaFiles(in: [movie, root.appendingPathComponent("b.txt"), root, movie])
        #expect(found.map(\.lastPathComponent) == ["a.mov", "a2.mp4"])
    }

    @Test func missingPathsAreIgnored() {
        #expect(MediaDiscovery.mediaFiles(in: [URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")]).isEmpty)
    }
}
