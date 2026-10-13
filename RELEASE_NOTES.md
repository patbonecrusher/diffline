Diffline 1.0.1

Fixes for `git difftool --dir-diff` (`git difftool -d`):

- Files on the working-tree side no longer fail with "Couldn't open the files… To view or change permissions". git builds that side out of symbolic links into your repository, which the sandboxed app couldn't follow; the `diffline` command now hands the link targets to Diffline too.
- Folder comparison follows file links, so sizes and "Identical/Different" reflect the real files instead of the links.
- Merges saved in a dir-diff now change the real working-tree file, not git's temporary link.
- A file that can't be read no longer aborts a whole folder comparison: it is listed as "Can't read", with the reason on hover.
- Errors name the file and say why it couldn't be opened.

The fix lives partly in the `diffline` command: `brew upgrade --cask diffline` updates both. If you installed the command with File › Install Command Line Tool…, run it again.

Homebrew: `brew install --cask patbonecrusher/tap/diffline`
