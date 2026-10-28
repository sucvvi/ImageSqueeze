// Draws the app icon (1024×1024 PNG). Usage: swift make_icon.swift out.png
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Rounded-square background with a teal → indigo gradient.
let inset = 100.0
let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset),
                      xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.78, blue: 0.70, alpha: 1),
           ending: NSColor(srgbRed: 0.28, green: 0.33, blue: 0.86, alpha: 1))!.draw(in: bg, angle: -60)

// Photo card.
let card = NSRect(x: 270, y: 330, width: 484, height: 380)
NSColor.white.withAlphaComponent(0.95).setFill()
NSBezierPath(roundedRect: card, xRadius: 48, yRadius: 48).fill()
// Mountains + sun inside the card.
let clip = NSBezierPath(roundedRect: card.insetBy(dx: 34, dy: 34), xRadius: 22, yRadius: 22)
NSGraphicsContext.current!.saveGraphicsState()
clip.addClip()
NSColor(srgbRed: 0.85, green: 0.93, blue: 0.98, alpha: 1).setFill()
clip.fill()
let m = NSBezierPath()
m.move(to: NSPoint(x: 300, y: 360)); m.line(to: NSPoint(x: 430, y: 530)); m.line(to: NSPoint(x: 510, y: 440))
m.line(to: NSPoint(x: 590, y: 560)); m.line(to: NSPoint(x: 730, y: 360)); m.close()
NSColor(srgbRed: 0.22, green: 0.62, blue: 0.62, alpha: 1).setFill(); m.fill()
NSColor(srgbRed: 1.0, green: 0.76, blue: 0.25, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 600, y: 580, width: 70, height: 70)).fill()
NSGraphicsContext.current!.restoreGraphicsState()

// Compression arrows pointing inward (top and bottom).
func arrow(tipY: Double, down: Bool) {
    let p = NSBezierPath()
    let d = down ? -1.0 : 1.0
    p.move(to: NSPoint(x: 512, y: tipY))
    p.line(to: NSPoint(x: 432, y: tipY - d * 80)); p.line(to: NSPoint(x: 482, y: tipY - d * 80))
    p.line(to: NSPoint(x: 482, y: tipY - d * 130)); p.line(to: NSPoint(x: 542, y: tipY - d * 130))
    p.line(to: NSPoint(x: 542, y: tipY - d * 80)); p.line(to: NSPoint(x: 592, y: tipY - d * 80)); p.close()
    NSColor.white.setFill(); p.fill()
}
arrow(tipY: 735, down: true)
arrow(tipY: 305, down: false)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
