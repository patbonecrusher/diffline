import Foundation

public enum EntryStatus: String, Codable { case same, different, leftOnly, rightOnly, unreadable }

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
    /// Why the entry couldn't be compared, for `.unreadable`.
    public var problem: String?

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
        var problem: String?
    }

    /// Lists a directory. Symbolic links are followed (git difftool --dir-diff builds one side out of links
    /// into the working tree); an entry that can't be inspected is kept, with the reason, instead of failing
    /// the whole comparison.
    private func list(_ dir: URL) throws -> [String: Item] {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isHiddenKey], options: [])
        var out: [String: Item] = [:]
        for u in urls {
            if !options.includeHidden, (try? u.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true { continue }
            let name = u.lastPathComponent
            let isLink = (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
            let target = isLink ? FileProblem.linkTarget(of: u) : u
            do {
                let v = try target.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                // Don't descend into linked directories: they can loop, and git never links directories.
                let isDir = v.isDirectory == true && !isLink
                out[name] = Item(name: name, isDirectory: isDir, size: isDir ? nil : v.fileSize, date: v.contentModificationDate,
                                 problem: (isLink && v.isDirectory == true) ? "Link to a folder; not followed" : nil)
            } catch {
                out[name] = Item(name: name, isDirectory: false, size: nil, date: nil,
                                 problem: FileProblem.describe(error, url: u, isLink: isLink))
            }
        }
        return out
    }

    private func compareDirectory(relative: String, name: String, leftExists: Bool, rightExists: Bool,
                                  counter: inout Int) throws -> FolderEntry {
        if isCancelled() { throw Cancelled() }
        // A subfolder that can't be listed shows up as unreadable; only the two roots are fatal.
        func listOrProblem(_ dir: URL) throws -> ([String: Item], String?) {
            do { return (try list(dir), nil) } catch {
                if relative.isEmpty { throw error }
                return ([:], FileProblem.describe(error, url: dir, isLink: false))
            }
        }
        let (lItems, lProblem) = leftExists ? try listOrProblem(left.appendingPathComponent(relative)) : ([:], nil)
        let (rItems, rProblem) = rightExists ? try listOrProblem(right.appendingPathComponent(relative)) : ([:], nil)
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
                if let problem = l?.problem ?? r?.problem {
                    e.status = .unreadable; e.problem = problem
                } else if l == nil { e.status = .rightOnly }
                else if r == nil { e.status = .leftOnly }
                else if l!.size != r!.size { e.status = .different }
                else if options.compareContents {
                    if isCancelled() { throw Cancelled() }
                    do {
                        e.status = try filesEqual(left.appendingPathComponent(rel), right.appendingPathComponent(rel)) ? .same : .different
                    } catch {
                        e.status = .unreadable
                        e.problem = FileProblem.describe(error, url: left.appendingPathComponent(rel), isLink: false)
                    }
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
        if let problem = lProblem ?? rProblem {
            return FolderEntry(name: name, relativePath: relative, isDirectory: true, status: .unreadable,
                               leftSize: nil, rightSize: nil, leftDate: nil, rightDate: nil, children: children, problem: problem)
        }
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

/// Turns a file-system error into one sentence a person can act on.
public enum FileProblem {
    /// Where a symbolic link points, even when the target doesn't exist (resolvingSymlinksInPath gives up then).
    public static func linkTarget(of url: URL) -> URL {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return url.resolvingSymlinksInPath() }
        return URL(fileURLWithPath: dest, relativeTo: url.deletingLastPathComponent()).standardizedFileURL.resolvingSymlinksInPath()
    }

    public static func describe(_ error: Error, url: URL, isLink: Bool) -> String {
        let ns = error as NSError
        let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
        let denied = ns.code == NSFileReadNoPermissionError || ns.code == NSFileWriteNoPermissionError || posix == Int(EPERM) || posix == Int(EACCES)
        let linked = isLink || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        let target = linked ? linkTarget(of: url).path : url.path
        if linked && denied {
            return "It's a link to \(target), outside the folders Diffline was given"
        }
        if ns.code == NSFileReadNoSuchFileError || posix == Int(ENOENT) {
            return linked ? "It's a link to \(target), which doesn't exist" : "The file no longer exists"
        }
        if posix == Int(EACCES) { return "Your user account isn't allowed to read it (check its permissions with Get Info)" }
        if denied { return "macOS didn't give Diffline access to it" }
        return ns.localizedFailureReason ?? ns.localizedDescription
    }
}
