# WSL Firefox Path Forms - Full Reference

Read this file when constructing Firefox CLI arguments, terminal chat links, or embedded hrefs in review artifacts.

## Universal rule: encoding DEPENDS on the consumer (firefox.exe vs MS Terminal)

Spaces (and other reserved chars) are encoded differently depending on WHO parses the URI:
- **firefox.exe arguments (Forms 2 and 4 below)**: build from the raw filesystem path with **literal
  characters** - a space stays a space, NEVER `%20`; likewise no `%28`/`%2D`/etc. Firefox parses its
  own CLI arg against the filesystem, where the real path has a literal space, so `%20` would not
  resolve.
- **MS Terminal clickable chat links (Forms 3 and 5 below)**: percent-encode spaces as **`%20`**. A
  literal space ENDS Terminal's auto-detected link (its URL-detection regex class contains no space),
  and surrounding single/double quotes are not part of the match either; `%20` IS detected as one
  contiguous link and Terminal's `FileUriToPath` decodes it back to a real space before opening.
  (Confirmed empirically + against Terminal source `703ef7f`; see plan `user-plans/068-wsl-clickable-file-uri-convention.md`.)

The host is ALWAYS the literal `wsl.localhost`;
the distro is the FIRST PATH SEGMENT, never the authority - `file://<distro>/...` (e.g. `file://nixos/...`,
dropping `wsl.localhost`) is the "forgot I'm in WSL" footgun and does not resolve. When emitting in a
Bash command use `printf '%s\n'`, NEVER `echo` (zsh's builtin echo corrupts backslash escapes).

## The Four Forms (MUST NOT be conflated)

### Form 1: Remote .md URL (pass straight through)
```bash
"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" "https://example.com/file.md"
```
A non-markdown URL (MR/PR, pipeline, any web page) does NOT go here - use `xdg-open "<url>"` (Edge) instead.

### Form 2: WSL-native local file as firefox.exe CLI argument  (5-slash form)
```bash
p=/abs/linux/path/doc.md                                   # absolute WSL path (keeps leading /)
distro="$(printf '%s' "${WSL_DISTRO_NAME:-$WSL_DISTRO}" | tr '[:upper:]' '[:lower:]')"   # nixos
"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" "file://///wsl.localhost/${distro}${p}" >/dev/null 2>&1 &
```
Pass the **5-slash** `file://///wsl.localhost/<distro>/<abs-path>` form (`file:` + five `/`; `${p}`'s
leading slash supplies one). **`wslpath` is NOT installed in this shell** - the old `"$(wslpath -w "$p")"`
recipe expands to an EMPTY arg and SILENTLY opens nothing (Firefox already running -> exit 0). Do NOT use
`wslpath`, and do NOT reach for the backslash UNC `\\wsl.localhost\...` form (it needs wslpath too). The
2-slash `file://wsl.localhost/...` is WRONG as a firefox arg - Firefox strips the authority to
`file:///<distro>/...` and nothing opens; the 5-slash form preserves `wsl.localhost`.

### Form 3: Terminal-clickable chat link (chat output only, NEVER an exe arg)  (2-slash form)
```
file://wsl.localhost/<distro>/<abs-path-without-leading-slash>
```
Two slashes after `file:`. MS Terminal renders this as a clickable link. Clicking does NOT go through
Edge - Terminal runs its OWN `FileUriToPath` on the link text, producing the UNC
`\\wsl.localhost\<distro>\...`, and hands THAT to `ShellExecute`, which opens the file in the OS
default handler for its type (e.g. Notepad for `.txt`). That is why this form is 2-slash and
self-contained, independent of the firefox.exe arg Forms 2/4. **Spaces MUST be `%20`** here (see the
Universal rule) - a literal space would end the link. **A `/mnt/<drive>` file does NOT use this form**
- use Form 5. ONLY for printing in chat responses.

### Form 4: Embedded href inside a doc opened in Firefox/docu.md  (5-slash form)
```
file://///wsl.localhost/<distro>/<abs-path-without-leading-slash>
```
Five slashes (`file:` + five `/`) - same as Form 2. Firefox strips the two-slash form's authority to `file:///<distro>/...` (bogus); the five-slash form preserves `wsl.localhost` as the UNC host so the link resolves. Heading anchors: `...#lower-case-github-slug`.

If docu.md cannot read a `file://`-opened local file (Firefox file-access restrictions), serve the directory over `http://localhost` and open that URL in Firefox instead.

### Form 5: Terminal-clickable chat link for a `/mnt/<drive>` (Windows DrvFs) file  (native drive form)
```
file:///<DRIVE>:/<path-after-the-mount>
```
Three slashes then a drive letter: `/mnt/c/Users/x/doc.md` -> `file:///C:/Users/x/doc.md` (spaces
`%20`). A `/mnt/<drive>` file is a Windows drive mount; routing it through the wsl.localhost UNC form
(`file://wsl.localhost/<distro>/mnt/c/...`) IS detected by Terminal but ShellExecute silently fails -
the resolved `\\wsl.localhost\<distro>\mnt\c\...` is a double hop (Windows -> wsl.localhost 9p -> DrvFs)
that the 9p share does not traverse. The native `file:///C:/...` resolves straight to `C:\...` and
opens. Confirmed by click-test; see plan 068.

## Quick Reference

| Scenario | Form | Example |
|---|---|---|
| WSL-native `.md` -> firefox.exe CLI arg | `file://///wsl.localhost/` (**5**-slash) | `file://///wsl.localhost/nixos/home/tim/...` |
| WSL-native chat link (click opens via Terminal ShellExecute) | `file://wsl.localhost/` (**2**-slash) | `file://wsl.localhost/nixos/home/tim/...` |
| `/mnt/<drive>` chat link (Windows DrvFs file) | native `file:///<D>:/` | `file:///C:/Users/me/doc.md` |
| Embedded href in review doc | `file://///wsl.localhost/` (**5**-slash) | `file://///wsl.localhost/nixos/home/tim/...` |
| Remote .md URL | Pass straight through | `firefox.exe "https://.../file.md"` |

The split: firefox.exe consumers (exe arg / embedded href, 5-slash) take LITERAL paths - no `%20`; MS
Terminal chat links (Forms 3 and 5) percent-encode spaces as `%20`. A `/mnt/<drive>` chat link uses
the native `file:///<D>:/` form, never the wsl.localhost double hop.

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
