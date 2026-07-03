#!/usr/bin/env swift
import AppKit

// Renders the app icon: orange→pink gradient rounded square + white lasso symbol.
// Draws into an explicitly-sized NSBitmapImageRep — NSImage.lockFocus would
// render at 2x on retina displays and iconutil rejects wrong pixel sizes.
let iconset = "assets/icon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.05
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.15, alpha: 1),
        ending: NSColor(calibratedRed: 0.95, green: 0.2, blue: 0.5, alpha: 1)
    )!
    gradient.draw(in: path, angle: -60)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "lasso.badge.sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let symbolRect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: symbolRect)
        symbolRect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        let drawSize = NSSize(width: s * 0.62, height: s * 0.62 * symbol.size.height / symbol.size.width)
        tinted.draw(in: NSRect(
            x: (s - drawSize.width) / 2, y: (s - drawSize.height) / 2,
            width: drawSize.width, height: drawSize.height
        ))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Valid iconset entries: 16, 32, 128, 256, 512 — each with an @2x variant
// at double pixels. A size-px render serves as icon_<size> and icon_<size/2>@2x.
let entries: [(pixels: Int, names: [String])] = [
    (16, ["icon_16x16"]),
    (32, ["icon_32x32", "icon_16x16@2x"]),
    (64, ["icon_32x32@2x"]),
    (128, ["icon_128x128"]),
    (256, ["icon_256x256", "icon_128x128@2x"]),
    (512, ["icon_512x512", "icon_256x256@2x"]),
    (1024, ["icon_512x512@2x"]),
]

for (pixels, names) in entries {
    let rep = render(pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    for name in names {
        try! png.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
    }
}
print("iconset written; run: iconutil -c icns \(iconset) -o assets/icon.icns")
