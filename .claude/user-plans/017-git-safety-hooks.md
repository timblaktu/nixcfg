# Plan 017: Git Safety Hooks for Claude Code

**Status**: PENDING
**Branch**: create from `main` (e.g., `feature/git-safety-hooks`)
**Created**: 2026-02-01
**Last Updated**: 2026-02-18 (rewritten based on current repo state and hook API research)

---

## Overview

Implement a Claude Code PreToolUse hook that blocks `git commit` and `git push` commands
containing `--no-verify` (or `-n` short form) flags. This provides defense-in-depth beyond
the system prompt instruction to never skip hooks.

**Motivation**: Claude's system prompt says "NEVER skip hooks" but a PreToolUse hook enforces
this at the tool level — the command is blocked before it ever executes.

---

## Progress Tracking

| Task | Name | Status | Date |
|------|------|--------|------|
| R1 | Research Claude Code hook API | TASK:COMPLETE | 2026-02-18 |
| I1 | Add gitSafety hook category to hooks.nix | TASK:PENDING | |
| T1 | Test hook blocking behavior | TASK:PENDING | |
| D1 | Document standalone usage for non-Nix repos | TASK:PENDING | |

---

## Task R1: Research Claude Code Hook API

**Status**: TASK:COMPLETE (2026-02-18)

**Findings**:

### Hook Input Format
PreToolUse hooks receive **JSON on stdin** (not environment variables). For Bash tool calls:
```json
{
  "session_id": "abc123",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit --no-verify -m 'test'"
  }
}
```

The command string is at `tool_input.command`. Requires `jq` to parse.

### Exit Code Semantics
| Exit Code | Behavior |
|-----------|----------|
| `0` | Allow (optionally output JSON for structured decisions) |
| `2` | **Block** — tool call prevented, stderr shown to Claude |
| Other | Non-blocking error — stderr in verbose mode, execution continues |

### Structured JSON Output (alternative to exit code 2)
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Explanation shown to Claude"
  }
}
```

### Environment Variables
- `$CLAUDE_PROJECT_DIR` — project root
- No env var for the command itself — must parse stdin JSON

### Existing Hook Architecture (hooks.nix)

The module at `modules/programs/claude-code/_hm/hooks.nix` already has:
- **Categorized hooks**: formatting, linting, security, git, testing, logging, notifications, development
- **`mkHook` helper**: Creates properly-structured hook entries with matcher, command, timeout, continueOnError
- **`security` category**: Currently blocks Read/Edit/Write access to sensitive file patterns (`.env`, `.secrets`, `id_rsa`, `.key`)
- **`custom` hooks option**: Escape hatch for arbitrary PreToolUse/PostToolUse/SessionStart/Stop hooks
- **Automatic serialization**: `_internal.hooks` → JSON → settings.json via `claude-code.nix` activation script

### Important Discovery: Existing Hook API Mismatch

The existing hooks in `hooks.nix` use `$1` to access file paths (e.g., `file_path="$1"`),
but the actual Claude Code API delivers input as **JSON on stdin**. This suggests either:
1. The module wraps commands to extract `$1` from JSON (needs verification), or
2. The existing hooks have never been tested end-to-end and may not work correctly

**Action**: Task I1 should use the documented stdin JSON approach. If it turns out the module
does wrapping, we can simplify. Don't assume `$1` works without verification.

---

## Task I1: Add gitSafety Hook Category to hooks.nix

**Status**: TASK:PENDING

**Purpose**: Add a `gitSafety` category to the existing hook system in `hooks.nix` that blocks
`--no-verify` and related flags on git commit/push commands.

### Implementation Location

**File**: `modules/programs/claude-code/_hm/hooks.nix`

### What to Add

1. **New option**: `hooks.gitSafety.enable` (default: `true`)
   - Under `options.programs.claude-code.hooks`
   - Similar pattern to existing `security` category

2. **New PreToolUse hook entry** in the `config.programs.claude-code._internal.hooks` merge:
   - Matcher: `Bash` (only intercepts Bash tool calls)
   - Parses stdin JSON with `jq` to extract `tool_input.command`
   - Pattern-matches for `--no-verify` / `-n` flags on git commit/push
   - Exits `2` with descriptive stderr message when blocked
   - Exits `0` to allow all other commands

3. **`jq` dependency**: Add `pkgs.jq` to the hook command (Nix store path, not bare `jq`)

### Hook Command Logic

```bash
# Read command from stdin JSON
COMMAND=$(${pkgs.jq}/bin/jq -r '.tool_input.command // empty' < /dev/stdin)
[ -z "$COMMAND" ] && exit 0

# Block git commit/push with --no-verify
if echo "$COMMAND" | ${pkgs.gnugrep}/bin/grep -qE 'git\s+(commit|push)\b.*--no-verify'; then
  echo "BLOCKED: --no-verify is not allowed. Git hooks must run." >&2
  exit 2
fi

# Block short form -n on git commit (not git push, where -n means --dry-run)
if echo "$COMMAND" | ${pkgs.gnugrep}/bin/grep -qE 'git\s+commit\b.*\s-[a-zA-Z]*n'; then
  echo "BLOCKED: -n (--no-verify) is not allowed on git commit. Git hooks must run." >&2
  exit 2
fi

# Block --no-gpg-sign as well (separate safety concern, same defense-in-depth rationale)
# NOTE: Uncomment if desired — currently out of scope per original plan
# if echo "$COMMAND" | grep -qE 'git\s+(commit|tag)\b.*--no-gpg-sign'; then
#   echo "BLOCKED: --no-gpg-sign is not allowed." >&2
#   exit 2
# fi

exit 0
```

### Edge Case: `-n` Ambiguity

- `git commit -n` = `--no-verify` (BLOCK)
- `git commit -an` = `-a` + `-n` = `--all --no-verify` (BLOCK)
- `git commit -am "msg"` = `-a` + `-m` (ALLOW — no `-n`)
- `git push -n` = `--dry-run` (ALLOW — different meaning on push)
- `git clean -n` = `--dry-run` (ALLOW — not commit/push)

The regex `git\s+commit\b.*\s-[a-zA-Z]*n` handles combined short flags like `-an`.
It only matches `git commit`, not `git push` or other subcommands.

### Definition of Done
- [ ] `hooks.gitSafety.enable` option added (default: true)
- [ ] PreToolUse hook reads command from stdin JSON via jq
- [ ] Blocks `--no-verify` on both `git commit` and `git push`
- [ ] Blocks `-n` (and combined forms like `-an`) on `git commit` only
- [ ] Does NOT false-positive on `git push -n` (dry-run), `git commit -am`, etc.
- [ ] Uses Nix store paths for `jq` and `grep` (no bare command assumptions)
- [ ] `nix flake check --no-build` passes
- [ ] Hooks appear in generated settings.json for all enabled accounts

---

## Task T1: Test Hook Blocking Behavior

**Status**: TASK:PENDING

**Purpose**: Verify the hook in a real Claude Code session.

### Test Matrix

| Command | Expected | Reason |
|---------|----------|--------|
| `git commit -m "test"` | ALLOW | No --no-verify |
| `git commit --no-verify -m "test"` | BLOCK | Has --no-verify |
| `git commit -m "test" --no-verify` | BLOCK | Flag at end |
| `git push --no-verify` | BLOCK | Push with --no-verify |
| `git push origin main` | ALLOW | Normal push |
| `echo foo && git commit --no-verify -m "x"` | BLOCK | In compound command |
| `git status` | ALLOW | Not commit/push |
| `git commit -n -m "test"` | BLOCK | Short form |
| `git commit -an -m "test"` | BLOCK | Combined short flags |
| `git commit -am "test"` | ALLOW | -a -m, no -n |
| `git push -n` | ALLOW | -n means --dry-run for push |
| `git clean -n` | ALLOW | Not commit/push |

### Test Method
1. Build and activate home-manager config with hook enabled
2. Start a Claude Code session in a test repo
3. Ask Claude to run each command from the matrix
4. Verify BLOCK commands show error message and don't execute
5. Verify ALLOW commands execute normally

### Definition of Done
- [ ] All 12 test cases verified
- [ ] No false positives (safe commands blocked)
- [ ] No false negatives (unsafe commands allowed)
- [ ] Error message is clear and visible in Claude output
- [ ] Hook doesn't add noticeable latency to normal commands

---

## Task D1: Document Standalone Usage for Non-Nix Repos

**Status**: TASK:PENDING

**Purpose**: Provide a self-contained hook script and settings.json snippet for repos that
don't use nixcfg's home-manager module.

### Deliverables

1. **Standalone script**: A portable version of the hook that uses bare `jq` (not Nix store path)
   - Location: Include as a code block in documentation (not a separate file)

2. **settings.json snippet**: Show how to add to `.claude/settings.json` in any repo:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [{
             "type": "command",
             "command": "/path/to/block-no-verify.sh"
           }]
         }
       ]
     }
   }
   ```

3. **Add to existing docs**: Append a section to an existing documentation file
   (e.g., within claude-code module README or CLAUDE.md guidance), NOT a new standalone doc file

### Definition of Done
- [ ] Standalone script works without Nix (requires only bash + jq)
- [ ] settings.json snippet is correct and tested
- [ ] Documentation added to existing file
- [ ] Instructions cover both project-level and user-level installation

---

## Technical Reference

### Current File Locations (post-dendritic migration)

| Purpose | Path |
|---------|------|
| Main module | `modules/programs/claude-code/claude-code.nix` |
| Hook definitions | `modules/programs/claude-code/_hm/hooks.nix` |
| Hook helper (mkHook) | `modules/programs/claude-code/_hm/hooks.nix:8-27` |
| Wrapper scripts | `modules/programs/claude-code/_hm/lib.nix` |
| Account presets | `modules/flake-parts/lib.nix` |
| Runtime configs | `claude-runtime/.claude-{max,pro,work}/settings.json` |

### Git Flags Reference

| Flag | Command | Purpose | Action |
|------|---------|---------|--------|
| `--no-verify` | commit, push | Skip pre-commit/pre-push hooks | BLOCK |
| `-n` | commit | Short form of --no-verify | BLOCK |
| `-n` | push | Short form of --dry-run | ALLOW |
| `--no-gpg-sign` | commit, tag | Skip GPG signing | Out of scope |

### mkHook Helper Signature

```nix
mkHook = {
  matcher,         # String: tool name regex (e.g., "Bash")
  type ? "command", # "command" or "script"
  command ? null,   # Inline shell command string
  script ? null,    # Path to script file
  env ? {},         # Extra environment variables
  timeout ? 60,     # Seconds before hook times out
  continueOnError ? true  # false = exit 2 blocks the tool call
}: { ... };
```

For blocking hooks, set `continueOnError = false`.

---

## Definition of Done (Overall)

- [ ] `hooks.gitSafety` category added to hooks.nix with enable toggle
- [ ] Hook blocks --no-verify on git commit/push via stdin JSON parsing
- [ ] Works across all accounts (max, pro, work) automatically
- [ ] `nix flake check --no-build` passes
- [ ] Tested in real Claude Code session (all 12 test cases)
- [ ] Standalone usage documented for non-Nix repos
