// Composites a window capture onto a 2560×1600 App Store screenshot canvas.
// usage: swift compose.swift <window.png> <out.png> [dark]
import AppKit

let args = CommandLine.arguments
let window = NSImage(contentsOfFile: args[1])!
let dark = args.count > 3 && args[3] == "dark"
let W = 2560, H = 1600

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let colors: [NSColor] = dark
    ? [NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1), NSColor(srgbRed: 0.18, green: 0.24, blue: 0.42, alpha: 1)]
    : [NSColor(srgbRed: 0.62, green: 0.76, blue: 1.00, alpha: 1), NSColor(srgbRed: 0.27, green: 0.36, blue: 0.80, alpha: 1)]
NSGradient(colors: colors)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)

// Fit the window into the canvas with generous margins, keeping pixel aspect.
let winPx = window.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? window.size
let maxW = CGFloat(W) - 320, maxH = CGFloat(H) - 260
let scale = min(maxW / winPx.width, maxH / winPx.height, 1.0)
let drawSize = CGSize(width: winPx.width * scale, height: winPx.height * scale)
let origin = CGPoint(x: (CGFloat(W) - drawSize.width) / 2, y: (CGFloat(H) - drawSize.height) / 2)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 70, color: CGColor(gray: 0, alpha: 0.45))
let clip = NSBezierPath(roundedRect: NSRect(origin: origin, size: drawSize), xRadius: 24 * scale, yRadius: 24 * scale)
NSColor.black.setFill()
clip.fill()
ctx.restoreGState()
clip.addClip()
window.draw(in: NSRect(origin: origin, size: drawSize), from: .zero, operation: .sourceOver, fraction: 1)

// Flatten alpha (App Store screenshots must be opaque).
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
