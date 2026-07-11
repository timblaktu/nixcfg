# Plan 040: Claude Code Permissions Optimization

> **SUPERSEDED (2026-07-11).** The "just upgrade CC past v2.1.126" resolution below
> was correct for the *protected-directory* bug of that era, but it was NOT the whole
> story. `.claude/` writes (esp. `.claude/user-plans/`) kept prompting long after CC
> reached v2.1.191. Real root cause: the later-added allow rules `Write(/.claude/**)` /
> `Edit(/.claude/**)` use a SINGLE leading slash, which in CC's permission-path grammar
> anchors to the **settings file's own directory** — and these rules render into the
> USER-level `~/.claude-<account>/settings.json`, so they resolved to
> `~/.claude-<account>/.claude/**` and never matched project writes (a silent no-op).
> Fixed by switching to a `//` (filesystem-root) anchor: `Write(//**/.claude/**)` /
> `Edit(//**/.claude/**)` in `modules/programs/claude-code/claude-code.nix`
> (branch `claude-code-permissions-path-fix`, commit `b8ad0a4`). See the
> `cc-permission-path-anchor` auto-memory for the path-grammar reference.

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
| T2 | Research opencode equivalent permission model | TASK:SKIPPED | Not needed - root cause found |
| T3 | Test permission boundaries empirically | TASK:COMPLETE | Confirmed: known CC bug, fixed in v2.1.126. Current v2.1.97 is affected. |
| T4 | Identify config changes to eliminate prompts | TASK:COMPLETE | Config is already correct per docs. Likely a bug, not a misconfiguration. |
| T5 | File bug report if empirical test confirms | TASK:SKIPPED | Already reported upstream: anthropics/claude-code#38806, #37157, #39523 |

## Resolution (2026-05-31)

**Root cause**: Known CC bug. `.claude/` is a protected directory, and pre-v2.1.126 versions
prompt for writes to non-exempt subdirectories even in `bypassPermissions` mode. Fixed in
v2.1.126 where `bypassPermissions` fully disables protected path checks.

**Exempt subdirectories** (never prompt in any version): `.claude/commands`, `.claude/agents`,
`.claude/skills`, `.claude/worktrees`.

**Affected subdirectories** (prompt in <v2.1.126): `.claude/session-log-*`, `.claude/user-plans/`,
`.claude/settings.json`, and any other non-exempt paths.

**Upstream issues**: anthropics/claude-code#38806, #37157, #37029, #39523

**Action**: Upgrade CC past v2.1.126. Current nixpkgs pin is v2.1.39; running version is v2.1.97
(likely npm global install). Either update the npm install or pin a newer version via overlay.

**Status**: PLAN COMPLETE - no config changes needed, just a version upgrade.
