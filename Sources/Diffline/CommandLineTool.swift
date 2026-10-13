import AppKit

/// The `diffline` shell script, installed by File > Install Command Line Tool…. It launches the app
/// through `open` so the sandbox grants access to the files, and `-W -n` makes git wait for a fresh
/// instance that quits when its window closes.
enum CommandLineTool {
    static let script = """
    #!/bin/zsh
    # diffline — command-line launcher for Diffline.app
    #   diffline A B                                 compare two files or folders
    #   diffline --wait A B                          …and wait until the window is closed (git difftool, also -d)
    #   diffline --merge BASE LOCAL REMOTE [MERGED]  three-way merge; waits until done (git mergetool)
    #
    # git setup:
    #   git config --global merge.tool diffline
    #   git config --global mergetool.diffline.cmd 'diffline --merge "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'
    #   git config --global mergetool.diffline.trustExitCode false
    #   git config --global diff.tool diffline
    #   git config --global difftool.diffline.cmd 'diffline --wait "$LOCAL" "$REMOTE"'
    emulate -L zsh
    set -e
    APP="Diffline"

    abs() { [[ $1 == /* ]] && print -r -- "$1" || print -r -- "$PWD/$1" }

    # Diffline runs in the App Sandbox: it can read what is handed to it through `open`, but not files that
    # symbolic links point to. `git difftool --dir-diff` builds one side out of links into the working tree,
    # so pass every link target along too; --compare tells the app which two items to compare.
    link_targets() {
      local d l t
      for d in "$@"; do
        [[ -d $d ]] || continue
        for l in "$d"/**/*(N@D); do
          t=${l:A}
          [[ -f $t ]] && print -r -- "$t"
        done
      done
    }

    compare() {   # compare WAIT A B
      local wait=$1 a=$(abs "$2") b=$(abs "$3")
      local -a targets flags extra
      targets=("${(@f)$(link_targets "$a" "$b")}")
      targets=(${targets:#})                        # drop the empty element when there are none
      if [[ $wait == 1 ]]; then flags=(-W -n); extra=(--quit-on-close); fi
      exec open $flags -a "$APP" "$a" "$b" $targets --args $extra --compare "$a" "$b"
    }

    case "${1:-}" in
      --merge)
        (( $# >= 4 )) || { print -u2 "usage: diffline --merge BASE LOCAL REMOTE [MERGED]"; exit 2 }
        BASE=$(abs "$2"); LOCAL=$(abs "$3"); REMOTE=$(abs "$4")
        if [[ -n ${5:-} ]]; then
          MERGED=$(abs "$5")
          [[ -e $MERGED ]] || : > "$MERGED"
          exec open -W -n -a "$APP" "$BASE" "$LOCAL" "$REMOTE" "$MERGED" --args --quit-on-close --merge "$BASE" "$LOCAL" "$REMOTE" --output "$MERGED"
        fi
        exec open -W -n -a "$APP" "$BASE" "$LOCAL" "$REMOTE" --args --quit-on-close --merge "$BASE" "$LOCAL" "$REMOTE" ;;
      --wait)
        (( $# >= 3 )) || { print -u2 "usage: diffline --wait A B"; exit 2 }
        compare 1 "$2" "$3" ;;
      -h|--help|"")
        sed -n '2,12p' "$0"; exit 0 ;;
      *)
        (( $# >= 2 )) || { print -u2 "usage: diffline A B"; exit 2 }
        compare 0 "$1" "$2" ;;
    esac

    """

    @MainActor
    static func install() {
        let panel = NSSavePanel()
        panel.title = "Install Command Line Tool"
        panel.message = "Choose where to put the diffline script. A directory on your PATH such as /opt/homebrew/bin or /usr/local/bin works best."
        panel.nameFieldStringValue = "diffline"
        panel.showsTagField = false
        let fm = FileManager.default
        for candidate in ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/bin"] where fm.isWritableFile(atPath: candidate) {
            panel.directoryURL = URL(fileURLWithPath: candidate)
            break
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Prefer the copy bundled by build.sh (Tools/diffline) so the two never drift; fall back to the embedded text.
            let text = Bundle.main.url(forResource: "diffline", withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? script
            try text.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            let alert = NSAlert()
            alert.messageText = "Installed \(url.lastPathComponent)"
            alert.informativeText = "Run `diffline --help` in Terminal for usage, including the git mergetool and difftool configuration."
            alert.runModal()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// Arguments the command-line tool (or a script) passes after `--args`.
struct LaunchRequest {
    var mergePaths: (base: String, left: String, right: String, output: String?)?
    /// The two items to compare when other files (link targets) were handed over only to grant access.
    var comparePaths: (left: String, right: String)?
    var quitOnClose = false

    static func parse(_ args: [String]) -> LaunchRequest {
        var req = LaunchRequest()
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--quit-on-close": req.quitOnClose = true
            case "--compare" where i + 2 < args.count:
                req.comparePaths = (args[i + 1], args[i + 2])
                i += 2
            case "--merge" where i + 3 < args.count:
                var output: String?
                if i + 5 < args.count, args[i + 4] == "--output" { output = args[i + 5] }
                req.mergePaths = (args[i + 1], args[i + 2], args[i + 3], output)
                i += output == nil ? 3 : 5
            default: break
            }
            i += 1
        }
        return req
    }
}
