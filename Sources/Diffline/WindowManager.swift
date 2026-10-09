import AppKit
import SwiftUI
import Combine

/// Tracks which comparison is in the key window so menu commands can target it.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var fileSession: FileCompareSession? {
        didSet { fileForward = fileSession?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }
    }
    @Published var folderSession: FolderCompareSession? {
        didSet { folderForward = folderSession?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }
    }
    // Menu commands observe AppState only, so changes inside the active session are forwarded.
    private var fileForward: AnyCancellable?
    private var folderForward: AnyCancellable?
}

@MainActor
final class CompareWindowController: NSWindowController, NSWindowDelegate {
    var fileSession: FileCompareSession?
    var folderSession: FolderCompareSession?
    private var cancellables: Set<AnyCancellable> = []

    init<Content: View>(content: Content, title: String, subtitle: String, size: NSSize, autosaveName: String) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.subtitle = subtitle
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(autosaveName)
        window.tabbingMode = .preferred
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    func bind(_ session: FileCompareSession) {
        fileSession = session
        session.undoManager = window?.undoManager
        session.$left.combineLatest(session.$right)
            .map { $0.isDirty || $1.isDirty }
            .removeDuplicates()
            .sink { [weak self] dirty in self?.window?.isDocumentEdited = dirty }
            .store(in: &cancellables)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        AppState.shared.fileSession = fileSession
        AppState.shared.folderSession = folderSession
    }

    func windowDidResignKey(_ notification: Notification) {
        if AppState.shared.fileSession === fileSession { AppState.shared.fileSession = nil }
        if AppState.shared.folderSession === folderSession { AppState.shared.folderSession = nil }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let s = fileSession, s.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to the compared files?"
        alert.informativeText = "Changes you merged will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: s.save(); return !s.isDirty
        case .alertSecondButtonReturn: return false
        default: return true
        }
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.forget(self)
    }
}

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var controllers: [NSWindowController] = []
    /// Set by the start window's view when it first appears (SwiftUI owns that scene).
    var openStartWindow: (() -> Void)?

    var hasComparisonWindows: Bool { !controllers.isEmpty }

    /// The SwiftUI start window, handed over by the view once it is on screen.
    weak var startWindow: NSWindow?

    func showStart(left: URL? = nil, right: URL? = nil) {
        if let w = startWindow {
            w.makeKeyAndOrderFront(nil)
        } else {
            openStartWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
        if left != nil || right != nil {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .prefillStart, object: [left, right] as [URL?])
            }
        }
    }

    func closeStart() { startWindow?.close() }

    func openFileCompare(_ left: URL, _ right: URL) {
        do {
            let session = try FileCompareSession(leftURL: left, rightURL: right)
            let c = CompareWindowController(content: FileCompareView(session: session), title: session.title,
                                            subtitle: left.deletingLastPathComponent().path(percentEncoded: false),
                                            size: NSSize(width: 1100, height: 700), autosaveName: "FileCompare")
            c.bind(session)
            present(c)
            Recents.add(left: left, right: right, isFolder: false)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't open the files"
            alert.runModal()
        }
    }

    func openFolderCompare(_ left: URL, _ right: URL) {
        let session = FolderCompareSession(leftURL: left, rightURL: right)
        let c = CompareWindowController(content: FolderCompareView(session: session), title: session.title,
                                        subtitle: left.deletingLastPathComponent().path(percentEncoded: false),
                                        size: NSSize(width: 1000, height: 640), autosaveName: "FolderCompare")
        c.folderSession = session
        present(c)
        Recents.add(left: left, right: right, isFolder: true)
    }

    /// Routes files handed over by Finder, the Dock, Services or the command line.
    func open(urls: [URL]) {
        let items = urls.filter { $0.isFileURL }
        switch items.count {
        case 2:
            let dirs = items.map(\.isDirectory)
            if dirs == [true, true] { openFolderCompare(items[0], items[1]) }
            else if dirs == [false, false] { openFileCompare(items[0], items[1]) }
            else { showStart(left: items[0], right: items[1]) }
        case 1:
            showStart(left: items[0], right: nil)
        default:
            showStart()
        }
    }

    private func present(_ c: NSWindowController) {
        controllers.append(c)
        if let last = controllers.dropLast().last?.window, let w = c.window {
            w.setFrameTopLeftPoint(last.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else {
            c.window?.center()
        }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        closeStart()
    }

    func forget(_ c: NSWindowController) {
        controllers.removeAll { $0 === c }
    }

    // MARK: Panels used by menu commands

    func chooseAndCompare(folders: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folders
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = true
        panel.message = folders ? "Choose two folders to compare" : "Choose two files to compare"
        panel.prompt = "Compare"
        guard panel.runModal() == .OK else { return }
        if panel.urls.count == 2 {
            open(urls: panel.urls)
        } else {
            showStart(left: panel.urls.first, right: nil)
        }
    }
}
