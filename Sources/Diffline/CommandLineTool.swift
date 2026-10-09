import AppKit

/// The `diffline` shell script, installed by File > Install Command Line Tool…. It launches the app
/// through `open` so the sandbox grants access to the files, and `-W -n` makes git wait for a fresh
/// instance that quits when its window closes.
enum CommandLineTool {
    static let script = """
    #!/bin/sh
    # diffline — command-line launcher for Diffline.app
    #   diffline A B                                 compare two files or folders
    #   diffline --wait A B                          …and wait until the window is closed (git difftool)
    #   diffline --merge BASE LOCAL REMOTE [MERGED]  three-way merge; waits until done (git mergetool)
    #
    # git setup:
    #   git config --global merge.tool diffline
    #   git config --global mergetool.diffline.cmd 'diffline --merge "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'
    #   git config --global mergetool.diffline.trustExitCode false
    #   git config --global difftool.diffline.cmd 'diffline --wait "$LOCAL" "$REMOTE"'
    set -e
    APP="Diffline"
    abs() { case "$1" in /*) printf '%s\\n' "$1" ;; *) printf '%s/%s\\n' "$(pwd)" "$1" ;; esac; }
    case "${1:-}" in
      --merge)
        [ $# -ge 4 ] || { echo "usage: diffline --merge BASE LOCAL REMOTE [MERGED]" >&2; exit 2; }
        BASE=$(abs "$2"); LOCAL=$(abs "$3"); REMOTE=$(abs "$4")
        if [ -n "${5:-}" ]; then
          MERGED=$(abs "$5")
          [ -e "$MERGED" ] || : > "$MERGED"
          exec open -W -n -a "$APP" "$BASE" "$LOCAL" "$REMOTE" "$MERGED" --args --quit-on-close --merge "$BASE" "$LOCAL" "$REMOTE" --output "$MERGED"
        fi
        exec open -W -n -a "$APP" "$BASE" "$LOCAL" "$REMOTE" --args --quit-on-close --merge "$BASE" "$LOCAL" "$REMOTE" ;;
      --wait)
        [ $# -ge 3 ] || { echo "usage: diffline --wait A B" >&2; exit 2; }
        exec open -W -n -a "$APP" "$(abs "$2")" "$(abs "$3")" --args --quit-on-close ;;
      -h|--help|"")
        sed -n '2,11p' "$0"; exit 0 ;;
      *)
        [ $# -ge 2 ] || { echo "usage: diffline A B" >&2; exit 2; }
        exec open -a "$APP" "$(abs "$1")" "$(abs "$2")" ;;
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
            try script.write(to: url, atomically: true, encoding: .utf8)
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
    var quitOnClose = false

    static func parse(_ args: [String]) -> LaunchRequest {
        var req = LaunchRequest()
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--quit-on-close": req.quitOnClose = true
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
