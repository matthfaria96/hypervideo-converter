// Renders the 1024px app icon. With a source image, fits it into the standard
// macOS icon squircle (824px with 100px margins) and adds a soft drop shadow.
import AppKit

let args = CommandLine.arguments
let output = args[1]
let source = args.count > 2 ? NSImage(contentsOfFile: args[2]) : nil

let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
    let tile = rect.insetBy(dx: 100, dy: 100)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    if let source {
        source.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        NSGradient(colors: [.systemIndigo, .systemPink, .systemOrange])!.draw(in: shape, angle: -55)
    }
    NSGraphicsContext.restoreGraphicsState()
    return true
}

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
