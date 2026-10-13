// Renders the website's icons and social card from Design/icon.svg.
//   swift Design/render-site-assets.swift Design/icon.svg <output-dir>
// The app icon itself is still drawn by Tools/MakeIcon at build time; icon.svg mirrors it for the web.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let icon = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("usage: render-site-assets.swift <icon.svg> <outdir>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func bitmap(_ width: Int, _ height: Int, draw: (NSRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func drawIcon(in rect: NSRect, shadow: Bool = true) {
    NSGraphicsContext.saveGraphicsState()
    if shadow {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.30)
        s.shadowBlurRadius = rect.width * 0.022
        s.shadowOffset = NSSize(width: 0, height: -rect.width * 0.012)
        s.set()
    }
    icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

for px in [32, 64, 180, 512] {
    let data = bitmap(px, px) { drawIcon(in: $0, shadow: px >= 64) }
    try data.write(to: outDir.appendingPathComponent("icon-\(px).png"))
    print("icon-\(px).png")
}

// 1200×630 card for link previews.
let card = bitmap(1200, 630) { bounds in
    NSGradient(colorsAndLocations: (color(0x0E1018), 0), (color(0x1A2238), 0.55), (color(0x26407A), 1))!.draw(in: bounds, angle: 35)
    NSGradient(starting: color(0xFFFFFF, alpha: 0.12), ending: color(0xFFFFFF, alpha: 0))!
        .draw(in: bounds, relativeCenterPosition: NSPoint(x: -0.7, y: 0.8))
    drawIcon(in: NSRect(x: 70, y: 135, width: 360, height: 360))
    NSAttributedString(string: "Diffline", attributes: [
        .font: NSFont.systemFont(ofSize: 124, weight: .bold), .foregroundColor: NSColor.white, .kern: -3.0,
    ]).draw(at: NSPoint(x: 452, y: 318))
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 6
    NSAttributedString(string: "Compare and merge files on your Mac.\nThree-way merge for git, made for macOS.", attributes: [
        .font: NSFont.systemFont(ofSize: 38, weight: .regular),
        .foregroundColor: color(0xFFFFFF, alpha: 0.82), .paragraphStyle: paragraph,
    ]).draw(in: NSRect(x: 458, y: 180, width: 720, height: 130))
}
try card.write(to: outDir.appendingPathComponent("social-card.png"))
print("social-card.png")
