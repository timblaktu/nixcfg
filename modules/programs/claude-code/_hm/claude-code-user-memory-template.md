# User-specific Claude Code Configuration - {{ACCOUNT}} Account

**Read the shared configuration first**: [CLAUDE-SHARED.md](../../../claude-runtime/.claude/CLAUDE-SHARED.md)
That file contains all rules, preferences, and technical learnings common to all accounts.
This file contains ONLY account-specific overrides.

<!-- The shared file is at: /home/tim/src/nixcfg/claude-runtime/.claude/CLAUDE-SHARED.md -->
<!-- ALWAYS read it at the start of every session - it is the primary source of rules -->

## Account-Specific Details

- **Account**: Anthropic {{ACCOUNT}}
- **Memory commands write to**: This file (path varies by account)
- `/nixmemory` (alias: `/usermemory`, `/globalmemory`) - Opens this file in editor
- `/nixremember <content>` (alias: `/userremember`, `/globalremember`) - Appends to this file
- Built-in `/memory` and `#` commands will fail on read-only files - use /nix* versions
- Changes auto-commit to git and rebuild to propagate

## Account-Specific Overrides

(None currently - all shared configuration is in CLAUDE-SHARED.md)
