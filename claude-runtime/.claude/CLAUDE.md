# Claude Code Configuration - Base Template

This is the base template for Claude Code account configuration. It is NOT the runtime
configuration file - each account has its own `CLAUDE.md` that references the shared
configuration.

**Shared configuration**: See [CLAUDE-SHARED.md](CLAUDE-SHARED.md) for all rules,
preferences, and technical learnings.

**Account-specific files** (runtime):
- PRO: `claude-runtime/.claude-pro/CLAUDE.md`
- MAX: `claude-runtime/.claude-max/CLAUDE.md`

**Memory placement rule**: When adding memory content, default to `CLAUDE-SHARED.md`.
Only put content in account-specific files if it truly applies to only one account.
See the "Memory Placement Rule" section in CLAUDE-SHARED.md.
