import Foundation
import DiffCore

/// A text file loaded for comparison, with enough detail to write it back unchanged.
struct TextFile {
    var url: URL
    var lines: [Substring]
    var lineEnding: String
    var trailingNewline: Bool
    var encoding: String.Encoding
    var isBinary: Bool
    var data: Data
    var isDirty = false

    var name: String { url.lastPathComponent }

    /// An error that names the file and says why it couldn't be read.
    struct LoadError: LocalizedError {
        var url: URL
        var reason: String
        var errorDescription: String? { "Diffline can't read “\(url.lastPathComponent)”." }
        var failureReason: String? { reason + "." }
        /// Set when the file is a link whose target the sandbox won't let Diffline read.
        var outsideLinkTarget: URL? {
            reason.contains("outside the folders") ? FileProblem.linkTarget(of: url) : nil
        }
    }

    static func load(_ url: URL) throws -> TextFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadError(url: url, reason: FileProblem.describe(error, url: url, isLink: false))
        }
        let probe = data.prefix(8192)
        if probe.contains(0) {
            return TextFile(url: url, lines: [], lineEnding: "\n", trailingNewline: false, encoding: .utf8, isBinary: true, data: data)
        }
        var encoding = String.Encoding.utf8
        var text: String
        if let s = String(data: data, encoding: .utf8) {
            text = s
        } else {
            var converted: NSString?
            let raw = NSString.stringEncoding(for: data, encodingOptions: [.suggestedEncodingsKey: [NSUTF8StringEncoding, NSISOLatin1StringEncoding, NSWindowsCP1252StringEncoding, NSUTF16StringEncoding]], convertedString: &converted, usedLossyConversion: nil)
            if raw != 0, let converted {
                encoding = String.Encoding(rawValue: raw)
                text = converted as String
            } else {
                encoding = .isoLatin1
                text = String(decoding: data, as: UTF8.self)
            }
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lineEnding = text.contains("\r\n") ? "\r\n" : (text.contains("\r") && !text.contains("\n") ? "\r" : "\n")
        let trailing = text.hasSuffix("\n") || text.hasSuffix("\r")
        return TextFile(url: url, lines: LineDiff.lines(of: text), lineEnding: lineEnding, trailingNewline: trailing,
                        encoding: encoding, isBinary: false, data: data)
    }

    var text: String {
        var s = lines.joined(separator: lineEnding)
        if trailingNewline && !lines.isEmpty { s += lineEnding }
        return s
    }

    mutating func replace(lines range: Range<Int>, with new: [Substring]) {
        lines.replaceSubrange(range, with: new)
        isDirty = true
    }

    func write() throws {
        guard let out = text.data(using: encoding) ?? text.data(using: .utf8) else { return }
        // Write through symbolic links (git difftool --dir-diff) so the real file changes, not the link.
        let target = url.resolvingSymlinksInPath()
        do {
            try out.write(to: target, options: .atomic)
        } catch {
            // Access granted to just the file (not its folder) can rule out the temporary file an atomic write needs.
            try out.write(to: target)
        }
    }

    /// Expands tabs to spaces for display and intra-line comparison.
    static func expandTabs(_ line: Substring, tabWidth: Int) -> String {
        guard line.contains("\t") else { return String(line) }
        var out = ""
        out.reserveCapacity(line.count + 8)
        var col = 0
        for ch in line {
            if ch == "\t" {
                let n = tabWidth - (col % tabWidth)
                out += String(repeating: " ", count: n); col += n
            } else {
                out.append(ch); col += 1
            }
        }
        return out
    }
}
