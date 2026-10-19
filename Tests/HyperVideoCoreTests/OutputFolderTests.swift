import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Queued jobs after relaunch")
struct OutputFolderTests {
    private let root: URL
    private let source: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hvc-outfolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        source = root.appendingPathComponent("Movie.mov")
        try Data("video".utf8).write(to: source)
    }

    private func job(into folder: URL) -> EncodeJob {
        EncodeJob(source: source, destination: folder.appendingPathComponent("Movie.mp4"),
                  settings: EncodeSettings(), presetName: "Test").bookmarked(securityScoped: false)
    }

    private func relaunched(_ job: EncodeJob) throws -> EncodeJob {
        let saved = try JSONDecoder().decode(EncodeJob.self, from: JSONEncoder().encode(job))
        return saved.resolvingBookmarks(securityScoped: false)
    }

    @Test func destinationFolderThatDoesNotExistYetStaysQueued() throws {
        let folder = root.appendingPathComponent("New Folder/Nested")
        let job = job(into: folder)
        #expect(job.destinationFolderBookmark == nil)
        let resolved = try relaunched(job)
        #expect(resolved.state == .queued)
        #expect(resolved.destination == job.destination)
    }

    @Test func destinationFolderRemovedAfterQueueingStaysQueued() throws {
        let folder = root.appendingPathComponent("Out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let job = job(into: folder)
        #expect(job.destinationFolderBookmark != nil)
        try FileManager.default.removeItem(at: folder)
        #expect(try relaunched(job).state == .queued)
    }

    @Test func destinationUnderAFileFailsClearly() throws {
        let blocker = root.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let resolved = try relaunched(job(into: blocker.appendingPathComponent("Out")))
        guard case .failed(let message) = resolved.state else {
            Issue.record("expected a failed job, got \(resolved.state)")
            return
        }
        #expect(message.contains("destination folder"))
    }

    @Test func missingSourceStillFailsEvenWhenTheFolderIsFine() throws {
        let queued = job(into: root)
        try FileManager.default.removeItem(at: source)
        guard case .failed(let message) = try relaunched(queued).state else {
            Issue.record("expected a failed job")
            return
        }
        #expect(message.contains("Movie.mov"))
    }

    @Test func completedJobsDropTheirBookmarks() {
        var queued = job(into: root)
        #expect(queued.droppingBookmarksWhenCompleted().sourceBookmark != nil)
        queued.state = .completed(outputBytes: 1, elapsed: 1)
        let lean = queued.droppingBookmarksWhenCompleted()
        #expect(lean.sourceBookmark == nil)
        #expect(lean.destinationFolderBookmark == nil)
        #expect(lean.source == queued.source)
        #expect(lean.state == queued.state)
    }

    @Test func failedJobsKeepBookmarksForRetry() {
        var failed = job(into: root)
        failed.state = .failed(message: "x")
        #expect(failed.droppingBookmarksWhenCompleted().sourceBookmark != nil)
    }
}

@Suite("Subtitle lookup for many videos")
struct SidecarBatchTests {
    @Test func matchesLookupPerVideoAndListsEachFolderOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hvc-sidecars-\(UUID().uuidString)")
        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let names = ["A.mov", "A.srt", "A.pt-BR.srt", "B.mov", "B.vtt", "C.mov", "notes.txt"]
        for name in names { try Data("x".utf8).write(to: root.appendingPathComponent(name)) }
        try Data("x".utf8).write(to: other.appendingPathComponent("D.mov"))
        try Data("x".utf8).write(to: other.appendingPathComponent("D.srt"))

        let videos = ["A.mov", "B.mov", "C.mov"].map { root.appendingPathComponent($0) } + [other.appendingPathComponent("D.mov")]
        let batch = SubtitleFile.sidecars(for: videos)
        for video in videos {
            #expect(batch[video, default: []] == SubtitleFile.sidecars(for: video))
        }
        #expect(batch[videos[0]]?.map(\.name) == ["A.pt-BR.srt", "A.srt"])
        #expect(batch[videos[2]] == nil)
        #expect(batch[videos[3]]?.map(\.name) == ["D.srt"])
    }
}
