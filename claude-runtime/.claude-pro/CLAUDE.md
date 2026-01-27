# User-specific Claude Code Configuration for User's Anthropic PRO Account

## ⚠️ CRITICAL RULES ⚠️
- NEVER clutter this user-global CLAUDE.md file with project- or session-specific content, e.g. tasks, status, etc
- **NO AI attribution in commit messages** - they should appear human-authored
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
- **When working with nix or NixOS, use mcp-nixos MCP server tools** to research and verify packages and their options BEFORE making any configuration changes. Why this is critical:
  1. NixOS and Home Manager options change between versions
  2. Options can be deprecated, renamed, or removed (e.g., `programs.zsh.initExtra` → `programs.zsh.initContent`)
  3. Different modules may have different option names (e.g., bash uses `initExtra`, zsh uses `initContent`)
  4. Making assumptions leads to evaluation warnings and errors
- NEVER sudo long-running commands with timeout parameters (causes Claude Code crashes with EPERM errors and inability to cleanup). 
  - What to do instead: Provide the command for user to run manually.
- **ALL github.com/timblaktu repositories are USER-OWNED**
  - When encountering issues with timblaktu repos, **ALWAYS use fd to locate the local working tree (typically cloned at ~/src) and work there in an appropriate branch**, instead of changing flake inputs to avoid them.
- ALWAYS use `echo "$WSL_DISTRO_NAME"` to determine if you're running in WSL, and what WSL instance you and/or your MCP servers are running in.
- If running in WSL, you can access other WSL instances' rootfs mounted at `/mnt/wsl/$WSL_DISTRO_NAME/`

## Custom Memory Management Commands
- /nixmemory (alias: /usermemory, /globalmemory) - Opens user-global memory file in editor (like /memory but always user-scoped)
- `/nixremember <content>` (alias: /userremember, /globalremember) - Appends content to memory (like # command but for Nix-managed memory)

### Important Notes
- These commands write to `/home/tim/src/nixcfg/claude-runtime/.claude-pro/CLAUDE.md` (this file)
- Changes auto-commit to git and rebuild to propagate to all accounts
- Built-in `/memory` and `#` commands will fail on read-only files - use the /nix* versions instead
- This file is the single source of truth for all Claude Code account configurations

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

- Check logs at: $HOME/.claude/logs/tool-usage.log
- Debug mode: Set `programs.claude-code.debug = true`
- MCP server issues: Check `/tmp/claude_desktop.log` and `~/AppData/Roaming/Claude/logs/`
- Hook failures: Review hook timeout settings
- MCP Documentation: See `home/modules/README-MCP.md` for detailed troubleshooting
- ALWAYS stage changed files related to nix-based flake-based workflows, which is most of what I do

## General Learnings

### WSL Process Termination and Mount Preservation (CRITICAL - 2026-01-27)
- **NEVER use SIGKILL (-9) on WSL when 9p mounts are temporarily unmounted**
  - `trap` handlers CANNOT catch SIGKILL - cleanup code never runs
  - If `kas-build` has unmounted `/mnt/c` and process is killed with -9, mounts stay unmounted
  - Once 9p mounts are severed by SIGKILL, they cannot be restored from within WSL
  - Requires `wsl --shutdown` from PowerShell to restore
- **Signal priority for terminating builds/processes in WSL**:
  1. **SIGTERM (15)** - Preferred. Allows trap handlers to run, remounts filesystems
  2. **SIGINT (2)** - Also trapped. Ctrl+C equivalent
  3. **SIGQUIT (3)** - Core dump but still trappable
  4. **SIGHUP (1)** - Hangup, trappable
  5. **SIGKILL (9)** - LAST RESORT ONLY. No cleanup, mounts stay broken
- **When you must kill a stuck process**:
  ```bash
  # Try graceful termination first (gives kas-build time to remount)
  kill -TERM <pid>
  sleep 5
  # If still running, try harder
  kill -INT <pid>
  sleep 3
  # Only if absolutely necessary (will break mounts if kas-build has them unmounted)
  kill -9 <pid>
  ```
- **Recovery after SIGKILL breaks mounts**:
  ```bash
  # Try the remount utility first
  nix run '.#wsl-remount'
  # If that reports empty filesystem, from PowerShell:
  wsl --shutdown
  # Then restart WSL
  ```
- **Best practice**: When working in parallel worktrees or separate Claude sessions, coordinate before killing builds that may have mounts unmounted

### WIC Generation Hang Issue (ROOT CAUSE IDENTIFIED - 2026-01-21)
- **Symptom**: Build hangs at 96% during `do_image_wic` task in WSL2
- **Root cause**: `sgdisk` (gptfdisk) calls global `sync()` in `DiskSync()` method
  - The `sync()` iterates ALL mounted filesystems including WSL2's 9p mounts (`/mnt/c`)
  - 9p filesystem sync hangs indefinitely, blocking the entire syscall
- **kas-build wrapper solution (UPDATED 2026-01-27)**:
  - Only unmounts `/mnt/c` (and other `/mnt/[a-z]` drives) - these are rw mounts that cause sync hangs
  - Leaves `/usr/lib/wsl/drivers` mounted - it's read-only and doesn't contribute to sync hangs
  - `/usr/lib/wsl/drivers` contains Windows kernel driver files (.sys), NOT user utilities
  - WSL utilities like `clip.exe`, `powershell.exe` live on `/mnt/c`, not `/usr/lib/wsl/drivers`

## TODO: User Memory Architecture Refactoring

**Issue**: The account-specific CLAUDE.md files (`.claude-max/CLAUDE.md`, `.claude-pro/CLAUDE.md`) have diverged significantly from the template (`home/modules/claude-code-user-memory-template.md`). Shared learnings must be manually copied between accounts.

**Proposed Solution**: Instead of having the Nix derivation merge templates into account files at build time:
1. Keep shared content in a single file (e.g., `claude-runtime/.claude/CLAUDE-SHARED.md`)
2. Account-specific files reference the shared file at the top
3. Claude Code can navigate to referenced files at runtime
4. This creates an effective inheritance system without complex Nix merging

**Benefits**:
- Single source of truth for shared learnings
- Account-specific customizations remain separate
- No divergence issues
- Claude can follow references to read shared content

**Files to update**:
- `home/modules/claude-code.nix` - Change deployment logic
- `claude-runtime/.claude/CLAUDE-SHARED.md` - Create shared content file
- `claude-runtime/.claude-*/CLAUDE.md` - Add reference to shared file