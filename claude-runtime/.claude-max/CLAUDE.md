# User-specific Claude Code Configuration for User's Anthropic MAX Account

## Critical Rules

- **MANDATORY RESPONSE ENDING**: EVERY response MUST end with a ready-to-paste prompt for the next session after context is cleared. NO EXCEPTIONS.
- NEVER clutter this user-global CLAUDE.md with project- or session-specific content
- **NEVER include AI attribution in commit messages** - NO "Generated with Claude Code", NO "Co-Authored-By: Claude", NO emoji robots. Commit messages must appear entirely human-authored.
- ALWAYS use timestamp format: `date +%Y-%m-%d\ %H:%M:%S\ %Z`
- ALWAYS use rg and fd for file searching (never grep/find or Search/Find tools)
- ALWAYS ensure shell commands support both bash AND zsh
- ALWAYS properly escape or quote special shell characters
- SCREENSHOTS folder: `/mnt/c/Users/tblack/OneDrive/Pictures/Screenshots 1`
- NEVER create files unless absolutely necessary - prefer editing existing files
- ALWAYS add documentation to existing markdown files - ASK where if ambiguous
- **ALWAYS ASK FOR HELP WITH AUTHENTICATION ISSUES** - GitHub, GitLab, Bitwarden, SOPS, SSH, etc.
- **ALWAYS single-quote Nix derivation references**: `nix build '.#thing'` (zsh glob expansion)
- **Use mcp-nixos MCP tools** to verify NixOS/Home Manager options BEFORE making changes
- NEVER sudo long-running commands with timeout (causes Claude Code EPERM crashes)
- **NEVER resolve merge conflicts automatically** - show conflicted files, let user decide
- **NEVER use `git add -f`** - respect .gitignore patterns
- **ALL github.com/timblaktu repos are USER-OWNED** - work in local worktrees, not flake input changes
- Use `echo "$WSL_DISTRO_NAME"` to determine WSL instance; access others at `/mnt/wsl/$WSL_DISTRO_NAME/`
- **ONE TASK PER SESSION** for multi-phase plans - stop after completing one task
- **ALWAYS stage changes before nix commands** - Nix only sees staged/committed changes
- **Task summaries**: Be explicit about SCOPE, list ALL artifacts, state what was NOT done
- **UPDATE MEMORY BEFORE SUMMARY** - update project memory first, then provide summary

## CI/CD and Testing Philosophy

CI/CD is just orchestration - everything must be reproducible everywhere.
- Tests that "only run in CI" indicate a design problem
- Use feature flags/environment detection for service availability
- Never create CI-specific test logic or separate test suites

## Documenting Workarounds Protocol

When applying version-incompatibility workarounds:
1. **Code Comments**: Error message, version context, TODO with migration path, WORKAROUND vs API-ADAPTATION
2. **Commit Message**: ERROR messages, files modified, when/how to remove
3. **Triggers**: "option 'X' does not exist", "unexpected argument", "attribute missing", "deprecated option"

## Nix Flake Verification

**CRITICAL: Always use `--no-build` for routine verification**
```bash
nix flake check --no-build          # Quick evaluation (~30-60s) - USE THIS
nix build '.#checks.x86_64-linux.TEST_NAME'  # Specific test
```
- Establish test BASELINE, run ONLY baseline tests as regression suite
- Full builds only when: explicitly requested, testing test infrastructure, final PR validation

## Custom Memory Commands

- `/nixmemory` - Opens this file in editor
- `/nixremember <content>` - Appends to this file
- Writes to `/home/tim/src/nixcfg/claude-runtime/.claude-max/CLAUDE.md`
- Built-in `/memory` fails on read-only files - use /nix* versions

## Plan File Conventions

**Location**: `.claude/user-plans/` with numbered prefix (`001-name.md`)

**Format**: Progress table with `TASK:PENDING`/`TASK:COMPLETE`, Definition of Done per task

**Task IDs**: Avoid `/:\*?"<>|` in names (filesystem-unsafe)

**Parallelism**: Design for internal parallelism via Claude Task tool (spawn subagents)

**Task Reset**: Update status to PENDING, delete artifacts, add reset note with date/reason

## Universal Technical Learnings

### WSL Process Termination
- **Signal priority**: SIGTERM (15) > SIGINT (2) > SIGQUIT (3) > SIGHUP (1) > SIGKILL (9)
- SIGKILL bypasses trap handlers - leaves 9p mounts broken if kas-build has them unmounted
- **Recovery**: `nix run '.#wsl-remount'` or `wsl --shutdown` from PowerShell

### Long-Running Task Strategy
- **Problem**: BashOutput polling consumes context rapidly (500-2000 tokens per poll)
- **Solution 1**: Sub-agent delegation - agent returns ONLY summary
- **Solution 2**: Fire-and-forget with single final check
- **Solution 3**: User runs in separate terminal, reports results
- **Avoid**: Polling every 30-60s, concurrent memory-heavy operations

### Git Worktree Workflow
- **Use case**: Parallel work across Claude accounts (Pro/Max) without interference
- **Setup**: `git worktree add ~/src/project-pro feature/foo-pro`
- **Integration**: Merge, rebase, or cherry-pick between worktrees
- **Cleanup**: `git worktree remove`, `git branch -d`

### Claude Task Runner Artifacts
- `.claude-task-logs/` and `.claude-task-state` are local session state
- Should be gitignored (pattern `**/.claude` doesn't match `.claude-task-*`)
- ALWAYS stage flake changes before nix commands
