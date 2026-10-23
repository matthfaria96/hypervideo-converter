import Foundation
import HyperVideoCore
import Testing
@testable import HyperVideoConverter

@Suite("AI Upscale mode", .serialized)
@MainActor
struct UpscaleModeTests {
    private func makeModel(_ count: Int = 2) throws -> (AppModel, TestEnvironment) {
        let env = try TestEnvironment()
        let model = env.makeModel()
        model.setSources((0..<count).map { WorkspaceTests.source("v\($0).mov") })
        return (model, env)
    }

    @Test func switchingThroughUpscaleKeepsEveryVideosSettings() throws {
        let (model, _) = try makeModel()
        model.update(model.sources[0].id) { $0.settings.videoCodec = .proRes422; $0.settings.container = .mov }
        let before = model.sources.map(\.settings)
        model.setMode(.upscale)
        #expect(model.mode == .upscale)
        model.setMode(.convert)
        #expect(model.sources.map(\.settings) == before)
    }

    @Test func compressThenUpscaleRestoresConvertSettings() throws {
        let (model, _) = try makeModel()
        let before = model.sources.map(\.settings)
        model.setMode(.compress)
        model.setMode(.upscale)
        model.setMode(.convert)
        #expect(model.sources.map(\.settings) == before)
    }

    @Test func upscaleJobsCarryTheUpscaleSettingsAsMP4() throws {
        let (model, _) = try makeModel(1)
        model.update(model.sources[0].id) { $0.settings.container = .mkv }
        model.setMode(.upscale)
        var upscale = UpscaleSettings()
        upscale.scale = .x3
        model.upscaleSettings = upscale
        model.enqueue([model.sources[0].id])
        let job = try #require(model.queue.jobs.first)
        #expect(job.settings.upscale == upscale)
        #expect(job.destination.pathExtension == "mp4")
        #expect(job.presetName.contains("3×"))
    }

    @Test func convertJobsDontUpscale() throws {
        let (model, _) = try makeModel(1)
        model.enqueue([model.sources[0].id])
        #expect(model.queue.jobs.first?.settings.upscale == nil)
    }

    @Test func estimateSumsEveryAnalysedVideo() throws {
        let (model, _) = try makeModel(2)
        model.setMode(.upscale)
        let estimate = model.upscaleEstimate
        #expect(estimate.count == 2)
        let one = UpscalePlan(info: try #require(model.sources[0].info), settings: model.upscaleSettings)
        #expect(estimate.predictedBytes == one.predictedBytes * 2)
        #expect(estimate.sourceBytes == one.sourceBytes * 2)
        #expect(abs(estimate.seconds - one.estimatedSeconds * 2) < 0.001)
    }

    @Test func selectionNarrowsTheEstimate() throws {
        let (model, _) = try makeModel(3)
        model.setMode(.upscale)
        model.selectedIDs = [model.sources[1].id]
        #expect(model.upscaleEstimate.count == 1)
    }

    @Test func buttonSaysUpscale() throws {
        let (model, _) = try makeModel(2)
        model.setMode(.upscale)
        #expect(model.convertButtonTitle == String(localized: "Upscale 2 Videos"))
    }

    @Test func settingsPersistAcrossLaunches() throws {
        let env = try TestEnvironment()
        var upscale = UpscaleSettings()
        upscale.model = .digitalArt
        env.makeModel().upscaleSettings = upscale
        #expect(env.makeModel().upscaleSettings.model == .digitalArt)
    }

    @Test func launchArgumentOpensUpscale() throws {
        let env = try TestEnvironment()
        env.defaults.set("upscale", forKey: "InitialSection")
        #expect(env.makeModel().mode == .upscale)
    }
}
