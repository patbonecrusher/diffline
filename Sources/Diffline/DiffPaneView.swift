import SwiftUI
import DiffCore

/// Hosts the AppKit diff view in a scroll view and keeps it in sync with the session.
struct DiffPaneView: NSViewRepresentable {
    @ObservedObject var session: FileCompareSession
    @AppStorage(Prefs.fontSize) private var fontSize = 12.0

    final class Coordinator {
        var generation = -1
        var observer: NSObjectProtocol?
        weak var docView: DiffDocumentView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = DiffColors.background
        let doc = DiffDocumentView(frame: NSRect(x: 0, y: 0, width: 800, height: 10))
        doc.onSelectHunk = { [weak session] in session?.select(hunk: $0) }
        doc.onTakeLeft = { [weak session] in session?.takeLeft(hunk: $0) }
        doc.onTakeRight = { [weak session] in session?.takeRight(hunk: $0) }
        scroll.documentView = doc
        scroll.contentView.postsFrameChangedNotifications = true
        context.coordinator.docView = doc
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scroll.contentView, queue: .main) { [weak doc, weak scroll] _ in
            guard let doc, let scroll else { return }
            doc.setAvailableWidth(scroll.contentView.bounds.width)
        }
        doc.setAvailableWidth(scroll.contentView.bounds.width)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let doc = context.coordinator.docView else { return }
        doc.font = Prefs.font
        doc.wrap = session.wrapLines
        doc.mergeEnabled = true
        if context.coordinator.generation != session.generation, let result = session.result {
            context.coordinator.generation = session.generation
            doc.reload(rows: result.rows, hunks: result.hunks, left: session.displayLeft, right: session.displayRight,
                       leftRaw: session.left.lines, rightRaw: session.right.lines)
        }
        doc.currentHunk = session.currentHunk
        if let h = session.scrollRequest {
            let r = doc.rect(forHunk: h)
            let clip = scroll.contentView.bounds
            var y = r.midY - clip.height / 2
            y = max(0, min(y, doc.bounds.height - clip.height))
            scroll.contentView.scroll(to: NSPoint(x: clip.origin.x, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            DispatchQueue.main.async { session.scrollRequest = nil }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let o = coordinator.observer { NotificationCenter.default.removeObserver(o) }
    }
}
