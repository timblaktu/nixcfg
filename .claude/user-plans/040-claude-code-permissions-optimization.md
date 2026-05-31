# Plan 040: Claude Code Permissions Optimization

## Problem Statement

Even with `defaultMode: "bypassPermissions"` in `.claude-max/.claude.json`, Claude Code still prompts for user approval on certain operations (e.g., writing to `.claude/` directories in project repos). This interrupts autonomous workflows and requires the user to be present for actions that should be auto-approved.

## Current State

**Global config** (`nixcfg/claude-runtime/.claude-max/.claude.json`):
- `defaultMode`: `bypassPermissions`
- `additionalDirectories`: `["/home/tim/src/nixcfg"]`
- `allow`: 30+ tools explicitly listed
- `deny`: `["Search", "Find", "Bash(rm -rf /*)"]`
- `ask`: `[]` (empty)

**Project config** (`n3x-foo/.claude/settings.json`): hooks only, no permissions override

**Observed prompts despite bypassPermissions:**
- Writing to `.claude/session-log-*` files in project directory
- Writing to `.claude/user-plans/` in project directory
- Possibly other `.claude/` subdirectory writes

## Research Tasks

| ID | Task | Status | Notes |
|----|------|--------|-------|
| T1 | Research Claude Code permission model documentation | TASK:COMPLETE | Docs explicitly state bypassPermissions covers .claude/ writes. Should NOT prompt. |
| T2 | Research opencode equivalent permission model | TASK:PENDING | Does opencode have the same restrictions? |
| T3 | Test permission boundaries empirically | TASK:PENDING | Run `/permissions` in session to verify mode is active. If active + prompts = bug. |
| T4 | Identify config changes to eliminate prompts | TASK:COMPLETE | Config is already correct per docs. Likely a bug, not a misconfiguration. |
| T5 | File bug report if empirical test confirms | TASK:PENDING | Use `/feedback` if `/permissions` shows bypassPermissions active but still prompts |

## Key Questions

1. Does `bypassPermissions` exempt `.claude/` directory writes, or is that a hard-coded safety boundary?
2. Would adding the project directory explicitly to `additionalDirectories` help? (It should already be allowed as cwd)
3. Is there a per-project `settings.json` override that can grant broader permissions?
4. Does the `allow` list need specific entries for file operations in `.claude/` paths?
5. Is there a difference between how Claude Code handles writes to gitignored vs tracked paths?

## Definition of Done

- All unnecessary permission prompts eliminated for the .claude-max profile
- Session log writes, plan file writes, and memory writes all auto-approved
- Document findings for future reference
- No security regressions (sensitive file patterns still blocked by PreToolUse hook)
