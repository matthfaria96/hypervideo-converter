import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@MainActor
@Suite("Burned-in subtitle is a per-video setting")
struct BurnInSettingsTests {
    @Test func presetsDropButAdoptingKeepsTheBurnIn() {
        var settings = EncodeSettings()
        settings.burnIn = .track(id: 2)
        #expect(settings.presetSettings.burnIn == nil)
        var template = EncodeSettings()
        template.videoCodec = .hevc
        let adopted = settings.adopting(template)
        #expect(adopted.videoCodec == .hevc)
        #expect(adopted.burnIn == .track(id: 2))
    }

    @Test func removingTheBurnedFileClearsTheBurnIn() async throws {
        let env = try TestEnvironment()
        let clip = try await AppTestClip.make(in: env.root, .init(name: "clip"))
        let srt = env.root.appendingPathComponent("extra.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nHi\n".write(to: srt, atomically: true, encoding: .utf8)
        let model = env.makeModel()
        await model.addSources([clip])
        let id = try #require(model.sources.first?.id)
        model.addSubtitleFiles([srt], to: id)
        let file = try #require(model.sources.first?.subtitleFiles.first { $0.url == srt })
        model.update(id) { $0.settings.burnIn = .file(srt) }

        model.removeSubtitleFile(file, from: id)
        #expect(model.sources.first?.settings.burnIn == nil)
    }
}
