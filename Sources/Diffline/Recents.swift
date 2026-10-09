import Foundation

/// A remembered comparison, stored as security-scoped bookmarks so it can be reopened after relaunch.
struct RecentComparison: Codable, Identifiable, Equatable {
    var id: String { leftPath + "|" + rightPath }
    var leftPath: String
    var rightPath: String
    var leftBookmark: Data
    var rightBookmark: Data
    var isFolder: Bool
    var date: Date

    func resolve() -> (URL, URL)? {
        guard let l = Self.resolve(leftBookmark), let r = Self.resolve(rightBookmark) else { return nil }
        return (l, r)
    }

    private static func resolve(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()   // balanced never: the app keeps access for its lifetime
        return url
    }
}

enum Recents {
    static let limit = 12

    static var all: [RecentComparison] {
        guard let data = UserDefaults.standard.data(forKey: Prefs.recents),
              let list = try? PropertyListDecoder().decode([RecentComparison].self, from: data) else { return [] }
        return list
    }

    static func add(left: URL, right: URL, isFolder: Bool) {
        guard let lb = try? left.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
              let rb = try? right.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        let item = RecentComparison(leftPath: left.path, rightPath: right.path, leftBookmark: lb, rightBookmark: rb, isFolder: isFolder, date: Date())
        var list = all.filter { $0.id != item.id }
        list.insert(item, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        save(list)
    }

    static func remove(_ item: RecentComparison) { save(all.filter { $0.id != item.id }) }
    static func clear() { save([]) }

    private static func save(_ list: [RecentComparison]) {
        UserDefaults.standard.set(try? PropertyListEncoder().encode(list), forKey: Prefs.recents)
        NotificationCenter.default.post(name: .recentsChanged, object: nil)
    }
}

extension Notification.Name {
    static let recentsChanged = Notification.Name("DifflineRecentsChanged")
}
