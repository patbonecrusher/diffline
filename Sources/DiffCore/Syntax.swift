import Foundation

public enum TokenKind: Equatable {
    case keyword, string, comment, number, type, attribute, tag
}

/// A colored span of one line, as UTF-16 offsets so AppKit can use it directly.
public struct SyntaxToken: Equatable {
    public var kind: TokenKind
    public var range: Range<Int>
    public init(kind: TokenKind, range: Range<Int>) { self.kind = kind; self.range = range }
}

/// A small, deliberately approximate description of a language: enough to color keywords, strings,
/// comments, numbers and a few shape-specific things (tags, keys, decorators).
public struct Language: Hashable {
    public enum Flavor: Equatable { case code, markup, markdown, data, shell, css }

    public var name: String
    public var flavor: Flavor
    var keywords: Set<String>
    var lineComments: [String]
    var blockComments: [(String, String)]
    var stringDelimiters: [String]      // longest first; multi-character ones are multi-line (""" or ```)
    var escapeChar: Character? = "\\"
    var attributePrefixes: [Character]  // @decorators, #directives, $variables
    var capitalizedIsType: Bool

    public static func == (a: Language, b: Language) -> Bool { a.name == b.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }

    static func cLike(_ name: String, keywords: String, lineComments: [String] = ["//"], blockComments: [(String, String)] = [("/*", "*/")],
                      strings: [String] = ["\"", "'"], attributes: [Character] = ["@", "#"], types: Bool = true) -> Language {
        Language(name: name, flavor: .code, keywords: Set(keywords.split(separator: " ").map(String.init)),
                 lineComments: lineComments, blockComments: blockComments, stringDelimiters: strings,
                 attributePrefixes: attributes, capitalizedIsType: types)
    }

    public static let swift = cLike("Swift", keywords: "associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as any false is nil self Self super throws true try async await actor some each macro consuming borrowing nonisolated lazy weak unowned override required convenience final mutating nonmutating indirect optional dynamic get set willSet didSet", strings: ["\"\"\"", "\""])
    public static let objc = cLike("Objective-C", keywords: "if else for while do switch case default break continue return goto sizeof typedef struct union enum static extern const volatile unsigned signed int char short long float double void auto register inline self super nil YES NO id Class SEL BOOL instancetype @interface @implementation @end @property @synthesize @dynamic @protocol @class @selector @try @catch @finally @throw @autoreleasepool @synchronized", strings: ["@\"", "\"", "'"])
    public static let c = cLike("C", keywords: "if else for while do switch case default break continue return goto sizeof typedef struct union enum static extern const volatile unsigned signed int char short long float double void auto register inline restrict bool true false NULL", types: false)
    public static let cpp = cLike("C++", keywords: "if else for while do switch case default break continue return goto sizeof typedef struct union enum static extern const volatile unsigned signed int char short long float double void auto register inline class namespace using template typename public private protected virtual override final new delete this nullptr true false try catch throw const_cast static_cast dynamic_cast reinterpret_cast constexpr consteval constinit noexcept explicit friend operator mutable bool export import module co_await co_return co_yield requires concept")
    public static let java = cLike("Java", keywords: "abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while var record sealed permits yield true false null")
    public static let kotlin = cLike("Kotlin", keywords: "as break class continue do else false for fun if in interface is null object package return super this throw true try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam value where abstract actual annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg it", strings: ["\"\"\"", "\"", "'"])
    public static let javascript = cLike("JavaScript", keywords: "break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set true false null undefined NaN Infinity", strings: ["`", "\"", "'"])
    public static let typescript = cLike("TypeScript", keywords: "break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set true false null undefined NaN Infinity type interface enum implements namespace declare abstract readonly keyof is as any unknown never string number boolean object symbol bigint public private protected satisfies override", strings: ["`", "\"", "'"])
    public static let go = cLike("Go", keywords: "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 string bool byte rune error any", strings: ["`", "\"", "'"])
    public static let rust = cLike("Rust", keywords: "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while union i8 i16 i32 i64 i128 u8 u16 u32 u64 u128 f32 f64 usize isize bool char str String Vec Option Some None Result Ok Err Box", strings: ["\"", "'"], attributes: ["#"])
    public static let csharp = cLike("C#", keywords: "abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using var virtual void volatile while async await record init get set value yield", strings: ["\"", "'"], attributes: ["#", "@"])
    public static let php = cLike("PHP", keywords: "abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield true false null self parent", lineComments: ["//", "#"], attributes: ["$", "#"])
    public static let python = Language(name: "Python", flavor: .code, keywords: Set("False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield self cls print match case".split(separator: " ").map(String.init)), lineComments: ["#"], blockComments: [], stringDelimiters: ["\"\"\"", "'''", "\"", "'"], attributePrefixes: ["@"], capitalizedIsType: true)
    public static let ruby = Language(name: "Ruby", flavor: .code, keywords: Set("alias and begin break case class def defined? do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield attr_accessor attr_reader attr_writer require require_relative include extend private public protected puts raise lambda proc".split(separator: " ").map(String.init)), lineComments: ["#"], blockComments: [("=begin", "=end")], stringDelimiters: ["\"", "'", "`"], attributePrefixes: ["@", ":"], capitalizedIsType: true)
    public static let sql = Language(name: "SQL", flavor: .code, keywords: Set("select from where insert into values update set delete create table drop alter add column index view as on join left right inner outer full cross group by order having limit offset union all distinct and or not null is in exists between like case when then else end primary key foreign references unique default check constraint begin commit rollback transaction with recursive returning if explain analyze vacuum pragma int integer text varchar char boolean date timestamp real float numeric blob serial bigint smallint true false asc desc count sum avg min max coalesce cast".split(separator: " ").flatMap { [String($0), String($0).uppercased()] }), lineComments: ["--"], blockComments: [("/*", "*/")], stringDelimiters: ["'", "\""], attributePrefixes: [], capitalizedIsType: false)
    public static let shell = Language(name: "Shell", flavor: .shell, keywords: Set("if then else elif fi for while until do done case esac in function select time return exit export local readonly declare typeset unset shift source alias set unalias break continue eval exec trap echo printf read cd test true false".split(separator: " ").map(String.init)), lineComments: ["#"], blockComments: [], stringDelimiters: ["\"", "'", "`"], attributePrefixes: ["$"], capitalizedIsType: false)
    public static let json = Language(name: "JSON", flavor: .data, keywords: ["true", "false", "null"], lineComments: [], blockComments: [], stringDelimiters: ["\""], attributePrefixes: [], capitalizedIsType: false)
    public static let yaml = Language(name: "YAML", flavor: .data, keywords: ["true", "false", "null", "yes", "no", "on", "off", "~"], lineComments: ["#"], blockComments: [], stringDelimiters: ["\"", "'"], attributePrefixes: ["&", "*", "!"], capitalizedIsType: false)
    public static let toml = Language(name: "TOML", flavor: .data, keywords: ["true", "false"], lineComments: ["#"], blockComments: [], stringDelimiters: ["\"\"\"", "'''", "\"", "'"], attributePrefixes: [], capitalizedIsType: false)
    public static let ini = Language(name: "INI", flavor: .data, keywords: ["true", "false", "yes", "no"], lineComments: [";", "#"], blockComments: [], stringDelimiters: ["\""], attributePrefixes: [], capitalizedIsType: false)
    public static let markup = Language(name: "HTML/XML", flavor: .markup, keywords: [], lineComments: [], blockComments: [("<!--", "-->")], stringDelimiters: ["\"", "'"], attributePrefixes: [], capitalizedIsType: false)
    public static let css = Language(name: "CSS", flavor: .css, keywords: Set("important inherit initial unset auto none block inline flex grid absolute relative fixed sticky solid dashed dotted bold normal italic".split(separator: " ").map(String.init)), lineComments: [], blockComments: [("/*", "*/")], stringDelimiters: ["\"", "'"], attributePrefixes: ["@", "$"], capitalizedIsType: false)
    public static let markdown = Language(name: "Markdown", flavor: .markdown, keywords: [], lineComments: [], blockComments: [], stringDelimiters: ["```"], escapeChar: nil, attributePrefixes: [], capitalizedIsType: false)
    public static let makefile = Language(name: "Makefile", flavor: .shell, keywords: Set("ifeq ifneq ifdef ifndef else endif include define endef export unexport override".split(separator: " ").map(String.init)), lineComments: ["#"], blockComments: [], stringDelimiters: ["\"", "'"], attributePrefixes: ["$", "@"], capitalizedIsType: false)

    /// Every language, for a picker. Order is alphabetical by name.
    public static let all: [Language] = [c, cpp, csharp, css, go, markup, ini, java, javascript, json, kotlin, makefile, markdown, objc, php, python, ruby, rust, shell, sql, swift, toml, typescript, yaml]
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    public static func detect(filename: String) -> Language? {
        let name = (filename as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "m", "mm": return .objc
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx": return .cpp
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "tsx", "mts", "cts": return .typescript
        case "go": return .go
        case "rs": return .rust
        case "cs": return .csharp
        case "php": return .php
        case "py", "pyi", "pyw": return .python
        case "rb", "rake", "gemspec": return .ruby
        case "sql": return .sql
        case "sh", "bash", "zsh", "fish", "command": return .shell
        case "json", "jsonc", "json5", "webmanifest": return .json
        case "yml", "yaml": return .yaml
        case "toml": return .toml
        case "ini", "cfg", "conf", "properties", "env": return .ini
        case "html", "htm", "xml", "svg", "plist", "xib", "storyboard", "xhtml", "xsl", "xsd", "entitlements", "vue", "svelte": return .markup
        case "css", "scss", "less": return .css
        case "md", "markdown", "mdx": return .markdown
        case "mk": return .makefile
        default:
            switch name.lowercased() {
            case "makefile", "gnumakefile": return .makefile
            case "dockerfile", "containerfile": return .shell
            case "podfile", "gemfile", "rakefile", "fastfile", "brewfile": return .ruby
            case "package.swift": return .swift
            case ".zshrc", ".bashrc", ".bash_profile", ".profile", ".zprofile": return .shell
            case ".gitignore", ".gitattributes", ".editorconfig": return .ini
            default: return nil
            }
        }
    }
}

/// Tokenizes whole files line by line, carrying the state needed for block comments and multi-line
/// strings from one line to the next.
public struct SyntaxHighlighter {
    public let language: Language

    public init(language: Language) { self.language = language }

    enum State: Equatable {
        case none
        case blockComment(end: String)
        case string(delimiter: String)
    }

    public func tokenize(lines: [String]) -> [[SyntaxToken]] {
        var state = State.none
        var out: [[SyntaxToken]] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            let (tokens, next) = tokenize(line: line, state: state)
            out.append(tokens)
            state = next
        }
        return out
    }

    func tokenize(line: String, state: State) -> ([SyntaxToken], State) {
        var scanner = LineScanner(line: line)
        var tokens: [SyntaxToken] = []
        var state = state

        func emit(_ kind: TokenKind, _ start: Int) {
            if scanner.utf16 > start { tokens.append(SyntaxToken(kind: kind, range: start..<scanner.utf16)) }
        }

        // Finish a construct carried over from the previous line.
        switch state {
        case .blockComment(let end):
            let start = scanner.utf16
            if scanner.scan(until: end) { state = .none }
            emit(.comment, start)
        case .string(let delimiter):
            let start = scanner.utf16
            if scanner.scanString(until: delimiter, escape: language.escapeChar) { state = .none }
            emit(.string, start)
        case .none:
            break
        }

        switch language.flavor {
        case .markdown:
            if state == .none { tokenizeMarkdown(&scanner, &tokens, &state) }
            return (tokens, state)
        case .markup:
            if state == .none { tokenizeMarkup(&scanner, &tokens, &state) }
            return (tokens, state)
        default:
            break
        }

        var lineStart = true
        var sawColon = false
        while !scanner.atEnd {
            // Comments.
            if let c = language.lineComments.first(where: { scanner.peek($0) }), !(language.flavor == .shell && c == "#" && scanner.previous == "$") {
                let start = scanner.utf16
                scanner.skipToEnd()
                emit(.comment, start)
                break
            }
            if let (open, close) = language.blockComments.first(where: { scanner.peek($0.0) }) {
                let start = scanner.utf16
                scanner.advance(open.count)
                if !scanner.scan(until: close) { state = .blockComment(end: close) }
                emit(.comment, start)
                continue
            }
            // Strings.
            if let d = language.stringDelimiters.first(where: { scanner.peek($0) }) {
                let start = scanner.utf16
                scanner.advance(d.count)
                let closed = scanner.scanString(until: d, escape: language.escapeChar)
                let multiline = d.count > 1
                if !closed && multiline { state = .string(delimiter: d) }
                // JSON/YAML/TOML keys: a string followed by a colon.
                if language.flavor == .data, scanner.peekSkippingSpaces(":") {
                    emit(.attribute, start)
                } else {
                    emit(.string, start)
                }
                lineStart = false
                continue
            }
            let ch = scanner.current!
            // Numbers.
            if ch.isNumber || (ch == "." && (scanner.next?.isNumber ?? false)) {
                let start = scanner.utf16
                scanner.scanWhile { $0.isNumber || $0.isLetter || $0 == "." || $0 == "_" }
                emit(.number, start)
                lineStart = false
                continue
            }
            // Attributes / decorators / variables.
            if language.attributePrefixes.contains(ch), let n = scanner.next, n.isLetter || n == "_" || n == "{" || n == "(" || n == "[" {
                let start = scanner.utf16
                scanner.advance(1)
                if scanner.current == "{" || scanner.current == "(" {
                    let close: Character = scanner.current == "{" ? "}" : ")"
                    scanner.scanWhile { $0 != close }
                    scanner.advance(1)
                } else if scanner.current == "[" {
                    scanner.scanWhile { $0 != "]" }
                    scanner.advance(1)
                } else {
                    scanner.scanWhile { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
                }
                emit(.attribute, start)
                lineStart = false
                continue
            }
            // Identifiers and keywords.
            if ch.isLetter || ch == "_" {
                let start = scanner.utf16
                let hyphenated = language.flavor == .data || language.flavor == .css
                let word = scanner.scanWord(allowHyphen: hyphenated)
                if language.keywords.contains(word) {
                    emit(.keyword, start)
                } else if language.flavor == .data || language.flavor == .css {
                    // Unquoted keys (YAML, TOML, INI) and CSS properties: `name:` at the start of a line.
                    if lineStart, scanner.peekSkippingSpaces(":") || scanner.peekSkippingSpaces("=") { emit(.attribute, start) }
                } else if language.capitalizedIsType, word.first!.isUppercase {
                    emit(.type, start)
                }
                lineStart = false
                continue
            }
            if ch == ":" { sawColon = true }
            if !ch.isWhitespace { lineStart = false }
            scanner.advance(1)
        }
        _ = sawColon
        return (tokens, state)
    }

    private func tokenizeMarkdown(_ scanner: inout LineScanner, _ tokens: inout [SyntaxToken], _ state: inout State) {
        func emit(_ kind: TokenKind, _ start: Int) {
            if scanner.utf16 > start { tokens.append(SyntaxToken(kind: kind, range: start..<scanner.utf16)) }
        }
        if scanner.peek("```") {
            let start = scanner.utf16
            scanner.skipToEnd()
            emit(.string, start)
            state = .string(delimiter: "```")
            return
        }
        scanner.scanWhile { $0 == " " }
        if scanner.peek("#") {
            let start = scanner.utf16
            scanner.skipToEnd()
            emit(.keyword, start)
            return
        }
        if scanner.peek(">") {
            let start = scanner.utf16
            scanner.skipToEnd()
            emit(.comment, start)
            return
        }
        if let c = scanner.current, c == "-" || c == "*" || c == "+", scanner.next == " " {
            let start = scanner.utf16
            scanner.advance(1)
            emit(.keyword, start)
        }
        while !scanner.atEnd {
            if scanner.peek("`") {
                let start = scanner.utf16
                scanner.advance(1)
                _ = scanner.scanString(until: "`", escape: nil)
                emit(.string, start)
                continue
            }
            if scanner.peek("](") {
                scanner.advance(2)
                let start = scanner.utf16
                scanner.scanWhile { $0 != ")" }
                emit(.string, start)
                continue
            }
            if scanner.peek("**") || scanner.peek("__") {
                let start = scanner.utf16
                let d = String(scanner.current!) + String(scanner.current!)
                scanner.advance(2)
                if scanner.scan(until: d) { emit(.type, start) }
                continue
            }
            scanner.advance(1)
        }
    }

    private func tokenizeMarkup(_ scanner: inout LineScanner, _ tokens: inout [SyntaxToken], _ state: inout State) {
        func emit(_ kind: TokenKind, _ start: Int) {
            if scanner.utf16 > start { tokens.append(SyntaxToken(kind: kind, range: start..<scanner.utf16)) }
        }
        while !scanner.atEnd {
            if scanner.peek("<!--") {
                let start = scanner.utf16
                scanner.advance(4)
                if !scanner.scan(until: "-->") { state = .blockComment(end: "-->") }
                emit(.comment, start)
                continue
            }
            if scanner.peek("<") {
                // Tag name.
                let start = scanner.utf16
                scanner.advance(1)
                if scanner.current == "/" || scanner.current == "?" || scanner.current == "!" { scanner.advance(1) }
                scanner.scanWhile { $0.isLetter || $0.isNumber || $0 == "-" || $0 == ":" || $0 == "_" || $0 == "." }
                emit(.tag, start)
                // Attributes until '>'.
                while !scanner.atEnd, !scanner.peek(">") {
                    if let d = ["\"", "'"].first(where: { scanner.peek($0) }) {
                        let s = scanner.utf16
                        scanner.advance(1)
                        _ = scanner.scanString(until: d, escape: nil)
                        emit(.string, s)
                    } else if let c = scanner.current, c.isLetter || c == "_" || c == ":" || c == "@" {
                        let s = scanner.utf16
                        scanner.scanWhile { $0.isLetter || $0.isNumber || $0 == "-" || $0 == ":" || $0 == "_" || $0 == "." }
                        emit(.attribute, s)
                    } else {
                        scanner.advance(1)
                    }
                }
                let s = scanner.utf16
                if scanner.peek("/>") { scanner.advance(2) } else { scanner.advance(1) }
                emit(.tag, s)
                continue
            }
            scanner.advance(1)
        }
    }
}

/// Character-by-character scanner over one line that also tracks the UTF-16 offset.
struct LineScanner {
    private let chars: [Character]
    private(set) var index = 0
    private(set) var utf16 = 0

    init(line: String) { chars = Array(line) }

    var atEnd: Bool { index >= chars.count }
    var current: Character? { index < chars.count ? chars[index] : nil }
    var next: Character? { index + 1 < chars.count ? chars[index + 1] : nil }
    var previous: Character? { index > 0 ? chars[index - 1] : nil }

    mutating func advance(_ n: Int) {
        for _ in 0..<n where index < chars.count {
            utf16 += chars[index].utf16.count
            index += 1
        }
    }

    func peek(_ s: String) -> Bool {
        var i = index
        for c in s {
            guard i < chars.count, chars[i] == c else { return false }
            i += 1
        }
        return true
    }

    func peekSkippingSpaces(_ s: String) -> Bool {
        var i = index
        while i < chars.count, chars[i] == " " { i += 1 }
        var j = i
        for c in s {
            guard j < chars.count, chars[j] == c else { return false }
            j += 1
        }
        return true
    }

    mutating func skipToEnd() { advance(chars.count - index) }

    mutating func scanWhile(_ p: (Character) -> Bool) {
        while let c = current, p(c) { advance(1) }
    }

    mutating func scanWord(allowHyphen: Bool = false) -> String {
        let start = index
        scanWhile { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "?" || $0 == "!" || (allowHyphen && ($0 == "-" || $0 == ".")) }
        return String(chars[start..<index])
    }

    /// Advances past the next occurrence of `s`; returns false (at end of line) if it never comes.
    mutating func scan(until s: String) -> Bool {
        while !atEnd {
            if peek(s) { advance(s.count); return true }
            advance(1)
        }
        return false
    }

    mutating func scanString(until delimiter: String, escape: Character?) -> Bool {
        while !atEnd {
            if let e = escape, current == e { advance(2); continue }
            if peek(delimiter) { advance(delimiter.count); return true }
            advance(1)
        }
        return false
    }
}
