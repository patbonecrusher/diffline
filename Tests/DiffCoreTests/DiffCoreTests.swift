import XCTest
@testable import DiffCore

final class MyersTests: XCTestCase {
    /// Length of the longest common subsequence by dynamic programming (the oracle).
    private func lcs(_ a: [Int], _ b: [Int]) -> Int {
        var dp = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...max(a.count, 1) where i <= a.count {
            for j in 1...max(b.count, 1) where j <= b.count {
                dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] + 1 : max(dp[i - 1][j], dp[i][j - 1])
            }
        }
        return dp[a.count][b.count]
    }

    /// Replays the edit script and checks it reproduces `b` from `a`, and that it is minimal.
    private func check(_ a: [Int], _ b: [Int], file: StaticString = #filePath, line: UInt = #line) {
        let segs = Myers.diff(a, b)
        var rebuilt: [Int] = []
        var ai = 0, bi = 0
        var equalCount = 0
        for s in segs {
            XCTAssertEqual(s.aRange.lowerBound, ai, "a gap", file: file, line: line)
            XCTAssertEqual(s.bRange.lowerBound, bi, "b gap", file: file, line: line)
            switch s.kind {
            case .equal:
                XCTAssertEqual(s.aRange.count, s.bRange.count, file: file, line: line)
                for (x, y) in zip(s.aRange, s.bRange) { XCTAssertEqual(a[x], b[y], file: file, line: line) }
                rebuilt += b[s.bRange]; equalCount += s.aRange.count
            case .delete:
                XCTAssertTrue(s.bRange.isEmpty, file: file, line: line)
            case .insert:
                XCTAssertTrue(s.aRange.isEmpty, file: file, line: line)
                rebuilt += b[s.bRange]
            }
            ai = s.aRange.upperBound; bi = s.bRange.upperBound
        }
        XCTAssertEqual(ai, a.count, file: file, line: line)
        XCTAssertEqual(bi, b.count, file: file, line: line)
        XCTAssertEqual(rebuilt, b, file: file, line: line)
        XCTAssertEqual(equalCount, lcs(a, b), "not a minimal edit script for \(a) vs \(b)", file: file, line: line)
    }

    func testTrivial() {
        check([], [])
        check([1], [])
        check([], [1])
        check([1, 2, 3], [1, 2, 3])
        check([1, 2, 3], [4, 5, 6])
        check([1, 2, 3], [1, 3])
        check([1, 3], [1, 2, 3])
        check([1, 2, 3, 4], [2, 3, 4, 1])
    }

    func testClassicExample() {
        // From the Myers paper: ABCABBA -> CBABAC, D = 5, LCS = 4.
        let a = Array("ABCABBA").map { Int($0.asciiValue!) }
        let b = Array("CBABAC").map { Int($0.asciiValue!) }
        check(a, b)
    }

    func testRandomAgainstOracle() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<400 {
            let n = Int.random(in: 0...14, using: &rng), m = Int.random(in: 0...14, using: &rng)
            let alphabet = Int.random(in: 1...4, using: &rng)
            let a = (0..<n).map { _ in Int.random(in: 0..<alphabet, using: &rng) }
            let b = (0..<m).map { _ in Int.random(in: 0..<alphabet, using: &rng) }
            check(a, b)
        }
    }

    func testLargeInputPerformance() {
        let a = (0..<20_000).map { $0 % 977 }
        var b = a
        for i in stride(from: 0, to: b.count, by: 97) { b[i] = -1 }
        b.insert(contentsOf: [5, 6, 7], at: 100)
        measure { _ = Myers.diff(a, b) }
    }

    func testCompletelyDifferentLargeInputs() {
        let a = (0..<5_000).map { $0 }
        let b = (0..<5_000).map { $0 + 10_000 }
        let segs = Myers.diff(a, b)
        XCTAssertEqual(segs.map(\.kind), [.delete, .insert])
    }
}

final class LineDiffTests: XCTestCase {
    func testLineSplitting() {
        XCTAssertEqual(LineDiff.lines(of: "a\nb\n").map(String.init), ["a", "b"])
        XCTAssertEqual(LineDiff.lines(of: "a\nb").map(String.init), ["a", "b"])
        XCTAssertEqual(LineDiff.lines(of: "a\r\nb\r\n").map(String.init), ["a", "b"])
        XCTAssertEqual(LineDiff.lines(of: "").map(String.init), [])
        XCTAssertEqual(LineDiff.lines(of: "\n\n").map(String.init), ["", ""])
    }

    func testAlignedRows() {
        let r = LineDiff.compare("one\ntwo\nthree\nfour\n", "one\n2\nthree\nfour\nfive\n")
        XCTAssertEqual(r.rows.map(\.kind), [.same, .changed, .same, .same, .inserted])
        XCTAssertEqual(r.rows[1].left, 1); XCTAssertEqual(r.rows[1].right, 1)
        XCTAssertEqual(r.rows[4].left, nil); XCTAssertEqual(r.rows[4].right, 4)
        XCTAssertEqual(r.hunks.count, 2)
        XCTAssertEqual(r.hunks[0].rows, 1..<2)
        XCTAssertEqual(r.hunks[0].leftLines, 1..<2)
        XCTAssertEqual(r.hunks[0].rightLines, 1..<2)
        XCTAssertEqual(r.hunks[1].leftLines, 4..<4)
        XCTAssertEqual(r.hunks[1].rightLines, 4..<5)
    }

    func testUnevenChangeBlock() {
        let r = LineDiff.compare("a\nb\nc\nd\n", "a\nX\nd\n")
        XCTAssertEqual(r.rows.map(\.kind), [.same, .changed, .deleted, .same])
        XCTAssertEqual(r.hunks.count, 1)
        XCTAssertEqual(r.hunks[0].leftLines, 1..<3)
        XCTAssertEqual(r.hunks[0].rightLines, 1..<2)
    }

    func testIdentical() {
        let r = LineDiff.compare("a\nb\n", "a\nb\n")
        XCTAssertTrue(r.isIdentical)
        XCTAssertEqual(r.rows.count, 2)
    }

    func testWhitespaceOptions() {
        var o = DiffOptions(); o.whitespace = .ignoreTrailing
        XCTAssertTrue(LineDiff.compare("a  \nb\n", "a\nb\n", options: o).isIdentical)
        o.whitespace = .ignoreChanges
        XCTAssertTrue(LineDiff.compare("  a   b \n", "a b\n", options: o).isIdentical)
        o.whitespace = .ignoreAll
        XCTAssertTrue(LineDiff.compare("a b\n", "ab\n", options: o).isIdentical)
        o.whitespace = .exact; o.ignoreCase = true
        XCTAssertTrue(LineDiff.compare("Hello\n", "hello\n", options: o).isIdentical)
    }

    func testIgnoreBlankLines() {
        var o = DiffOptions(); o.ignoreBlankLines = true
        let r = LineDiff.compare("a\n\n\nb\n", "a\nb\n", options: o)
        XCTAssertTrue(r.isIdentical)
        XCTAssertEqual(r.rows.count, 4)
    }

    func testIntraLineHighlights() {
        let (l, r) = IntraLine.highlights("let x = 10", "let y = 10", options: DiffOptions())
        XCTAssertEqual(l, [4..<5])
        XCTAssertEqual(r, [4..<5])
        let (l2, r2) = IntraLine.highlights("abc", "xyz", options: DiffOptions())
        XCTAssertTrue(l2.isEmpty && r2.isEmpty, "completely different lines get no inline highlights")
        let (l3, r3) = IntraLine.highlights("foo(bar, baz)", "foo(bar, qux, baz)", options: DiffOptions())
        XCTAssertTrue(l3.isEmpty)
        XCTAssertEqual(r3, [9..<14])   // "qux, "
    }

    func testUnifiedOutput() {
        let a = "1\n2\n3\n4\n5\n6\n7\n8\n9\n", b = "1\n2\n3\n4\nfive\n6\n7\n8\n9\n"
        let r = LineDiff.compare(a, b)
        let u = UnifiedDiff.render(left: LineDiff.lines(of: a), right: LineDiff.lines(of: b), segments: r.segments,
                                   leftName: "a.txt", rightName: "b.txt")
        XCTAssertEqual(u, """
        --- a.txt
        +++ b.txt
        @@ -2,7 +2,7 @@
         2
         3
         4
        -5
        +five
         6
         7
         8

        """)
    }

    func testUnifiedInsertAtStartAndEnd() {
        let a = "b\n", b = "a\nb\nc\n"
        let r = LineDiff.compare(a, b)
        let u = UnifiedDiff.render(left: LineDiff.lines(of: a), right: LineDiff.lines(of: b), segments: r.segments,
                                   leftName: "a", rightName: "b")
        XCTAssertEqual(u, "--- a\n+++ b\n@@ -1,1 +1,3 @@\n+a\n b\n+c\n")
    }
}

final class FolderCompareTests: XCTestCase {
    func testTreeStatuses() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let l = tmp.appendingPathComponent("left"), r = tmp.appendingPathComponent("right")
        try FileManager.default.createDirectory(at: l.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: r.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: l.appendingPathComponent("onlyleft"), withIntermediateDirectories: true)
        try "same".write(to: l.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)
        try "same".write(to: r.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)
        try "aaaa".write(to: l.appendingPathComponent("sub/diff.txt"), atomically: true, encoding: .utf8)
        try "bbbb".write(to: r.appendingPathComponent("sub/diff.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: r.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        try "h".write(to: l.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let root = try FolderComparer(left: l, right: r).run()
        let byName = Dictionary(uniqueKeysWithValues: root.children!.map { ($0.name, $0) })
        XCTAssertEqual(byName["same.txt"]?.status, .same)
        XCTAssertEqual(byName["new.txt"]?.status, .rightOnly)
        XCTAssertEqual(byName["onlyleft"]?.status, .leftOnly)
        XCTAssertEqual(byName["sub"]?.status, .different)
        XCTAssertEqual(byName["sub"]?.children?.first?.status, .different)
        XCTAssertNil(byName[".hidden"])
        XCTAssertEqual(root.status, .different)
        XCTAssertEqual(root.differenceCount, 3)
        let filtered = root.filteredToDifferences()!
        XCTAssertEqual(filtered.children!.map(\.name), ["new.txt", "onlyleft", "sub"])
    }
}

final class AssembleTests: XCTestCase {
    func testInterleavedDeletesAndInsertsFormOneBlock() {
        // a: x A B y   b: x C D E y, as the script  eq(x) del(A) ins(C) del(B) ins(D E) eq(y)
        let left: [Substring] = ["x", "A", "B", "y"], right: [Substring] = ["x", "C", "D", "E", "y"]
        let segs = [
            Segment(kind: .equal, aRange: 0..<1, bRange: 0..<1),
            Segment(kind: .delete, aRange: 1..<2, bRange: 1..<1),
            Segment(kind: .insert, aRange: 2..<2, bRange: 1..<2),
            Segment(kind: .delete, aRange: 2..<3, bRange: 2..<2),
            Segment(kind: .insert, aRange: 3..<3, bRange: 2..<4),
            Segment(kind: .equal, aRange: 3..<4, bRange: 4..<5),
        ]
        let (rows, hunks) = LineDiff.assemble(segments: segs, left: left, right: right, options: DiffOptions(), intraLine: false, isBlank: { _, _ in false })
        XCTAssertEqual(rows.map(\.kind), [.same, .changed, .changed, .inserted, .same])
        XCTAssertEqual(rows.map(\.left), [0, 1, 2, nil, 3])
        XCTAssertEqual(rows.map(\.right), [0, 1, 2, 3, 4])
        XCTAssertEqual(hunks, [Hunk(rows: 1..<4, leftLines: 1..<3, rightLines: 1..<4)])
    }
}

final class SyntaxTests: XCTestCase {
    private func kinds(_ lang: Language, _ lines: [String]) -> [[(TokenKind, String)]] {
        SyntaxHighlighter(language: lang).tokenize(lines: lines).enumerated().map { i, toks in
            toks.map { t in
                let s = lines[i] as NSString
                return (t.kind, s.substring(with: NSRange(location: t.range.lowerBound, length: t.range.count)))
            }
        }
    }

    func testSwiftLine() {
        let t = kinds(.swift, ["let x = \"hi\\\"there\" // done", "@MainActor func f() -> Int { return 42 }"])
        XCTAssertEqual(t[0].map(\.0), [.keyword, .string, .comment])
        XCTAssertEqual(t[0][1].1, "\"hi\\\"there\"")
        XCTAssertEqual(t[1].map { $0.1 }, ["@MainActor", "func", "Int", "return", "42"])
    }

    func testBlockCommentAcrossLines() {
        let t = kinds(.c, ["int a; /* start", "still comment", "end */ int b;"])
        XCTAssertEqual(t[0].map(\.0), [.keyword, .comment])
        XCTAssertEqual(t[1].map(\.0), [.comment])
        XCTAssertEqual(t[2].map(\.0), [.comment, .keyword])
        XCTAssertEqual(t[2][0].1, "end */")
    }

    func testPythonTripleQuotedString() {
        let t = kinds(.python, ["def f():", "    \"\"\"Doc", "    more\"\"\"", "    return None  # c"])
        XCTAssertEqual(t[0].map(\.0), [.keyword])
        XCTAssertEqual(t[1].map(\.0), [.string])
        XCTAssertEqual(t[2].map(\.0), [.string])
        XCTAssertEqual(t[3].map(\.0), [.keyword, .keyword, .comment])
    }

    func testJSONKeysAndValues() {
        let t = kinds(.json, ["{\"name\": \"x\", \"n\": 3, \"ok\": true}"])
        XCTAssertEqual(t[0].map(\.0), [.attribute, .string, .attribute, .number, .attribute, .keyword])
    }

    func testMarkup() {
        let t = kinds(.markup, ["<a href=\"x\">hi</a> <!-- c -->"])
        XCTAssertEqual(t[0].map(\.0), [.tag, .attribute, .string, .tag, .tag, .tag, .comment])
    }

    func testYAMLKeys() {
        let t = kinds(.yaml, ["name: Build", "  runs-on: macos-15  # ci", "on: [push]"])
        XCTAssertEqual(t[0].map { $0.1 }, ["name"])
        XCTAssertEqual(t[1].map(\.0), [.attribute, .comment])
        XCTAssertEqual(t[2].map { $0.1 }, ["on"])
    }

    func testShellVariableIsNotAComment() {
        let t = kinds(.shell, ["echo \"$HOME\" $#  # comment"])
        XCTAssertEqual(t[0].map(\.0), [.keyword, .string, .comment])
    }

    func testDetection() {
        XCTAssertEqual(Language.detect(filename: "/x/y/Foo.swift"), .swift)
        XCTAssertEqual(Language.detect(filename: "Makefile"), .makefile)
        XCTAssertEqual(Language.detect(filename: "Package.swift"), .swift)
        XCTAssertNil(Language.detect(filename: "notes.txt"))
    }
}

final class ThreeWayTests: XCTestCase {
    private func lines(_ s: String) -> [Substring] { LineDiff.lines(of: s) }

    func testNonOverlappingChangesMergeAutomatically() {
        let base = lines("a\nb\nc\nd\ne\n")
        let left = lines("a\nB\nc\nd\ne\n")        // left changed line 2
        let right = lines("a\nb\nc\nd\nE\n")       // right changed line 5
        let m = ThreeWayMerge.merge(base: base, left: left, right: right)
        XCTAssertEqual(m.chunks.map(\.kind), [.stable, .leftOnly, .stable, .rightOnly])
        XCTAssertFalse(m.hasConflicts)
        XCTAssertEqual(m.output(base: base, left: left, right: right, resolutions: [:]).map(String.init), ["a", "B", "c", "d", "E"])
    }

    func testConflict() {
        let base = lines("a\nb\nc\n")
        let left = lines("a\nL\nc\n")
        let right = lines("a\nR\nc\n")
        let m = ThreeWayMerge.merge(base: base, left: left, right: right)
        XCTAssertEqual(m.chunks.map(\.kind), [.stable, .conflict, .stable])
        XCTAssertEqual(m.conflicts, [1])
        let marked = m.output(base: base, left: left, right: right, resolutions: [:]).map(String.init)
        XCTAssertEqual(marked, ["a", "<<<<<<< ours", "L", "=======", "R", ">>>>>>> theirs", "c"])
        XCTAssertEqual(m.output(base: base, left: left, right: right, resolutions: [1: .right]).map(String.init), ["a", "R", "c"])
        XCTAssertEqual(m.output(base: base, left: left, right: right, resolutions: [1: .both]).map(String.init), ["a", "L", "R", "c"])
        XCTAssertEqual(m.output(base: base, left: left, right: right, resolutions: [1: .base]).map(String.init), ["a", "b", "c"])
    }

    func testSameChangeOnBothSides() {
        let base = lines("a\nb\n"), left = lines("a\nX\n"), right = lines("a\nX\n")
        let m = ThreeWayMerge.merge(base: base, left: left, right: right)
        XCTAssertEqual(m.chunks.map(\.kind), [.stable, .bothSame])
        XCTAssertEqual(m.output(base: base, left: left, right: right, resolutions: [:]).map(String.init), ["a", "X"])
    }

    func testInsertionsBeforeAnAnchor() {
        let base = lines("a\nb\n")
        let left = lines("a\nL1\nL2\nb\n")          // inserted before b
        let right = lines("a\nb\nR\n")              // appended at end
        let m = ThreeWayMerge.merge(base: base, left: left, right: right)
        XCTAssertEqual(m.chunks.map(\.kind), [.stable, .leftOnly, .stable, .rightOnly])
        XCTAssertEqual(m.output(base: base, left: left, right: right, resolutions: [:]).map(String.init), ["a", "L1", "L2", "b", "R"])
    }

    func testDeletionOnOneSideAndEditOnTheOtherConflicts() {
        let base = lines("a\nb\nc\n")
        let left = lines("a\nc\n")                  // deleted b
        let right = lines("a\nb2\nc\n")             // edited b
        let m = ThreeWayMerge.merge(base: base, left: left, right: right)
        XCTAssertEqual(m.chunks.map(\.kind), [.stable, .conflict, .stable])
        XCTAssertEqual(m.chunks[1].left, 1..<1)
        XCTAssertEqual(m.chunks[1].right, 1..<2)
    }

    func testBothSidesInsertDifferentThingsAtTheSamePlace() {
        let base = lines("a\nb\n"), left = lines("a\nL\nb\n"), right = lines("a\nR\nb\n")
        let m = ThreeWayMerge.merge(base: base, left: left, right: right)
        XCTAssertEqual(m.chunks.map(\.kind), [.stable, .conflict, .stable])
        XCTAssertEqual(m.chunks[1].base, 1..<1)
    }

    func testEmptyInputs() {
        let m = ThreeWayMerge.merge(base: [], left: lines("x\n"), right: [])
        XCTAssertEqual(m.chunks.map(\.kind), [.leftOnly])
        XCTAssertTrue(ThreeWayMerge.merge(base: [], left: [], right: []).chunks.isEmpty)
    }
}
