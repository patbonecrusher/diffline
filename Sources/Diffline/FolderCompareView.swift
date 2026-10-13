import SwiftUI
import DiffCore

struct FolderCompareView: View {
    @ObservedObject var session: FolderCompareSession

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter(); f.countStyle = .file; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            header
            Divider()
            table
            Divider()
            statusBar
        }
        .frame(minWidth: 640, minHeight: 320)
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $session.differencesOnly) {
                Text("Differences").tag(true)
                Text("All Items").tag(false)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Toggle("Hidden Files", isOn: $session.includeHidden)
            Spacer()
            Button { session.run() } label: { Image(systemName: "arrow.clockwise") }
                .help("Compare Again (⌘R)")
                .disabled(session.isRunning)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var header: some View {
        HStack(spacing: 0) {
            folderHeader(session.leftURL)
            Divider()
            folderHeader(session.rightURL)
        }
        .frame(height: 26)
    }

    private func folderHeader(_ url: URL) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
            Text(url.lastPathComponent).fontWeight(.medium).lineLimit(1)
            Text(url.deletingLastPathComponent().path(percentEncoded: false))
                .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .help(url.path)
    }

    private var table: some View {
        Table(session.rows, selection: $session.selection) {
            TableColumn("Name") { row in
                HStack(spacing: 4) {
                    Spacer().frame(width: CGFloat(row.depth) * 16)
                    Image(systemName: row.entry.isDirectory ? "folder" : "doc")
                        .foregroundStyle(.secondary)
                    Text(row.entry.name)
                }
            }
            .width(min: 200, ideal: 320)
            TableColumn("Status") { row in
                Label(statusTitle(row.entry.status), systemImage: statusSymbol(row.entry.status))
                    .foregroundStyle(statusColor(row.entry.status))
                    .help(row.entry.problem ?? "")
            }
            .width(min: 90, ideal: 110)
            TableColumn("Left Size") { row in Text(size(row.entry.leftSize)).foregroundStyle(.secondary).monospacedDigit() }
                .width(min: 60, ideal: 80)
            TableColumn("Right Size") { row in Text(size(row.entry.rightSize)).foregroundStyle(.secondary).monospacedDigit() }
                .width(min: 60, ideal: 80)
            TableColumn("Left Modified") { row in Text(date(row.entry.leftDate)).foregroundStyle(.secondary) }
                .width(min: 110, ideal: 140)
            TableColumn("Right Modified") { row in Text(date(row.entry.rightDate)).foregroundStyle(.secondary) }
                .width(min: 110, ideal: 140)
        }
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let e = session.entry(for: id) {
                Button(e.isDirectory ? "Compare Folders" : "Compare Files") { session.open(e) }
                    .disabled(e.status == .leftOnly || e.status == .rightOnly)
                Divider()
                Button("Reveal Left in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.leftURL(for: e)]) }
                    .disabled(e.status == .rightOnly)
                Button("Reveal Right in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.rightURL(for: e)]) }
                    .disabled(e.status == .leftOnly)
            }
        } primaryAction: { ids in
            if let id = ids.first, let e = session.entry(for: id) { session.open(e) }
        }
        .overlay {
            if session.isRunning && session.root == nil {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Comparing \(session.scanned) files…").foregroundStyle(.secondary)
                }
            } else if !session.isRunning, session.rows.isEmpty, session.root != nil {
                ContentUnavailableView(session.differencesOnly ? "Folders are identical" : "Folders are empty",
                                       systemImage: "checkmark.circle")
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if session.isRunning {
                ProgressView().controlSize(.small)
                Text("Comparing… \(session.scanned) files")
            } else if session.root != nil {
                Text("\(session.differenceCount) difference\(session.differenceCount == 1 ? "" : "s")")
            }
            if let msg = session.errorMessage {
                Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            Spacer()
            Text("Double-click a file to compare it").foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.bar)
    }

    private func size(_ n: Int?) -> String { n.map { Self.sizeFormatter.string(fromByteCount: Int64($0)) } ?? "" }
    private func date(_ d: Date?) -> String { d.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "" }

    private func statusTitle(_ s: EntryStatus) -> String {
        switch s {
        case .same: "Identical"
        case .different: "Different"
        case .leftOnly: "Left only"
        case .rightOnly: "Right only"
        case .unreadable: "Can't read"
        }
    }
    private func statusSymbol(_ s: EntryStatus) -> String {
        switch s {
        case .same: "equal.circle"
        case .different: "circle.lefthalf.filled"
        case .leftOnly: "arrow.left.circle"
        case .rightOnly: "arrow.right.circle"
        case .unreadable: "exclamationmark.triangle"
        }
    }
    private func statusColor(_ s: EntryStatus) -> Color {
        switch s {
        case .same: .secondary
        case .different: .orange
        case .leftOnly: .red
        case .rightOnly: .green
        case .unreadable: .yellow
        }
    }
}
