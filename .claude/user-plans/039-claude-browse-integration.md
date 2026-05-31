# Plan 039: Cross-Platform Browser Integration for AI Agent Sessions

**Branch**: `feat/claude-browse`
**Created**: 2026-05-20

## Context

### Problem
When Claude Code produces URLs (PR links, pipeline URLs) or creates visual artifacts (diagrams, documentation), the user must manually copy-paste or `xdg-open` them. The user's dev environment is Terminal + Browser exclusively. Automating browser opens for reviewable content would eliminate friction and better integrate the browser into AI-assisted workflows.

### Current State
- **Global CLAUDE.md** already has two rules added 2026-05-20 in the n3x-foo session:
  1. "Opening files and URLs" in Critical Rules: explicit `xdg-open` mechanism instruction
  2. "Proactive Browser Integration" section: auto-open policy (PR URLs, diagrams, new docs, next-step links)
- These rules reference `xdg-open` directly, which works but has limitations
- **Existing xdg-open wrapper** (`modules/system/settings/wsl-home/wsl-home.nix:330-342`): WSL-only, wraps `wslview` from `wslu`, recovers 9p mounts. Not available on Mac or bare Linux.
- **Claude wrapper scripts** (`modules/programs/claude-code/_hm/lib.nix`): already set session env vars like `CLAUDE_TERMINAL_WIDTH` in `setup_environment()` at line 143. This is the natural place to add a `CLAUDE_BROWSE_STATE` tempfile for session scoping.

### Design Goals
1. **Session-grouped window management**: First browser open in a session creates a new window; subsequent opens become tabs in that window. Prevents tab sprawl across existing browser windows.
2. **Cross-platform**: WSL (Edge via wslview/edge.exe), macOS (open -a), bare Linux (xdg-open or direct browser). The nixcfg and nixcfg-work repos are shared with teammates on Macs and bare metal Linux.
3. **Quantity guardrail**: Cap auto-opens at 3 per burst; list remainder and let user choose.
4. **Graceful degradation**: If no session-aware browser invocation is possible, fall back to plain `xdg-open`/`open`. Window grouping is a nice-to-have, not a hard requirement.
5. **Separation of concerns**: The script handles HOW to open (platform detection, window grouping, session state). CLAUDE.md rules handle WHAT to open (behavioral policy). These are independent.

### Architecture Decision: Script vs Module Option

The `claude-browse` script should be a standalone `writeShellApplication` in `home.packages`, not a home-manager module option. Reasons:
- It's a simple utility, not a configurable service
- No per-user option surface needed (platform detection is automatic)
- Follows the pattern of `claudevloop`, `restart_claude`, `pdf2md` in `development-tools.nix`
- Can be used by any AI agent or even manually, not coupled to claude-code

### Where It Lives

`modules/programs/claude-code/` is the right home since:
- It's consumed primarily by Claude Code (and potentially other AI agents)
- The Claude wrapper scripts need modification to set the session env var
- Keeps browser integration co-located with the AI tooling that uses it

Script source: `modules/programs/claude-code/files/claude-browse`
Package: added to `home.packages` in `claude-code.nix` when claude-code is enabled

### Cross-Platform Browser Invocation

**Chromium-based browsers** (Edge, Chrome) accept:
- `--new-window URL` to create a new window
- Bare `URL` to open as a tab in the most recently focused window

**Platform detection logic:**
```
WSL?        -> edge.exe --new-window / edge.exe (direct .exe, bypasses wslview overhead)
macOS?      -> open -na "Microsoft Edge" --args --new-window / open -a "Microsoft Edge"
bare Linux? -> microsoft-edge --new-window / microsoft-edge (or $BROWSER)
fallback    -> xdg-open / open (no window grouping)
```

**Session state**: `CLAUDE_BROWSE_STATE` env var points to a tempfile created by the Claude wrapper. First `claude-browse` call checks if file exists; if not, uses `--new-window` and creates it. Subsequent calls skip `--new-window`.

If `CLAUDE_BROWSE_STATE` is unset (manual usage, non-Claude context), every call uses `--new-window` (safe default, no session grouping).

### Existing xdg-open Wrapper Interaction

The WSL `xdg-open` wrapper in `wsl-home.nix:330-342` handles mount recovery and wslpath. `claude-browse` on WSL should NOT go through this wrapper (it calls `edge.exe` directly for window control). The mount recovery is only needed for `wslview` which uses Windows shell associations. Direct `.exe` invocation doesn't need it.

On non-WSL platforms, `claude-browse` fallback calls `xdg-open` (Linux) or `open` (macOS) directly.

## Progress Table

| Task | Status | Description |
|------|--------|-------------|
| T1 | `TASK:COMPLETE` | Write `claude-browse` script with cross-platform detection and session state |
| T2 | `TASK:COMPLETE` | Add `CLAUDE_BROWSE_STATE` tempfile to Claude wrapper `setup_environment()` |
| T3 | `TASK:COMPLETE` | Package script and wire into `claude-code.nix` home.packages |
| T4 | `TASK:COMPLETE` | Update global CLAUDE.md rules to reference `claude-browse` instead of `xdg-open` |
| T5 | `TASK:COMPLETE` | Add quantity guardrail to CLAUDE.md "Proactive Browser Integration" section |
| T6 | `TASK:PENDING` | Test on WSL (primary dev env) |
| T7 | `TASK:PENDING` | Verify graceful degradation (unset CLAUDE_BROWSE_STATE, missing browser) |

## Task Details

### T1: Write `claude-browse` Script
**Status**: `TASK:PENDING`

Create `modules/programs/claude-code/files/claude-browse`:

**Behavior:**
1. Accept one argument: URL or file path
2. Detect platform (WSL via `$WSL_DISTRO_NAME`, macOS via `$OSTYPE`, bare Linux as default)
3. Check `$CLAUDE_BROWSE_STATE`:
   - If set and file does NOT exist: first open, use `--new-window`, create the state file
   - If set and file exists: subsequent open, bare URL (tab in existing window)
   - If unset: use `--new-window` every time (no session grouping)
4. Open the URL/file using platform-appropriate command
5. Exit 0 on success, exit 1 with stderr message on failure

**Platform commands:**
- WSL: `edge.exe --new-window "$1"` / `edge.exe "$1"`
- macOS: `open -na "Microsoft Edge" --args --new-window "$1"` / `open -a "Microsoft Edge" "$1"`
- Bare Linux: `microsoft-edge --new-window "$1"` / `microsoft-edge "$1"`
- Fallback (no Edge): `xdg-open "$1"` (Linux) / `open "$1"` (macOS)

**Edge detection:**
- WSL: `command -v edge.exe`
- macOS: `[ -d "/Applications/Microsoft Edge.app" ]`
- Linux: `command -v microsoft-edge`

**DoD**: Script exists, is executable, handles all 4 platform paths, handles missing browser gracefully.

### T2: Add `CLAUDE_BROWSE_STATE` to Wrapper
**Status**: `TASK:PENDING`

In `modules/programs/claude-code/_hm/lib.nix`, in the `setup_environment()` function (line 143), add after the `CLAUDE_TERMINAL_WIDTH` export:

```bash
# Session-scoped browser state for claude-browse window grouping
export CLAUDE_BROWSE_STATE="$(mktemp -t claude-browse-XXXXXX)"
rm -f "$CLAUDE_BROWSE_STATE"  # Create path, remove file; claude-browse creates on first use
```

The tempfile path is created but the file itself is removed. `claude-browse` creates the file on first invocation (`--new-window`), and subsequent calls see it exists (tab mode). The temp path is unique per session (mktemp) and cleaned up by the OS on reboot.

**Cleanup consideration**: Add a trap to the wrapper to remove the state file on exit? Not strictly necessary (tmpfiles are cleaned by systemd-tmpfiles or reboot), but cleaner. Check if the wrapper already has an EXIT trap.

**DoD**: `CLAUDE_BROWSE_STATE` is exported in `setup_environment()`, unique per Claude session.

### T3: Package and Wire
**Status**: `TASK:PENDING`

In `modules/programs/claude-code/claude-code.nix`, add to `home.packages`:

```nix
(pkgs.writeShellApplication {
  name = "claude-browse";
  text = builtins.readFile ./files/claude-browse;
  runtimeInputs = [ ]; # No runtime deps - uses only builtins and direct exe paths
})
```

Wire it into the conditional that gates on `programs.claude-code.enable`.

**DoD**: `claude-browse` appears on PATH after `home-manager switch`. `which claude-browse` resolves.

### T4: Update Global CLAUDE.md HOW Rule
**Status**: `TASK:PENDING`

Change the "Opening files and URLs" rule in Critical Rules from:
```
Use `xdg-open <path-or-url>` to open files or URLs...
```
To:
```
Use `claude-browse <path-or-url>` to open files or URLs in the user's browser. 
Session opens are grouped into a single browser window automatically. Falls back 
to xdg-open if claude-browse is not available.
```

**DoD**: Global CLAUDE.md references `claude-browse` as primary, `xdg-open` as fallback.

### T5: Add Quantity Guardrail
**Status**: `TASK:PENDING`

Add to the "Proactive Browser Integration" section in global CLAUDE.md, in the "Do not open automatically" list:

```
- More than 3 items in quick succession: list them and let the user choose which to open. 
  Exception: a single action producing multiple related URLs (e.g., MR link + pipeline link) 
  counts as one logical open.
```

**DoD**: Guardrail documented in CLAUDE.md.

### T6: Test on WSL
**Status**: `TASK:PENDING`

After `home-manager switch`:
1. Verify `which claude-browse` resolves
2. Run `claude-browse https://example.com` manually (should open new Edge window)
3. Run `claude-browse https://example.org` again (should open as tab in same window, if CLAUDE_BROWSE_STATE set)
4. Start a `claudemax` session, ask it to create a dummy URL and open it, verify window grouping
5. Verify the session state file is created in /tmp

**DoD**: Window grouping works in WSL with Edge. New session = new window, subsequent = tabs.

### T7: Verify Graceful Degradation
**Status**: `TASK:PENDING`

1. Unset `CLAUDE_BROWSE_STATE`, run `claude-browse <url>` -- should still open (new window every time)
2. Test with `edge.exe` not on PATH (rename temporarily) -- should fall back to `xdg-open`/`wslview`
3. Test with completely broken browser detection -- should exit 1 with useful error

**DoD**: All fallback paths work without errors. No silent failures.

## Execution Notes

- T1-T3 are implementation (can be done in one session)
- T4-T5 are CLAUDE.md edits (trivial, can bundle with T1-T3)
- T6-T7 require `home-manager switch` on the WSL dev machine
- macOS testing deferred until a teammate validates (no Mac in current dev env)
- The global CLAUDE.md changes from the n3x-foo session (2026-05-20) that added the initial xdg-open rules should be committed first or folded into this branch
