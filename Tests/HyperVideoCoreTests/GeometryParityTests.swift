import CoreGraphics
import Testing
@testable import HyperVideoCore

@Suite("Geometry parity")
struct GeometryParityTests {
    private func plan(
        _ size: CGSize, limit: MaxResolution = .source, rotation: Rotation = .none,
        picture: PictureOptions = PictureOptions(), par: CGSize = CGSize(width: 1, height: 1)
    ) -> GeometryPlan {
        GeometryPlanner.plan(
            naturalSize: size, preferredTransform: .identity, crop: .zero, rotation: rotation,
            flipHorizontal: false, maxResolution: limit, picture: picture, sourcePixelAspect: par
        )
    }

    @Test(arguments: [CGSize(width: 1920, height: 1080), CGSize(width: 1280, height: 720), CGSize(width: 640, height: 360)])
    func defaultsReproduceTodaysPlan(size: CGSize) {
        let result = plan(size, limit: .hd720)
        let expected = GeometryPlanner.scaledSize(size, limit: .hd720)
        #expect(result.renderSize == expected)
        #expect(result.pictureRect == CGRect(origin: .zero, size: expected))
        #expect(result.pixelAspect == nil)
    }

    @Test func upscalingAndEightK() {
        let hd = CGSize(width: 1280, height: 720)
        #expect(GeometryPlanner.scaledSize(hd, limit: .fhd1080, allowUpscaling: true) == CGSize(width: 1920, height: 1080))
        #expect(GeometryPlanner.scaledSize(hd, limit: .fhd1080, allowUpscaling: false) == hd)
        #expect(GeometryPlanner.scaledSize(CGSize(width: 3840, height: 2160), limit: .uhd4320, allowUpscaling: true)
                == CGSize(width: 7680, height: 4320))
        #expect(GeometryPlanner.scaledSize(hd, limit: .source, allowUpscaling: true) == hd)
    }

    @Test func paddingGeometry() {
        let letter = GeometryPlanner.padded(CGSize(width: 1920, height: 800), mode: .letterbox, limit: .fhd1080)
        #expect(letter.canvas == CGSize(width: 1920, height: 1080))
        #expect(letter.origin == CGPoint(x: 0, y: 140))
        let pillar = GeometryPlanner.padded(CGSize(width: 1440, height: 1080), mode: .pillarbox, limit: .fhd1080)
        #expect(pillar.canvas == CGSize(width: 1920, height: 1080))
        #expect(pillar.origin == CGPoint(x: 240, y: 0))
        let both = GeometryPlanner.padded(CGSize(width: 1440, height: 800), mode: .both, limit: .fhd1080)
        #expect(both.canvas == CGSize(width: 1920, height: 1080))
        #expect(both.origin == CGPoint(x: 240, y: 140))
        let none = GeometryPlanner.padded(CGSize(width: 1440, height: 800), mode: .none, limit: .fhd1080)
        #expect(none.canvas == CGSize(width: 1440, height: 800))
        #expect(none.origin == .zero)
        let free = GeometryPlanner.padded(CGSize(width: 1920, height: 800), mode: .letterbox, limit: .source)
        #expect(free.canvas == CGSize(width: 1920, height: 1080))
        #expect(free.origin == CGPoint(x: 0, y: 140))
    }

    @Test func planWithPaddingKeepsPictureSize() {
        var options = PictureOptions()
        options.padding = Padding(mode: .letterbox, color: .white)
        let result = plan(CGSize(width: 1920, height: 800), limit: .fhd1080, picture: options)
        #expect(result.renderSize == CGSize(width: 1920, height: 1080))
        #expect(result.pictureRect == CGRect(x: 0, y: 140, width: 1920, height: 800))
    }

    @Test func anamorphicAutomaticTagsPixelAspect() {
        var options = PictureOptions()
        options.anamorphic = .automatic
        let size = CGSize(width: 640, height: 480)
        let none = plan(size)
        let auto = plan(size, picture: options, par: CGSize(width: 4, height: 3))
        #expect(auto.pixelAspect == CGSize(width: 4, height: 3))
        #expect(abs(auto.renderSize.width * 4 / 3 - none.renderSize.width) <= 2)
        #expect(auto.renderSize.height == none.renderSize.height)
    }

    @Test func anamorphicIgnoredWhenRotatedOrSquare() {
        var options = PictureOptions()
        options.anamorphic = .automatic
        let size = CGSize(width: 640, height: 480)
        let rotated = plan(size, rotation: .cw90, picture: options, par: CGSize(width: 4, height: 3))
        #expect(rotated.pixelAspect == nil)
        let square = plan(size, picture: options)
        #expect(square.pixelAspect == nil)
        #expect(square.renderSize == plan(size).renderSize)
    }
}
