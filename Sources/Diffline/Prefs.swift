import SwiftUI
import DiffCore

enum Prefs {
    static let fontSize = "fontSize"
    static let tabWidth = "tabWidth"
    static let wrapLines = "wrapLines"
    static let syntaxHighlighting = "syntaxHighlighting"
    static let showOverview = "showOverview"
    static let whitespace = "whitespace"
    static let ignoreCase = "ignoreCase"
    static let ignoreBlankLines = "ignoreBlankLines"
    static let folderIncludeHidden = "folderIncludeHidden"
    static let folderDifferencesOnly = "folderDifferencesOnly"
    static let recents = "recentComparisons"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            fontSize: 12.0,
            tabWidth: 4,
            wrapLines: true,
            syntaxHighlighting: true,
            showOverview: true,
            whitespace: DiffOptions.Whitespace.exact.rawValue,
            ignoreCase: false,
            ignoreBlankLines: false,
            folderIncludeHidden: false,
            folderDifferencesOnly: true,
        ])
    }

    static var defaultDiffOptions: DiffOptions {
        let d = UserDefaults.standard
        var o = DiffOptions()
        o.whitespace = DiffOptions.Whitespace(rawValue: d.string(forKey: whitespace) ?? "") ?? .exact
        o.ignoreCase = d.bool(forKey: ignoreCase)
        o.ignoreBlankLines = d.bool(forKey: ignoreBlankLines)
        o.tabWidth = max(1, d.integer(forKey: tabWidth))
        return o
    }

    static var font: NSFont {
        let size = CGFloat(UserDefaults.standard.double(forKey: fontSize))
        return NSFont.monospacedSystemFont(ofSize: size > 0 ? size : 12, weight: .regular)
    }
}

extension DiffOptions.Whitespace {
    var title: String {
        switch self {
        case .exact: "Compare Whitespace Exactly"
        case .ignoreTrailing: "Ignore Trailing Whitespace"
        case .ignoreChanges: "Ignore Whitespace Changes"
        case .ignoreAll: "Ignore All Whitespace"
        }
    }
}
