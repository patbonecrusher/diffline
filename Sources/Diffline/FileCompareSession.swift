import AppKit
import Combine
import DiffCore

/// Everything one file-comparison window needs: both files, the diff, navigation and merge state.
@MainActor
final class FileCompareSession: ObservableObject {
    @Published private(set) var left: TextFile
    @Published private(set) var right: TextFile
    @Published var options: DiffOptions { didSet { if options != oldValue { recompute() } } }
    @Published var wrapLines: Bool
    @Published var syntaxHighlighting: Bool { didSet { if syntaxHighlighting != oldValue { recompute() } } }
    /// nil = detect from the file name; set from the Language menu to force one.
    @Published var languageOverride: Language? { didSet { if languageOverride != oldValue { recompute() } } }
    @Published private(set) var leftTokens: [[SyntaxToken]] = []
    @Published private(set) var rightTokens: [[SyntaxToken]] = []
    @Published private(set) var result: LineDiffResult?
    @Published private(set) var displayLeft: [String] = []
    @Published private(set) var displayRight: [String] = []
    @Published private(set) var isComputing = false
    @Published var currentHunk: Int?
    @Published private(set) var errorMessage: String?
    /// Bumped every time rows/display text change, so views know to relayout.
    @Published private(set) var generation = 0
    /// Set by the view to scroll to a hunk; cleared after use.
    @Published var scrollRequest: Int?

    weak var undoManager: UndoManager?
    private var computeTask: Task<Void, Never>?

    init(left: TextFile, right: TextFile) {
        self.left = left
        self.right = right
        self.options = Prefs.defaultDiffOptions
        self.wrapLines = UserDefaults.standard.bool(forKey: Prefs.wrapLines)
        self.syntaxHighlighting = UserDefaults.standard.bool(forKey: Prefs.syntaxHighlighting)
        recompute()
    }

    convenience init(leftURL: URL, rightURL: URL) throws {
        self.init(left: try TextFile.load(leftURL), right: try TextFile.load(rightURL))
    }

    var title: String { "\(left.name) ↔ \(right.name)" }
    var leftLanguage: Language? { languageOverride ?? Language.detect(filename: left.name) }
    var rightLanguage: Language? { languageOverride ?? Language.detect(filename: right.name) ?? Language.detect(filename: left.name) }
    /// What the Language menu shows as selected: the override, else the detected language of the left file.
    var effectiveLanguage: Language? { leftLanguage ?? rightLanguage }
    var isBinary: Bool { left.isBinary || right.isBinary }
    var binaryIdentical: Bool { left.data == right.data }
    var hunkCount: Int { result?.hunks.count ?? 0 }
    var isDirty: Bool { left.isDirty || right.isDirty }

    // MARK: Diff

    func recompute() {
        computeTask?.cancel()
        guard !isBinary else { result = nil; return }
        let l = left.lines, r = right.lines, opts = options
        let gen = generation + 1
        let langL = syntaxHighlighting ? leftLanguage : nil
        let langR = syntaxHighlighting ? rightLanguage : nil
        isComputing = true
        computeTask = Task.detached(priority: .userInitiated) { [weak self] in
            var res = LineDiff.compare(l, r, options: opts, intraLine: false)
            let dl = l.map { TextFile.expandTabs($0, tabWidth: opts.tabWidth) }
            let dr = r.map { TextFile.expandTabs($0, tabWidth: opts.tabWidth) }
            if Task.isCancelled { return }
            let tl = langL.map { SyntaxHighlighter(language: $0).tokenize(lines: dl) } ?? []
            let tr = langR.map { SyntaxHighlighter(language: $0).tokenize(lines: dr) } ?? []
            if Task.isCancelled { return }
            for i in res.rows.indices where res.rows[i].kind == .changed {
                let (lh, rh) = IntraLine.highlights(Substring(dl[res.rows[i].left!]), Substring(dr[res.rows[i].right!]), options: opts)
                res.rows[i].leftHighlights = lh
                res.rows[i].rightHighlights = rh
            }
            if Task.isCancelled { return }
            let final = res
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.result = final
                self.displayLeft = dl
                self.displayRight = dr
                self.leftTokens = tl
                self.rightTokens = tr
                self.generation = gen
                self.isComputing = false
                if let cur = self.currentHunk, cur >= final.hunks.count { self.currentHunk = final.hunks.isEmpty ? nil : final.hunks.count - 1 }
            }
        }
    }

    // MARK: Navigation

    func nextChange() {
        guard let hunks = result?.hunks, !hunks.isEmpty else { return }
        let next = currentHunk.map { min($0 + 1, hunks.count - 1) } ?? 0
        currentHunk = next
        scrollRequest = next
    }

    func previousChange() {
        guard let hunks = result?.hunks, !hunks.isEmpty else { return }
        let prev = currentHunk.map { max($0 - 1, 0) } ?? 0
        currentHunk = prev
        scrollRequest = prev
    }

    func select(hunk: Int) {
        currentHunk = hunk
    }

    // MARK: Merge

    func takeLeft(hunk index: Int? = nil) { merge(hunk: index ?? currentHunk, from: .left) }
    func takeRight(hunk index: Int? = nil) { merge(hunk: index ?? currentHunk, from: .right) }

    enum Side { case left, right }

    private func merge(hunk index: Int?, from side: Side) {
        guard let index, let hunk = result?.hunks[safe: index] else { return }
        let before = (left, right)
        switch side {
        case .left: right.replace(lines: hunk.rightLines, with: Array(left.lines[hunk.leftLines]))
        case .right: left.replace(lines: hunk.leftLines, with: Array(right.lines[hunk.rightLines]))
        }
        registerUndo(restoring: before, actionName: side == .left ? "Take Left" : "Take Right")
        recompute()
    }

    private func registerUndo(restoring: (TextFile, TextFile), actionName: String) {
        undoManager?.registerUndo(withTarget: self) { target in
            let current = (target.left, target.right)
            target.left = restoring.0
            target.right = restoring.1
            target.registerUndo(restoring: current, actionName: actionName)
            target.recompute()
        }
        undoManager?.setActionName(actionName)
    }

    func swapSides() {
        let before = (left, right)
        (left, right) = (right, left)
        registerUndo(restoring: before, actionName: "Swap Sides")
        recompute()
    }

    // MARK: Files

    func save() {
        do {
            if left.isDirty { try left.write(); left.isDirty = false }
            if right.isDirty { try right.write(); right.isDirty = false }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func reload() {
        do {
            left = try TextFile.load(left.url)
            right = try TextFile.load(right.url)
            errorMessage = nil
            recompute()
        } catch {
            errorMessage = "Couldn't reload: \(error.localizedDescription)"
        }
    }

    func unifiedDiff() -> String {
        guard let result else { return "" }
        return UnifiedDiff.render(left: left.lines, right: right.lines, segments: result.segments,
                                  leftName: left.url.path, rightName: right.url.path)
    }

    func exportUnifiedDiff() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = left.url.deletingPathExtension().lastPathComponent + ".diff"
        panel.allowedContentTypes = [.plainText]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { try self.unifiedDiff().write(to: url, atomically: true, encoding: .utf8) }
            catch { self.errorMessage = "Couldn't export: \(error.localizedDescription)" }
        }
    }

    func copyUnifiedDiff() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(unifiedDiff(), forType: .string)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
