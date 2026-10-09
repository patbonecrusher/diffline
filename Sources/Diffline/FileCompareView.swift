import SwiftUI
import DiffCore

struct FileCompareView: View {
    @ObservedObject var session: FileCompareSession

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            header
            Divider()
            if session.isBinary {
                ContentUnavailableView(session.binaryIdentical ? "Binary files are identical" : "Binary files differ",
                                       systemImage: "doc.zipper",
                                       description: Text("Diffline compares text files line by line. These files contain binary data."))
            } else {
                ZStack(alignment: .top) {
                    DiffPaneView(session: session)
                    if let result = session.result, result.isIdentical {
                        identicalBanner
                    }
                }
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 640, minHeight: 320)
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                Button { session.previousChange() } label: { Image(systemName: "chevron.up") }
                    .help("Previous Change (⌘↑)")
                Button { session.nextChange() } label: { Image(systemName: "chevron.down") }
                    .help("Next Change (⌘↓)")
            }
            .disabled(session.hunkCount == 0)
            Text(counterText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .leading)
            Spacer()
            Button { session.takeLeft() } label: { Label("Take Left", systemImage: "arrow.right.to.line") }
                .help("Copy the current change from the left file into the right file (⌥⌘→)")
                .disabled(session.currentHunk == nil)
            Button { session.takeRight() } label: { Label("Take Right", systemImage: "arrow.left.to.line") }
                .help("Copy the current change from the right file into the left file (⌥⌘←)")
                .disabled(session.currentHunk == nil)
            Divider().frame(height: 16)
            Toggle(isOn: $session.wrapLines) { Image(systemName: "text.word.spacing") }
                .toggleStyle(.button)
                .help("Wrap Lines")
            Menu {
                Picker("Whitespace", selection: $session.options.whitespace) {
                    ForEach(DiffOptions.Whitespace.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Ignore Case", isOn: $session.options.ignoreCase)
                Toggle("Ignore Blank Lines", isOn: $session.options.ignoreBlankLines)
            } label: {
                Label("Options", systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button { session.swapSides() } label: { Image(systemName: "arrow.left.arrow.right") }
                .help("Swap Sides")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .disabled(session.isBinary)
    }

    private var counterText: String {
        guard session.hunkCount > 0 else { return session.result == nil ? "" : "No changes" }
        if let c = session.currentHunk { return "\(c + 1) of \(session.hunkCount)" }
        return "\(session.hunkCount) change\(session.hunkCount == 1 ? "" : "s")"
    }

    private var header: some View {
        HStack(spacing: 0) {
            fileHeader(session.left)
            Divider()
            fileHeader(session.right)
        }
        .frame(height: 26)
    }

    private func fileHeader(_ file: TextFile) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable().frame(width: 16, height: 16)
            Text(file.name).fontWeight(.medium).lineLimit(1)
            Text(file.url.deletingLastPathComponent().path(percentEncoded: false))
                .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            Spacer()
            if file.isDirty {
                Text("Edited").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .help(file.url.path)
    }

    private var identicalBanner: some View {
        Label("Files are identical", systemImage: "checkmark.circle.fill")
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 10)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if session.isComputing {
                ProgressView().controlSize(.small)
                Text("Comparing…")
            } else if let r = session.result {
                let s = r.stats
                Text("\(r.hunks.count) change\(r.hunks.count == 1 ? "" : "s")")
                Text("\(s.inserted) added · \(s.deleted) removed · \(s.changed) modified").foregroundStyle(.secondary)
            }
            if let msg = session.errorMessage {
                Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            Spacer()
            Text("\(session.left.lines.count) ↔ \(session.right.lines.count) lines").foregroundStyle(.secondary)
            if session.options.whitespace != .exact || session.options.ignoreCase || session.options.ignoreBlankLines {
                Text("Filtered").foregroundStyle(.secondary)
                    .help("Some differences are hidden by the comparison options")
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.bar)
    }
}
