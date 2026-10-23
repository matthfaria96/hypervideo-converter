import Foundation
import HyperVideoCore
import Testing
@testable import HyperVideoConverter

@Suite("Status presentation")
@MainActor
struct StatusPresentationTests {
    @Test func everyJobStateHasItsOwnLabelSymbolAndTint() {
        let states: [JobState] = [.queued, .running(progress: 0.3), .completed(outputBytes: 1, elapsed: 1),
                                  .failed(message: "x"), .cancelled]
        let looks = states.map(JobStatusLook.init)
        #expect(Set(looks.map(\.title)).count == states.count)
        #expect(Set(looks.map(\.symbol)).count == states.count)
        #expect(JobStatusLook(.completed(outputBytes: 1, elapsed: 1)).tone == .success)
        #expect(JobStatusLook(.failed(message: "x")).tone == .danger)
        #expect(JobStatusLook(.running(progress: 0)).tone == .accent)
        #expect(JobStatusLook(.running(progress: 0)).isLive)
        #expect(!JobStatusLook(.queued).isLive)
    }

    @Test func sizeChangeTagSaysSmallerOrLarger() {
        let smaller = try! #require(SizeChangeLook(before: 100, after: 60))
        #expect(smaller.text == "−40%" && smaller.tone == .success)
        let larger = try! #require(SizeChangeLook(before: 100, after: 250))
        #expect(larger.text == "+150%" && larger.tone == .warning)
        #expect(SizeChangeLook(before: 100, after: 100)?.tone == .neutral)
        #expect(SizeChangeLook(before: 0, after: 10) == nil)
    }

    @Test func jobsKnowWhichModeMadeThem() {
        var settings = EncodeSettings()
        #expect(JobKindLook(settings: settings, presetID: nil).kind == .convert)
        #expect(JobKindLook(settings: settings, presetID: QualityProfile.balanced.compressPresetID).kind == .compress)
        settings.upscale = UpscaleSettings()
        #expect(JobKindLook(settings: settings, presetID: nil).kind == .upscale)
    }

    @Test func historyMarksTheLastRunAsNewEvenAfterTheBannerIsDismissed() throws {
        let model = try TestEnvironment().makeModel()
        let old = EncodeJob(source: URL(fileURLWithPath: "/tmp/a.mov"), destination: URL(fileURLWithPath: "/tmp/a.mp4"),
                            settings: EncodeSettings(), presetName: "T")
        model.setSources([WorkspaceTests.source("b.mov")])
        model.convertAll()
        let fresh = EncodeJob(source: URL(fileURLWithPath: "/tmp/b.mov"), destination: URL(fileURLWithPath: "/tmp/b.mp4"),
                              settings: EncodeSettings(), presetName: "T")
        model.dismissFinishedBatch()
        #expect(model.isFromLastRun(fresh))
        #expect(!model.isFromLastRun(old))
        model.queue.cancelAll()
    }

    @Test func openingHistoryClearsTheNewResultsBadge() throws {
        let model = try TestEnvironment().makeModel()
        model.ui.hasUnseenResults = true
        model.presentedPage = .favorites
        #expect(model.ui.hasUnseenResults)
        model.presentedPage = .history
        #expect(!model.ui.hasUnseenResults)
    }

    @Test func containersHaveDistinctTints() {
        let tints = ["MP4", "MOV", "MKV", "M4V"].map { ContainerTag.tone(for: $0) }
        #expect(Set(tints).count == 4)
        #expect(ContainerTag.tone(for: "AVI") == .neutral)
    }
}
