import AppKit
import Combine
import DiffCore

/// A flattened, always-expanded row of the folder comparison table.
struct FolderRow: Identifiable {
    var id: String { entry.relativePath }
    var entry: FolderEntry
    var depth: Int
}

@MainActor
final class FolderCompareSession: ObservableObject {
    let leftURL: URL
    let rightURL: URL
    @Published private(set) var root: FolderEntry?
    @Published private(set) var isRunning = false
    @Published private(set) var scanned = 0
    @Published private(set) var errorMessage: String?
    @Published var differencesOnly: Bool { didSet { UserDefaults.standard.set(differencesOnly, forKey: Prefs.folderDifferencesOnly) } }
    @Published var includeHidden: Bool { didSet { UserDefaults.standard.set(includeHidden, forKey: Prefs.folderIncludeHidden); run() } }
    @Published var selection: Set<String> = []

    private var task: Task<Void, Never>?

    init(leftURL: URL, rightURL: URL) {
        self.leftURL = leftURL
        self.rightURL = rightURL
        self.differencesOnly = UserDefaults.standard.bool(forKey: Prefs.folderDifferencesOnly)
        self.includeHidden = UserDefaults.standard.bool(forKey: Prefs.folderIncludeHidden)
        run()
    }

    var title: String { "\(leftURL.lastPathComponent) ↔ \(rightURL.lastPathComponent)" }

    func run() {
        task?.cancel()
        isRunning = true
        scanned = 0
        errorMessage = nil
        var opts = FolderCompareOptions()
        opts.includeHidden = includeHidden
        let l = leftURL, r = rightURL
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let comparer = FolderComparer(left: l, right: r, options: opts,
                                          isCancelled: { Task.isCancelled },
                                          progress: { n in Task { @MainActor [weak self] in self?.scanned = n } })
            let outcome: Result<FolderEntry, Error>
            do { outcome = .success(try comparer.run()) } catch { outcome = .failure(error) }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch outcome {
                case .success(let root): self.root = root; self.isRunning = false
                case .failure(is FolderComparer.Cancelled): break
                case .failure(let error): self.errorMessage = error.localizedDescription; self.isRunning = false
                }
            }
        }
    }

    var rows: [FolderRow] {
        guard let root else { return [] }
        guard let shown = differencesOnly ? root.filteredToDifferences() : root else { return [] }
        var out: [FolderRow] = []
        func walk(_ e: FolderEntry, depth: Int) {
            for c in e.children ?? [] {
                out.append(FolderRow(entry: c, depth: depth))
                if c.isDirectory { walk(c, depth: depth + 1) }
            }
        }
        walk(shown, depth: 0)
        return out
    }

    var differenceCount: Int { root?.differenceCount ?? 0 }

    func entry(for id: String) -> FolderEntry? {
        rows.first { $0.id == id }?.entry
    }

    func leftURL(for e: FolderEntry) -> URL { leftURL.appendingPathComponent(e.relativePath) }
    func rightURL(for e: FolderEntry) -> URL { rightURL.appendingPathComponent(e.relativePath) }

    func open(_ e: FolderEntry) {
        if e.status == .unreadable {
            let alert = NSAlert()
            alert.messageText = "Diffline can't read “\(e.name)”."
            alert.informativeText = (e.problem ?? "Unknown problem") + "."
            alert.runModal()
            return
        }
        if e.isDirectory {
            WindowManager.shared.openFolderCompare(leftURL(for: e), rightURL(for: e))
        } else if e.status == .different || e.status == .same {
            WindowManager.shared.openFileCompare(leftURL(for: e), rightURL(for: e))
        } else {
            NSWorkspace.shared.open(e.status == .leftOnly ? leftURL(for: e) : rightURL(for: e))
        }
    }
}
