# User-specific Claude Code Configuration for User's Anthropic MAX Account

## ⚠️ CRITICAL RULES ⚠️
- **MANDATORY RESPONSE ENDING**: EVERY response MUST end with a ready-to-paste prompt for the next session after context is cleared. NO EXCEPTIONS.
- NEVER clutter this user-global CLAUDE.md file with project- or session-specific content, e.g. tasks, status, etc
- **NEVER include AI attribution in commit messages** - NO "Generated with Claude Code", NO "Co-Authored-By: Claude", NO emoji robots, NO links to claude.com. Commit messages must appear entirely human-authored.
- **Commit messages focus on technical content** - describe what changed and why
- ALWAYS use the following date/time stamp format for time annotations: `date +%Y-%m-%d\ %H:%M:%S\ %Z`
- ALWAYS use rg and fd commands with Bash tool for file searching (never grep/find or Search/Find tools)
- ALWAYS ensure any generated shell commands support both bash AND zsh syntaxes
- ALWAYS properly escape or quote special shell characters when generating commands
- SCREENSHOTS folder is `/mnt/c/Users/tblack/OneDrive/Pictures/Screenshots 1`
- NEVER create files unless absolutely necessary
- ALWAYS prefer editing existing files to creating new ones
- ALWAYS add documentation to existing markdown files instead of creating new files 
- ALWAYS ASK where to add documentation if there is significant ambiguity or uncertainty
- **ALWAYS ASK FOR HELP WITH AUTHENTICATION ISSUES** - If encountering ANY auth issues (GitHub, GitLab, Bitwarden, SOPS, SSH, etc.), IMMEDIATELY ask the user for help rather than trying to work around them
- **ALWAYS single-quote Nix derivation references** - When running `nix build`, `nix flake check`, or similar commands with derivation paths like `.#thing`, ALWAYS use single quotes: `nix build '.#thing'`. Unquoted paths like `.#thing` fail in zsh due to glob expansion.
- **When working with nix or NixOS, use mcp-nixos MCP server tools** to research and verify packages and their options BEFORE making any configuration changes. Why this is critical:
  1. NixOS and Home Manager options change between versions
  2. Options can be deprecated, renamed, or removed (e.g., `programs.zsh.initExtra` → `programs.zsh.initContent`)
  3. Different modules may have different option names (e.g., bash uses `initExtra`, zsh uses `initContent`)
  4. Making assumptions leads to evaluation warnings and errors
- NEVER sudo long-running commands with timeout parameters (causes Claude Code crashes with EPERM errors and inability to cleanup).
  - This rule does NOT apply to non-sudo builds like kas-container, nix-build, etc.
  - ISAR/Yocto/BitBake builds: Incremental builds typically complete in 5-10 minutes due to sstate-cache. Full clean builds of Debian-based ISAR images are also fast (minimal compilation). Don't overestimate build times.
  - Only defer to user for truly unpredictable long-running sudo commands.
- **NEVER resolve merge conflicts automatically** - When encountering git merge conflicts, ALWAYS stop immediately and ask the user to review conflicts. Show conflicted files and let user make resolution decisions.
- **NEVER use `git add -f` or `--force`** - If `git add` fails because a file matches .gitignore, that's intentional. Do not bypass gitignore patterns. If you believe a file should be tracked, ask the user first.
- **Respect .gitignore** - Files matching gitignore patterns (like `.claude/`, `CLAUDE.md`) should NOT be committed. Plan files and session state work locally without git tracking.
- **ALL github.com/timblaktu repositories are USER-OWNED**
  - When encountering issues with timblaktu repos, **ALWAYS use fd to locate the local working tree (typically cloned at ~/src) and work there in an appropriate branch**, instead of changing flake inputs to avoid them.
- ALWAYS use `echo "$WSL_DISTRO_NAME"` to determine if you're running in WSL, and what WSL instance you and/or your MCP servers are running in.
- If running in WSL, you can access other WSL instances' rootfs mounted at `/mnt/wsl/$WSL_DISTRO_NAME/`

## CI/CD and Testing Philosophy

**CRITICAL PREFERENCE**: CI/CD is just orchestration - everything must be reproducible everywhere.
- Tests that "only run in CI" or "only run locally" indicate a design problem
- If something can run in CI, it should run identically on any developer machine with the same inputs/environment
- Use feature flags, environment detection, or pytest skip conditions based on available services
- Never create CI-specific test logic or separate test suites for CI vs local
- Example: E2E tests should check for required services (Typesense, VLM endpoints) and skip gracefully if unavailable, but the test code itself is identical everywhere

## Custom Memory Management Commands
- /nixmemory (alias: /usermemory, /globalmemory) - Opens user-global memory file in editor (like /memory but always user-scoped)
- `/nixremember <content>` (alias: /userremember, /globalremember) - Appends content to memory (like # command but for Nix-managed memory)

### Important Notes
- These commands write to `/home/tim/src/nixcfg/claude-runtime/.claude-max/CLAUDE.md` (this file)
- Changes auto-commit to git and rebuild to propagate to all accounts
- Built-in `/memory` and `#` commands will fail on read-only files - use the /nix* versions instead
- This file is the single source of truth for all Claude Code account configurations

## Plan File Conventions

**Canonical location for plan files**: `.claude/user-plans/` directory in each project

**Naming conventions**:
- Numbered prefix for sequenced plans: `001-name.md`, `002-name.md`, etc.
- Lower numbers execute first; higher numbers are deferred/later phases
- Use descriptive names: `001-isar-prototype.md`, `002-isar-ci-design.md`

**Plan file format** (for `run-tasks` compatibility):
- Progress Tracking table with `TASK:PENDING` / `TASK:COMPLETE` status tokens
- Clear Definition of Done for each task
- Execution Strategy diagrams for tasks with parallel subagents

**Task ID naming rules** (CRITICAL for `run-tasks` log file generation):
- Task IDs appear in first column of Progress Tracking table (e.g., `R0.1`, `D1`, `P2.3`)
- Task Names appear in second column - these are used for log filenames
- **AVOID these characters in Task Name column**: `/` `:` `\` `*` `?` `"` `<` `>` `|` (filesystem-unsafe)
- Good: `R0.2.01 | Terms_AMD_Platform-Users-Guide`
- Bad: `R0.2.01 | Terms: AMD/Platform-Users-Guide` (contains `:` and `/`)
- The script sanitizes names but descriptive safe names are preferred
- Use underscores `_` or hyphens `-` as separators instead of `/` or `:`

**Parallelism pattern** (Option C - recommended):
- Design tasks for internal parallelism via Claude Task tool
- Spawn parallel subagents within a single task
- Sequential prereqs → Parallel work → Synthesis
- See `nixcfg/.claude/user-plans/parallel-task-runner-enhancement.md` for details

**Interactive tasks**:
- Tasks requiring user decisions should be marked as "Interactive"
- Claude presents options, waits for explicit user approval
- Do NOT proceed without documented user decisions

**Task Reset Protocol**:
When a task fails, is rejected, or needs re-execution:
1. **Update Status**: Change `TASK:COMPLETE` back to `TASK:PENDING` in Progress Tracking table
2. **Clear Artifacts**: Delete or rename ALL artifacts listed in the task's "Definition of Done"
3. **Add Reset Note**: Document why the task was reset in the task section with date and reason

Why this matters: Stale artifacts from failed/incomplete runs cause subsequent runs to falsely detect completion. The model sees the artifact exists and may conclude work is done without verifying quality/completeness.

Example reset note format:
```
**Reset History**:
- 2026-01-13: Reset - previous run created doc but actual work not performed
  - Deleted: `path/to/artifact.md`
  - Reason: Task requires X, previous run only did Y
```

## Task Artifact Management

**Critical Rule**: When `/next-task` or any task runner finds a PENDING task:
- Check if artifacts from "Definition of Done" already exist
- If artifacts exist but task is PENDING, treat as **conflict**:
  - Artifacts may be stale from a failed previous run
  - Do NOT assume existing artifacts mean task is complete
  - Delete stale artifacts before proceeding, or ask user
- Never skip task execution just because an output file exists

**When resetting tasks**:
- ALL artifacts listed in "Definition of Done" MUST be deleted or renamed
- Document the reset with date and reason in the task section
- This prevents false completion detection on re-run

## Active Configuration

### Model
- Default: sonnet
- Debug mode: disabled

### Sub-Agents
- code-searcher

### Slash Commands
- /documentation generate-readme
    - /documentation api-docs
- /security audit
    - /security secrets-scan
- /refactor extract-function
    - /refactor rename-symbol
- /context cleanup
    - /context save
    - /context load

### Active Hooks
- Security checks: 
- Auto-formatting: 
- Linting: 
- Testing: 
- Git integration: 
- Logging: 
- Notifications: 

## Performance Tips

- Use sub-agents for specialized tasks to reduce token usage
- Leverage slash commands for common operations
- Enable caching where appropriate
- Use project overrides for context-specific settings

## Troubleshooting

- Check logs at: ~/.claude/logs/tool-usage.log
- Debug mode: Set `programs.claude-code.debug = true`
- MCP server issues: Check `/tmp/claude_desktop.log` and `~/AppData/Roaming/Claude/logs/`
- Hook failures: Review hook timeout settings
- MCP Documentation: See `home/modules/README-MCP.md` for detailed troubleshooting

## General Learnings

### ISAR Test Framework
- **Decision**: Use NixOS VM Test Driver (nixos-test-driver) with ISAR-built .wic images - NOT Avocado
- ISAR builds images (BitBake/kas produces .wic files), Nix provides test harness
- Tests run on host NixOS/Nix environment, not inside kas-container
- Test images need `nixos-test-backdoor` package - include via `kas/test-overlay.yml`
- Build test images: `kas-container --isar build kas/converix.yml:kas/machine/qemu-amd64.yml:kas/test-overlay.yml:kas/image/minimal-base.yml`
- VM script derivations must NOT use `run-<name>-vm` pattern in derivation name (conflicts with nixos-test-driver regex)
- nixos-test-driver backdoor protocol: service prints "Spawning backdoor root shell..." to /dev/hvc0 (virtconsole)
- Key doc: `isar/.research/CRITICAL-DECISION-SUMMARY.md`

### Claude Task Runner Artifacts
- `.claude-task-logs/` and `.claude-task-state` are local session state
- Should be gitignored explicitly (pattern `**/.claude` doesn't match `.claude-task-*` prefix)
- Generated by automated task runner scripts, not manually created
