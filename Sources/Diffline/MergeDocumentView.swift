import AppKit
import DiffCore

extension DiffColors {
    static let mergeLeft = dynamicColor(NSColor(srgbRed: 0.87, green: 0.92, blue: 1.00, alpha: 1), NSColor(srgbRed: 0.13, green: 0.22, blue: 0.38, alpha: 1))
    static let mergeRight = rightChange
    static let mergeBoth = dynamicColor(NSColor(srgbRed: 0.93, green: 0.90, blue: 1.00, alpha: 1), NSColor(srgbRed: 0.24, green: 0.19, blue: 0.40, alpha: 1))
    static let mergeBase = dynamicColor(NSColor(white: 0.95, alpha: 1), NSColor(white: 0.17, alpha: 1))
    static let conflict = dynamicColor(NSColor(srgbRed: 1.00, green: 0.91, blue: 0.86, alpha: 1), NSColor(srgbRed: 0.38, green: 0.17, blue: 0.12, alpha: 1))
    static let conflictStripe = dynamicColor(NSColor(srgbRed: 0.98, green: 0.75, blue: 0.62, alpha: 1), NSColor(srgbRed: 0.55, green: 0.27, blue: 0.18, alpha: 1))

    static func dynamicColor(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
}

/// Draws the columns of a three-way merge (optionally Base, then Mine, Merged, Theirs) with aligned
/// rows and two action gutters around the merged column.
final class MergeDocumentView: NSView, OverviewSource {
    enum Role { case base, left, merged, right }
    struct Column {
        var role: Role
        var lines: [String]
        var raw: [Substring]
        var tokens: [[SyntaxToken]]
    }

    private var columns: [Column] = []
    private var rows: [MergeRow] = []
    private var chunkRows: [Range<Int>] = []
    private var chunkKinds: [MergeChunk.Kind] = []
    private var chunkResolutions: [Resolution?] = []
    private var lineLengths: [[Int]] = []

    var wrap = true { didSet { if wrap != oldValue { relayout() } } }
    var font: NSFont = Prefs.font { didSet { if font != oldValue { updateMetrics(); relayout() } } }
    var currentChunk: Int? { didSet { if currentChunk != oldValue { needsDisplay = true; onOverviewChange?() } } }
    var onOverviewChange: (() -> Void)?

    /// One band per changed chunk: orange for unresolved conflicts, otherwise the side the result came from.
    var overviewMarks: [OverviewMark] {
        guard rowY.count == rows.count + 1 else { return [] }
        var marks: [OverviewMark] = []
        for c in chunkKinds.indices where chunkKinds[c] != .stable && !chunkRows[c].isEmpty {
            let r = chunkRows[c]
            let color: NSColor
            switch (chunkKinds[c], chunkResolutions[c]) {
            case (.conflict, nil): color = DiffColors.overviewConflict
            case (_, .left?), (.leftOnly, _): color = DiffColors.overviewChanged
            case (_, .right?), (.rightOnly, _): color = DiffColors.overviewInserted
            case (_, .both?), (_, .bothReversed?), (.bothSame, _): color = DiffColors.overviewBoth
            default: color = NSColor.tertiaryLabelColor
            }
            marks.append(OverviewMark(y0: rowY[r.lowerBound], y1: rowY[r.upperBound], color: color, emphasized: c == currentChunk))
        }
        return marks
    }
    var onSelectChunk: ((Int) -> Void)?
    var onResolve: ((Int, Resolution) -> Void)?

    private var rowY: [CGFloat] = [0]
    private var lineHeight: CGFloat = 16
    private var charWidth: CGFloat = 7
    private var lineNumberWidths: [CGFloat] = []
    private var paneWidth: CGFloat = 200
    private var availableWidth: CGFloat = 1000
    private var heightCache: [Int: CGFloat] = [:]
    private var columnX: [CGFloat] = []          // x of each column's line-number area
    private var gutterX: [CGFloat] = []          // x of the gutter after each column (width gutterWidth(after:))
    static let actionGutter: CGFloat = 40
    static let thinGutter: CGFloat = 10
    static let padX: CGFloat = 8
    static let padY: CGFloat = 2

    private var selection: (column: Int, rows: ClosedRange<Int>)?
    private var anchorRow: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame: NSRect) { super.init(frame: frame); updateMetrics() }
    required init?(coder: NSCoder) { fatalError() }

    func reload(columns: [Column], rows: [MergeRow], chunkRows: [Range<Int>], kinds: [MergeChunk.Kind], resolutions: [Resolution?]) {
        self.columns = columns; self.rows = rows; self.chunkRows = chunkRows
        self.chunkKinds = kinds; self.chunkResolutions = resolutions
        lineLengths = columns.map { $0.lines.map(\.count) }
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

    private func gutterWidth(after i: Int) -> CGFloat {
        guard i + 1 < columns.count else { return 0 }
        let pair = (columns[i].role, columns[i + 1].role)
        return pair == (.left, .merged) || pair == (.merged, .right) ? Self.actionGutter : Self.thinGutter
    }

    private func lineIndex(_ row: MergeRow, in column: Int) -> Int? {
        switch columns[column].role {
        case .base: row.base
        case .left: row.left
        case .merged: row.merged
        case .right: row.right
        }
    }

    private func relayout() {
        guard !columns.isEmpty else { setFrameSize(NSSize(width: availableWidth, height: 1)); needsDisplay = true; return }
        lineNumberWidths = columns.map { col in
            let digits = max(2, String(max(col.lines.count, 1)).count)
            return ceil(CGFloat(digits) * charWidth + 2 * Self.padX)
        }
        let gutters = (0..<columns.count).reduce(CGFloat(0)) { $0 + gutterWidth(after: $1) }
        let fixed = gutters + lineNumberWidths.reduce(0, +)
        let fitPane = max(100, floor((availableWidth - fixed) / CGFloat(columns.count)))
        let maxChars = lineLengths.flatMap { $0 }.max() ?? 0
        let newPane = wrap ? fitPane : max(fitPane, ceil(CGFloat(maxChars) * charWidth + 2 * Self.padX + 4))
        if newPane != paneWidth { heightCache.removeAll() }
        paneWidth = newPane
        var x: CGFloat = 0
        columnX = []; gutterX = []
        for i in columns.indices {
            columnX.append(x)
            x += lineNumberWidths[i] + paneWidth
            gutterX.append(x)
            x += gutterWidth(after: i)
        }
        var ys: [CGFloat] = [0]
        ys.reserveCapacity(rows.count + 1)
        var y: CGFloat = 0
        for i in rows.indices { y += rowHeight(i); ys.append(y) }
        rowY = ys
        setFrameSize(NSSize(width: max(x, availableWidth), height: max(y, 1)))
        needsDisplay = true
        onOverviewChange?()
    }

    private func rowHeight(_ i: Int) -> CGFloat {
        guard wrap else { return lineHeight + 2 * Self.padY }
        if let h = heightCache[i] { return h }
        let fitChars = Int((paneWidth - 2 * Self.padX) / charWidth)
        var lines = 1
        for c in columns.indices {
            if let li = lineIndex(rows[i], in: c), lineLengths[c][li] > fitChars {
                lines = max(lines, wrappedLineCount(columns[c].lines[li]))
            }
        }
        let h = CGFloat(lines) * lineHeight + 2 * Self.padY
        heightCache[i] = h
        return h
    }

    private func wrappedLineCount(_ text: String) -> Int {
        let attr = NSAttributedString(string: text, attributes: baseAttributes())
        let rect = attr.boundingRect(with: NSSize(width: paneWidth - 2 * Self.padX, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
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

    func rect(forChunk c: Int) -> CGRect {
        guard chunkRows.indices.contains(c) else { return .zero }
        let r = chunkRows[c]
        guard !r.isEmpty else { return CGRect(x: 0, y: rowY[min(r.lowerBound, rows.count)], width: bounds.width, height: 0) }
        return CGRect(x: 0, y: rowY[r.lowerBound], width: bounds.width, height: rowY[r.upperBound] - rowY[r.lowerBound])
    }

    private func buttonRect(gutterAfter i: Int, chunk c: Int) -> CGRect {
        let r = rect(forChunk: c)
        let size: CGFloat = 16
        return CGRect(x: gutterX[i] + (Self.actionGutter - size) / 2, y: r.minY + 3, width: size, height: size)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        DiffColors.background.setFill()
        dirtyRect.fill()
        guard !rows.isEmpty, let first = rowIndex(atY: max(0, dirtyRect.minY)) else { return }
        let last = rowIndex(atY: min(dirtyRect.maxY - 0.01, rowY[rows.count] - 0.01)) ?? rows.count - 1

        for i in columns.indices where gutterWidth(after: i) > 0 {
            DiffColors.gutter.setFill()
            CGRect(x: gutterX[i], y: dirtyRect.minY, width: gutterWidth(after: i), height: dirtyRect.height).fill()
        }
        for i in first...last {
            let row = rows[i]
            let y = rowY[i], h = rowY[i + 1] - y
            for c in columns.indices { drawCell(column: c, row: row, y: y, height: h) }
        }
        DiffColors.separator.setFill()
        for c in columns.indices {
            CGRect(x: columnX[c] + lineNumberWidths[c] - 0.5, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
            if c > 0 { CGRect(x: columnX[c] - 0.5, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill() }
            if gutterWidth(after: c) > 0 { CGRect(x: gutterX[c] - 0.5, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill() }
        }
        if let sel = selection {
            let y0 = rowY[sel.rows.lowerBound], y1 = rowY[sel.rows.upperBound + 1]
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
            CGRect(x: columnX[sel.column] + lineNumberWidths[sel.column], y: y0, width: paneWidth, height: y1 - y0).fill()
        }
        // Chunk outline and gutter buttons.
        let visibleChunks = Set(rows[first...last].map(\.chunk))
        for c in chunkKinds.indices where chunkKinds[c] != .stable && (visibleChunks.contains(c) || chunkRows[c].lowerBound == last + 1) {
            let r = rect(forChunk: c)
            if c == currentChunk {
                let path = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 1.5
                NSColor.controlAccentColor.setStroke()
                path.stroke()
            }
            for i in columns.indices where gutterWidth(after: i) == Self.actionGutter {
                let takesLeft = columns[i].role == .left
                let chosen = chunkResolutions[c] == (takesLeft ? .left : .right)
                drawArrow(in: buttonRect(gutterAfter: i, chunk: c), pointingRight: takesLeft, filled: chosen, emphasized: c == currentChunk)
            }
        }
    }

    private func cellBackground(column: Int, chunk: Int) -> NSColor? {
        let kind = chunkKinds[chunk]
        guard kind != .stable else { return nil }
        switch columns[column].role {
        case .base: return DiffColors.mergeBase
        case .left:
            switch kind { case .leftOnly, .bothSame: return DiffColors.mergeLeft; case .conflict: return DiffColors.conflict; default: return nil }
        case .right:
            switch kind { case .rightOnly, .bothSame: return DiffColors.mergeRight; case .conflict: return DiffColors.conflict; default: return nil }
        case .merged:
            guard let res = chunkResolutions[chunk] else { return DiffColors.conflict }
            switch res {
            case .left: return DiffColors.mergeLeft
            case .right: return DiffColors.mergeRight
            case .base: return DiffColors.mergeBase
            case .both, .bothReversed: return DiffColors.mergeBoth
            }
        }
    }

    private func drawCell(column c: Int, row: MergeRow, y: CGFloat, height h: CGFloat) {
        let col = columns[c]
        let numX = columnX[c], textX = numX + lineNumberWidths[c]
        let cell = CGRect(x: numX, y: y, width: lineNumberWidths[c] + paneWidth, height: h)
        let unresolved = col.role == .merged && chunkKinds[row.chunk] == .conflict && chunkResolutions[row.chunk] == nil
        if let bg = cellBackground(column: c, chunk: row.chunk) { bg.setFill(); cell.fill() }
        guard let li = lineIndex(row, in: c) else {
            if unresolved {
                drawStripes(in: cell, color: DiffColors.conflictStripe)
                if chunkRows[row.chunk].lowerBound == rows.firstIndex(where: { $0.chunk == row.chunk && $0.merged == nil }) {
                    let label = "Unresolved conflict — take left, right, both or base" as NSString
                    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: font.pointSize - 1, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
                    label.draw(at: NSPoint(x: textX + Self.padX, y: y + Self.padY), withAttributes: attrs)
                }
            } else if chunkKinds[row.chunk] != .stable {
                drawStripes(in: cell, color: DiffColors.paddingStripe)
            }
            return
        }
        let num = "\(li + 1)" as NSString
        let numAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: DiffColors.lineNumber]
        let numSize = num.size(withAttributes: numAttrs)
        num.draw(at: NSPoint(x: numX + lineNumberWidths[c] - Self.padX - numSize.width, y: y + Self.padY), withAttributes: numAttrs)

        let text = col.lines[li]
        guard !text.isEmpty else { return }
        let attr = NSMutableAttributedString(string: text, attributes: baseAttributes())
        if let lineTokens = col.tokens[safe: li] {
            let length = attr.length
            for t in lineTokens where t.range.lowerBound < length {
                attr.addAttribute(.foregroundColor, value: DiffColors.color(for: t.kind),
                                  range: NSRange(location: t.range.lowerBound, length: min(t.range.count, length - t.range.lowerBound)))
            }
        }
        attr.draw(with: CGRect(x: textX + Self.padX, y: y + Self.padY, width: paneWidth - 2 * Self.padX, height: h - 2 * Self.padY),
                  options: [.usesLineFragmentOrigin], context: nil)
    }

    private func drawStripes(in rect: CGRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: NSPoint(x: x, y: rect.maxY)); path.line(to: NSPoint(x: x + rect.height, y: rect.minY))
            x += 8
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawArrow(in rect: CGRect, pointingRight: Bool, filled: Bool, emphasized: Bool) {
        let bg = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        (filled ? NSColor.controlAccentColor : (emphasized ? NSColor.controlAccentColor.withAlphaComponent(0.35) : NSColor.quaternaryLabelColor)).setFill()
        bg.fill()
        let p = NSBezierPath()
        let cx = rect.midX, cy = rect.midY, d: CGFloat = pointingRight ? 1 : -1
        p.move(to: NSPoint(x: cx - 4 * d, y: cy)); p.line(to: NSPoint(x: cx + 4 * d, y: cy))
        p.move(to: NSPoint(x: cx + 1 * d, y: cy - 3)); p.line(to: NSPoint(x: cx + 4 * d, y: cy)); p.line(to: NSPoint(x: cx + 1 * d, y: cy + 3))
        p.lineWidth = 1.5; p.lineCapStyle = .round; p.lineJoinStyle = .round
        (filled ? NSColor.white : NSColor.secondaryLabelColor).setStroke()
        p.stroke()
    }

    // MARK: Mouse and keyboard

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        for i in columns.indices where gutterWidth(after: i) == Self.actionGutter && p.x >= gutterX[i] && p.x < gutterX[i] + Self.actionGutter {
            guard let row = rowIndex(atY: p.y) ?? (rows.isEmpty ? nil : rows.count - 1) else { break }
            let candidates = [rows[row].chunk, rows[row].chunk + 1].filter { chunkKinds.indices.contains($0) && chunkKinds[$0] != .stable }
            for c in candidates where buttonRect(gutterAfter: i, chunk: c).contains(p) {
                onSelectChunk?(c)
                onResolve?(c, columns[i].role == .left ? .left : .right)
                return
            }
        }
        guard let row = rowIndex(atY: p.y) else { selection = nil; needsDisplay = true; return }
        let column = columns.indices.last { p.x >= columnX[$0] } ?? 0
        if event.modifierFlags.contains(.shift), let anchor = anchorRow, let sel = selection, sel.column == column {
            selection = (column, min(anchor, row)...max(anchor, row))
        } else {
            selection = (column, row...row)
            anchorRow = row
        }
        if chunkKinds[rows[row].chunk] != .stable { onSelectChunk?(rows[row].chunk) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let anchor = anchorRow, let sel = selection, let row = rowIndex(atY: min(max(p.y, 0), rowY[rows.count] - 0.01)) else { return }
        selection = (sel.column, min(anchor, row)...max(anchor, row))
        autoscroll(with: event)
        needsDisplay = true
    }

    @objc func copy(_ sender: Any?) {
        guard let sel = selection else { NSSound.beep(); return }
        var out: [Substring] = []
        for i in sel.rows { if let li = lineIndex(rows[i], in: sel.column) { out.append(columns[sel.column].raw[li]) } }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out.joined(separator: "\n"), forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        guard !rows.isEmpty else { return }
        selection = (selection?.column ?? 0, 0...(rows.count - 1))
        needsDisplay = true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(copy(_:)) { return selection != nil }
        return super.responds(to: aSelector)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { selection = nil; needsDisplay = true } else { super.keyDown(with: event) }
    }
}
