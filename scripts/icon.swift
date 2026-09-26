import AppKit
import Foundation
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let n = CGFloat(pixels), inset = n * 0.08
        let rounded = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: n - inset * 2, height: n - inset * 2), xRadius: n * 0.2, yRadius: n * 0.2)
        let colors = [NSColor(calibratedRed: 0.23, green: 0.26, blue: 0.36, alpha: 1), NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.11, alpha: 1)]
        NSGradient(colors: colors)!.draw(in: rounded, angle: -90)
        NSColor.white.withAlphaComponent(0.3).setStroke(); rounded.lineWidth = max(1, n * 0.006); rounded.stroke()
        let mountain = NSBezierPath(); mountain.move(to: NSPoint(x: n * 0.23, y: n * 0.32)); mountain.line(to: NSPoint(x: n * 0.48, y: n * 0.71)); mountain.line(to: NSPoint(x: n * 0.74, y: n * 0.32)); mountain.line(to: NSPoint(x: n * 0.57, y: n * 0.43)); mountain.line(to: NSPoint(x: n * 0.48, y: n * 0.38)); mountain.close()
        NSGradient(colors: [NSColor(calibratedRed: 1, green: 0.77, blue: 0.59, alpha: 1), NSColor(calibratedRed: 1, green: 0.45, blue: 0.3, alpha: 1)])!.draw(in: mountain, angle: -90)
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
