import SwiftUI
import DiffCore

struct MergePaneView: NSViewRepresentable {
    @ObservedObject var session: MergeSession
    @AppStorage(Prefs.fontSize) private var fontSize = 12.0
    @AppStorage(Prefs.showOverview) private var showOverview = true

    final class Coordinator {
        var generation = -1
        var showBase: Bool?
        var observer: NSObjectProtocol?
        weak var docView: MergeDocumentView?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> OverviewContainer {
        let doc = MergeDocumentView(frame: NSRect(x: 0, y: 0, width: 1000, height: 10))
        doc.onSelectChunk = { [weak session] in session?.select(chunk: $0) }
        doc.onResolve = { [weak session] c, r in session?.resolve(chunk: c, with: r) }
        let container = OverviewContainer(document: doc)
        let scroll = container.scrollView
        context.coordinator.docView = doc
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scroll.contentView, queue: .main) { [weak doc, weak scroll] _ in
            guard let doc, let scroll else { return }
            doc.setAvailableWidth(scroll.contentView.bounds.width)
        }
        doc.setAvailableWidth(scroll.contentView.bounds.width)
        return container
    }

    func updateNSView(_ container: OverviewContainer, context: Context) {
        guard let doc = context.coordinator.docView else { return }
        let scroll = container.scrollView
        container.rulerHidden = !showOverview
        doc.font = Prefs.font
        doc.wrap = session.wrapLines
        if context.coordinator.generation != session.generation || context.coordinator.showBase != session.showBase {
            context.coordinator.generation = session.generation
            context.coordinator.showBase = session.showBase
            var cols: [MergeDocumentView.Column] = []
            if session.showBase { cols.append(.init(role: .base, lines: session.display[0], raw: session.base.lines, tokens: session.tokens[0])) }
            cols.append(.init(role: .left, lines: session.display[1], raw: session.left.lines, tokens: session.tokens[1]))
            cols.append(.init(role: .merged, lines: session.display[3], raw: session.mergedLines, tokens: session.tokens[3]))
            cols.append(.init(role: .right, lines: session.display[2], raw: session.right.lines, tokens: session.tokens[2]))
            doc.reload(columns: cols, rows: session.rows, chunkRows: session.chunkRows, kinds: session.merge.chunks.map(\.kind),
                       resolutions: session.merge.chunks.indices.map { session.resolution(of: $0) })
        }
        doc.currentChunk = session.currentChunk
        if let c = session.scrollRequest {
            let r = doc.rect(forChunk: c)
            let clip = scroll.contentView.bounds
            let y = max(0, min(r.midY - clip.height / 2, doc.bounds.height - clip.height))
            scroll.contentView.scroll(to: NSPoint(x: clip.origin.x, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            DispatchQueue.main.async { session.scrollRequest = nil }
        }
    }

    static func dismantleNSView(_ nsView: OverviewContainer, coordinator: Coordinator) {
        if let o = coordinator.observer { NotificationCenter.default.removeObserver(o) }
    }
}

struct MergeView: View {
    @ObservedObject var session: MergeSession

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            header
            Divider()
            MergePaneView(session: session)
            Divider()
            statusBar
        }
        .frame(minWidth: 820, minHeight: 360)
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                Button { session.previousConflict() } label: { Image(systemName: "chevron.up") }.help("Previous Conflict (⇧⌘↑)")
                Button { session.nextConflict() } label: { Image(systemName: "chevron.down") }.help("Next Conflict (⇧⌘↓)")
            }
            .disabled(session.conflictCount == 0)
            Text(counterText).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 120, alignment: .leading)
            Spacer()
            Button { session.resolve(with: .left) } label: { Label("Take Left", systemImage: "arrow.right.to.line") }.help("Use the left version for this change (⌥⌘→)")
            Button { session.resolve(with: .both) } label: { Label("Both", systemImage: "arrow.down.to.line.compact") }.help("Keep both, left first (⌥⌘B)")
            Button { session.resolve(with: .base) } label: { Label("Base", systemImage: "arrow.counterclockwise") }.help("Keep the original (⌥⌘0)")
            Button { session.resolve(with: .right) } label: { Label("Take Right", systemImage: "arrow.left.to.line") }.help("Use the right version for this change (⌥⌘←)")
            Divider().frame(height: 16)
            Toggle(isOn: $session.showBase) { Image(systemName: "rectangle.split.3x1") }.toggleStyle(.button).help("Show Base")
            Toggle(isOn: $session.wrapLines) { Image(systemName: "text.word.spacing") }.toggleStyle(.button).help("Wrap Lines")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var counterText: String {
        let unresolved = session.unresolvedConflicts.count
        if session.conflictCount == 0 { return "No conflicts" }
        if unresolved == 0 { return "All \(session.conflictCount) conflict\(session.conflictCount == 1 ? "" : "s") resolved" }
        if let cur = session.currentChunk, let pos = session.merge.conflicts.firstIndex(of: cur) {
            return "Conflict \(pos + 1) of \(session.conflictCount) · \(unresolved) left"
        }
        return "\(unresolved) of \(session.conflictCount) conflicts left"
    }

    private var header: some View {
        HStack(spacing: 0) {
            if session.showBase { columnHeader("Base", session.base.url, dirty: false); Divider() }
            columnHeader("Left · \(session.leftLabel)", session.left.url, dirty: false)
            Divider()
            columnHeader("Merged", session.outputURL, dirty: session.isDirty)
            Divider()
            columnHeader("Right · \(session.rightLabel)", session.right.url, dirty: false)
        }
        .frame(height: 26)
    }

    private func columnHeader(_ title: String, _ url: URL?, dirty: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).fontWeight(.medium).lineLimit(1)
            if let url {
                Text(url.path(percentEncoded: false)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            } else {
                Text("not saved yet").foregroundStyle(.tertiary)
            }
            Spacer()
            if dirty {
                Text("Edited").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.quaternary))
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .help(url?.path ?? "")
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            let kinds = session.merge.chunks.map(\.kind)
            Text("\(kinds.filter { $0 == .leftOnly }.count) left-only · \(kinds.filter { $0 == .rightOnly }.count) right-only · \(kinds.filter { $0 == .bothSame }.count) same on both · \(session.conflictCount) conflict\(session.conflictCount == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            if let msg = session.errorMessage { Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            Spacer()
            Text("\(session.mergedLines.count) lines merged").foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.bar)
    }
}
