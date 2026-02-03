# Plan 017: Git Safety Hooks for Claude Code

**Status**: PENDING
**Branch**: `opencode`
**Created**: 2026-02-01
**Last Updated**: 2026-02-01

---

## Overview

Implement Claude Code hooks to enforce git safety policies, starting with blocking `--no-verify` flags that bypass git hooks.

**Motivation**: Claude Code's system prompt already instructs it to never skip hooks, but a PreToolUse hook provides defense-in-depth by blocking such commands at the tool level.

---

## Progress Tracking

| Task | Name | Status | Date |
|------|------|--------|------|
| R1 | Research Claude Code hook documentation | TASK:PENDING | |
| I1 | Implement no-verify blocking hook script | TASK:PENDING | |
| I2 | Configure hook in settings.json | TASK:PENDING | |
| I3 | Integrate with home-manager module | TASK:PENDING | |
| T1 | Test hook blocking behavior | TASK:PENDING | |
| D1 | Document installation for other repos | TASK:PENDING | |

---

## Task R1: Research Claude Code Hook Documentation

**Status**: TASK:PENDING

**Purpose**: Understand Claude Code hook system before implementation.

**Research Questions**:
1. How are hooks configured in settings.json?
2. What environment variables are available to PreToolUse hooks?
3. What exit codes control allow/block behavior?
4. How does hook output appear to users?
5. Can hooks access the full command being executed?

**Deliverables**:
- [ ] Document hook configuration format
- [ ] List available environment variables
- [ ] Document exit code semantics
- [ ] Note any limitations or edge cases

---

## Task I1: Implement No-Verify Blocking Hook Script

**Status**: TASK:PENDING

**Purpose**: Create shell script that blocks git commands with --no-verify.

**Requirements**:
1. Intercept Bash tool calls only
2. Detect `git commit` or `git push` with `--no-verify` flag
3. Handle variations: `--no-verify`, `-n` (if applicable)
4. Handle command anywhere in pipeline (e.g., `echo foo && git commit --no-verify`)
5. Work in both bash and zsh
6. Exit non-zero to block, zero to allow
7. Provide clear error message when blocking

**Script Location**: `claude-runtime/hooks/block-no-verify.sh`

**Pseudo-implementation**:
```bash
#!/usr/bin/env bash
# Block git commands that skip hooks with --no-verify

# Get command from Claude Code environment variable (TBD from R1)
command="$CLAUDE_BASH_COMMAND"  # Placeholder - actual var from research

# Check for git commit/push with --no-verify
if echo "$command" | grep -qE 'git\s+(commit|push).*--no-verify'; then
  echo "BLOCKED: --no-verify is not allowed. Git hooks must run." >&2
  exit 1
fi

# Also check for -n flag on git commit (short form)
if echo "$command" | grep -qE 'git\s+commit.*\s-n(\s|$)'; then
  echo "BLOCKED: -n (--no-verify) is not allowed. Git hooks must run." >&2
  exit 1
fi

exit 0
```

**Definition of Done**:
- [ ] Script handles all --no-verify variations
- [ ] Script is shell-agnostic (bash/zsh compatible)
- [ ] Script provides actionable error message
- [ ] Script passes shellcheck

---

## Task I2: Configure Hook in settings.json

**Status**: TASK:PENDING

**Purpose**: Enable the hook in Claude Code configuration.

**Expected Configuration** (format TBD from R1):
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "~/src/nixcfg/claude-runtime/hooks/block-no-verify.sh"
      }
    ]
  }
}
```

**Considerations**:
- Hook should only trigger for Bash tool, not Read/Write/etc.
- Path should be absolute or use ~ expansion
- May need to pass command as argument or via env var

**Definition of Done**:
- [ ] Hook registered in settings.json
- [ ] Hook triggers only for Bash tool calls
- [ ] Configuration works with current claude-code module

---

## Task I3: Integrate with Home-Manager Module

**Status**: TASK:PENDING

**Purpose**: Add hook to Nix-managed Claude Code configuration.

**Implementation Location**: `home/modules/claude-code/` or `home/modules/base.nix`

**Options**:
1. Add to existing `hooks` option in claude-code module
2. Create new `gitSafetyHooks` option with enable flag
3. Add hook script to home.file and reference in settings

**Considerations**:
- Hook script needs to be in a path accessible at runtime
- Should work with multi-account setup (max, pro, work)
- May want enable/disable toggle per account

**Definition of Done**:
- [ ] Hook script deployed via home-manager
- [ ] Hook configured in generated settings.json
- [ ] Works for all enabled accounts
- [ ] `nix flake check` passes

---

## Task T1: Test Hook Blocking Behavior

**Status**: TASK:PENDING

**Purpose**: Verify hook blocks intended commands and allows safe ones.

**Test Cases**:

| Command | Expected | Reason |
|---------|----------|--------|
| `git commit -m "test"` | ALLOW | No --no-verify |
| `git commit --no-verify -m "test"` | BLOCK | Has --no-verify |
| `git commit -m "test" --no-verify` | BLOCK | Flag at end |
| `git push --no-verify` | BLOCK | Push with flag |
| `git push origin main` | ALLOW | Normal push |
| `echo foo && git commit --no-verify -m "x"` | BLOCK | In pipeline |
| `git status` | ALLOW | Not commit/push |
| `git commit -n -m "test"` | BLOCK | Short form |
| `git commit -am "test"` | ALLOW | -a is not -n |

**Definition of Done**:
- [ ] All test cases pass
- [ ] No false positives (blocking safe commands)
- [ ] No false negatives (allowing unsafe commands)
- [ ] Error message is visible and clear

---

## Task D1: Document Installation for Other Repos

**Status**: TASK:PENDING

**Purpose**: Enable hook use in repos that don't use nixcfg home-manager.

**Deliverables**:
1. Standalone hook script (no Nix dependencies)
2. Manual settings.json configuration instructions
3. Example for adding to any project's `.claude/settings.json`

**Documentation Location**: `docs/claude-code-git-safety-hooks.md` or README section

**Definition of Done**:
- [ ] Clear installation instructions
- [ ] Works without home-manager
- [ ] Can be added to any repo's .claude/settings.json

---

## Technical Notes

### Claude Code Hook System (To be filled in from R1)

- **Configuration location**: `settings.json` under `hooks` key
- **Hook types**: PreToolUse, PostToolUse, Notification, Stop
- **Environment variables**: TBD
- **Exit codes**: TBD (likely 0=allow, non-zero=block)

### Related Files

- `home/modules/claude-code/default.nix` - Main module
- `home/modules/claude-code/lib.nix` - Helper functions
- `home/modules/base.nix` - Account configuration
- `claude-runtime/.claude-*/settings.json` - Generated configs

### Git Flags Reference

| Flag | Command | Purpose |
|------|---------|---------|
| `--no-verify` | commit, push | Skip pre-commit/pre-push hooks |
| `-n` | commit | Short form of --no-verify |
| `--no-gpg-sign` | commit | Skip GPG signing (separate concern) |

---

## Definition of Done (Overall)

- [ ] Hook script implemented and tested
- [ ] Integrated with home-manager claude-code module
- [ ] Works across all accounts (max, pro, work)
- [ ] Documented for standalone use
- [ ] `nix flake check` passes
- [ ] Tested in real Claude Code session
