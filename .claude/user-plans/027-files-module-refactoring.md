# Plan 027: Files Module Refactoring — Detailed Breakdown

**Branch**: `feat/usb-jetson-pa161878`
**Created**: 2026-03-14
**Parent**: Plan 026 Task 1 (Files Module Refactoring F5)

## Context

The files module (`modules/programs/files [nd]/`) has accumulated significant
technical debt during the dendritic migration. Feature modules (shell-utils,
tmux, terminal, development-tools, system-tools) now install scripts via
`writeShellApplication` with proper `runtimeInputs`, but the files module
ALSO installs the same scripts as plain symlinks. An exclusion list
(`validatedScriptNames`) was added to prevent duplicates, but it is
incomplete (18 scripts missing) and has 4 orphaned entries.

**Critical discovery**: Two modules (shell-utils, tmux) already have their OWN
copies of scripts in `./files/` subdirectories, creating true file-level
duplication in the git repo. Three others (terminal, development-tools,
system-tools) read from `files [nd]/files/bin/` via `builtins.readFile`
with relative paths like `(../../.. + "/modules/programs/files [nd]/files/bin/...")`.

**Goal**: Eliminate script duplication, remove the exclusion list, and make
each feature module fully own its scripts. The files module becomes a thin
manager for the ~8 scripts that don't belong to any feature module.

## Progress Table

| Step | Status | Description |
|------|--------|-------------|
| 0 | TASK:COMPLETE | Audit verification & baseline |
| 1 | TASK:COMPLETE | Remove 4 orphaned exclusion entries |
| 2 | TASK:COMPLETE | Remove duplicate scripts (shell-utils batch: 8 scripts) |
| 3 | TASK:COMPLETE | Remove duplicate scripts (tmux batch: 7 scripts) |
| 4 | TASK:COMPLETE | Remove duplicate libraries (9 .bash files) |
| 5 | TASK:COMPLETE | Move terminal scripts to terminal module (4 scripts) |
| 6 | TASK:COMPLETE | Move development-tools scripts (4 scripts) |
| 7 | TASK:COMPLETE | Move system-tools scripts (5 scripts) |
| 8 | TASK:COMPLETE | Handle remaining files-only scripts (~8 scripts) |
| 9 | TASK:COMPLETE | Eliminate exclusion list + fix completion scope |
| 10 | TASK:COMPLETE | Final validation & plan 026 update |

---

## Step 0: Audit Verification & Baseline

**Status**: TASK:PENDING
**Risk**: None (read-only)

Establish the starting state before any changes.

### Actions

1. Run `nix flake check --no-build` — confirm green baseline
2. Run `home-manager switch --flake ".#${USER}@$(hostname)" --dry-run` — confirm green
3. Verify the duplicate inventory by diffing files between locations
4. Document the exact count of home.file entries the files module generates

### Definition of Done

- [ ] Both checks pass on current branch state
- [ ] Duplicate inventory confirmed (see reference table below)

### Reference: Current Duplication Map

**Duplicated in shell-utils/files/bin/ AND files [nd]/files/bin/ (IDENTICAL):**
```
colorfuncs.sh, help-format-template.sh, mytree.sh, remote-wifi-analyzer,
soundcloud-dl, stress.sh, vwatch, wifi-test-comparison
```

**Duplicated in tmux/files/ AND files [nd]/files/bin/ (IDENTICAL):**
```
tmux-auto-attach, tmux-cpu-mem, tmux-save-with-rename, tmux-session-picker,
tmux-session-picker-profiled, tmux-test-data-generator, tmux-window-status-format
```

**Duplicated libraries in shell-utils/files/lib/ AND files [nd]/files/lib/ (IDENTICAL):**
```
claude-utils.bash, color-utils.bash, datetime-utils.bash, fs-utils.bash,
general-utils.bash, git-utils.bash, path-utils.bash, profiling-utils.bash,
terminal-utils.bash
```

**Read FROM files [nd] via relative builtins.readFile paths (no own copy):**
```
terminal.nix      → setup-terminal-fonts, check-terminal-setup,
                    diagnose-emoji-rendering, is_terminal_background_light_or_dark.sh
development-tools → claudevloop, restart_claude, mkclaude_desktop_config, pdf2md.py
system-tools      → bootstrap-secrets.sh, bootstrap-ssh-keys.sh, build-wsl-tarball,
                    restart-usb, restart-usb-improved
```

**Not installed by any feature module (files-only):**
```
ensure-nix.sh, fix-terminal-fonts.ps1, font-detection-functions.ps1,
install-noto-emoji.ps1, install-terminal-fonts.ps1, restart-usb-v4.ps1
```

**Orphaned exclusion entries (not in files/bin, not installed anywhere):**
```
simple-test, hello-validated, claude-code-wrapper, claude-code-update
```

---

## Step 1: Remove Orphaned Exclusion Entries

**Status**: TASK:PENDING
**Risk**: Minimal
**Files**: `_completion-generator.nix`

### Problem

4 entries in `validatedScriptNames` reference scripts that don't exist in
`files/bin/` and aren't installed by any module. They're harmless but add
confusion.

### Actions

Remove from `validatedScriptNames` (lines 315-338):
- `"simple-test"` — not in files/bin, not installed anywhere
- `"hello-validated"` — not in files/bin, not installed anywhere
- `"claude-code-wrapper"` — not in files/bin, not installed anywhere
- `"claude-code-update"` — not in files/bin, not installed anywhere

### Validation

- `nix flake check --no-build` passes
- No change to installed scripts (entries were already no-ops)

### Definition of Done

- [ ] 4 orphaned entries removed
- [ ] `nix flake check --no-build` passes
- [ ] Commit: `refactor(files): remove 4 orphaned exclusion list entries`

---

## Step 2: Remove Duplicate Scripts — Shell-Utils Batch

**Status**: TASK:PENDING
**Risk**: Medium — dual installation currently "works" because PATH precedence
**Files**: `files [nd]/files/bin/` (delete 8 files), `_completion-generator.nix`

### Problem

These 8 scripts exist identically in BOTH locations:
- `modules/programs/shell-utils/files/bin/{script}` ← shell-utils reads from HERE
- `modules/programs/files [nd]/files/bin/{script}` ← files module symlinks from HERE

The files module symlinks them to `~/bin/` AND generates auto-completions.
The shell-utils module installs them via `writeShellApplication` with
`runtimeInputs` to `~/.nix-profile/bin/`. The `~/.nix-profile/bin/` version
takes precedence in PATH, so the `~/bin/` symlink is shadowed but wasteful.

**None of these 8 are in the exclusion list** — confirming dual installation.

### Scripts

| Script | shell-utils runtimeInputs |
|--------|---------------------------|
| colorfuncs.sh | coreutils |
| help-format-template.sh | coreutils |
| mytree.sh | tree, coreutils |
| remote-wifi-analyzer | coreutils, openssh, bash |
| soundcloud-dl | yt-dlp, coreutils |
| stress.sh | stress-ng, coreutils |
| vwatch | coreutils |
| wifi-test-comparison | coreutils, openssh, bash |

### Actions

1. Delete 8 files from `modules/programs/files [nd]/files/bin/`
2. Verify shell-utils still reads from `./files/bin/` (its own copy) — no path change needed
3. Verify files module no longer tries to symlink or generate completions for them
   (they're auto-discovered from `filesDir + "/bin"`, so removing the source file is sufficient)
4. DO NOT add to exclusion list — the file is gone, nothing to exclude

### Completions Impact

These scripts lose auto-generated completions from the files module. The
completions were generic (parse `--help` at TAB-time) and fragile. The
shell-utils module does not generate its own completions. This is acceptable —
scripts can gain proper completions in shell-utils later if needed.

### Validation

- `nix flake check --no-build` passes
- `home-manager switch --flake ".#${USER}@$(hostname)" --dry-run` succeeds
- Verify `~/bin/` no longer has symlinks for these 8 scripts (after actual switch)
- Verify `~/.nix-profile/bin/` still has them (from shell-utils)

### Definition of Done

- [ ] 8 files deleted from `files [nd]/files/bin/`
- [ ] Both checks pass
- [ ] Commit: `refactor(files): remove 8 scripts duplicated in shell-utils`

---

## Step 3: Remove Duplicate Scripts — Tmux Batch

**Status**: TASK:PENDING
**Risk**: Medium (same dual-install pattern as Step 2)
**Files**: `files [nd]/files/bin/` (delete 7 files), `_completion-generator.nix`

### Problem

7 tmux scripts exist identically in both locations. The tmux module reads
from `./files/` (its own directory). Only `tmux-session-picker` is in the
exclusion list — the other 6 are dual-installed.

### Scripts

| Script | In exclusion list? | tmux.nix installation |
|--------|--------------------|----------------------|
| tmux-session-picker | YES | writeBashBin + symlinkJoin + wrapProgram (fzf, parallel) |
| tmux-session-picker-profiled | NO | writeShellApplication (fzf, tmux, parallel) |
| tmux-cpu-mem | NO | writeShellApplication (procps, coreutils) |
| tmux-save-with-rename | NO | writeShellApplication + string substitution |
| tmux-test-data-generator | NO | writeShellApplication (coreutils) |
| tmux-window-status-format | NO | writeBashBin + string substitution |
| tmux-auto-attach | NO | Sourced directly by shell.nix in zsh.initContent |

### Actions

1. Delete 7 files from `modules/programs/files [nd]/files/bin/`
2. Remove `"tmux-session-picker"` from `validatedScriptNames` (no longer in files/bin)
3. Verify tmux module still reads from `./files/` (its own directory)

### Special Case: tmux-auto-attach

`tmux-auto-attach` is sourced by `shell.nix` via `source ~/bin/tmux-auto-attach`.
After removing from files [nd], the `~/bin/` symlink disappears. Need to verify:
- Does the tmux module install it? (It's in `tmux/files/` but may not be in `home.packages`)
- If not installed by tmux module, the `source` in shell.nix would break

**CHECK THIS before deleting tmux-auto-attach.**

### Validation

- `nix flake check --no-build` passes
- HM dry-run succeeds
- Verify tmux-auto-attach is still available at `~/bin/` after switch

### Definition of Done

- [ ] 7 files deleted (or 6 if tmux-auto-attach needs to stay)
- [ ] `tmux-session-picker` removed from exclusion list
- [ ] Both checks pass
- [ ] Commit: `refactor(files): remove 7 tmux scripts duplicated in tmux module`

---

## Step 4: Remove Duplicate Libraries

**Status**: TASK:PENDING
**Risk**: Medium-High — libraries are consumed by multiple scripts
**Files**: `files [nd]/files/lib/` (delete 9 .bash files), `_completion-generator.nix`

### Problem

9 .bash library files exist identically in:
- `modules/programs/shell-utils/files/lib/{lib}.bash` ← shell-utils reads from here
- `modules/programs/files [nd]/files/lib/{lib}.bash` ← files module copies to `~/lib/`

The files module installs them via:
```nix
"lib" = { source = filesDir + "/lib"; recursive = true; };
```
This copies ALL of `files/lib/` to `~/lib/`, including 2 .nix files
(`_script-libraries.nix`, `_domain-generators.nix`) that shouldn't be deployed.

### Analysis Needed

1. **Who consumes `~/lib/*.bash`?** Do scripts `source ~/lib/general-utils.bash`
   at runtime? Or is the library inlining done at build time by the module?
2. **Does shell-utils install these libraries independently?** If shell-utils
   puts them in `~/.nix-profile/` or `~/lib/`, removing from files module is safe.
3. **Can we drop the `home.file."lib"` entry entirely** after confirming no
   runtime `source ~/lib/...` references?

### Actions (after analysis)

1. If libraries are inlined at build time: Delete 9 .bash files from `files [nd]/files/lib/`
2. If libraries are sourced at runtime: Ensure one module (shell-utils or files)
   still installs them — not both
3. Fix the `home.file."lib"` entry to either:
   a. Not exist (if all libraries are inlined), or
   b. Use explicit file list (exclude .nix files), or
   c. Point to shell-utils location

### Definition of Done

- [ ] No duplicate .bash library files in git
- [ ] `~/lib/` doesn't contain .nix files
- [ ] Scripts that `source` libraries still work
- [ ] Both checks pass
- [ ] Commit: `refactor(files): deduplicate 9 bash libraries`

---

## Step 5: Move Terminal Scripts to Terminal Module

**Status**: TASK:PENDING
**Risk**: Low (straightforward path change)
**Files**: terminal.nix, `files [nd]/files/bin/` (delete 4), new `terminal/files/`

### Problem

`terminal.nix` reads 4 scripts from `files [nd]` via:
```nix
text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/setup-terminal-fonts");
```
This creates cross-module coupling. The scripts should live IN the terminal module.

### Scripts

```
setup-terminal-fonts
check-terminal-setup
diagnose-emoji-rendering
is_terminal_background_light_or_dark.sh
```

### Actions

1. Create `modules/programs/terminal/files/` directory
2. Move 4 scripts from `files [nd]/files/bin/` to `terminal/files/`
3. Update `terminal.nix` readFile paths from:
   `(../../.. + "/modules/programs/files [nd]/files/bin/...")` → `./files/...`
4. Verify no other module references these scripts

### Definition of Done

- [ ] 4 scripts moved to `terminal/files/`
- [ ] `terminal.nix` uses `./files/` paths
- [ ] 4 scripts removed from `files [nd]/files/bin/`
- [ ] Both checks pass
- [ ] Commit: `refactor(terminal): own script sources, remove files [nd] dependency`

---

## Step 6: Move Development-Tools Scripts

**Status**: TASK:PENDING
**Risk**: Low
**Files**: development-tools.nix, `files [nd]/files/bin/` (delete 4), new `development-tools/files/`

### Scripts

```
claudevloop
restart_claude
mkclaude_desktop_config
pdf2md.py
```

### Actions

1. Create `modules/programs/development-tools/files/` directory
2. Move 4 scripts from `files [nd]/files/bin/`
3. Update `development-tools.nix` readFile paths from:
   `(../../.. + "/modules/programs/files [nd]/files/bin/...")` → `./files/...`

### Definition of Done

- [ ] 4 scripts moved, paths updated, both checks pass
- [ ] Commit: `refactor(development-tools): own script sources`

---

## Step 7: Move System-Tools Scripts

**Status**: TASK:PENDING
**Risk**: Low
**Files**: system-tools.nix, `files [nd]/files/bin/` (delete 5), new `system-tools/files/`

### Scripts

```
bootstrap-secrets.sh
bootstrap-ssh-keys.sh
build-wsl-tarball
restart-usb
restart-usb-improved
```

### Actions

1. Create `modules/programs/system-tools/files/` directory
2. Move 5 scripts from `files [nd]/files/bin/`
3. Update `system-tools.nix` readFile paths
4. Also remove these 3 from exclusion list (if still present):
   `bootstrap-secrets.sh`, `bootstrap-ssh-keys.sh`, `build-wsl-tarball`

### Definition of Done

- [ ] 5 scripts moved, paths updated, 3 exclusion entries removed
- [ ] Both checks pass
- [ ] Commit: `refactor(system-tools): own script sources`

---

## Step 8: Handle Remaining Files-Only Scripts

**Status**: TASK:PENDING
**Risk**: Low — these scripts only exist in one place
**Files**: `files [nd]/files/bin/`

### Remaining Scripts After Steps 2-7

```
ensure-nix.sh              ← Hook script (used by dev-shell startup)
fix-terminal-fonts.ps1     ← PowerShell (Windows-side)
font-detection-functions.ps1
install-noto-emoji.ps1
install-terminal-fonts.ps1
restart-usb-v4.ps1         ← PowerShell (Windows-side)
```

Plus non-bin content:
```
files/claude/prompt/static-prompt.md
files/content/
files/glow.yml
files/yazi-*.lua
files/yazi-debug
```

### Analysis & Decisions

**PowerShell scripts (4 files):** These are Windows-side utilities. Options:
- Keep in files module (simplest)
- Move to system-tools (they're system utilities)
- Move to terminal module (font-related ones)

**ensure-nix.sh:** Already referenced by dev-shell hooks. Options:
- Keep in files module
- Move to `modules/flake-parts/dev-shells.nix` area

**Config files (glow, yazi, claude prompt):** Options:
- Keep in files module (they're generic "user files")
- Move to dedicated modules if they exist (yazi module? glow module?)

**Decision**: This step documents the remaining inventory and decides placement.
The files module may legitimately continue to exist as a "miscellaneous user
files" manager for things that don't belong to any specific feature module.

### Definition of Done

- [ ] Inventory of remaining scripts documented
- [ ] Each script has a decided owner (stay in files or move)
- [ ] Moves executed if applicable
- [ ] Both checks pass

---

## Step 9: Eliminate Exclusion List + Fix Completion Scope

**Status**: TASK:PENDING
**Risk**: Medium — changes the files module's core logic
**Files**: `_completion-generator.nix`

### Problem

After Steps 1-8, the exclusion list should be nearly empty. The remaining
entries reference scripts for esp-idf, onedrive, smart-nvimdiff, colorfuncs,
and mergejson — all of which have sources OUTSIDE files [nd] (inline in
their modules or in module-local files/) and DON'T exist in `files [nd]/files/bin/`.
These exclusion entries are dead weight — excluding names that don't exist.

### Actions

1. Remove `validatedScriptNames` list entirely
2. Remove all `excludeNames = validatedScriptNames` references in:
   - `mkHomeFiles` call (line 400-405)
   - `mkBashCompletionFiles` (line 363)
   - `mkZshCompletionFiles` (line 382)
3. Simplify `mkHomeFiles`, `mkBashCompletionFiles`, `mkZshCompletionFiles`:
   - Remove `excludeNames` parameter from `mkHomeFiles`
   - Remove `validatedScriptNames` filter from completion functions
4. Completions now only cover the ~6 scripts remaining in `files [nd]/files/bin/`

### Completion Generation Status

Completions are already build-time (`pkgs.writeText` derivations). The
generated functions parse `--help` at TAB-completion runtime — this is the
standard approach and doesn't need changing. The plan's original item 1c
("move completion generation to build-time derivations") was based on a
misunderstanding — no change needed.

### Definition of Done

- [ ] `validatedScriptNames` list deleted
- [ ] All `excludeNames` / filter logic removed
- [ ] `_completion-generator.nix` is significantly simpler
- [ ] Both checks pass
- [ ] Commit: `refactor(files): eliminate exclusion list — all scripts owned by feature modules`

---

## Step 10: Final Validation & Plan 026 Update

**Status**: TASK:PENDING
**Risk**: None

### Actions

1. Run `nix flake check --no-build` — must pass
2. Run HM dry-run for pa161878-nixos — must pass
3. Verify all 7 consumer host configs evaluate:
   - wsl-enterprise, mbp, thinky-ubuntu, macbook-air, thinky-nixos, potato
   - tests.nix (lines 180, 562-625)
4. Audit `files [nd]/files/bin/` — only files-only scripts remain
5. Audit exclusion list — must not exist
6. Update Plan 026 Task 1 status to TASK:COMPLETE
7. Update CLAUDE.md if needed

### Plan 026 Task 1 DoD Checklist

- [ ] No `validatedScriptNames` exclusion list exists
- [ ] No hardcoded `./files` relative path used by OTHER modules
   (files module's own `filesDir = ./files;` is fine — standard Nix practice)
- [ ] Completion generation confirmed as build-time (was already correct)
- [ ] `nix flake check --no-build` passes
- [ ] HM dry-run succeeds
- [ ] All 7 consumers still work

---

## Execution Notes

- **One step per session** (per session workflow protocol)
- Steps 1-3 are independent and low-risk — good starting points
- Steps 5-7 follow the same pattern (move + update path) — could batch
- Step 4 (libraries) requires investigation — may be the most complex
- Step 8 is a decision point, not code change
- Step 9 depends on all prior steps being complete
- Step 10 is pure validation

### Dependency Graph

```
Step 0 (baseline)
  └──> Step 1 (orphaned entries)
  └──> Step 2 (shell-utils dups) ─┐
  └──> Step 3 (tmux dups)        ─┤
  └──> Step 4 (lib dups)         ─┤
  └──> Step 5 (terminal move)    ─┤
  └──> Step 6 (dev-tools move)   ─┤
  └──> Step 7 (system-tools move)─┤
  └──> Step 8 (remaining scripts) ┤
                                   └──> Step 9 (eliminate exclusion list)
                                          └──> Step 10 (final validation)
```

Steps 1-8 are all independent of each other. Step 9 requires all prior
steps. Step 10 requires Step 9.

### Risk Mitigation

- Each step has its own commit — easy to revert individual changes
- Each step validates independently with `nix flake check --no-build`
- The exclusion list is only removed AFTER all scripts are moved (Step 9)
- Steps 2-3 are safest because the feature modules already have their own copies
