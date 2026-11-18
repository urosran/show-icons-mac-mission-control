// Draws the 1024px app icon: three "window thumbnails", each with a small app-icon dot + label bar.
import Cocoa
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.47, blue: 0.98, alpha: 1),
           ending: NSColor(calibratedRed: 0.39, green: 0.24, blue: 0.86, alpha: 1))!.draw(in: bg, angle: -60)
let wins = [NSRect(x: 190, y: 520, width: 300, height: 220), NSRect(x: 534, y: 520, width: 300, height: 220),
            NSRect(x: 362, y: 250, width: 300, height: 220)]
let dots = [NSColor.systemOrange, .systemGreen, .systemPink]
for (i, r) in wins.enumerated() {
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26).fill()
    NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.maxY - 40, width: r.width, height: 40), xRadius: 20, yRadius: 20).fill()
    let d = NSRect(x: r.midX - 42, y: r.minY - 42, width: 84, height: 84)
    NSColor.white.setFill(); NSBezierPath(ovalIn: d.insetBy(dx: -8, dy: -8)).fill()
    dots[i].setFill(); NSBezierPath(roundedRect: d, xRadius: 20, yRadius: 20).fill()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
