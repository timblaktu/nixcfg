# WSL Firefox Path Forms - Full Reference

Read this file when constructing Firefox CLI arguments, terminal chat links, or embedded hrefs in review artifacts.

## The Four Forms (MUST NOT be conflated)

### Form 1: Remote .md URL (pass straight through)
```bash
"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" "https://example.com/file.md"
```
A non-markdown URL (MR/PR, pipeline, any web page) does NOT go here - use `xdg-open "<url>"` (Edge) instead.

### Form 2: WSL-native local file as firefox.exe CLI argument
```bash
p=/abs/linux/path/doc.md
"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" "$(wslpath -w "$p")" >/dev/null 2>&1 &
```
MUST use the UNC path from `wslpath -w` (emits `\\wsl.localhost\<distro>\...`). NEVER pass `file://wsl.localhost/...` as a firefox.exe argument - Firefox strips the authority and mangles it to `file:///<distro>/...` (bogus path; nothing opens).

### Form 3: Terminal-clickable chat link (chat output only, NEVER an exe arg)
```
file://wsl.localhost/<distro>/<abs-path-without-leading-slash>
```
Two slashes after `file:`. MS Terminal renders this as a clickable link. This form is ONLY for printing in chat responses. When echoing in a Bash command, use `printf '%s\n'`, NEVER `echo` (zsh's builtin echo interprets backslash escapes and corrupts the path).

### Form 4: Embedded href inside a doc opened in Firefox/docu.md
```
file://///wsl.localhost/<distro>/<abs-path-without-leading-slash>
```
Five slashes (`file:` + five `/`). The two-slash form gets its authority stripped by Firefox to `file:///<distro>/...` (bogus). The five-slash form preserves `wsl.localhost` as the UNC host so the link resolves. Heading anchors: `...#lower-case-github-slug`.

If docu.md cannot read a `file://`-opened local file (Firefox file-access restrictions), serve the directory over `http://localhost` and open that URL in Firefox instead.

## Quick Reference

| Scenario | Form | Example |
|---|---|---|
| Local `.md` -> firefox.exe CLI arg | `wslpath -w` UNC | `"$(wslpath -w "$p")"` |
| Chat response link | `file://wsl.localhost/` (2-slash) | `file://wsl.localhost/nixos/home/tim/...` |
| Embedded href in review doc | `file://///wsl.localhost/` (5-slash) | `file://///wsl.localhost/nixos/home/tim/...` |
| Remote .md URL | Pass straight through | `firefox.exe "https://.../file.md"` |

## Image Review Workflow

NEVER open images one-by-one (each spawns a separate Windows Photos window). Instead:
1. Put all images in ONE folder with zero-padded lexicographic names (e.g. `01-before.png`, `02-after.png`)
2. Open the FOLDER: `explorer.exe 'C:\path\to\dir'`
3. Regenerate to a fresh folder name to bust Explorer's thumbnail cache

Shell note (zsh): arrays are 1-indexed. Build label lists with:
```zsh
for e in "1:Foo" "2:Bar"; do p=${e%%:*}; n=${e##*:}; done
```
Not a bash index-0 placeholder.
