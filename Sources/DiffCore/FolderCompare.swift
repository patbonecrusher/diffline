import Foundation

public enum EntryStatus: String, Codable { case same, different, leftOnly, rightOnly }

public struct FolderEntry: Identifiable, Equatable {
    public var id: String { relativePath }
    public var name: String
    public var relativePath: String
    public var isDirectory: Bool
    public var status: EntryStatus
    public var leftSize: Int?
    public var rightSize: Int?
    public var leftDate: Date?
    public var rightDate: Date?
    public var children: [FolderEntry]?

    /// Count of differing files below this entry (including itself when it is a file).
    public var differenceCount: Int {
        if let children {
            let n = children.reduce(0) { $0 + $1.differenceCount }
            return (n == 0 && status != .same) ? 1 : n   // an empty one-sided folder is still a difference
        }
        return status == .same ? 0 : 1
    }

    /// Returns a copy with only non-identical entries (directories kept when they contain any).
    public func filteredToDifferences() -> FolderEntry? {
        if let children {
            let kept = children.compactMap { $0.filteredToDifferences() }
            if kept.isEmpty && status == .same { return nil }
            var copy = self; copy.children = kept
            return copy
        }
        return status == .same ? nil : self
    }
}

public struct FolderCompareOptions: Equatable {
    public var includeHidden = false
    public var compareContents = true    // false: size + date only
    public init() {}
}

public struct FolderComparer {
    public struct Cancelled: Error {}

    let left: URL
    let right: URL
    let options: FolderCompareOptions
    let isCancelled: () -> Bool
    let progress: (Int) -> Void

    public init(left: URL, right: URL, options: FolderCompareOptions = FolderCompareOptions(),
                isCancelled: @escaping () -> Bool = { false }, progress: @escaping (Int) -> Void = { _ in }) {
        self.left = left; self.right = right; self.options = options
        self.isCancelled = isCancelled; self.progress = progress
    }

    public func run() throws -> FolderEntry {
        var counter = 0
        return try compareDirectory(relative: "", name: left.lastPathComponent + " ↔ " + right.lastPathComponent,
                                    leftExists: true, rightExists: true, counter: &counter)
    }

    private struct Item {
        var name: String
        var isDirectory: Bool
        var size: Int?
        var date: Date?
    }

    private func list(_ dir: URL) throws -> [String: Item] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey, .isSymbolicLinkKey]
        let urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: [])
        var out: [String: Item] = [:]
        for u in urls {
            let v = try u.resourceValues(forKeys: keys)
            if !options.includeHidden, v.isHidden == true { continue }
            let isDir = v.isDirectory == true && v.isSymbolicLink != true
            out[u.lastPathComponent] = Item(name: u.lastPathComponent, isDirectory: isDir,
                                            size: isDir ? nil : v.fileSize, date: v.contentModificationDate)
        }
        return out
    }

    private func compareDirectory(relative: String, name: String, leftExists: Bool, rightExists: Bool,
                                  counter: inout Int) throws -> FolderEntry {
        if isCancelled() { throw Cancelled() }
        let lItems = leftExists ? try list(left.appendingPathComponent(relative)) : [:]
        let rItems = rightExists ? try list(right.appendingPathComponent(relative)) : [:]
        let names = Set(lItems.keys).union(rItems.keys).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var children: [FolderEntry] = []
        var anyDifferent = false
        for n in names {
            let rel = relative.isEmpty ? n : relative + "/" + n
            let l = lItems[n], r = rItems[n]
            let isDir = (l?.isDirectory ?? false) || (r?.isDirectory ?? false)
            if isDir {
                var child = try compareDirectory(relative: rel, name: n, leftExists: l?.isDirectory == true,
                                                 rightExists: r?.isDirectory == true, counter: &counter)
                if l == nil { child.status = .rightOnly }
                if r == nil { child.status = .leftOnly }
                // A file on one side and a directory on the other counts as different.
                if (l != nil && l!.isDirectory == false) || (r != nil && r!.isDirectory == false) { child.status = .different }
                if child.status != .same { anyDifferent = true }
                children.append(child)
            } else {
                counter += 1
                if counter % 50 == 0 { progress(counter) }
                var e = FolderEntry(name: n, relativePath: rel, isDirectory: false, status: .same,
                                    leftSize: l?.size, rightSize: r?.size, leftDate: l?.date, rightDate: r?.date, children: nil)
                if l == nil { e.status = .rightOnly }
                else if r == nil { e.status = .leftOnly }
                else if l!.size != r!.size { e.status = .different }
                else if options.compareContents {
                    if isCancelled() { throw Cancelled() }
                    e.status = try filesEqual(left.appendingPathComponent(rel), right.appendingPathComponent(rel)) ? .same : .different
                } else if l!.date != r!.date {
                    e.status = .different
                }
                if e.status != .same { anyDifferent = true }
                children.append(e)
            }
        }
        var status: EntryStatus = anyDifferent ? .different : .same
        if !leftExists { status = .rightOnly }
        if !rightExists { status = .leftOnly }
        return FolderEntry(name: name, relativePath: relative, isDirectory: true, status: status,
                           leftSize: nil, rightSize: nil, leftDate: nil, rightDate: nil, children: children)
    }

    private func filesEqual(_ a: URL, _ b: URL) throws -> Bool {
        let fa = try FileHandle(forReadingFrom: a)
        let fb = try FileHandle(forReadingFrom: b)
        defer { try? fa.close(); try? fb.close() }
        let chunk = 1 << 20
        while true {
            let da = try fa.read(upToCount: chunk) ?? Data()
            let db = try fb.read(upToCount: chunk) ?? Data()
            if da != db { return false }
            if da.isEmpty { return true }
        }
    }
}
