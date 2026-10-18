import CoreGraphics
import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Geometry")
struct GeometryTests {
    let hd = CGSize(width: 1920, height: 1080)

    @Test func identityKeepsSourceSize() {
        let plan = GeometryPlanner.plan(naturalSize: hd, preferredTransform: .identity, crop: .zero,
                                        rotation: .none, flipHorizontal: false, maxResolution: .source)
        #expect(plan.renderSize == hd)
        #expect(plan.transform == .identity)
    }

    @Test func downscalesTo720p() {
        let plan = GeometryPlanner.plan(naturalSize: hd, preferredTransform: .identity, crop: .zero,
                                        rotation: .none, flipHorizontal: false, maxResolution: .hd720)
        #expect(plan.renderSize == CGSize(width: 1280, height: 720))
    }

    @Test func neverUpscales() {
        let plan = GeometryPlanner.plan(naturalSize: CGSize(width: 640, height: 360), preferredTransform: .identity,
                                        crop: .zero, rotation: .none, flipHorizontal: false, maxResolution: .uhd2160)
        #expect(plan.renderSize == CGSize(width: 640, height: 360))
    }

    @Test func rotation90SwapsDimensionsAndStaysInFrame() {
        let plan = GeometryPlanner.plan(naturalSize: hd, preferredTransform: .identity, crop: .zero,
                                        rotation: .cw90, flipHorizontal: false, maxResolution: .source)
        #expect(plan.renderSize == CGSize(width: 1080, height: 1920))
        let mapped = CGRect(origin: .zero, size: hd).applying(plan.transform)
        #expect(abs(mapped.minX) < 0.001 && abs(mapped.minY) < 0.001)
    }

    @Test func portraitPhoneVideoUsesPortraitBox() {
        let phone = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let plan = GeometryPlanner.plan(naturalSize: hd, preferredTransform: phone, crop: .zero,
                                        rotation: .none, flipHorizontal: false, maxResolution: .hd720)
        #expect(plan.renderSize == CGSize(width: 720, height: 1280))
    }

    @Test func cropReducesAndOffsets() {
        let plan = GeometryPlanner.plan(naturalSize: hd, preferredTransform: .identity,
                                        crop: Crop(top: 140, bottom: 140, left: 0, right: 0),
                                        rotation: .none, flipHorizontal: false, maxResolution: .source)
        #expect(plan.renderSize == CGSize(width: 1920, height: 800))
        #expect(CGPoint(x: 0, y: 140).applying(plan.transform) == .zero)
    }

    @Test func absurdCropIsClamped() {
        let crop = GeometryPlanner.clampedCrop(Crop(top: 5000, bottom: 5000, left: -3, right: 0), in: hd)
        #expect(crop.left == 0)
        #expect(1080 - crop.top - crop.bottom >= 16)
    }

    @Test func dimensionsAreEven() {
        #expect(GeometryPlanner.even(721) .truncatingRemainder(dividingBy: 2) == 0)
        #expect(GeometryPlanner.even(1) == 2)
    }

    @Test func flipMirrorsHorizontally() {
        let plan = GeometryPlanner.plan(naturalSize: hd, preferredTransform: .identity, crop: .zero,
                                        rotation: .none, flipHorizontal: true, maxResolution: .source)
        #expect(CGPoint(x: 0, y: 0).applying(plan.transform) == CGPoint(x: 1920, y: 0))
    }
}

@Suite("Settings")
struct SettingsTests {
    @Test func defaultsAreValid() {
        #expect(EncodeSettings().isValid)
    }

    @Test func everyBuiltInPresetIsValid() {
        for preset in BuiltInPresets.all {
            #expect(preset.settings.isValid, "\(preset.name): \(preset.settings.validationIssues)")
        }
    }

    @Test func builtInPresetIDsAreUnique() {
        #expect(Set(BuiltInPresets.all.map(\.id)).count == BuiltInPresets.all.count)
    }

    @Test func proResNeedsMov() {
        var settings = EncodeSettings()
        settings.videoCodec = .proRes422
        settings.container = .mp4
        #expect(!settings.isValid)
        settings.container = .mov
        #expect(settings.isValid)
    }

    @Test func passthroughRejectsGeometry() {
        var settings = EncodeSettings()
        settings.videoCodec = .passthrough
        settings.maxResolution = .hd720
        #expect(!settings.isValid)
    }

    @Test func invalidTrimRejected() {
        var settings = EncodeSettings()
        settings.trim = TrimRange(start: 10, end: 5)
        #expect(!settings.isValid)
    }

    @Test func mixdownFallsBackToSource() {
        #expect(AudioMixdown.surround51.resolved(sourceChannels: 2) == .stereo)
        #expect(AudioMixdown.stereo.resolved(sourceChannels: 1) == .mono)
        #expect(AudioMixdown.surround51.resolved(sourceChannels: 6) == .surround51)
    }

    @Test func settingsRoundTripThroughJSON() throws {
        var settings = EncodeSettings()
        settings.rateControl = .averageBitrate(4_000)
        settings.trim = TrimRange(start: 1, end: 9)
        let decoded = try JSONDecoder().decode(EncodeSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func aacBitrateClamped() {
        #expect(OutputSettingsBuilder.clampedAACBitrate(1_000, channels: 2) == 320)
        #expect(OutputSettingsBuilder.clampedAACBitrate(8, channels: 2) == 32)
    }

    @Test func sdrForcedOnEightBitCodecs() {
        let pq = OutputSettingsBuilder.ColorSpace(primaries: "ITU_R_2020", transfer: "SMPTE_ST_2084_PQ", matrix: "ITU_R_2020")
        #expect(OutputSettingsBuilder.outputColorSpace(for: .h264, source: pq) == .rec709)
        #expect(OutputSettingsBuilder.outputColorSpace(for: .hevc10, source: pq) == pq)
    }
}

@Suite("Jobs and naming")
struct JobTests {
    let folder = URL(fileURLWithPath: "/tmp/out")
    let source = URL(fileURLWithPath: "/videos/Clip.mov")

    @Test func namingAvoidsCollisions() {
        let first = OutputNaming.destination(for: source, in: folder, container: .mp4, fileExists: { _ in false })
        #expect(first.lastPathComponent == "Clip.mp4")
        let second = OutputNaming.destination(for: source, in: folder, container: .mp4, taken: [first], fileExists: { _ in false })
        #expect(second.lastPathComponent == "Clip 2.mp4")
    }

    @Test func neverOverwritesSource() {
        let sameFolder = source.deletingLastPathComponent()
        let url = OutputNaming.destination(for: source, in: sameFolder, container: .mov, fileExists: { _ in false })
        #expect(url != source)
    }

    @Test func runningJobsRequeueAfterRelaunch() {
        let job = EncodeJob(source: source, destination: folder, settings: .init(), presetName: "x")
            .with(state: .running(progress: 0.4))
        #expect(job.restoredAfterRelaunch().state == .queued)
        #expect(job.with(state: .cancelled).restoredAfterRelaunch().state == .cancelled)
    }

    @Test func fourCCFriendlyNames() {
        #expect(FourCC.string(0x6876_6331) == "HEVC")
        #expect(FourCC.string(0x6176_6331) == "H.264")
    }
}
