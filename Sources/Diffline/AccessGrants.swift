import AppKit
import DiffCore

/// Folders the user has explicitly let Diffline read, remembered as security-scoped bookmarks.
///
/// `git difftool --dir-diff` hands Diffline a temporary folder whose files are symbolic links into the
/// working tree. The `diffline` command normally passes those targets on, which grants access; when it
/// doesn't (an old copy of the command, a different launcher), the user can grant the repository once.
enum AccessGrants {
    private static let key = "grantedFolders"

    /// Re-activates every remembered folder. Call once at launch.
    static func restore() {
        for data in stored {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
            }
        }
    }

    static var grantedPaths: [String] {
        stored.compactMap { data in
            var stale = false
            return (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale))?.path
        }
    }

    static func revokeAll() { UserDefaults.standard.removeObject(forKey: key) }

    private static var stored: [Data] { UserDefaults.standard.array(forKey: key) as? [Data] ?? [] }

    private static func remember(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(stored + [data], forKey: key)
        _ = url.startAccessingSecurityScopedResource()
    }

    /// The folder to suggest for a link target: the enclosing git repository if there is one.
    static func suggestedFolder(for target: URL) -> URL {
        var dir = target.deletingLastPathComponent()
        let fm = FileManager.default
        while dir.path != "/" {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return target.deletingLastPathComponent()
    }

    /// Explains the problem and, if the user agrees, asks for the folder. Returns true when access was granted.
    @MainActor
    static func requestAccess(fileName: String, linkTarget: URL) -> Bool {
        let folder = suggestedFolder(for: linkTarget)
        let alert = NSAlert()
        alert.messageText = "Allow Diffline to read “\(folder.lastPathComponent)”?"
        alert.informativeText = "“\(fileName)” is a link to \(linkTarget.path), outside the folders Diffline was given. "
            + "This is how git difftool --dir-diff works. Allow access to the folder once and Diffline will remember it."
        alert.addButton(withTitle: "Allow Access…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder.deletingLastPathComponent()
        panel.nameFieldStringValue = folder.lastPathComponent
        panel.message = "Choose “\(folder.lastPathComponent)” (or any folder that contains \(linkTarget.lastPathComponent)) to let Diffline read it."
        panel.prompt = "Allow"
        guard panel.runModal() == .OK, let chosen = panel.url else { return false }
        remember(chosen)
        return FileManager.default.isReadableFile(atPath: linkTarget.path)
    }
}
