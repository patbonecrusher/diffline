// Generates the Diffline app icon (an .iconset folder) with CoreGraphics, so the build has no binary assets.
import AppKit

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: MakeIcon <output.iconset>\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Two columns of text lines on a dark slate card, one pair of lines lit up red and green, joined by
/// a short connector: the diff at a glance. Drawn in a 1024×1024 space, origin bottom-left.
func drawIcon(in ctx: CGContext, pixels: CGFloat) {
    ctx.scaleBy(x: pixels / 1024, y: pixels / 1024)
    let square = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: square, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.30))
    ctx.setFillColor(rgb(30, 34, 46))
    ctx.addPath(shape); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(52, 58, 82), rgb(24, 27, 38)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 824, y: 100), options: [])

    // Column geometry.
    let leftX: CGFloat = 196, rightX: CGFloat = 556, colW: CGFloat = 272
    let rowH: CGFloat = 40, gap: CGFloat = 36
    let rows: [CGFloat] = (0..<8).map { 760 - CGFloat($0) * (rowH + gap) }
    // Line widths as fractions of the column, so the two sides look like real text.
    let widths: [(CGFloat, CGFloat)] = [(0.62, 0.62), (0.88, 0.88), (0.45, 0.70), (0.76, 0.76), (0.0, 0.58), (0.83, 0.83), (0.55, 0.55), (0.70, 0.70)]
    let changed = 2, inserted = 4

    func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ color: CGColor) {
        guard w > 0 else { return }
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: rowH), cornerWidth: rowH / 2, cornerHeight: rowH / 2, transform: nil))
        ctx.fillPath()
    }

    // Row backgrounds for the highlighted rows span the whole column.
    ctx.setFillColor(rgb(255, 92, 92, 0.22))
    ctx.fill(CGRect(x: leftX - 28, y: rows[changed] - 18, width: colW + 56, height: rowH + 36))
    ctx.setFillColor(rgb(74, 222, 128, 0.22))
    ctx.fill(CGRect(x: rightX - 28, y: rows[changed] - 18, width: colW + 56, height: rowH + 36))
    ctx.fill(CGRect(x: rightX - 28, y: rows[inserted] - 18, width: colW + 56, height: rowH + 36))

    for (i, y) in rows.enumerated() {
        let (lw, rw) = widths[i]
        let base = CGColor(gray: 1, alpha: 0.78)
        if i == changed {
            bar(leftX, y, colW * lw, rgb(255, 118, 118))
            bar(rightX, y, colW * rw, rgb(96, 230, 150))
        } else if i == inserted {
            bar(rightX, y, colW * rw, rgb(96, 230, 150))
        } else {
            bar(leftX, y, colW * lw, base)
            bar(rightX, y, colW * rw, base)
        }
    }

    // Center spine with the merge arrow at the changed row.
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    ctx.setLineWidth(6)
    ctx.move(to: CGPoint(x: 512, y: 190)); ctx.addLine(to: CGPoint(x: 512, y: 834)); ctx.strokePath()
    let ay = rows[changed] + rowH / 2
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    ctx.setLineWidth(16)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 478, y: ay)); ctx.addLine(to: CGPoint(x: 546, y: ay))
    ctx.move(to: CGPoint(x: 520, y: ay + 26)); ctx.addLine(to: CGPoint(x: 546, y: ay)); ctx.addLine(to: CGPoint(x: 520, y: ay - 26))
    ctx.strokePath()
    ctx.restoreGState()
}

let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
for v in variants {
    let px = v.points * v.scale
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let gc = NSGraphicsContext(bitmapImageRep: rep) else { exit(2) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    drawIcon(in: gc.cgContext, pixels: CGFloat(px))
    gc.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(v.points)x\(v.points)\(v.scale == 2 ? "@2x" : "").png"
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}
print("wrote \(variants.count) icon sizes to \(outDir.path)")
