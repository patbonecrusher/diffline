import Foundation

/// How lines are normalized before comparison.
public struct DiffOptions: Equatable, Codable {
    public enum Whitespace: String, Codable, CaseIterable {
        case exact            // compare bytes as they are
        case ignoreTrailing   // ignore trailing whitespace
        case ignoreChanges    // collapse runs of whitespace, ignore leading/trailing
        case ignoreAll        // drop all whitespace
    }
    public var whitespace: Whitespace = .exact
    public var ignoreCase = false
    public var ignoreBlankLines = false
    public var tabWidth = 4

    public init() {}

    public func normalize(_ line: Substring) -> String {
        var s: String
        switch whitespace {
        case .exact: s = String(line)
        case .ignoreTrailing:
            s = String(line)
            while let last = s.last, last == " " || last == "\t" { s.removeLast() }
        case .ignoreChanges:
            s = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        case .ignoreAll:
            s = line.filter { $0 != " " && $0 != "\t" }
        }
        if ignoreCase { s = s.lowercased() }
        return s
    }
}

/// One row of an aligned side-by-side display.
public struct DiffRow: Equatable {
    public enum Kind: Equatable { case same, changed, deleted, inserted }
    public var kind: Kind
    /// Index into the left/right line arrays, nil for a padding cell.
    public var left: Int?
    public var right: Int?
    /// Character ranges (in the display text of that line) to emphasize for `changed` rows.
    public var leftHighlights: [Range<Int>] = []
    public var rightHighlights: [Range<Int>] = []

    public init(kind: Kind, left: Int?, right: Int?) { self.kind = kind; self.left = left; self.right = right }
}

/// A contiguous run of non-identical rows, which is the unit of navigation and merging.
public struct Hunk: Equatable {
    public var rows: Range<Int>
    public var leftLines: Range<Int>     // lines of the left file covered (may be empty)
    public var rightLines: Range<Int>
    public init(rows: Range<Int>, leftLines: Range<Int>, rightLines: Range<Int>) {
        self.rows = rows; self.leftLines = leftLines; self.rightLines = rightLines
    }
}

/// The result of comparing two texts line by line.
public struct LineDiffResult: Equatable {
    public var rows: [DiffRow]
    public var hunks: [Hunk]
    public var segments: [Segment]
    public var options: DiffOptions

    public var isIdentical: Bool { hunks.isEmpty }

    public var stats: (changed: Int, inserted: Int, deleted: Int) {
        var c = 0, i = 0, d = 0
        for r in rows {
            switch r.kind {
            case .changed: c += 1
            case .inserted: i += 1
            case .deleted: d += 1
            case .same: break
            }
        }
        return (c, i, d)
    }
}

public enum LineDiff {
    /// Splits text into lines without their terminators. A trailing newline does not produce an empty final line.
    public static func lines(of text: String) -> [Substring] {
        var out: [Substring] = []
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "\n" || ch == "\r\n" || ch == "\r" {
                out.append(text[start..<i])
                i = text.index(after: i)
                start = i
            } else {
                i = text.index(after: i)
            }
        }
        if start < text.endIndex { out.append(text[start..<text.endIndex]) }
        return out
    }

    public static func compare(_ left: [Substring], _ right: [Substring], options: DiffOptions = DiffOptions(),
                               intraLine: Bool = true) -> LineDiffResult {
        var table: [String: Int] = [:]
        func token(_ s: Substring) -> Int {
            let key = options.normalize(s)
            if let t = table[key] { return t }
            let t = table.count
            table[key] = t
            return t
        }
        let blankToken: Int? = options.ignoreBlankLines ? token("") : nil
        let a = left.map(token), b = right.map(token)
        let segments = Myers.diff(a, b)
        let (rows, hunks) = assemble(segments: segments, left: left, right: right, options: options, intraLine: intraLine,
                                     isBlank: { side, i in blankToken.map { (side == 0 ? a[i] : b[i]) == $0 } ?? false })
        return LineDiffResult(rows: rows, hunks: hunks, segments: segments, options: options)
    }

    /// Turns an edit script into aligned rows and hunks. Every maximal run of non-equal segments becomes
    /// one change block, whatever order the deletes and inserts came out of the search in.
    static func assemble(segments: [Segment], left: [Substring], right: [Substring], options: DiffOptions, intraLine: Bool,
                         isBlank: (Int, Int) -> Bool) -> ([DiffRow], [Hunk]) {
        var rows: [DiffRow] = []
        rows.reserveCapacity(max(left.count, right.count))
        var hunks: [Hunk] = []
        var i = 0
        while i < segments.count {
            let seg = segments[i]
            if seg.kind == .equal {
                for (l, r) in zip(seg.aRange, seg.bRange) { rows.append(DiffRow(kind: .same, left: l, right: r)) }
                i += 1
                continue
            }
            // Gather the whole block of deletes and inserts; they are contiguous in each file.
            var del = seg.aRange.lowerBound..<seg.aRange.lowerBound
            var ins = seg.bRange.lowerBound..<seg.bRange.lowerBound
            while i < segments.count, segments[i].kind != .equal {
                let s = segments[i]
                if s.kind == .delete { del = del.lowerBound..<s.aRange.upperBound }
                else { ins = ins.lowerBound..<s.bRange.upperBound }
                i += 1
            }
            let blankOnly = options.ignoreBlankLines && del.allSatisfy { isBlank(0, $0) } && ins.allSatisfy { isBlank(1, $0) }
            let start = rows.count
            let paired = min(del.count, ins.count)
            for k in 0..<paired {
                var row = DiffRow(kind: blankOnly ? .same : .changed, left: del.lowerBound + k, right: ins.lowerBound + k)
                if intraLine && !blankOnly {
                    let (lh, rh) = IntraLine.highlights(left[row.left!], right[row.right!], options: options)
                    row.leftHighlights = lh; row.rightHighlights = rh
                }
                rows.append(row)
            }
            for k in paired..<del.count { rows.append(DiffRow(kind: blankOnly ? .same : .deleted, left: del.lowerBound + k, right: nil)) }
            for k in paired..<ins.count { rows.append(DiffRow(kind: blankOnly ? .same : .inserted, left: nil, right: ins.lowerBound + k)) }
            if !blankOnly {
                hunks.append(Hunk(rows: start..<rows.count, leftLines: del, rightLines: ins))
            }
        }
        return (rows, hunks)
    }


    public static func compare(_ leftText: String, _ rightText: String, options: DiffOptions = DiffOptions()) -> LineDiffResult {
        compare(lines(of: leftText), lines(of: rightText), options: options)
    }
}

// MARK: - Intra-line highlighting

public enum IntraLine {
    /// Tokenizes into words, whitespace runs and single punctuation characters.
    static func tokens(_ s: Substring) -> [(Range<Int>, Substring)] {
        var out: [(Range<Int>, Substring)] = []
        let chars = Array(s.indices)
        var i = 0
        func cls(_ c: Character) -> Int {
            if c.isLetter || c.isNumber || c == "_" { return 0 }
            if c == " " || c == "\t" { return 1 }
            return 2
        }
        while i < chars.count {
            let c = s[chars[i]]
            let k = cls(c)
            var j = i + 1
            if k != 2 { while j < chars.count && cls(s[chars[j]]) == k { j += 1 } }
            let end = j < chars.count ? chars[j] : s.endIndex
            out.append((i..<j, s[chars[i]..<end]))
            i = j
        }
        return out
    }

    /// Character ranges that differ between two lines. Returns empty ranges when the lines are so
    /// different that highlighting would cover most of them.
    public static func highlights(_ l: Substring, _ r: Substring, options: DiffOptions) -> ([Range<Int>], [Range<Int>]) {
        let lt = tokens(l), rt = tokens(r)
        var table: [String: Int] = [:]
        func tok(_ s: Substring) -> Int {
            var key = String(s)
            if options.ignoreCase { key = key.lowercased() }
            if options.whitespace != .exact, key.allSatisfy({ $0 == " " || $0 == "\t" }) { key = " " }
            if let t = table[key] { return t }
            let t = table.count; table[key] = t; return t
        }
        let segs = Myers.diff(lt.map { tok($0.1) }, rt.map { tok($0.1) })
        var lh: [Range<Int>] = [], rh: [Range<Int>] = []
        var lCount = 0, rCount = 0
        for s in segs {
            switch s.kind {
            case .equal: break
            case .delete:
                let range = lt[s.aRange.lowerBound].0.lowerBound..<lt[s.aRange.upperBound - 1].0.upperBound
                lh.append(range); lCount += range.count
            case .insert:
                let range = rt[s.bRange.lowerBound].0.lowerBound..<rt[s.bRange.upperBound - 1].0.upperBound
                rh.append(range); rCount += range.count
            }
        }
        // If nearly everything changed, a whole-row tint reads better than a sea of highlights.
        let lLen = max(l.count, 1), rLen = max(r.count, 1)
        if Double(lCount) / Double(lLen) > 0.7 && Double(rCount) / Double(rLen) > 0.7 { return ([], []) }
        return (merge(lh), merge(rh))
    }

    private static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for r in ranges {
            if let last = out.last, last.upperBound >= r.lowerBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                out.append(r)
            }
        }
        return out
    }
}

// MARK: - Unified diff output

public enum UnifiedDiff {
    public static func render(left: [Substring], right: [Substring], segments: [Segment],
                              leftName: String, rightName: String, context: Int = 3) -> String {
        var out = "--- \(leftName)\n+++ \(rightName)\n"
        // Expand segments into per-line ops.
        enum Op { case eq(Int, Int), del(Int), ins(Int) }
        var ops: [Op] = []
        for s in segments {
            switch s.kind {
            case .equal: for (l, r) in zip(s.aRange, s.bRange) { ops.append(.eq(l, r)) }
            case .delete: for l in s.aRange { ops.append(.del(l)) }
            case .insert: for r in s.bRange { ops.append(.ins(r)) }
            }
        }
        // Group into hunks with context.

        func nextRight(_ ops: [Op], from: Int) -> Int {
            for op in ops[from...] { switch op { case .eq(_, let r): return r; case .ins(let r): return r; default: continue } }
            return right.count
        }
        func nextLeft(_ ops: [Op], from: Int) -> Int {
            for op in ops[from...] { switch op { case .eq(let l, _): return l; case .del(let l): return l; default: continue } }
            return left.count
        }
        var i = 0
        func isChange(_ op: Op) -> Bool { if case .eq = op { return false } else { return true } }
        while i < ops.count {
            guard isChange(ops[i]) else { i += 1; continue }
            let start = max(0, i - context)
            var end = i
            // Extend while the next change is within 2*context lines.
            var j = i
            while j < ops.count {
                if isChange(ops[j]) { end = j + 1; j += 1; continue }
                var k = j
                while k < ops.count && !isChange(ops[k]) && k - j < 2 * context { k += 1 }
                if k < ops.count && isChange(ops[k]) { j = k } else { break }
            }
            end = min(ops.count, end + context)
            // Header.
            var lStart = 0, rStart = 0, lCount = 0, rCount = 0
            var firstSet = false
            var body = ""
            for op in ops[start..<end] {
                switch op {
                case .eq(let l, let r):
                    if !firstSet { lStart = l; rStart = r; firstSet = true }
                    lCount += 1; rCount += 1
                    body += " \(left[l])\n"
                case .del(let l):
                    if !firstSet { lStart = l; rStart = nextRight(ops, from: start); firstSet = true }
                    lCount += 1
                    body += "-\(left[l])\n"
                case .ins(let r):
                    if !firstSet { lStart = nextLeft(ops, from: start); rStart = r; firstSet = true }
                    rCount += 1
                    body += "+\(right[r])\n"
                }
            }
            out += "@@ -\(lCount == 0 ? lStart : lStart + 1),\(lCount) +\(rCount == 0 ? rStart : rStart + 1),\(rCount) @@\n"
            out += body
            i = end
        }
        return out
    }
}
