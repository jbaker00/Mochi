// Renders Mochi's app icon using the same drawing code as the app (PetView).
// Usage: swiftc scripts/IconGen/main.swift Sources/PetView.swift Sources/Models.swift -o /tmp/icongen && /tmp/icongen <AppIcon.appiconset dir>
import Cocoa

func render(size px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctxNS = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctxNS
    let ctx = ctxNS.cgContext
    let S = CGFloat(px) / 1024   // design in a 1024pt canvas

    ctx.scaleBy(x: S, y: S)
    ctx.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    // macOS icon grid: 824pt tile centered, ~185pt corner radius
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.30).cgColor)
    NSColor(hex: 0xBDE8C8).setFill()
    tilePath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    tilePath.addClip()
    NSGradient(colors: [NSColor(hex: 0xFFD9E2), NSColor(hex: 0xFFEFD9), NSColor(hex: 0xC9F0D3)])!
        .draw(in: tile, angle: -90)
    // grassy hill Mochi stands on
    let hill = NSBezierPath()
    hill.move(to: NSPoint(x: 80, y: 330))
    hill.curve(to: NSPoint(x: 944, y: 330), controlPoint1: NSPoint(x: 330, y: 400), controlPoint2: NSPoint(x: 700, y: 400))
    hill.line(to: NSPoint(x: 944, y: 80)); hill.line(to: NSPoint(x: 80, y: 80)); hill.close()
    NSColor(hex: 0x9EDB9A).setFill(); hill.fill()
    // little sparkles in the sky
    for (x, y, r) in [(250.0, 760.0, 22.0), (790.0, 800.0, 16.0), (820.0, 640.0, 12.0), (205.0, 590.0, 11.0)] {
        let p = NSBezierPath()
        for k in 0..<8 {
            let a = CGFloat(k) * .pi / 4
            let rr = k % 2 == 0 ? r : r * 0.35
            let pt = NSPoint(x: x + cos(a) * rr, y: y + sin(a) * rr)
            if k == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
        p.close(); NSColor(hex: 0xFFFFFF, alpha: 0.9).setFill(); p.fill()
    }
    ctx.restoreGState()

    // Mochi itself, drawn by the app's PetView (excited = happy face)
    let view = PetView(frame: NSRect(x: 0, y: 0, width: 120, height: 100))
    view.mood = .excited
    let petScale: CGFloat = 6.4
    ctx.saveGState()
    ctx.translateBy(x: 512 - 60 * petScale - 15, y: 330 - view.groundY * petScale - 6)
    ctx.scaleBy(x: petScale, y: petScale)
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: 120, height: 100))
    // PetView clears its bounds with .copy; draw into a transparency layer so the background survives
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    view.draw(view.bounds)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.appiconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! render(size: px).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
print("Wrote icons to \(out.path)")
