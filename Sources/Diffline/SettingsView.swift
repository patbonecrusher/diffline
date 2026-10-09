import SwiftUI
import DiffCore

struct SettingsView: View {
    @AppStorage(Prefs.fontSize) private var fontSize = 12.0
    @AppStorage(Prefs.tabWidth) private var tabWidth = 4
    @AppStorage(Prefs.wrapLines) private var wrapLines = true
    @AppStorage(Prefs.whitespace) private var whitespace = DiffOptions.Whitespace.exact.rawValue
    @AppStorage(Prefs.ignoreCase) private var ignoreCase = false
    @AppStorage(Prefs.ignoreBlankLines) private var ignoreBlankLines = false
    @AppStorage(Prefs.folderIncludeHidden) private var includeHidden = false

    var body: some View {
        Form {
            Section("Text") {
                Slider(value: $fontSize, in: 9...20, step: 1) { Text("Font size: \(Int(fontSize)) pt") }
                Stepper("Tab width: \(tabWidth)", value: $tabWidth, in: 1...16)
                Toggle("Wrap long lines", isOn: $wrapLines)
            }
            Section("Defaults for new comparisons") {
                Picker("Whitespace", selection: $whitespace) {
                    ForEach(DiffOptions.Whitespace.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Ignore case", isOn: $ignoreCase)
                Toggle("Ignore blank lines", isOn: $ignoreBlankLines)
            }
            Section("Folders") {
                Toggle("Include hidden files", isOn: $includeHidden)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
