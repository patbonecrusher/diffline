import AppKit
import DiffCore

enum DiffColors {
    private static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
    static let leftChange = dyn(NSColor(srgbRed: 0.99, green: 0.90, blue: 0.89, alpha: 1), NSColor(srgbRed: 0.33, green: 0.15, blue: 0.14, alpha: 1))
    static let leftEmphasis = dyn(NSColor(srgbRed: 0.98, green: 0.72, blue: 0.69, alpha: 1), NSColor(srgbRed: 0.56, green: 0.22, blue: 0.20, alpha: 1))
    static let rightChange = dyn(NSColor(srgbRed: 0.88, green: 0.97, blue: 0.90, alpha: 1), NSColor(srgbRed: 0.12, green: 0.28, blue: 0.17, alpha: 1))
    static let rightEmphasis = dyn(NSColor(srgbRed: 0.66, green: 0.90, blue: 0.72, alpha: 1), NSColor(srgbRed: 0.18, green: 0.48, blue: 0.27, alpha: 1))
    static let padding = dyn(NSColor(white: 0.94, alpha: 1), NSColor(white: 0.16, alpha: 1))
    static let paddingStripe = dyn(NSColor(white: 0.86, alpha: 1), NSColor(white: 0.22, alpha: 1))
    static let gutter = dyn(NSColor(white: 0.965, alpha: 1), NSColor(white: 0.13, alpha: 1))
    static let lineNumber = NSColor.tertiaryLabelColor
    static let separator = NSColor.separatorColor
    static let background = NSColor.textBackgroundColor

    // Syntax colors, in the spirit of Xcode's default themes.
    static let keyword = dyn(NSColor(srgbRed: 0.61, green: 0.14, blue: 0.58, alpha: 1), NSColor(srgbRed: 0.99, green: 0.37, blue: 0.64, alpha: 1))
    static let string = dyn(NSColor(srgbRed: 0.77, green: 0.10, blue: 0.09, alpha: 1), NSColor(srgbRed: 0.99, green: 0.42, blue: 0.36, alpha: 1))
    static let comment = dyn(NSColor(srgbRed: 0.36, green: 0.42, blue: 0.47, alpha: 1), NSColor(srgbRed: 0.49, green: 0.55, blue: 0.60, alpha: 1))
    static let number = dyn(NSColor(srgbRed: 0.11, green: 0.00, blue: 0.81, alpha: 1), NSColor(srgbRed: 0.82, green: 0.75, blue: 0.40, alpha: 1))
    static let type = dyn(NSColor(srgbRed: 0.11, green: 0.44, blue: 0.56, alpha: 1), NSColor(srgbRed: 0.36, green: 0.85, blue: 1.00, alpha: 1))
    static let attribute = dyn(NSColor(srgbRed: 0.60, green: 0.32, blue: 0.00, alpha: 1), NSColor(srgbRed: 0.99, green: 0.72, blue: 0.34, alpha: 1))
    static let tag = dyn(NSColor(srgbRed: 0.11, green: 0.44, blue: 0.56, alpha: 1), NSColor(srgbRed: 0.36, green: 0.85, blue: 1.00, alpha: 1))

    static func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword: keyword
        case .string: string
        case .comment: comment
        case .number: number
        case .type: type
        case .attribute: attribute
        case .tag: tag
        }
    }
}

/// Draws an aligned side-by-side diff: line numbers, both panes and the merge gutter. Only the rows
/// intersecting the dirty rect are laid out, so files with tens of thousands of lines stay smooth.
final class DiffDocumentView: NSView {
    enum Side { case left, right }

    // Data
    private var rows: [DiffRow] = []
    private var hunks: [Hunk] = []
    private var leftText: [String] = []
    private var rightText: [String] = []
    private var leftRaw: [Substring] = []
    private var rightRaw: [Substring] = []
    private var leftLen: [Int] = []
    private var rightLen: [Int] = []
    private var leftTokens: [[SyntaxToken]] = []
    private var rightTokens: [[SyntaxToken]] = []

    var wrap = true { didSet { if wrap != oldValue { relayout() } } }
    var font: NSFont = Prefs.font { didSet { if font != oldValue { updateMetrics(); relayout() } } }
    var currentHunk: Int? { didSet { if currentHunk != oldValue { needsDisplay = true } } }
    var onSelectHunk: ((Int) -> Void)?
    var onTakeLeft: ((Int) -> Void)?
    var onTakeRight: ((Int) -> Void)?
    var mergeEnabled = true { didSet { needsDisplay = true } }

    // Layout
    private var rowY: [CGFloat] = [0]
    private var lineHeight: CGFloat = 16
    private var charWidth: CGFloat = 7
    private var lineNumberWidth: CGFloat = 40
    private var paneWidth: CGFloat = 300
    private var maxChars = 0
    private var availableWidth: CGFloat = 800
    private var heightCache: [Int: CGFloat] = [:]
    static let gutterWidth: CGFloat = 40
    static let padX: CGFloat = 8
    static let padY: CGFloat = 2

    // Selection
    private var selection: (side: Side, rows: ClosedRange<Int>)?
    private var anchorRow: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        updateMetrics()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Data

    func reload(rows: [DiffRow], hunks: [Hunk], left: [String], right: [String], leftRaw: [Substring], rightRaw: [Substring],
                leftTokens: [[SyntaxToken]] = [], rightTokens: [[SyntaxToken]] = []) {
        self.rows = rows; self.hunks = hunks
        self.leftText = left; self.rightText = right
        self.leftRaw = leftRaw; self.rightRaw = rightRaw
        self.leftTokens = leftTokens; self.rightTokens = rightTokens
        leftLen = left.map(\.count)
        rightLen = right.map(\.count)
        maxChars = max(leftLen.max() ?? 0, rightLen.max() ?? 0)
        selection = nil
        heightCache.removeAll()
        relayout()
    }

    func setAvailableWidth(_ w: CGFloat) {
        guard abs(w - availableWidth) > 0.5 else { return }
        availableWidth = w
        relayout()
    }

    private func updateMetrics() {
        lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        heightCache.removeAll()
    }

    // MARK: Layout

    private var gutter: CGFloat { Self.gutterWidth }

    private func relayout() {
        let digits = max(2, String(max(leftText.count, rightText.count)).count)
        lineNumberWidth = ceil(CGFloat(digits) * charWidth + 2 * Self.padX)
        let fitPane = max(120, floor((availableWidth - gutter - 2 * lineNumberWidth) / 2))
        let newPane = wrap ? fitPane : max(fitPane, ceil(CGFloat(maxChars) * charWidth + 2 * Self.padX + 4))
        if newPane != paneWidth { heightCache.removeAll() }
        paneWidth = newPane

        var ys: [CGFloat] = [0]
        ys.reserveCapacity(rows.count + 1)
        var y: CGFloat = 0
        for i in rows.indices {
            y += rowHeight(i)
            ys.append(y)
        }
        rowY = ys
        let width = wrap ? availableWidth : 2 * (lineNumberWidth + paneWidth) + gutter
        setFrameSize(NSSize(width: max(width, availableWidth), height: max(y, 1)))
        needsDisplay = true
    }

    private func rowHeight(_ i: Int) -> CGFloat {
        guard wrap else { return lineHeight + 2 * Self.padY }
        if let h = heightCache[i] { return h }
        let row = rows[i]
        let fitChars = Int((paneWidth - 2 * Self.padX) / charWidth)
        var lines = 1
        if let l = row.left, leftLen[l] > fitChars { lines = max(lines, wrappedLineCount(leftText[l])) }
        if let r = row.right, rightLen[r] > fitChars { lines = max(lines, wrappedLineCount(rightText[r])) }
        let h = CGFloat(lines) * lineHeight + 2 * Self.padY
        heightCache[i] = h
        return h
    }

    private func wrappedLineCount(_ text: String) -> Int {
        let attr = NSAttributedString(string: text, attributes: baseAttributes())
        let rect = attr.boundingRect(with: NSSize(width: paneWidth - 2 * Self.padX, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin])
        return max(1, Int((rect.height / lineHeight).rounded()))
    }

    private func baseAttributes(color: NSColor = .labelColor) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = wrap ? .byCharWrapping : .byClipping
        p.minimumLineHeight = lineHeight
        p.maximumLineHeight = lineHeight
        return [.font: font, .foregroundColor: color, .paragraphStyle: p]
    }

    private func rowIndex(atY y: CGFloat) -> Int? {
        guard rows.count > 0, y >= 0, y < rowY[rows.count] else { return nil }
        var lo = 0, hi = rows.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if rowY[mid] <= y { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    private var leftNumX: CGFloat { 0 }
    private var leftTextX: CGFloat { lineNumberWidth }
    private var gutterX: CGFloat { lineNumberWidth + paneWidth }
    private var rightNumX: CGFloat { gutterX + gutter }
    private var rightTextX: CGFloat { rightNumX + lineNumberWidth }

    func rect(forHunk h: Int) -> CGRect {
        guard let hunk = hunks[safe: h] else { return .zero }
        let y0 = rowY[hunk.rows.lowerBound], y1 = rowY[hunk.rows.upperBound]
        return CGRect(x: 0, y: y0, width: bounds.width, height: y1 - y0)
    }

    func rect(forRow i: Int) -> CGRect {
        CGRect(x: 0, y: rowY[i], width: bounds.width, height: rowY[i + 1] - rowY[i])
    }

    private func buttonRects(forHunk h: Int) -> (toRight: CGRect, toLeft: CGRect) {
        let r = rect(forHunk: h)
        let size: CGFloat = 16
        let x = gutterX + (gutter - size) / 2
        let y = r.minY + 3
        return (CGRect(x: x, y: y, width: size, height: size), CGRect(x: x, y: y + size + 4, width: size, height: size))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        DiffColors.background.setFill()
        dirtyRect.fill()
        guard !rows.isEmpty else { return }
        guard let first = rowIndex(atY: max(0, dirtyRect.minY)) else { return }
        let last = rowIndex(atY: min(dirtyRect.maxY - 0.01, rowY[rows.count] - 0.01)) ?? rows.count - 1

        // Gutter and line-number column backgrounds for the dirty area.
        DiffColors.gutter.setFill()
        CGRect(x: gutterX, y: dirtyRect.minY, width: gutter, height: dirtyRect.height).fill()

        for i in first...last {
            let row = rows[i]
            let y = rowY[i], h = rowY[i + 1] - y
            drawCell(side: .left, row: row, index: i, y: y, height: h)
            drawCell(side: .right, row: row, index: i, y: y, height: h)
        }

        // Separators between columns.
        DiffColors.separator.setFill()
        for x in [leftTextX - 0.5, gutterX - 0.5, rightNumX - 0.5, rightTextX - 0.5] {
            CGRect(x: x, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        }

        // Selection.
        if let sel = selection {
            let y0 = rowY[sel.rows.lowerBound], y1 = rowY[sel.rows.upperBound + 1]
            let x = sel.side == .left ? leftTextX : rightTextX
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
            CGRect(x: x, y: y0, width: paneWidth, height: y1 - y0).fill()
        }

        // Current hunk outline and merge buttons.
        for (h, hunk) in hunks.enumerated() where hunk.rows.overlaps(first...last) || hunk.rows.lowerBound == last + 1 {
            let r = rect(forHunk: h)
            if h == currentHunk {
                let path = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 1.5
                NSColor.controlAccentColor.setStroke()
                path.stroke()
            }
            if mergeEnabled {
                let (toRight, toLeft) = buttonRects(forHunk: h)
                drawArrow(in: toRight, pointingRight: true, emphasized: h == currentHunk)
                drawArrow(in: toLeft, pointingRight: false, emphasized: h == currentHunk)
            }
        }
    }

    private func drawCell(side: Side, row: DiffRow, index i: Int, y: CGFloat, height h: CGFloat) {
        let lineIndex = side == .left ? row.left : row.right
        let numX = side == .left ? leftNumX : rightNumX
        let textX = side == .left ? leftTextX : rightTextX
        let cell = CGRect(x: numX, y: y, width: lineNumberWidth + paneWidth, height: h)

        if lineIndex == nil {
            DiffColors.padding.setFill(); cell.fill()
            drawStripes(in: cell)
            return
        }
        if row.kind != .same {
            (side == .left ? DiffColors.leftChange : DiffColors.rightChange).setFill()
            cell.fill()
        }
        // Line number.
        let num = "\(lineIndex! + 1)" as NSString
        let numAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: DiffColors.lineNumber]
        let numSize = num.size(withAttributes: numAttrs)
        num.draw(at: NSPoint(x: numX + lineNumberWidth - Self.padX - numSize.width, y: y + Self.padY), withAttributes: numAttrs)

        // Text with intra-line emphasis.
        let text = side == .left ? leftText[lineIndex!] : rightText[lineIndex!]
        guard !text.isEmpty else { return }
        let attr = NSMutableAttributedString(string: text, attributes: baseAttributes())
        let tokens = side == .left ? leftTokens : rightTokens
        if let lineTokens = tokens[safe: lineIndex!] {
            let length = attr.length
            for t in lineTokens where t.range.lowerBound < length {
                attr.addAttribute(.foregroundColor, value: DiffColors.color(for: t.kind),
                                  range: NSRange(location: t.range.lowerBound, length: min(t.range.count, length - t.range.lowerBound)))
            }
        }
        let highlights = side == .left ? row.leftHighlights : row.rightHighlights
        if !highlights.isEmpty {
            let color = side == .left ? DiffColors.leftEmphasis : DiffColors.rightEmphasis
            for r in highlights {
                let lo = text.index(text.startIndex, offsetBy: r.lowerBound, limitedBy: text.endIndex) ?? text.endIndex
                let hi = text.index(text.startIndex, offsetBy: r.upperBound, limitedBy: text.endIndex) ?? text.endIndex
                attr.addAttribute(.backgroundColor, value: color, range: NSRange(lo..<hi, in: text))
            }
        }
        let textRect = CGRect(x: textX + Self.padX, y: y + Self.padY, width: paneWidth - 2 * Self.padX, height: h - 2 * Self.padY)
        attr.draw(with: textRect, options: [.usesLineFragmentOrigin], context: nil)
    }

    private func drawStripes(in rect: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        DiffColors.paddingStripe.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: NSPoint(x: x, y: rect.maxY))
            path.line(to: NSPoint(x: x + rect.height, y: rect.minY))
            x += 8
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawArrow(in rect: CGRect, pointingRight: Bool, emphasized: Bool) {
        let bg = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        (emphasized ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).setFill()
        bg.fill()
        let p = NSBezierPath()
        let cx = rect.midX, cy = rect.midY
        let d: CGFloat = pointingRight ? 1 : -1
        p.move(to: NSPoint(x: cx - 4 * d, y: cy))
        p.line(to: NSPoint(x: cx + 4 * d, y: cy))
        p.move(to: NSPoint(x: cx + 1 * d, y: cy - 3))
        p.line(to: NSPoint(x: cx + 4 * d, y: cy))
        p.line(to: NSPoint(x: cx + 1 * d, y: cy + 3))
        p.lineWidth = 1.5
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        (emphasized ? NSColor.white : NSColor.secondaryLabelColor).setStroke()
        p.stroke()
    }

    // MARK: Mouse and keyboard

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if mergeEnabled, p.x >= gutterX, p.x < gutterX + gutter, let row = rowIndex(atY: p.y) ?? (rows.isEmpty ? nil : rows.count - 1) {
            // The buttons sit at the top of the hunk, so look at the hunk containing this row and the one just below.
            for (h, hunk) in hunks.enumerated() where hunk.rows.contains(row) || hunk.rows.lowerBound == row + 1 {
                let (toRight, toLeft) = buttonRects(forHunk: h)
                if toRight.contains(p) { onSelectHunk?(h); onTakeLeft?(h); return }
                if toLeft.contains(p) { onSelectHunk?(h); onTakeRight?(h); return }
            }
        }
        guard let row = rowIndex(atY: p.y) else { selection = nil; needsDisplay = true; return }
        let side: Side = p.x < gutterX ? .left : .right
        if event.modifierFlags.contains(.shift), let anchor = anchorRow, let sel = selection, sel.side == side {
            selection = (side, min(anchor, row)...max(anchor, row))
        } else {
            selection = (side, row...row)
            anchorRow = row
        }
        if let h = hunks.firstIndex(where: { $0.rows.contains(row) }) { onSelectHunk?(h) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let anchor = anchorRow, let sel = selection, let row = rowIndex(atY: min(max(p.y, 0), rowY[rows.count] - 0.01)) else { return }
        selection = (sel.side, min(anchor, row)...max(anchor, row))
        autoscroll(with: event)
        needsDisplay = true
    }

    @objc func copy(_ sender: Any?) {
        guard let sel = selection else { NSSound.beep(); return }
        var out: [Substring] = []
        for i in sel.rows {
            let row = rows[i]
            if sel.side == .left, let l = row.left { out.append(leftRaw[l]) }
            if sel.side == .right, let r = row.right { out.append(rightRaw[r]) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out.joined(separator: "\n"), forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        guard !rows.isEmpty else { return }
        selection = (selection?.side ?? .left, 0...(rows.count - 1))
        needsDisplay = true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(copy(_:)) { return selection != nil }
        return super.responds(to: aSelector)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: selection = nil; needsDisplay = true     // escape
        default: super.keyDown(with: event)
        }
    }
}
