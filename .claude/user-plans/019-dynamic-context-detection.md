# Plan 019: Dynamic Context Detection for AI Assistant Configuration

**Created**: 2026-02-03
**Status**: TASK:PENDING
**Priority**: Medium
**Branch**: TBD

## Problem Statement

AI assistants (Claude Code, OpenCode) receive context from CLAUDE.md and other config files that contain hardcoded values specific to one host or user. This causes the AI to make incorrect assumptions about the environment.

**Root Cause Example**: In this session, Claude assumed the current host was `thinky-nixos` because CLAUDE.md contains:
```bash
home-manager switch --flake .#tim@thinky-nixos  # Test config switch
```

This is the same class of problem as the recently-fixed screenshot path issue (commit 2a28930), where hardcoded `/mnt/c/Users/tblack/...` paths were replaced with dynamic detection.

## Audit Results

### Category 1: Hardcoded Hostnames (HIGH PRIORITY - Causes AI Confusion)

| File | Line | Issue |
|------|------|-------|
| `CLAUDE.md` | 60-61 | Example commands use `tim@thinky-nixos` |
| `FLAKE-PARTS-QUICK-REFERENCE.md` | 105 | Example uses `tim@tblack-t14-nixos` |
| `flake-modules/tests.nix` | 88,309,590,615,640,698 | Tests hardcode `thinky-nixos` |

### Category 2: Hardcoded Home Paths (MEDIUM - Documentation only)

| File | Issue |
|------|-------|
| `CLAUDE.md` | 66-69 | `/home/tim/src/*` paths for local forks |
| `docs/*.md` | Multiple `/home/tim/...` references in docs |
| `secrets/SECRETS-MANAGEMENT.md` | `/home/tim/.ssh/id_ed25519` |

### Category 3: Hardcoded Windows Paths (LOW - Already addressed pattern)

| File | Issue |
|------|-------|
| `modules/nixos/wsl-storage-mount.nix` | `/mnt/c/Users/timbl/...` |
| `home/modules/windows-terminal.nix` | `/mnt/c/Users/blackt1/...` |

## Solution Design

### Pattern from Screenshot Fix (2a28930)

The screenshot fix established the pattern:
1. Replace hardcoded path with dynamic shell command
2. Command uses glob patterns and `fd`/`find` for discovery
3. Single source of truth in `ai-instructions.nix`
4. Propagates to all account CLAUDE.md files via Nix

### Proposed Dynamic Detection Commands

```bash
# Current hostname
hostname

# Current home-manager config name
echo "${USER}@$(hostname)"

# Available homeConfigurations (for examples)
nix eval '.#homeConfigurations' --apply 'builtins.attrNames' --json | jq -r '.[]'
```

### Implementation Tasks

#### Task 1: Add Runtime Context Section to ai-instructions.nix
**Priority**: HIGH
**Effort**: Small

Add new `runtimeContext` attribute that generates dynamic detection instructions:

```nix
runtimeContext = ''
  ## Runtime Environment Detection

  Before making host-specific assumptions, detect the current environment:
  - **Current hostname**: Run `hostname`
  - **Current user**: `$USER` or `whoami`
  - **WSL detection**: `echo "$WSL_DISTRO_NAME"` (empty if not WSL)
  - **Available configs**: `nix eval '.#homeConfigurations' --apply 'builtins.attrNames' --json`

  **NEVER assume the host is a specific value** - always check first.
'';
```

#### Task 2: Update CLAUDE.md Example Commands
**Priority**: HIGH
**Effort**: Small

Replace hardcoded examples with dynamic placeholders:

```markdown
# Common Nix Development Workflow Commands
```bash
nixpkgs-fmt <file>              # Format Nix files
nix flake check                 # Validate entire flake
nix flake update                # Update flake inputs
# Use hostname to get current config:
home-manager switch --flake ".#${USER}@$(hostname)"
```

#### Task 3: Parameterize Test Configurations
**Priority**: MEDIUM
**Effort**: Medium

`flake-modules/tests.nix` hardcodes `thinky-nixos` for test configs. Options:
1. Use first available homeConfiguration
2. Create a dedicated test configuration
3. Accept config name as parameter

#### Task 4: Document Dynamic Detection Pattern
**Priority**: LOW
**Effort**: Small

Add to module README explaining the pattern for future context additions.

## Definition of Done

- [ ] `ai-instructions.nix` includes runtime detection instructions
- [ ] CLAUDE.md uses dynamic examples or explicit "replace with your hostname" notes
- [ ] No AI confusion about current host in testing
- [ ] Pattern documented for future additions

## Related

- Commit 2a28930: Screenshot detection fix (established pattern)
- Plan 018: nixcfg modularization (will benefit from this)

## Notes

This is a "developer experience" fix - the code works correctly, but the AI assistants make incorrect assumptions due to stale context. The fix improves AI reliability across different hosts.
