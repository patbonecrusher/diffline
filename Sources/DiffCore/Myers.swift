import Foundation

/// One run of an edit script: a slice of `a` and a slice of `b` that are equal, or that were
/// deleted from `a` / inserted into `b`. Ranges are indices into the original sequences.
public struct Segment: Equatable {
    public enum Kind { case equal, delete, insert }
    public var kind: Kind
    public var aRange: Range<Int>
    public var bRange: Range<Int>

    public init(kind: Kind, aRange: Range<Int>, bRange: Range<Int>) {
        self.kind = kind; self.aRange = aRange; self.bRange = bRange
    }
}

/// Myers' O(ND) diff with the linear-space "bisect" refinement (the divide-and-conquer form used by
/// diff-match-patch and git's xdiff). Works on integer tokens so callers can hash lines or words.
public enum Myers {
    public static func diff(_ a: [Int], _ b: [Int]) -> [Segment] {
        var out: [Segment] = []
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                solve(pa, pb, 0, pa.count, 0, pb.count, &out)
            }
        }
        return coalesce(out)
    }

    private static func solve(_ a: UnsafeBufferPointer<Int>, _ b: UnsafeBufferPointer<Int>,
                              _ a0: Int, _ a1: Int, _ b0: Int, _ b1: Int, _ out: inout [Segment]) {
        var a0 = a0, a1 = a1, b0 = b0, b1 = b1
        // Common prefix.
        var p = 0
        while a0 + p < a1 && b0 + p < b1 && a[a0 + p] == b[b0 + p] { p += 1 }
        if p > 0 { out.append(Segment(kind: .equal, aRange: a0..<a0 + p, bRange: b0..<b0 + p)); a0 += p; b0 += p }
        // Common suffix (emitted after the middle is solved).
        var s = 0
        while a1 - s > a0 && b1 - s > b0 && a[a1 - s - 1] == b[b1 - s - 1] { s += 1 }
        let suffix = s > 0 ? Segment(kind: .equal, aRange: a1 - s..<a1, bRange: b1 - s..<b1) : nil
        a1 -= s; b1 -= s

        let n = a1 - a0, m = b1 - b0
        if n == 0 && m == 0 {
            // nothing
        } else if n == 0 {
            out.append(Segment(kind: .insert, aRange: a0..<a0, bRange: b0..<b1))
        } else if m == 0 {
            out.append(Segment(kind: .delete, aRange: a0..<a1, bRange: b0..<b0))
        } else if let (x, y) = bisect(a, b, a0, a1, b0, b1) {
            solve(a, b, a0, a0 + x, b0, b0 + y, &out)
            solve(a, b, a0 + x, a1, b0 + y, b1, &out)
        } else {
            out.append(Segment(kind: .delete, aRange: a0..<a1, bRange: b0..<b0))
            out.append(Segment(kind: .insert, aRange: a1..<a1, bRange: b0..<b1))
        }
        if let suffix { out.append(suffix) }
    }

    /// Finds a point (x, y) relative to (a0, b0) that lies on an optimal edit path, by running the
    /// forward and reverse searches until they overlap. Returns nil when the two slices share nothing.
    private static func bisect(_ a: UnsafeBufferPointer<Int>, _ b: UnsafeBufferPointer<Int>,
                               _ a0: Int, _ a1: Int, _ b0: Int, _ b1: Int) -> (Int, Int)? {
        let n = a1 - a0, m = b1 - b0
        let maxD = (n + m + 1) / 2
        let vOffset = maxD
        let vLength = 2 * maxD
        var v1 = [Int](repeating: -1, count: vLength + 2)
        var v2 = [Int](repeating: -1, count: vLength + 2)
        v1[vOffset + 1] = 0
        v2[vOffset + 1] = 0
        let delta = n - m
        let front = delta % 2 != 0
        var k1start = 0, k1end = 0, k2start = 0, k2end = 0

        for d in 0..<maxD {
            // Forward path.
            var k1 = -d + k1start
            while k1 <= d - k1end {
                let k1o = vOffset + k1
                var x1: Int
                if k1 == -d || (k1 != d && v1[k1o - 1] < v1[k1o + 1]) { x1 = v1[k1o + 1] } else { x1 = v1[k1o - 1] + 1 }
                var y1 = x1 - k1
                while x1 < n && y1 < m && a[a0 + x1] == b[b0 + y1] { x1 += 1; y1 += 1 }
                v1[k1o] = x1
                if x1 > n {
                    k1end += 2
                } else if y1 > m {
                    k1start += 2
                } else if front {
                    let k2o = vOffset + delta - k1
                    if k2o >= 0 && k2o < vLength && v2[k2o] != -1 {
                        let x2 = n - v2[k2o]
                        if x1 >= x2 { return (x1, y1) }
                    }
                }
                k1 += 2
            }
            // Reverse path.
            var k2 = -d + k2start
            while k2 <= d - k2end {
                let k2o = vOffset + k2
                var x2: Int
                if k2 == -d || (k2 != d && v2[k2o - 1] < v2[k2o + 1]) { x2 = v2[k2o + 1] } else { x2 = v2[k2o - 1] + 1 }
                var y2 = x2 - k2
                while x2 < n && y2 < m && a[a1 - x2 - 1] == b[b1 - y2 - 1] { x2 += 1; y2 += 1 }
                v2[k2o] = x2
                if x2 > n {
                    k2end += 2
                } else if y2 > m {
                    k2start += 2
                } else if !front {
                    let k1o = vOffset + delta - k2
                    if k1o >= 0 && k1o < vLength && v1[k1o] != -1 {
                        let x1 = v1[k1o]
                        let y1 = vOffset + x1 - k1o
                        let x2f = n - x2
                        if x1 >= x2f { return (x1, y1) }
                    }
                }
                k2 += 2
            }
        }
        return nil
    }

    private static func coalesce(_ segs: [Segment]) -> [Segment] {
        var out: [Segment] = []
        out.reserveCapacity(segs.count)
        for s in segs {
            if s.aRange.isEmpty && s.bRange.isEmpty { continue }
            if let last = out.last, last.kind == s.kind,
               last.aRange.upperBound == s.aRange.lowerBound, last.bRange.upperBound == s.bRange.lowerBound {
                out[out.count - 1].aRange = last.aRange.lowerBound..<s.aRange.upperBound
                out[out.count - 1].bRange = last.bRange.lowerBound..<s.bRange.upperBound
            } else {
                out.append(s)
            }
        }
        return out
    }
}
