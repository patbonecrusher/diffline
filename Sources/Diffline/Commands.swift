import SwiftUI
import DiffCore

struct DifflineCommands: Commands {
    @ObservedObject var app = AppState.shared

    private var file: FileCompareSession? { app.fileSession }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Comparison") { WindowManager.shared.showStart() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Compare Files…") { WindowManager.shared.chooseAndCompare(folders: false) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Compare Folders…") { WindowManager.shared.chooseAndCompare(folders: true) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { file?.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(file?.isDirty ?? false))
            Button("Revert to Saved") { file?.reload() }
                .disabled(!(file?.isDirty ?? false))
            Divider()
            Button("Export Unified Diff…") { file?.exportUnifiedDiff() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(file == nil || file!.isBinary)
            Button("Copy Unified Diff") { file?.copyUnifiedDiff() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(file == nil || file!.isBinary)
            Divider()
            Button("Reveal Left in Finder") { if let f = file { NSWorkspace.shared.activateFileViewerSelecting([f.left.url]) } }
                .disabled(file == nil)
            Button("Reveal Right in Finder") { if let f = file { NSWorkspace.shared.activateFileViewerSelecting([f.right.url]) } }
                .disabled(file == nil)
        }
        CommandMenu("Changes") {
            Button("Next Change") { file?.nextChange() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled((file?.hunkCount ?? 0) == 0)
            Button("Previous Change") { file?.previousChange() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled((file?.hunkCount ?? 0) == 0)
            Divider()
            Button("Take Left") { file?.takeLeft() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(file?.currentHunk == nil)
            Button("Take Right") { file?.takeRight() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(file?.currentHunk == nil)
            Divider()
            Button("Swap Sides") { file?.swapSides() }
                .disabled(file == nil)
        }
        CommandGroup(before: .toolbar) {
            Toggle("Wrap Lines", isOn: Binding(get: { file?.wrapLines ?? UserDefaults.standard.bool(forKey: Prefs.wrapLines) },
                                                set: { file?.wrapLines = $0 }))
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(file == nil)
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
            Toggle("Syntax Highlighting", isOn: Binding(get: { file?.syntaxHighlighting ?? UserDefaults.standard.bool(forKey: Prefs.syntaxHighlighting) },
                                                        set: { file?.syntaxHighlighting = $0 }))
                .keyboardShortcut("h", modifiers: [.command, .option])
                .disabled(file == nil)
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
