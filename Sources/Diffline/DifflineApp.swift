import SwiftUI

@main
struct DifflineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The start window is a SwiftUI scene; comparison windows are AppKit windows managed by
        // WindowManager, so files handed over by Finder, the Dock or Services can open from anywhere.
        Window("Diffline", id: "start") {
            StartView()
                .registerOpenWindow()
        }
        .windowResizability(.contentSize)
        .commands { DifflineCommands() }

        Settings { SettingsView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServiceProvider()

    override init() {
        super.init()
        Prefs.registerDefaults()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Debug/screenshot hooks, as in the other apps: `-windowSize 1280x800`, `-preferRetina YES`.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "preferRetina") || defaults.string(forKey: "windowSize") != nil {
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow, window.isVisible, window.styleMask.contains(.resizable) else { return }
                var frame = window.frame
                if let spec = defaults.string(forKey: "windowSize") {
                    let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
                    if parts.count == 2 { frame.size = NSSize(width: parts[0], height: parts[1]) }
                }
                if defaults.bool(forKey: "preferRetina"),
                   let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) {
                    let v = screen.visibleFrame
                    frame.origin = NSPoint(x: v.midX - frame.width / 2, y: v.midY - frame.height / 2)
                }
                window.setFrame(frame, display: true)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        WindowManager.shared.open(urls: urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.showStart() }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Finder's Services menu: "Compare with Diffline" on two selected items.
final class ServiceProvider: NSObject {
    @objc func compareItems(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        DispatchQueue.main.async { WindowManager.shared.open(urls: urls) }
    }
}
