import SwiftUI
import DiffCore

struct DifflineCommands: Commands {
    @ObservedObject var app = AppState.shared

    private var file: FileCompareSession? { app.fileSession }
    private var merge: MergeSession? { app.mergeSession }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Comparison") { WindowManager.shared.showStart() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Compare Files…") { WindowManager.shared.chooseAndCompare(folders: false) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Compare Folders…") { WindowManager.shared.chooseAndCompare(folders: true) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Merge Files…") { WindowManager.shared.showStart(mode: .merge) }
                .keyboardShortcut("o", modifiers: [.command, .option])
        }
        CommandGroup(after: .saveItem) {
            Button("Save") { if let merge { merge.save() } else { file?.save() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(file?.isDirty ?? false) && merge == nil)
            Button("Revert to Saved") { file?.reload() }
                .disabled(!(file?.isDirty ?? false))
            Divider()
            Button("Export Unified Diff…") { file?.exportUnifiedDiff() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(file == nil || file!.isBinary)
            Button("Copy Unified Diff") { file?.copyUnifiedDiff() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(file == nil || file!.isBinary)
            Button("Copy Merged Result") { merge?.copyMergedResult() }
                .disabled(merge == nil)
            Divider()
            Button("Reveal Left in Finder") { if let f = file { NSWorkspace.shared.activateFileViewerSelecting([f.left.url]) } }
                .disabled(file == nil)
            Button("Reveal Right in Finder") { if let f = file { NSWorkspace.shared.activateFileViewerSelecting([f.right.url]) } }
                .disabled(file == nil)
            Divider()
            Button("Install Command Line Tool…") { CommandLineTool.install() }
        }
        CommandMenu("Changes") {
            Button("Next Change") { if let merge { merge.nextChange() } else { file?.nextChange() } }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled((file?.hunkCount ?? 0) == 0 && (merge?.changedChunks.isEmpty ?? true))
            Button("Previous Change") { if let merge { merge.previousChange() } else { file?.previousChange() } }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled((file?.hunkCount ?? 0) == 0 && (merge?.changedChunks.isEmpty ?? true))
            Button("Next Conflict") { merge?.nextConflict() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                .disabled((merge?.conflictCount ?? 0) == 0)
            Button("Previous Conflict") { merge?.previousConflict() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                .disabled((merge?.conflictCount ?? 0) == 0)
            Divider()
            Button("Take Left") { if let merge { merge.resolve(with: .left) } else { file?.takeLeft() } }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(file?.currentHunk == nil && merge?.currentChunk == nil)
            Button("Take Right") { if let merge { merge.resolve(with: .right) } else { file?.takeRight() } }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(file?.currentHunk == nil && merge?.currentChunk == nil)
            Button("Take Both") { merge?.resolve(with: .both) }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(merge?.currentChunk == nil)
            Button("Take Both, Right First") { merge?.resolve(with: .bothReversed) }
                .disabled(merge?.currentChunk == nil)
            Button("Take Base") { merge?.resolve(with: .base) }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(merge?.currentChunk == nil)
            Divider()
            Button("Swap Sides") { file?.swapSides() }
                .disabled(file == nil)
        }
        CommandGroup(before: .toolbar) {
            Toggle("Wrap Lines", isOn: Binding(get: { file?.wrapLines ?? merge?.wrapLines ?? UserDefaults.standard.bool(forKey: Prefs.wrapLines) },
                                                set: { file?.wrapLines = $0; merge?.wrapLines = $0 }))
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(file == nil && merge == nil)
            Toggle("Show Change Overview", isOn: Binding(get: { UserDefaults.standard.bool(forKey: Prefs.showOverview) },
                                                         set: { UserDefaults.standard.set($0, forKey: Prefs.showOverview) }))
                .keyboardShortcut("m", modifiers: [.command, .option])
            Toggle("Show Base", isOn: Binding(get: { merge?.showBase ?? false }, set: { merge?.showBase = $0 }))
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(merge == nil)
            Menu("Whitespace") {
                Picker("Whitespace", selection: Binding(get: { file?.options.whitespace ?? .exact },
                                                       set: { file?.options.whitespace = $0 })) {
                    ForEach(DiffOptions.Whitespace.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            .disabled(file == nil)
            Toggle("Ignore Case", isOn: Binding(get: { file?.options.ignoreCase ?? false }, set: { file?.options.ignoreCase = $0 }))
                .disabled(file == nil)
            Toggle("Ignore Blank Lines", isOn: Binding(get: { file?.options.ignoreBlankLines ?? false }, set: { file?.options.ignoreBlankLines = $0 }))
                .disabled(file == nil)
            Divider()
            Toggle("Syntax Highlighting", isOn: Binding(get: { file?.syntaxHighlighting ?? merge?.syntaxHighlighting ?? UserDefaults.standard.bool(forKey: Prefs.syntaxHighlighting) },
                                                        set: { file?.syntaxHighlighting = $0; merge?.syntaxHighlighting = $0 }))
                .keyboardShortcut("h", modifiers: [.command, .option])
                .disabled(file == nil && merge == nil)
            if let file {
                LanguageMenu(session: file)
            }
            Divider()
            Button("Compare Again") {
                if let f = file { f.reload() } else { app.folderSession?.run() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(file == nil && app.folderSession == nil)
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Diffline Help") { NSWorkspace.shared.open(URL(string: "https://patbonecrusher.github.io/diffline/")!) }
        }
    }
}
