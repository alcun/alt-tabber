// Draws the app icon: three window cards fanned out on a deep blue squircle.
// Run: swift scripts/icon.swift Resources/AppIcon.icns
import AppKit

func draw(_ size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let s = size / 1024
        // Apple's grid: the shape sits inside a 824pt square with a 185pt corner radius.
        let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let squircle = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.shadowBlurRadius = 24 * s
        shadow.set()
        NSColor(srgbRed: 0.16, green: 0.19, blue: 0.52, alpha: 1).setFill()
        squircle.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.42, blue: 0.98, alpha: 1),
                   ending: NSColor(srgbRed: 0.15, green: 0.16, blue: 0.50, alpha: 1))!.draw(in: squircle, angle: -90)

        // Back to front: each card a little higher, further right and brighter.
        let cards: [(dx: CGFloat, dy: CGFloat, alpha: CGFloat)] = [(-70, -70, 0.28), (0, 0, 0.5), (70, 70, 1)]
        for (i, card) in cards.enumerated() {
            let rect = NSRect(x: (297 + card.dx) * s, y: (347 + card.dy) * s, width: 430 * s, height: 330 * s)
            let path = NSBezierPath(roundedRect: rect, xRadius: 44 * s, yRadius: 44 * s)
            NSGraphicsContext.current?.saveGraphicsState()
            let cardShadow = NSShadow()
            cardShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            cardShadow.shadowOffset = NSSize(width: 0, height: -8 * s)
            cardShadow.shadowBlurRadius = 20 * s
            cardShadow.set()
            NSColor.white.withAlphaComponent(card.alpha).setFill()
            path.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            guard i == cards.count - 1 else { continue }
            // The front card gets a title bar with the three traffic lights.
            let colors = [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                          NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                          NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)]
            for (j, color) in colors.enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.minX + (40 + CGFloat(j) * 46) * s, y: rect.maxY - 66 * s,
                                            width: 28 * s, height: 28 * s)).fill()
            }
            NSColor(srgbRed: 0.2, green: 0.25, blue: 0.62, alpha: 0.16).setFill()
            for (k, width) in [300.0, 220.0, 260.0].enumerated() {
                NSBezierPath(roundedRect: NSRect(x: rect.minX + 40 * s, y: rect.maxY - (130 + CGFloat(k) * 52) * s,
                                                 width: CGFloat(width) * s, height: 24 * s), xRadius: 12 * s, yRadius: 12 * s).fill()
            }
        }
        return true
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(px).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()
try? FileManager.default.copyItem(at: iconset.appendingPathComponent("icon_512x512@2x.png"),
                                  to: out.deletingLastPathComponent().appendingPathComponent("AppIcon.png"))
