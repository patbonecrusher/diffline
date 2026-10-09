# Diffline

A native macOS diff and merge tool, written in Swift (SwiftUI + AppKit). Compares two text files side by
side with every changed line aligned and the differing words highlighted, merges changes in either
direction, and compares folders recursively.

## Build

```sh
./build.sh            # release build → build/Diffline.app (ad-hoc signed, sandboxed)
./build.sh --open     # …and launch it
./build.sh --sign dev # sign with the Apple Development certificate (tests the sandbox for real)
swift test            # the diff engine's tests
```

Requires Xcode 15+ (macOS 14 deployment target). No Xcode project: it's a Swift Package, and `build.sh`
assembles the `.app` bundle (Info.plist, generated icon, sandbox entitlements, signature).
Copy `build/Diffline.app` to `/Applications` to get *Compare with Diffline* in Finder's Services menu.

Signed / notarized / App Store builds: see [RELEASING.md](RELEASING.md).

## Features

- Side-by-side file comparison; long lines wrap on both sides without breaking row alignment
- Word-level highlighting inside changed lines
- Syntax coloring for 24 languages (detected from the file name, or pick one from the Language menu)
- Next/Previous change (⌘↓ / ⌘↑), Take Left / Take Right per change (⌥⌘→ / ⌥⌘←) with Undo, Save (⌘S)
- Folder comparison: identical / different / left only / right only, differences-only filter, drill into files
- Comparison options: whitespace (exact, trailing, changes, all), ignore case, ignore blank lines
- Export Unified Diff… (⇧⌘E) and Copy Unified Diff (⌥⌘C)
- Three-way merge (File > Merge Files…): base, mine and theirs side by side with the merged result in
  the middle. Non-overlapping changes merge by themselves; conflicts are stepped through (⇧⌘↓ / ⇧⌘↑)
  and resolved with Take Left, Take Right, Both or Base, with Undo. Unresolved conflicts save with
  git-style markers.
- A `diffline` command-line tool (File > Install Command Line Tool…) for `git difftool` and
  `git mergetool`; see below
- Open by dropping two items on the start window or the Dock icon, `open -a Diffline a b`, or the
  Finder service *Compare with Diffline*; Recent comparisons use security-scoped bookmarks
- Binary files are detected and compared byte for byte
- Files with tens of thousands of lines stay responsive: only visible rows are laid out

## git integration

Install the tool with File > Install Command Line Tool… (put it somewhere on your PATH), then:

```sh
git config --global merge.tool diffline
git config --global mergetool.diffline.cmd 'diffline --merge "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'
git config --global mergetool.diffline.trustExitCode false
git config --global difftool.diffline.cmd 'diffline --wait "$LOCAL" "$REMOTE"'
```

`git mergetool` then opens each conflicted file in Diffline and waits until its window closes. The
script launches the app through `open -W -n` with the files as open arguments, which is what lets a
sandboxed app read and write them; `--args --merge … --quit-on-close` tells the app which file is which
and to quit when done.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/DiffCore/Myers.swift` | Myers O(ND) diff with the linear-space bisect refinement, on integer tokens |
| `Sources/DiffCore/LineDiff.swift` | Line splitting, normalization options, aligned rows and hunks, intra-line highlights, unified diff output |
| `Sources/DiffCore/FolderCompare.swift` | Recursive folder comparison with content compare and cancellation |
| `Sources/DiffCore/Syntax.swift` | Language definitions and the line-state tokenizer behind syntax coloring |
| `Sources/DiffCore/ThreeWay.swift` | diff3-style three-way merge: chunk classification and output with conflict markers |
| `Sources/Diffline/MergeSession.swift`, `MergeView.swift`, `MergeDocumentView.swift` | The merge window: resolutions, navigation, the column view |
| `Sources/Diffline/CommandLineTool.swift` | The `diffline` script and its installer, launch-argument parsing |
| `Sources/Diffline/DifflineApp.swift` | App entry, app delegate (open URLs, Services provider), start window scene |
| `Sources/Diffline/WindowManager.swift` | AppKit comparison windows, key-window tracking for menu commands |
| `Sources/Diffline/FileCompareSession.swift` | Per-window state: files, diff, navigation, merge with undo, save, export |
| `Sources/Diffline/DiffDocumentView.swift` | The custom AppKit view that draws both panes, line numbers and the merge gutter |
| `Sources/Diffline/FileCompareView.swift` | Control bar, file headers, status bar around the diff view |
| `Sources/Diffline/FolderCompareSession.swift`, `FolderCompareView.swift` | Folder comparison table |
| `Sources/Diffline/StartView.swift` | Drop targets, Choose… buttons, Recent list |
| `Sources/Diffline/Commands.swift` | File / Changes / View menus |
| `Tools/MakeIcon` | Generates the app icon at build time |
| `Tools/asc.py` | App Store Connect listing automation |

## Notes

- Sandboxed, App Store ready, public API only, no third-party code.
- The diff runs on a background task; the view relays out only the rows intersecting the visible rect.
- Merging edits the in-memory line arrays and re-diffs; nothing is written until Save.
- Encoding: UTF-8 first, then Foundation's encoding detection; line endings (LF / CRLF / CR) and a
  trailing newline are preserved on save.

## Testing

```sh
swift test
open -a build/Diffline.app Samples/server-v1.py Samples/server-v2.py --args -windowSize 1280x800
```

`Samples/` holds a pair of files with changes, insertions, a wrapped line and tabs. `-windowSize WxH`
and `-preferRetina YES` are debug flags for screenshots.
