import AppKit

/// One colored band in the overview, in document-view coordinates.
struct OverviewMark {
    var y0: CGFloat
    var y1: CGFloat
    var color: NSColor
    var emphasized = false
}

/// Something that can be summarized in an overview ruler (the file diff and merge document views).
protocol OverviewSource: NSView {
    var overviewMarks: [OverviewMark] { get }
    /// Called after every layout or state change that moves or recolors marks.
    var onOverviewChange: (() -> Void)? { get set }
}

/// A narrow strip showing where every change is in the whole document, the visible region, and
/// letting you click or drag to jump there.
final class OverviewRuler: NSView {
    static let width: CGFloat = 18
    weak var source: OverviewSource?
    weak var scrollView: NSScrollView?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var documentHeight: CGFloat { max(source?.bounds.height ?? 1, 1) }
    /// The document is squeezed to fit the strip, but never stretched: a short file uses only the top.
    private var scale: CGFloat { min(bounds.height / documentHeight, 1) }

    override func draw(_ dirtyRect: NSRect) {
        DiffColors.gutter.setFill()
        bounds.fill()
        DiffColors.separator.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        guard let source else { return }
        let s = scale
        let inset: CGFloat = 3
        for m in source.overviewMarks {
            let y = floor(m.y0 * s)
            let h = max(2, ceil((m.y1 - m.y0) * s))
            let r = NSRect(x: inset, y: y, width: bounds.width - inset - 2, height: h)
            m.color.setFill()
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
            if m.emphasized {
                NSColor.controlAccentColor.setStroke()
                let p = NSBezierPath(roundedRect: r.insetBy(dx: -1.5, dy: -1.5), xRadius: 2.5, yRadius: 2.5)
                p.lineWidth = 1.5
                p.stroke()
            }
        }
        // The part of the document currently on screen.
        if let clip = scrollView?.contentView.bounds, documentHeight > clip.height + 1 {
            let r = NSRect(x: 1.5, y: clip.minY * s, width: bounds.width - 2.5, height: max(10, clip.height * s))
            NSColor.labelColor.withAlphaComponent(0.14).setFill()
            NSColor.labelColor.withAlphaComponent(0.55).setStroke()
            let p = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            p.fill()
            p.lineWidth = 1
            p.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) { jump(to: event) }
    override func mouseDragged(with event: NSEvent) { jump(to: event) }

    private func jump(to event: NSEvent) {
        guard let scroll = scrollView else { return }
        let p = convert(event.locationInWindow, from: nil)
        let clip = scroll.contentView.bounds
        let docY = p.y / scale
        let y = max(0, min(docY - clip.height / 2, documentHeight - clip.height))
        scroll.contentView.scroll(to: NSPoint(x: clip.origin.x, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// A scroll view with the overview ruler down its right edge.
final class OverviewContainer: NSView {
    let scrollView = NSScrollView()
    let ruler = OverviewRuler()
    private var observers: [NSObjectProtocol] = []

    var rulerHidden = false {
        didSet { if rulerHidden != oldValue { ruler.isHidden = rulerHidden; needsLayout = true } }
    }

    init(document: OverviewSource) {
        super.init(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DiffColors.background
        scrollView.documentView = document
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        ruler.source = document
        ruler.scrollView = scrollView
        addSubview(scrollView)
        addSubview(ruler)
        document.onOverviewChange = { [weak ruler] in ruler?.needsDisplay = true }
        for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: scrollView.contentView, queue: .main) { [weak ruler] _ in
                ruler?.needsDisplay = true
            })
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func layout() {
        super.layout()
        let w = rulerHidden ? 0 : OverviewRuler.width
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width - w, height: bounds.height)
        ruler.frame = NSRect(x: bounds.width - w, y: 0, width: w, height: bounds.height)
        ruler.needsDisplay = true
    }

    override var isFlipped: Bool { true }
}
