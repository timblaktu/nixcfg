# Plan 033: Package Version Upgrades

## Context

`package-update-analysis.md` (commit `9b666a6`) identified 6 packages with available upgrades.
This plan executes those upgrades in risk order, validates each, and deletes the analysis file
(its content is now here). The `/analyze-package-updates` command can regenerate it in the future.

## Tasks

Progress table — one task per package, ordered by risk (low → medium):

| Task | Package | Current → Target | Risk | Pin Location | Status |
|------|---------|-----------------|------|-------------|--------|
| T0 | sops-nix | 2026-02-15 → latest | Low | `flake.lock` (flake input) | TASK:COMPLETE |
| T1 | zsh-autosuggestions | v0.7.0 → v0.7.1 | Low | `modules/programs/shell/shell.nix:418-423` | TASK:COMPLETE |
| T2 | marker-pdf | 1.10.1 → 1.10.2 | Low | `pkgs/marker-pdf/default.nix:47` | TASK:COMPLETE |
| T3 | zsh-syntax-highlighting | 0.7.1 → 0.8.0 | Low | `modules/programs/shell/shell.nix:427-432` | TASK:COMPLETE |
| T4 | opencode | 1.3.2 → 1.4.3 | Medium | `overlays/default.nix:24-31` | TASK:COMPLETE |
| T5 | claude-code | 2.1.87 → 2.1.97 | Medium | `overlays/default.nix:15-22` | TASK:COMPLETE |
| T6 | Cleanup | Delete `package-update-analysis.md` | — | repo root | TASK:COMPLETE |

## Execution Details

### T0: sops-nix
```bash
nix flake update sops-nix
```
- Fixes real race condition (`sops-install-secrets.service` now waits for `local-fs.target`)
- sops binary 3.11.0 → 3.12.2, dependency housekeeping
- **Validate**: `nix flake check --no-build`

### T1: zsh-autosuggestions (v0.7.0 → v0.7.1)
- File: `modules/programs/shell/shell.nix:421-422`
- Update `rev` to `v0.7.1`, update `sha256`
- Pure bugfix: `POSTDISPLAY` fix, async fd reset, builtin exec, history-search widgets
- **Get new hash**: `nix-prefetch-fetchFromGitHub --owner zsh-users --repo zsh-autosuggestions --rev v0.7.1` or use `nix build` and let it fail with expected hash
- **Validate**: `nix flake check --no-build`

### T2: marker-pdf (1.10.1 → 1.10.2)
- File: `pkgs/marker-pdf/default.nix:48` — change `version = "1.10.1"` → `"1.10.2"`
- Update hash (likely in same file or fetchPypi call)
- LaTeX detokenization bugfix via surya 0.17.1 bump
- **Validate**: `nix flake check --no-build`, optionally `nix build '.#marker-pdf'`

### T3: zsh-syntax-highlighting (0.7.1 → 0.8.0)
- File: `modules/programs/shell/shell.nix:431-432`
- Update `rev` to `0.8.0`, update `sha256`
- Major: `zle-line-pre-redraw` architecture (active on zsh 5.8.1.1+, NixOS ships 5.9+)
- One minor incompatibility: failed Tab completion no longer removes highlighting
- **Validate**: `nix flake check --no-build`

### T4: opencode (1.3.2 → 1.4.3)
- File: `overlays/default.nix:24-27` — find nixpkgs commit with opencode 1.4.3
- Method: search nixpkgs commit history for opencode version bump, get new tarball URL + sha256
- Breaking (SDK-level only): diff metadata simplified, `UserMessage.variant` path moved — config schema unchanged
- Key new features: TUI plugins, Effect architecture, mouse disable, fast mode variants
- **Nix module opportunities**: expose mouse disable option, fast mode variants
- **Validate**: `nix flake check --no-build`

### T5: claude-code (2.1.87 → 2.1.100)
- File: `overlays/default.nix:15-22` — find nixpkgs commit with claude-code 2.1.100 (or latest)
- **Breaking/behavioral changes to verify**:
  1. Default effort → "high" (increases tokens for API-key/Team/Enterprise users)
  2. Thinking summaries disabled by default
  3. `cleanupPeriodDays: 0` now rejected — check our settings.json files
  4. `/tag` and `/vim` removed
  5. Bash permission hardening — may cause new prompts for previously auto-allowed commands
- **Action items**:
  - Grep for `cleanupPeriodDays` in settings — ensure not set to 0
  - Review hook `if` conditions that match compound Bash commands
  - New statusline `git_worktree` field useful for our multi-worktree setup
- **Validate**: `nix flake check --no-build`, then test `claude --version`

### T6: Cleanup
- Delete `package-update-analysis.md` from repo root
- Commit all changes

## Verification

After all upgrades:
1. `nix flake check --no-build` — must pass
2. `home-manager switch --flake ".#${USER}@$(hostname)" --dry-run` — must succeed
3. Spot-check: `claude --version`, `opencode --version` after activation

## Commit Strategy

- One commit per package upgrade (atomic, easy to bisect/revert)
- Final commit deletes `package-update-analysis.md`
- Branch: current `feat/usb-jetson-pa161878`
