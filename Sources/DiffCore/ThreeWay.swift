import Foundation

/// One region of a three-way merge: a run of lines that is either unchanged in both sides, changed on
/// one side only, changed identically on both sides, or changed differently on both (a conflict).
public struct MergeChunk: Equatable {
    public enum Kind: Equatable { case stable, leftOnly, rightOnly, bothSame, conflict }
    public var kind: Kind
    public var base: Range<Int>
    public var left: Range<Int>
    public var right: Range<Int>

    public init(kind: Kind, base: Range<Int>, left: Range<Int>, right: Range<Int>) {
        self.kind = kind; self.base = base; self.left = left; self.right = right
    }
}

/// How a conflict (or any chunk, if the user overrides the automatic choice) is resolved.
public enum Resolution: Equatable, Codable {
    case left, right, base, both, bothReversed
}

public struct ThreeWayMerge: Equatable {
    public var chunks: [MergeChunk]

    public var conflicts: [Int] { chunks.indices.filter { chunks[$0].kind == .conflict } }
    public var hasConflicts: Bool { chunks.contains { $0.kind == .conflict } }

    /// The classic diff3 algorithm: diff base against each side, then walk the base finding lines that
    /// both sides kept; everything between two such anchors is one change chunk.
    public static func merge(base: [Substring], left: [Substring], right: [Substring], options: DiffOptions = DiffOptions()) -> ThreeWayMerge {
        var table: [String: Int] = [:]
        func token(_ s: Substring) -> Int {
            let key = options.normalize(s)
            if let t = table[key] { return t }
            let t = table.count; table[key] = t; return t
        }
        let b = base.map(token), l = left.map(token), r = right.map(token)
        return merge(baseTokens: b, leftTokens: l, rightTokens: r)
    }

    static func merge(baseTokens b: [Int], leftTokens l: [Int], rightTokens r: [Int]) -> ThreeWayMerge {
        var baseToLeft = [Int?](repeating: nil, count: b.count)
        var baseToRight = [Int?](repeating: nil, count: b.count)
        for s in Myers.diff(b, l) where s.kind == .equal { for (x, y) in zip(s.aRange, s.bRange) { baseToLeft[x] = y } }
        for s in Myers.diff(b, r) where s.kind == .equal { for (x, y) in zip(s.aRange, s.bRange) { baseToRight[x] = y } }

        func isAnchor(_ i: Int) -> Bool { i < b.count && baseToLeft[i] != nil && baseToRight[i] != nil }

        var chunks: [MergeChunk] = []
        var i = 0, li = 0, ri = 0
        func appendStable(_ i0: Int, _ i1: Int, _ l0: Int, _ r0: Int) {
            let n = i1 - i0
            if let last = chunks.last, last.kind == .stable, last.base.upperBound == i0 {
                chunks[chunks.count - 1].base = last.base.lowerBound..<i1
                chunks[chunks.count - 1].left = last.left.lowerBound..<l0 + n
                chunks[chunks.count - 1].right = last.right.lowerBound..<r0 + n
            } else {
                chunks.append(MergeChunk(kind: .stable, base: i0..<i1, left: l0..<l0 + n, right: r0..<r0 + n))
            }
        }
        while i < b.count || li < l.count || ri < r.count {
            if isAnchor(i), baseToLeft[i] == li, baseToRight[i] == ri {
                appendStable(i, i + 1, li, ri)
                i += 1; li += 1; ri += 1
                continue
            }
            // A change region: runs until the next anchor (which may be this very line if only insertions precede it).
            var i2 = isAnchor(i) ? i : i + 1
            while i2 < b.count && !isAnchor(i2) { i2 += 1 }
            let lEnd = i2 < b.count ? baseToLeft[i2]! : l.count
            let rEnd = i2 < b.count ? baseToRight[i2]! : r.count
            let bRange = i..<min(i2, b.count), lRange = li..<lEnd, rRange = ri..<rEnd
            let baseSlice = b[bRange], leftSlice = l[lRange], rightSlice = r[rRange]
            let kind: MergeChunk.Kind
            if leftSlice.elementsEqual(baseSlice) && rightSlice.elementsEqual(baseSlice) {
                kind = .stable
            } else if leftSlice.elementsEqual(baseSlice) {
                kind = .rightOnly
            } else if rightSlice.elementsEqual(baseSlice) {
                kind = .leftOnly
            } else if leftSlice.elementsEqual(rightSlice) {
                kind = .bothSame
            } else {
                kind = .conflict
            }
            chunks.append(MergeChunk(kind: kind, base: bRange, left: lRange, right: rRange))
            i = bRange.upperBound; li = lEnd; ri = rEnd
        }
        return ThreeWayMerge(chunks: chunks)
    }

    /// The automatic choice for a chunk, before the user overrides anything. Conflicts have none.
    public static func defaultResolution(for kind: MergeChunk.Kind) -> Resolution? {
        switch kind {
        case .stable: .base
        case .leftOnly: .left
        case .rightOnly: .right
        case .bothSame: .left
        case .conflict: nil
        }
    }

    /// Lines a chunk contributes to the merged output under a resolution.
    public static func lines<T>(of chunk: MergeChunk, resolution: Resolution, base: [T], left: [T], right: [T]) -> [T] {
        switch resolution {
        case .left: Array(left[chunk.left])
        case .right: Array(right[chunk.right])
        case .base: Array(base[chunk.base])
        case .both: Array(left[chunk.left]) + Array(right[chunk.right])
        case .bothReversed: Array(right[chunk.right]) + Array(left[chunk.left])
        }
    }

    /// The merged file. Unresolved conflicts are written with git-style markers so nothing is lost.
    public func output(base: [Substring], left: [Substring], right: [Substring], resolutions: [Int: Resolution],
                       leftLabel: String = "ours", rightLabel: String = "theirs", baseLabel: String? = nil) -> [Substring] {
        var out: [Substring] = []
        for (idx, chunk) in chunks.enumerated() {
            if let res = resolutions[idx] ?? Self.defaultResolution(for: chunk.kind) {
                out += Self.lines(of: chunk, resolution: res, base: base, left: left, right: right)
            } else {
                out.append(Substring("<<<<<<< " + leftLabel))
                out += left[chunk.left]
                if let baseLabel {
                    out.append(Substring("||||||| " + baseLabel))
                    out += base[chunk.base]
                }
                out.append(Substring("======="))
                out += right[chunk.right]
                out.append(Substring(">>>>>>> " + rightLabel))
            }
        }
        return out
    }
}
