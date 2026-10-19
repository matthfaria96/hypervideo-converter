import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Queue bookmarks")
struct BookmarkTests {
    private let root: URL
    private let source: URL
    private let output: URL
    private let subtitle: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hvc-bookmarks-\(UUID().uuidString)")
        output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        source = root.appendingPathComponent("Movie.mov")
        subtitle = root.appendingPathComponent("Movie.srt")
        try Data("video".utf8).write(to: source)
        try Data("1\n00:00:00,000 --> 00:00:01,000\nHi\n".utf8).write(to: subtitle)
    }

    private func job() -> EncodeJob {
        EncodeJob(
            source: source, destination: output.appendingPathComponent("Movie.mp4"),
            settings: EncodeSettings(), presetName: "Test",
            subtitleFiles: [SubtitleFile(url: subtitle, language: "en")]
        ).bookmarked(securityScoped: false)
    }

    private func roundTrip(_ job: EncodeJob) throws -> EncodeJob {
        try JSONDecoder().decode(EncodeJob.self, from: JSONEncoder().encode(job))
    }

    @Test func bookmarksSurviveEncodeDecode() throws {
        let original = job()
        #expect(original.sourceBookmark != nil)
        #expect(original.destinationFolderBookmark != nil)
        #expect(original.subtitleFiles?.first?.bookmark != nil)
        let decoded = try roundTrip(original)
        #expect(decoded == original)
        let resolved = decoded.resolvingBookmarks(securityScoped: false)
        #expect(resolved.state == .queued)
        #expect(resolved.source.standardizedFileURL.resolvingSymlinksInPath().path
            == source.resolvingSymlinksInPath().path)
    }

    @Test func legacyQueueWithoutBookmarksDecodesAndGainsBookmarks() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","source":"\(source.absoluteString)",
          "destination":"\(output.appendingPathComponent("Movie.mp4").absoluteString)",
          "settings":\(String(decoding: try JSONEncoder().encode(EncodeSettings()), as: UTF8.self)),
          "presetName":"Old","state":{"queued":{}},"createdAt":0,
          "subtitleFiles":[{"url":"\(subtitle.absoluteString)","language":"en"}]}]
        """
        let jobs = try JSONDecoder().decode([EncodeJob].self, from: Data(legacy.utf8))
        let job = try #require(jobs.first)
        #expect(job.sourceBookmark == nil)
        #expect(job.subtitleFiles?.first?.bookmark == nil)
        let resolved = job.resolvingBookmarks(securityScoped: false)
        #expect(resolved.state == .queued)
        #expect(resolved.sourceBookmark != nil)
        #expect(resolved.destinationFolderBookmark != nil)
        #expect(resolved.subtitleFiles?.first?.bookmark != nil)
    }

    @Test func movedSourceIsFollowed() throws {
        let original = try roundTrip(job())
        let moved = root.appendingPathComponent("Renamed.mov")
        try FileManager.default.moveItem(at: source, to: moved)
        let resolved = original.resolvingBookmarks(securityScoped: false)
        #expect(resolved.state == .queued)
        #expect(resolved.source.lastPathComponent == "Renamed.mov")
    }

    @Test func missingFilesFailTheJobWithAClearMessage() throws {
        let original = try roundTrip(job())
        try FileManager.default.removeItem(at: source)
        try FileManager.default.removeItem(at: subtitle)
        let resolved = original.resolvingBookmarks(securityScoped: false)
        guard case .failed(let message) = resolved.state else {
            Issue.record("expected failure, got \(resolved.state)")
            return
        }
        #expect(message.contains("Movie.mov"))
        #expect(message.contains("Movie.srt"))
    }

    @Test func missingDestinationFolderFailsTheJob() throws {
        let original = try roundTrip(job())
        try FileManager.default.removeItem(at: output)
        let resolved = original.resolvingBookmarks(securityScoped: false)
        guard case .failed(let message) = resolved.state else {
            Issue.record("expected failure, got \(resolved.state)")
            return
        }
        #expect(message.contains("destination folder"))
    }

    @Test func finishedJobsAreLeftAlone() throws {
        let done = job().with(state: .completed(outputBytes: 1, elapsed: 1))
        try FileManager.default.removeItem(at: source)
        #expect(done.resolvingBookmarks(securityScoped: false) == done)
    }

    @Test func plainProcessIsNotSandboxed() {
        #expect(FileBookmarks.isSandboxed == false)
    }
}
