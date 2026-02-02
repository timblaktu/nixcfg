# Plan 014: Per-Worktree Claude Config Isolation

**Status**: DESIGN DISCUSSION (Iterative)
**Branch**: `opencode`
**Created**: 2026-01-28
**Last Updated**: 2026-01-31

---

## Implementation Tasks

| Task | Status | Description |
|------|--------|-------------|
| 0. Design discussion | **PENDING** | Clarify memory hierarchy, worktree orthogonality, skills path, open questions |
| 1. Add detection function | PENDING | `detect_worktree_context()` in lib.nix |
| 2. Add MCP merge function | PENDING | `merge_mcp_configs()` helper with atomic writes |
| 3. Update wrapper logic | PENDING | Conditional worktree vs account config |
| 4. Update PID file naming | PENDING | Include worktree hash |
| 5. Add gitignore patterns | PENDING | Ignore `**/claude-runtime/` in git repos |
| 6. Test scenarios | PENDING | Main, linked, non-git, bare, submodule, coalescence |
| 7. Documentation | PENDING | Update README-CLAUDE-CODE.md |

---

## Task 0: Design Discussion Topics

**Process**: Iterative rapid sessions until user explicitly approves. Update this section with discussion outcomes after each session.

### Topic A: Memory Hierarchy Clarity

The plan conflates several orthogonal concepts that need explicit separation:

**User-Global Memory** (applies to ALL projects):
- Location: `~/.claude/CLAUDE.md` or `~/.config/claude-code/CLAUDE.md`
- Owner: User
- Scope: All Claude sessions regardless of project
- Examples: Personal preferences, universal workflows, cross-project learnings

**Project Memory** (applies to ONE project):
- Location: `$PROJECT_ROOT/CLAUDE.md` or `$PROJECT_ROOT/.claude/CLAUDE.md`
- Owner: Project (checked into git)
- Scope: All sessions within this project
- Examples: Project conventions, architecture notes, team practices

**Account Config** (Claude Code settings per account):
- Location: `~/.claude-max/`, `~/.claude-pro/`, etc.
- Owner: home-manager (Nix-managed)
- Scope: All sessions using this account
- Examples: API keys, MCP servers, permissions, hooks

**Session Runtime** (ephemeral state):
- Location: Varies (account dir, worktree dir, or /tmp)
- Owner: Claude Code process
- Scope: Single session
- Examples: `.claude.json`, conversation history, logs

**Key Insight**: Git worktrees affect WHERE session runtime lives, but are completely orthogonal to:
- User-global vs project memory (both still apply regardless of worktree)
- Account config (same account settings across all worktrees)

**Discussion Questions**:
1. Is this 4-layer hierarchy accurate and complete?
2. Does "project memory" belong at the git repo level or worktree level?
3. Should user-global CLAUDE.md be part of this plan's scope, or separate concern?

### Topic B: Worktree Isolation Scope

Current design isolates **session runtime only** (`.claude.json`, logs) per worktree.

Does NOT isolate:
- Account config (settings.json, hooks) - same across worktrees
- Project CLAUDE.md - same for all worktrees of same repo
- User-global CLAUDE.md - always same

**Discussion Questions**:
1. Is runtime-only isolation the right scope?
2. Should project CLAUDE.md support worktree-specific overrides?
3. What happens when worktree is on a different branch with different `.claude/` contents?

### Topic C: Skills Path Handling

Current claude-code module places skills in `.claude/skills/` within CLAUDE_CONFIG_DIR.

**Unresolved**:
- Does Claude Code load skills from `$CLAUDE_CONFIG_DIR/skills/`?
- Or does it use a separate `CLAUDE_SKILLS_DIR` or hardcoded path?
- If skills are in CLAUDE_CONFIG_DIR, the symlink chain applies to them too

**Discussion Questions**:
1. Need to verify actual Claude Code skill loading behavior
2. Should skills be account-level (Nix-managed) or project-level (git-managed)?
3. Can skills be merged like MCP configs?

### Topic D: Open Questions (from initial review)

**D1: Does Claude Code ever write to settings.json?**
- Current assumption: No, read-only config
- If yes: Need copy-on-write strategy
- **Initial assessment**: Likely safe assumption based on observed behavior

**D2: Should worktree runtime persist across reboots?**
- Current design: Yes ($GIT_DIR storage)
- Alternative: /tmp for ephemeral
- **Initial assessment**: Persistence is correct - session context should survive reboots

**D3: Per-project settings.json override?**
- Current design: MCP-only merge
- Could extend to settings merge
- **Initial assessment**: Defer - start with MCP, extend later if needed

**D4: Coalescence interaction?**
- V2.0 coalescence operates on `$CLAUDE_CONFIG_DIR/.claude.json`
- With worktree isolation, this becomes worktree-specific
- **Initial assessment**: Should work unchanged, needs explicit test case

**D5: Race condition during MCP merge?**
- Two simultaneous wrapper launches could conflict
- **Solution**: Atomic write with temp file + mv

### Topic E: Additional Refinements Identified

1. **Atomic MCP merge**: Use temp file + mv to prevent race conditions
2. **EROFS safety check**: Log warning if symlink resolution fails on first launch
3. **Coalescence test case**: Add explicit test for worktree + coalescence interaction

---

## Discussion Log

*(Record outcomes of each design discussion session here)*

### Session 1 (2026-01-31): Initial Review
- **Attendees**: Claude (reviewer), User
- **Topics covered**: Initial plan review, identified need for memory hierarchy clarity
- **Outcome**: Plan updated with Task 0 design discussion as first priority
- **Next session**: Address Topics A-E iteratively

---

## Problem Statement

When working in multiple git worktrees with the same Claude account (e.g., `claudemax`), all worktrees share:
- Same `CLAUDE_CONFIG_DIR` (e.g., `~/.claude-max/`)
- Same `.claude.json` runtime state (conversation history, project context)
- Same MCP server configuration

This causes conflicts when:
- Different worktrees have different project-specific MCP servers
- Session state from one worktree pollutes another
- Multiple Claude instances run concurrently in different worktrees

## Design Goals

1. **Zero user intervention** - Automatic detection and isolation
2. **Nix store compatibility** - Respect immutable derivations
3. **Seamless UX** - Same wrapper commands work everywhere
4. **Clean isolation** - Each worktree has its own runtime state
5. **Automatic cleanup** - `git worktree remove` cleans up config
6. **Backward compatible** - Non-git contexts work as before

---

## Architecture Overview

### Three-Layer Config Hierarchy

```
Layer 1: Nix Store (IMMUTABLE)
    │
    │ symlinks created by home-manager activation
    ▼
Layer 2: Account Config (SEMI-MUTABLE)
    │
    │ symlinks created by wrapper script at launch
    ▼
Layer 3: Worktree Runtime (FULLY MUTABLE)
    │
    │ CLAUDE_CONFIG_DIR points here
    ▼
    Claude Code Process
```

---

## Detailed Architecture

### Layer 1: Nix Store (Immutable)

**Location**: `/nix/store/<hash>-home-manager-files/.claude-max/`

**Contents**:
```
/nix/store/<hash>-home-manager-files/
└── .claude-max/
    ├── settings.json     # Generated from programs.claude-code.accounts
    ├── .mcp.json         # Generated from mcpServers option
    └── commands/         # Generated from commands option + git-commands
        ├── git/
        │   ├── worktree-create.md
        │   ├── worktree-status.md
        │   ├── worktree-sync.md
        │   └── worktree-integrate.md
        └── ...
```

**Owner**: Nix/home-manager
**Mutability**: IMMUTABLE (read-only filesystem)
**Update Trigger**: `home-manager switch`

**Source**: Defined in `home/modules/claude-code/*.nix`:
```nix
programs.claude-code.accounts.max = {
  enable = true;
  settings = {
    permissions = { ... };
    hooks = { ... };
    statusLine = "compact";
  };
  mcpServers = { ... };
};
```

---

### Layer 2: Account Config (Semi-Mutable)

**Location**: `~/.claude-max/`

**Contents**:
```
~/.claude-max/
├── settings.json ──────→ /nix/store/<hash>/.claude-max/settings.json  [SYMLINK]
├── .mcp.json ──────────→ /nix/store/<hash>/.claude-max/.mcp.json      [SYMLINK]
├── commands/ ──────────→ /nix/store/<hash>/.claude-max/commands/      [SYMLINK]
└── .claude.json         [MUTABLE FILE - used when NOT in git worktree]
```

**Owner**: home-manager activation (symlinks), Claude Code (`.claude.json`)
**Mutability**: Directory is writable; symlinked files point to immutable Nix store
**Update Trigger**: `home-manager switch` updates symlinks

**Key Insight**: The directory `~/.claude-max/` is NOT a symlink - it's a real writable directory. home-manager places symlinks INTO it, allowing Claude to write `.claude.json` alongside the read-only symlinked config files.

---

### Layer 3: Worktree Runtime (Fully Mutable)

**Location**: `$GIT_DIR/claude-runtime/`
- Main repo: `.git/claude-runtime/`
- Linked worktree: `.git/worktrees/<name>/claude-runtime/`

**Contents**:
```
$GIT_DIR/claude-runtime/
├── settings.json ──────→ ~/.claude-max/settings.json    [SYMLINK - 2-hop chain]
├── commands ───────────→ ~/.claude-max/commands         [SYMLINK - 2-hop chain]
├── .mcp.json            [MERGED FILE - account + project MCP configs]
├── .claude.json         [MUTABLE - this worktree's session state]
└── logs/                [MUTABLE - this worktree's logs]
```

**Owner**: Wrapper script (symlinks, merged MCP), Claude Code (runtime files)
**Mutability**: Fully writable
**Update Trigger**: Wrapper launch
**Cleanup**: Automatic when `git worktree remove` is run

---

## Symlink Chain Detail

For immutable files (settings.json, commands/), a 2-hop symlink chain provides indirection:

```
$GIT_DIR/claude-runtime/settings.json
    │
    │ symlink created by wrapper script
    ▼
~/.claude-max/settings.json
    │
    │ symlink created by home-manager
    ▼
/nix/store/<hash>/.claude-max/settings.json
```

**Why 2-hop instead of direct?**

When `home-manager switch` runs with a new configuration:
1. New Nix store derivation created: `/nix/store/<NEW-hash>/...`
2. home-manager updates `~/.claude-max/settings.json` symlink to point to new hash
3. Worktree symlinks (`$GIT_DIR/claude-runtime/settings.json`) continue to work
   because they point to the account directory, not directly to Nix store

If we used direct symlinks to Nix store:
- Every `home-manager switch` would invalidate all worktree symlinks
- Wrapper would need to detect and fix broken symlinks on every launch

---

## File Ownership Matrix

| File | Created By | Location | Mutability | Update Trigger |
|------|------------|----------|------------|----------------|
| `settings.json` | home-manager | Nix store | Immutable | `home-manager switch` |
| `.mcp.json` (account) | home-manager | Nix store | Immutable | `home-manager switch` |
| `.mcp.json` (worktree) | wrapper script | `$GIT_DIR/claude-runtime/` | Regenerated | Wrapper launch |
| `commands/*.md` | home-manager | Nix store | Immutable | `home-manager switch` |
| `.claude.json` | Claude Code | Runtime dir | Mutable | Claude session |
| `logs/*` | Claude Code | Runtime dir | Mutable | Claude session |
| Wrapper script | home-manager | Nix store | Immutable | `home-manager switch` |

---

## Symlink Ownership Matrix

| Symlink Location | Created By | Points To | Survives `home-manager switch`? |
|------------------|------------|-----------|--------------------------------|
| `~/.claude-max/settings.json` | home-manager | Nix store derivation | Replaced with new target |
| `~/.claude-max/.mcp.json` | home-manager | Nix store derivation | Replaced with new target |
| `~/.claude-max/commands` | home-manager | Nix store derivation | Replaced with new target |
| `$GIT_DIR/.../settings.json` | wrapper | `~/.claude-max/settings.json` | YES (indirection) |
| `$GIT_DIR/.../commands` | wrapper | `~/.claude-max/commands` | YES (indirection) |

---

## Complete Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           NIX STORE (IMMUTABLE)                             │
│  /nix/store/<hash>-home-manager-files/                                      │
│  └── .claude-max/                                                           │
│      ├── settings.json     <- Generated from programs.claude-code.accounts  │
│      ├── .mcp.json         <- Generated from mcpServers option              │
│      └── commands/         <- Generated from commands + git-commands        │
│          ├── git/worktree-create.md                                         │
│          ├── git/worktree-status.md                                         │
│          └── ...                                                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │ symlinks (created by home-manager activation)
                                    │
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ACCOUNT CONFIG DIR (SEMI-MUTABLE)                        │
│  ~/.claude-max/                                                             │
│  ├── settings.json ──────→ /nix/store/<hash>/.claude-max/settings.json     │
│  ├── .mcp.json ──────────→ /nix/store/<hash>/.claude-max/.mcp.json         │
│  ├── commands/ ──────────→ /nix/store/<hash>/.claude-max/commands/         │
│  └── .claude.json          [MUTABLE - used when NOT in git worktree]       │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │ symlinks (created by wrapper at launch)
                                    │
┌─────────────────────────────────────────────────────────────────────────────┐
│                    WORKTREE RUNTIME DIR (MUTABLE)                           │
│  $GIT_DIR/claude-runtime/   [e.g., .git/worktrees/foo/claude-runtime/]     │
│  ├── settings.json ──────→ ~/.claude-max/settings.json ──→ Nix store       │
│  ├── commands ───────────→ ~/.claude-max/commands ──────→ Nix store        │
│  ├── .mcp.json             [MERGED FILE - account + project MCP configs]   │
│  ├── .claude.json          [MUTABLE - this worktree's session state]       │
│  └── logs/                 [MUTABLE - this worktree's logs]                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │ CLAUDE_CONFIG_DIR points here
                                    │
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CLAUDE CODE PROCESS                                 │
│  Reads:  settings.json (via 2-hop symlink chain -> Nix store)              │
│  Reads:  .mcp.json (merged file in worktree runtime)                       │
│  Reads:  commands/*.md (via 2-hop symlink chain -> Nix store)              │
│  Writes: .claude.json (direct to worktree runtime)                         │
│  Writes: logs/* (direct to worktree runtime)                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Process View: What Claude Code Sees

From Claude Code's perspective, `CLAUDE_CONFIG_DIR` is a directory with mixed permissions:

| File/Dir | Permission | Claude Action | Result |
|----------|------------|---------------|--------|
| `settings.json` | Read-only (symlink -> Nix store) | READ | Works (symlink transparent) |
| `settings.json` | Read-only (symlink -> Nix store) | WRITE | FAILS with EROFS |
| `.mcp.json` | Read-write (merged file) | READ | Works |
| `.mcp.json` | Read-write (merged file) | WRITE | Works (if Claude ever writes) |
| `commands/` | Read-only (symlink -> Nix store) | READ | Works (symlink transparent) |
| `.claude.json` | Read-write (real file) | READ/WRITE | Works |
| `logs/` | Read-write (real dir) | WRITE | Works |

**Assumption**: Claude Code treats `settings.json` as configuration input (read-only) and writes runtime state to `.claude.json`. This matches observed behavior.

---

## Lifecycle Events

### Event 1: `home-manager switch`

```
1. Nix builds new derivation: /nix/store/<NEW-hash>-home-manager-files/
2. home-manager updates symlinks in ~/.claude-max/:
   settings.json -> /nix/store/<NEW-hash>/...  (symlink target changed)
   .mcp.json -> /nix/store/<NEW-hash>/...      (symlink target changed)
3. Worktree symlinks CONTINUE TO WORK:
   $GIT_DIR/claude-runtime/settings.json
       -> ~/.claude-max/settings.json           (unchanged)
           -> /nix/store/<NEW-hash>/...         (now points to new hash)
4. Running Claude instances may need restart to pick up new settings
```

### Event 2: Wrapper Launch (In Worktree)

```
1. Detect git context:
   git rev-parse --git-dir  # Returns e.g., ".git/worktrees/foo"

2. Create worktree runtime directory:
   mkdir -p "$GIT_DIR/claude-runtime"

3. Create/update symlinks (idempotent):
   ln -sf ~/.claude-max/settings.json $GIT_DIR/claude-runtime/settings.json
   ln -sf ~/.claude-max/commands $GIT_DIR/claude-runtime/commands

4. Merge MCP configs (account base + project overlay):
   jq -s '.[0] * .[1]' \
     ~/.claude-max/.mcp.json \
     $TOPLEVEL/.claude/.mcp.json \
     > $GIT_DIR/claude-runtime/.mcp.json

5. Set environment:
   export CLAUDE_CONFIG_DIR="$GIT_DIR/claude-runtime"

6. Launch Claude Code
```

### Event 3: Wrapper Launch (NOT In Git)

```
1. Detect no git context:
   git rev-parse --git-dir fails

2. Fall back to account config:
   export CLAUDE_CONFIG_DIR=~/.claude-max

3. Launch Claude Code
   (Claude writes .claude.json to ~/.claude-max/)
```

### Event 4: `git worktree remove`

```
1. Git removes worktree directory
2. Git removes $GIT_DIR (e.g., .git/worktrees/foo/)
3. This automatically removes $GIT_DIR/claude-runtime/ and all contents
4. No manual cleanup needed
```

---

## MCP Config Merging

The `.mcp.json` in worktree runtime is a MERGED file, not a symlink:

```bash
merge_mcp_configs() {
  local account_mcp="$1"    # ~/.claude-max/.mcp.json (from Nix)
  local project_mcp="$2"    # $TOPLEVEL/.claude/.mcp.json (optional)
  local output="$3"         # $GIT_DIR/claude-runtime/.mcp.json

  if [[ -f "$project_mcp" && -f "$account_mcp" ]]; then
    # Project overlay merges with account base
    # Project servers override account servers with same name
    jq -s '.[0] * .[1]' "$account_mcp" "$project_mcp" > "$output"
  elif [[ -f "$account_mcp" ]]; then
    # No project MCP, use account only
    cp "$account_mcp" "$output"
  elif [[ -f "$project_mcp" ]]; then
    # No account MCP (unusual), use project only
    cp "$project_mcp" "$output"
  fi
}
```

**Merge Semantics**: Project MCP servers OVERLAY account servers. If both define a server named "my-server", project version wins.

---

## Fallback Behavior Matrix

| Context | Detection | CLAUDE_CONFIG_DIR | PID File |
|---------|-----------|-------------------|----------|
| Not in git | `git rev-parse` fails | `~/.claude-max/` | `/tmp/claude-max.pid` |
| Main repo | `$GIT_DIR` = `.git` | `.git/claude-runtime/` | `/tmp/claude-max-<hash>.pid` |
| Linked worktree | `$GIT_DIR` = `.git/worktrees/<name>` | `$GIT_DIR/claude-runtime/` | `/tmp/claude-max-<hash>.pid` |
| Bare repo | `--is-bare-repository` = true | `~/.claude-max/` | `/tmp/claude-max.pid` |
| Submodule | Has own `$GIT_DIR` | `$GIT_DIR/claude-runtime/` | `/tmp/claude-max-<hash>.pid` |

**Hash calculation**: `echo "$TOPLEVEL" | md5sum | cut -c1-8`

---

## Definition of Done

- [ ] Task 0 design discussion explicitly approved by user
- [ ] Wrapper detects worktree context automatically
- [ ] Each worktree has isolated `.claude.json`
- [ ] Nix-managed settings accessible via symlink chain
- [ ] MCP configs merged (account + project) with atomic writes
- [ ] `git worktree remove` cleans up config
- [ ] Non-git fallback works as before
- [ ] `home-manager switch` doesn't break worktree symlinks
- [ ] Coalescence interaction tested
- [ ] Skills path behavior verified and documented
- [ ] Documentation updated
