# Claude Code Memory System - Current State Analysis

## Purpose

This document captures a detailed analysis of how the Claude Code multi-account memory
system actually works at the filesystem/Nix level. It is the source material for a
review session: read it, critique it, find gaps, then propose improvements to both
the document and the underlying system.

## The Full Symlink Chain (Proven)

When a PRO session starts, Claude Code resolves `CLAUDE_CONFIG_DIR` as follows:

```
~/.claude-pro                                             (home.file entry)
  └─→ /nix/store/56ps4.../home-manager-files/.claude-pro  (HM link record)
        └─→ /nix/store/ri7c0px...-hm_.claudepro            (nix store entry)
              └─→ ~/src/nixcfg/claude-runtime/.claude-pro   (THE LIVE DIRECTORY)
```

The nix store entry `ri7c0px...-hm_.claudepro` is not an immutable derivation output -
it is a **symlink** created by `config.lib.file.mkOutOfStoreSymlink`. Proof: the inode
of `/nix/store/ri7c0px...-hm_.claudepro/` equals the inode of
`~/src/nixcfg/claude-runtime/.claude-pro/` (both inode 23339946, device 8:48 at time
of analysis). They are the same directory.

The same chain applies to MAX (`.claude-max`) and WORK (`.claude-work`):
- MAX: `~/.claude-max` → nix store → `~/src/nixcfg/claude-runtime/.claude-max`
- WORK: `~/.claude-work` → nix store → `~/src/nixcfg/claude-runtime/.claude-work`

`~/.claude` is a **real mutable directory** (not a symlink) containing only runtime
state (history, session data). It has NO CLAUDE.md. This is intentional - see
claude-code.nix comment: "~/.claude symlink intentionally removed to prevent Claude
Code from loading CLAUDE.md twice (once via CLAUDE_CONFIG_DIR, once via ~/.claude
fallback)."

## The home-manager Module: How Files Actually Get There

Source: `~/src/nixcfg/modules/programs/claude-code/claude-code.nix`

**Structural files** (`settings.json`, `.mcp.json`, `agents/`): Deployed by the
`claudeConfigTemplates` activation script at `home-manager switch` time. These ARE
regenerated from Nix expressions on every switch.

**CLAUDE.md**: Special-cased in the activation script:
```bash
if [[ -f "$accountDir/CLAUDE.md" ]]; then
  echo "Preserved existing memory file"
  chmod 644 "$accountDir/CLAUDE.md"   # just chmod, no content update
else
  copy_template "${claudeMdTemplate}" "$accountDir/CLAUDE.md"
fi
```
Where `claudeMdTemplate = builtins.readFile ./_hm/claude-code-user-memory-template.md`.

CLAUDE.md is **initialized once from the template, then never overwritten by Nix**.
It is a living mutable file - Claude Code sessions edit it. Runtime edits persist
across home-manager switches. The template is only used for brand-new accounts.

## The CLAUDE-SHARED.md Problem (Critical Regression)

Commit 16af8f0 (2026-06-07) refactored memory into a shared file:
- Created `claude-runtime/.claude/CLAUDE-SHARED.md` (~215 lines of rules)
- Slimmed `.claude-pro/CLAUDE.md` and `.claude-max/CLAUDE.md` to ~19 lines each
- Each account CLAUDE.md now contains only: "Read shared config first: [link to CLAUDE-SHARED.md]"

**This broke content loading.** Claude Code does NOT follow markdown hyperlinks in
CLAUDE.md files. `CLAUDE-SHARED.md` lives in `claude-runtime/.claude/`, which is the
base account's runtime directory - NOT in the PRO, MAX, or WORK account directories.
Claude Code only loads CLAUDE.md from:
1. The account config dir (CLAUDE_CONFIG_DIR)
2. The project tree (walking up from cwd)

`claude-runtime/.claude/CLAUDE-SHARED.md` is not in either of those paths for PRO/MAX/WORK
sessions.

**Consequence**: Any session in a project that does NOT have a detailed project-level
CLAUDE.md will have only the 19-line pointer file in context - zero shared rules loaded.
The session in n3x-infrathon at time of analysis was OK only because n3x-infrathon's
own `CLAUDE.md` is ~500 lines and incidentally covers many of the same rules.

## Account-by-Account Status After 16af8f0

| Account | CLAUDE.md state | Shared rules loaded? |
|---------|-----------------|----------------------|
| PRO | 19-line pointer (markdown link only) | No |
| MAX | 19-line pointer (markdown link only) | No |
| WORK | Still OLD full-content format (~95 lines), NOT migrated | Partially (old content) |

The WORK account migration was not completed. It still has the pre-refactoring format
with duplicate rules, stale MCP server status entries, and content that duplicates what
is now in CLAUDE-SHARED.md.

## What CLAUDE-SHARED.md Contains

The shared file (at `claude-runtime/.claude/CLAUDE-SHARED.md`, ~215 lines) contains:

- Memory Placement Rule (which file to write new content to)
- Critical Rules (commit practices, search tools, shell compat, etc.)
- WSL Interop patterns
- Nix and Git Safety rules
- Nix Flake Verification commands
- Proactive Browser Integration guidance
- Terminal-Width-Aware Output Formatting
- Content Delivery for Copy-Paste
- CI/CD and Testing Philosophy
- Documenting Workarounds Protocol
- Session Workflow Protocol (one task per session, continuation prompt)
- Plan File Conventions
- Continuation Prompt Protocol
- Long-Running Task Strategy
- Universal Technical Learnings (WSL process termination, WIC hang, git worktree, etc.)
- Custom Memory Management Commands reference
- Active Configuration section

## Fix Options

### Option A: Restore full content to each account CLAUDE.md

Put the CLAUDE-SHARED.md content directly into each account's CLAUDE.md. Eliminates
the shared file concept. Simple but duplicates content across accounts - the original
problem this refactoring tried to solve.

### Option B: Update template + delete existing account files

Update `_hm/claude-code-user-memory-template.md` to include the full shared content.
Delete the existing slim account CLAUDE.md files. Run `home-manager switch` to
re-initialize from the new template. Going forward, all accounts start with full content.

Downside: any runtime-edits accumulated in existing CLAUDE.md files are lost (though
with the current slim pointer files, there's nothing of value to lose). Also, next time
someone creates a new account, it gets the full content bootstrapped correctly.

### Option C: Inline shared content at switch time (generate, not preserve)

Change the activation script to always regenerate CLAUDE.md from a template that
includes shared content + account-specific overrides, rather than preserving existing.
Runtime edits to CLAUDE.md would be lost on next switch.

This breaks the "writable memory" model where Claude edits CLAUDE.md at runtime. To
preserve that, the activation script would need to merge rather than replace - complex.

### Option D: Use ~/.claude/CLAUDE.md as shared fallback

Put CLAUDE-SHARED.md content into `~/.claude/CLAUDE.md`. Claude Code loads this as
a fallback. But the module intentionally avoids the `~/.claude` symlink to prevent
double-loading. This would require re-enabling ~/.claude management and carefully
controlling what goes there vs account dirs.

### Option E: Accept project-level CLAUDE.md as the answer

For ALL actively used projects, ensure a project-level CLAUDE.md with the shared rules.
The account-level CLAUDE.md becomes truly account-specific only. This is arguably the
right semantic separation (project knowledge in project, user preferences in account).

Downside: orphan sessions in new/small projects get no shared rules until a CLAUDE.md
is added. Requires maintaining shared content in every project's CLAUDE.md.

## Recommended Fix (Pending Review)

**Option B** (update template + delete existing) is the lowest-risk path:

1. Verify `_hm/claude-code-user-memory-template.md` currently contains the right base
   for new accounts (check its content vs CLAUDE-SHARED.md)
2. Update the template to embed the full CLAUDE-SHARED.md content
3. Delete `.claude-pro/CLAUDE.md`, `.claude-max/CLAUDE.md`, `.claude-work/CLAUDE.md`
4. Run `home-manager switch` to re-initialize all three from the new template
5. Archive or delete `claude-runtime/.claude/CLAUDE-SHARED.md` (no longer needed)
6. Update the Memory Placement Rule in the template to say "write new content to
   your account's CLAUDE.md directly" rather than referencing the now-deleted shared file

The WORK account also needs its `CLAUDE.md` migrated from the old full-content format -
either merged into the template or simply deleted and re-initialized.

## Questions for Review Session

1. Is Option B actually the right choice, or does one of the other options better fit
   the intended workflow?
2. The template is only used for NEW accounts - should there be a mechanism to ALSO
   push template updates to existing accounts without losing runtime edits?
3. Should CLAUDE-SHARED.md be kept as a human reference document even if Claude Code
   doesn't load it automatically?
4. What is the right split between account-level and project-level CLAUDE.md content?
   Are there rules in CLAUDE-SHARED.md that belong in project CLAUDE.md instead?
5. The `/nixremember` command appends to the account CLAUDE.md. After this fix, will
   that command still work correctly given the new file structure?
6. Are there any other files in the account dirs (settings.json, .mcp.json, agents/)
   that have similar drift/staleness issues needing a home-manager switch to fix?
