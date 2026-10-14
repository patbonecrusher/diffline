Diffline 1.0.3

Makes `git difftool -d` work even when an old copy of the `diffline` command is around:

- **The `diffline` command launches the app it belongs to.** Homebrew and File › Install Command Line Tool… now point at the script inside Diffline.app, so updating the app updates the command, and an older Diffline elsewhere on the disk can't be picked by mistake. `diffline --version` shows which app it launches.
- **One-time folder access.** If a file is a link outside the folders Diffline was given, Diffline offers **Allow Access…**, suggests the repository folder, and remembers your choice. Settings › Folder access lists and clears these.

Homebrew: `brew upgrade --cask diffline`. If you installed the command with File › Install Command Line Tool…, run it once more so it becomes a link.
