import AppKit
import Combine
import DiffCore

/// One row of the merge display: a line index (or nil for padding) in each column.
struct MergeRow: Equatable {
    var chunk: Int
    var base: Int?
    var left: Int?
    var right: Int?
    var merged: Int?
}

/// Everything a three-way merge window needs: the three inputs, the chunk structure, the user's
/// resolutions, the merged result, and navigation.
@MainActor
final class MergeSession: ObservableObject {
    let base: TextFile
    let left: TextFile
    let right: TextFile
    @Published var outputURL: URL?
    let leftLabel: String
    let rightLabel: String

    @Published private(set) var merge: ThreeWayMerge
    @Published private(set) var resolutions: [Int: Resolution] = [:]
    @Published private(set) var rows: [MergeRow] = []
    @Published private(set) var chunkRows: [Range<Int>] = []
    @Published private(set) var mergedLines: [Substring] = []
    @Published private(set) var display: [[String]] = [[], [], [], []]        // base, left, right, merged (tabs expanded)
    @Published private(set) var tokens: [[[SyntaxToken]]] = [[], [], [], []]
    @Published var options: DiffOptions { didSet { if options != oldValue { recomputeMerge() } } }
    @Published var wrapLines: Bool
    @Published var showBase = false
    @Published var syntaxHighlighting: Bool { didSet { if syntaxHighlighting != oldValue { rebuildRows() } } }
    @Published var currentChunk: Int?
    @Published var scrollRequest: Int?
    @Published private(set) var isDirty = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var generation = 0
    /// Set when launched for a tool like git mergetool: closing the window quits the app.
    var quitOnClose = false

    weak var undoManager: UndoManager?

    init(base: TextFile, left: TextFile, right: TextFile, output: URL?, leftLabel: String? = nil, rightLabel: String? = nil) {
        self.base = base; self.left = left; self.right = right
        self.outputURL = output
        self.leftLabel = leftLabel ?? left.name
        self.rightLabel = rightLabel ?? right.name
        let opts = Prefs.defaultDiffOptions
        self.options = opts
        self.wrapLines = UserDefaults.standard.bool(forKey: Prefs.wrapLines)
        self.syntaxHighlighting = UserDefaults.standard.bool(forKey: Prefs.syntaxHighlighting)
        self.merge = ThreeWayMerge.merge(base: base.lines, left: left.lines, right: right.lines, options: opts)
        rebuildRows()
        currentChunk = merge.conflicts.first ?? changedChunks.first
    }

    convenience init(baseURL: URL, leftURL: URL, rightURL: URL, output: URL?, leftLabel: String? = nil, rightLabel: String? = nil) throws {
        self.init(base: try TextFile.load(baseURL), left: try TextFile.load(leftURL), right: try TextFile.load(rightURL),
                  output: output, leftLabel: leftLabel, rightLabel: rightLabel)
    }

    var title: String { "Merge: \(leftLabel) ↔ \(rightLabel)" }
    var language: Language? {
        syntaxHighlighting ? (Language.detect(filename: outputURL?.lastPathComponent ?? left.name) ?? Language.detect(filename: left.name) ?? Language.detect(filename: right.name)) : nil
    }
    var changedChunks: [Int] { merge.chunks.indices.filter { merge.chunks[$0].kind != .stable } }
    var unresolvedConflicts: [Int] { merge.conflicts.filter { resolutions[$0] == nil } }
    var conflictCount: Int { merge.conflicts.count }

    func resolution(of chunk: Int) -> Resolution? {
        resolutions[chunk] ?? ThreeWayMerge.defaultResolution(for: merge.chunks[chunk].kind)
    }

    // MARK: Model

    private func recomputeMerge() {
        merge = ThreeWayMerge.merge(base: base.lines, left: left.lines, right: right.lines, options: options)
        resolutions = [:]
        rebuildRows()
        currentChunk = merge.conflicts.first ?? changedChunks.first
    }

    private func rebuildRows() {
        var merged: [Substring] = []
        var rows: [MergeRow] = []
        var chunkRows: [Range<Int>] = []
        for (idx, chunk) in merge.chunks.enumerated() {
            let res = resolutions[idx] ?? ThreeWayMerge.defaultResolution(for: chunk.kind)
            let mergedStart = merged.count
            if let res { merged += ThreeWayMerge.lines(of: chunk, resolution: res, base: base.lines, left: left.lines, right: right.lines) }
            let mergedCount = merged.count - mergedStart
            let n = max(chunk.base.count, chunk.left.count, chunk.right.count, mergedCount, chunk.kind == .conflict && res == nil ? 1 : 0)
            let start = rows.count
            for k in 0..<n {
                rows.append(MergeRow(chunk: idx,
                                     base: k < chunk.base.count ? chunk.base.lowerBound + k : nil,
                                     left: k < chunk.left.count ? chunk.left.lowerBound + k : nil,
                                     right: k < chunk.right.count ? chunk.right.lowerBound + k : nil,
                                     merged: k < mergedCount ? mergedStart + k : nil))
            }
            chunkRows.append(start..<rows.count)
        }
        mergedLines = merged
        self.rows = rows
        self.chunkRows = chunkRows
        let tw = options.tabWidth
        display = [base.lines, left.lines, right.lines, merged].map { $0.map { TextFile.expandTabs($0, tabWidth: tw) } }
        if let lang = language {
            let h = SyntaxHighlighter(language: lang)
            tokens = display.map { h.tokenize(lines: $0) }
        } else {
            tokens = [[], [], [], []]
        }
        generation += 1
    }

    // MARK: Resolving

    func resolve(chunk: Int? = nil, with resolution: Resolution) {
        guard let chunk = chunk ?? currentChunk, merge.chunks.indices.contains(chunk) else { return }
        let before = resolutions
        if ThreeWayMerge.defaultResolution(for: merge.chunks[chunk].kind) == resolution && merge.chunks[chunk].kind != .conflict {
            resolutions[chunk] = nil
        } else {
            resolutions[chunk] = resolution
        }
        isDirty = true
        registerUndo(restoring: before)
        rebuildRows()
    }

    func unresolve(chunk: Int) {
        guard merge.chunks[chunk].kind == .conflict else { return }
        let before = resolutions
        resolutions[chunk] = nil
        registerUndo(restoring: before)
        rebuildRows()
    }

    private func registerUndo(restoring: [Int: Resolution]) {
        undoManager?.registerUndo(withTarget: self) { target in
            let current = target.resolutions
            target.resolutions = restoring
            target.registerUndo(restoring: current)
            target.rebuildRows()
        }
        undoManager?.setActionName("Resolve")
    }

    // MARK: Navigation

    func nextChange() { step(in: changedChunks, forward: true) }
    func previousChange() { step(in: changedChunks, forward: false) }
    func nextConflict() { step(in: merge.conflicts, forward: true) }
    func previousConflict() { step(in: merge.conflicts, forward: false) }

    private func step(in list: [Int], forward: Bool) {
        guard !list.isEmpty else { return }
        let target: Int
        if let cur = currentChunk {
            if forward { target = list.first { $0 > cur } ?? list.last! } else { target = list.last { $0 < cur } ?? list.first! }
        } else {
            target = forward ? list.first! : list.last!
        }
        currentChunk = target
        scrollRequest = target
    }

    func select(chunk: Int) { currentChunk = chunk }

    // MARK: Output

    var mergedText: String {
        let lines = merge.output(base: base.lines, left: left.lines, right: right.lines, resolutions: resolutions,
                                 leftLabel: leftLabel, rightLabel: rightLabel)
        var s = lines.joined(separator: left.lineEnding)
        if left.trailingNewline && !lines.isEmpty { s += left.lineEnding }
        return s
    }

    /// Writes the merged file. Asks before writing conflict markers for anything still unresolved.
    func save(completion: ((Bool) -> Void)? = nil) {
        let unresolved = unresolvedConflicts.count
        if unresolved > 0 {
            let alert = NSAlert()
            alert.messageText = unresolved == 1 ? "One conflict is still unresolved" : "\(unresolved) conflicts are still unresolved"
            alert.informativeText = "Unresolved conflicts are written with <<<<<<< / ======= / >>>>>>> markers, like git does."
            alert.addButton(withTitle: "Save with Markers")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { completion?(false); return }
        }
        if let url = outputURL {
            write(to: url, completion: completion)
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = left.name
            panel.directoryURL = left.url.deletingLastPathComponent()
            panel.message = "Save the merged file"
            panel.begin { [weak self] response in
                guard let self else { return }
                guard response == .OK, let url = panel.url else { completion?(false); return }
                self.outputURL = url
                self.write(to: url, completion: completion)
            }
        }
    }

    private func write(to url: URL, completion: ((Bool) -> Void)?) {
        do {
            guard let data = mergedText.data(using: left.encoding) ?? mergedText.data(using: .utf8) else { return }
            let target = url.resolvingSymlinksInPath()
            do { try data.write(to: target, options: .atomic) } catch { try data.write(to: target) }
            isDirty = false
            errorMessage = nil
            completion?(true)
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            completion?(false)
        }
    }

    func copyMergedResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mergedText, forType: .string)
    }
}
