import SwiftUI
import UniformTypeIdentifiers

/// The window shown when nothing is being compared: pick two files or folders.
struct StartView: View {
    @State private var left: URL?
    @State private var right: URL?
    @State private var message: String?
    @State private var recents = Recents.all

    init(left: URL? = nil, right: URL? = nil) {
        _left = State(initialValue: left)
        _right = State(initialValue: right)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Compare two files or folders").font(.title2.weight(.semibold))
                Text("Drop them below, or choose them. Folders are compared recursively.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                DropTarget(title: "Left", url: $left)
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.tertiary).font(.title3)
                DropTarget(title: "Right", url: $right)
            }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Button("Swap") { swap(&left, &right) }.disabled(left == nil && right == nil)
                Spacer()
                Button("Compare") { compare() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(left == nil || right == nil)
            }
            if !recents.isEmpty {
                Divider()
                recentList
            }
        }
        .padding(24)
        .frame(width: 560)
        .onReceive(NotificationCenter.default.publisher(for: .recentsChanged)) { _ in recents = Recents.all }
        .onReceive(NotificationCenter.default.publisher(for: .prefillStart)) { note in
            let urls = note.object as? [URL?] ?? []
            if urls.count == 2 { left = urls[0] ?? left; right = urls[1] ?? right }
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                Button("Clear") { Recents.clear() }.buttonStyle(.link).controlSize(.small)
            }
            ForEach(recents.prefix(6)) { item in
                Button {
                    if let (l, r) = item.resolve() {
                        if item.isFolder { WindowManager.shared.openFolderCompare(l, r) }
                        else { WindowManager.shared.openFileCompare(l, r) }
                    } else {
                        message = "One of those items can't be found any more."
                        Recents.remove(item)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.isFolder ? "folder" : "doc.on.doc").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(URL(fileURLWithPath: item.leftPath).lastPathComponent) ↔ \(URL(fileURLWithPath: item.rightPath).lastPathComponent)")
                                .lineLimit(1)
                            Text(URL(fileURLWithPath: item.leftPath).deletingLastPathComponent().path(percentEncoded: false))
                                .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Text(item.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func compare() {
        guard let left, let right else { return }
        message = nil
        let lDir = left.isDirectory, rDir = right.isDirectory
        if lDir && rDir {
            WindowManager.shared.openFolderCompare(left, right)
        } else if !lDir && !rDir {
            WindowManager.shared.openFileCompare(left, right)
        } else {
            message = "Choose two files or two folders, not one of each."
        }
    }
}

struct DropTarget: View {
    let title: String
    @Binding var url: URL?
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 48, height: 48)
                Text(url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                Text(url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            } else {
                Image(systemName: "plus.circle.dashed").font(.system(size: 36, weight: .light)).foregroundStyle(.tertiary)
                Text(title).font(.callout).foregroundStyle(.secondary)
            }
            Button(url == nil ? "Choose…" : "Change…") { choose() }.controlSize(.small)
        }
        .padding(12)
        .frame(width: 220, height: 150)
        .background(RoundedRectangle(cornerRadius: 10).fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .quaternarySystemFill)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1, dash: url == nil ? [5, 4] : [])))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let p = providers.first else { return false }
            p.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let u = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { url = u }
            }
            return true
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the \(title.lowercased()) file or folder"
        if panel.runModal() == .OK { url = panel.url }
    }
}

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

extension Notification.Name {
    static let prefillStart = Notification.Name("DifflinePrefillStart")
}

/// Captures the scene's `openWindow` action so AppKit code (the app delegate, Services) can reopen the start window.
struct RegisterOpenWindow: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content
            .onAppear { WindowManager.shared.openStartWindow = { openWindow(id: "start") } }
            .background(WindowAccessor { window in
                WindowManager.shared.startWindow = window
                // SwiftUI opens this window at launch even when files were handed over; step aside.
                if WindowManager.shared.hasComparisonWindows { window.close() }
            })
    }
}

/// Hands the hosting NSWindow to AppKit code once the view is in a window.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func registerOpenWindow() -> some View { modifier(RegisterOpenWindow()) }
}
