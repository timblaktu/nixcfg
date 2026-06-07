<!-- This file is Nix-managed. Edit the template at -->
<!-- modules/programs/claude-code/_hm/claude-code-user-memory-template.md -->
<!-- and run home-manager switch to regenerate. -->

# User-specific Claude Code Configuration - {{ACCOUNT}} Account

## Critical Rules

- NEVER clutter user-global CLAUDE.md files with project- or session-specific content
- **NO AI attribution in commit messages** - they should appear human-authored. NO "Generated with Claude Code", NO "Co-Authored-By: Claude", NO emoji robots
- **Commit messages focus on technical content** - describe what changed and why
- ALWAYS use timestamp format: `date +%Y-%m-%d\ %H:%M:%S\ %Z`
- ALWAYS use rg and fd for file searching (never grep/find or Search/Find tools)
- ALWAYS ensure shell commands support both bash AND zsh
- ALWAYS properly escape or quote special shell characters
- **ALWAYS single-quote Nix derivation references**: `nix build '.#thing'` (zsh glob expansion)
- **Screenshots (WSL)**: Find dynamically with `fd -t f -e png -e jpg -e jpeg . '/mnt/c/Users/'*/OneDrive*/Pictures/Screenshots* -d 1 --exec stat --printf='%Y %n\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-`
- NEVER create files unless absolutely necessary - prefer editing existing files
- ALWAYS add documentation to existing markdown files - ASK where if ambiguous
- **ALWAYS ASK FOR HELP WITH AUTHENTICATION ISSUES** - GitHub, GitLab, Bitwarden, SOPS, SSH, etc.
- **Use mcp-nixos MCP tools** to verify NixOS/Home Manager options BEFORE making changes. Options change between versions, get deprecated/renamed/removed. Making assumptions leads to eval errors.
- NEVER sudo long-running commands with timeout (causes Claude Code EPERM crashes). Provide the command for user to run manually instead.
- **ALL github.com/timblaktu repos are USER-OWNED** - work in local worktrees (typically ~/src), not flake input changes
- **ALWAYS stage changes before nix commands** - Nix only sees staged/committed changes
- **LOCAL-FIRST RESEARCH** - look in `~/src/` for existing clones before web searches. Clone repos to `~/src/` if needed. Web search is last resort for non-code info.
- ALWAYS use relative paths for inter-document markdown links in shared repos
- **NEVER hard-wrap lines in files** - let lines run naturally, editors handle wrapping
- **NEVER use emdashes** (U+2014) anywhere - always use single normal hyphen '-'
- ALWAYS remove temporary troubleshooting artifacts after completing tasks (test scripts, debug logs, temp dirs)

## WSL Interop

- Use `echo "${WSL_DISTRO_NAME:-$WSL_DISTRO}"` to determine WSL instance (NixOS WSL sets `WSL_DISTRO`, not `WSL_DISTRO_NAME`); access others at `/mnt/wsl/$WSL_DISTRO/`
- **Windows executables callable directly from WSL** (e.g., `usbipd.exe list`, `powershell.exe -c "command"`). NEVER tell user to "open PowerShell" - call `.exe` directly. Windows PATH is on `$PATH` via `appendWindowsPath`.
- **Opening files and URLs**: Use `claude-browse <path-or-url>` to open in browser. Falls back to xdg-open.

## Nix and Git Safety

- **NEVER run nix commands concurrently** - no background nix tasks, no multiple nix Bash calls in same response. Concurrent nix evaluations cause OOM kills. A `nix-guarded` flock wrapper exists as safety net, but always serialize explicitly. Bypass with `NIX_NO_GUARD=1` if needed.
- **NEVER run parallel git commands in the same worktree** - `index.lock` is per-worktree; parallel git ops race on it, especially on WSL2 where 9p latency widens the window. Cross-worktree git is safe in parallel.
- **NEVER resolve merge conflicts automatically** - show conflicted files, let user decide
- **NEVER use `git add -f`** - respect .gitignore patterns
- **ALWAYS pass `-f` to `rm`** in non-interactive Bash tool calls (`rm -f`, `rm -rf`). The user's shell aliases `rm` to `rm -i`, which hangs in non-interactive subshells. Same for `cp -i`, `mv -i`.
- **VERIFY PROCESS PROVENANCE BEFORE KILLING** - Multiple sessions run concurrently. Before killing any PID you didn't spawn: walk parent chain (`pstree -p -s PID`), check `/proc/<claude-pid>/cwd`. If cwd != your session's cwd, DO NOT kill it.

## Nix Flake Verification

```bash
nix flake check --no-build          # Quick evaluation (~30-60s) - USE THIS
nix build '.#checks.x86_64-linux.TEST_NAME'  # Specific test
```
- Full builds only when: explicitly requested, testing test infrastructure, final PR validation

## Proactive Browser Integration

The user's dev environment is Terminal + Browser. Proactively `claude-browse` content that would naturally need viewing.

**Always open automatically**: PR/MR links after creation, pipeline URLs, diagram files after editing, docs after substantial rewriting, URLs user needs to visit next.

**Do not open automatically**: Files with small edits, build logs, the same URL twice, more than 3 items in quick succession.

## Terminal-Width-Aware Output Formatting

All markdown tables in chat MUST fit within terminal width.

**Width detection**: `echo "$CLAUDE_TERMINAL_WIDTH"` (set by wrapper scripts).

**Strategy**: Calculate available width -> estimate table width -> if too wide, compress in order: abbreviate headers -> truncate cells -> remove columns -> split table -> switch to vertical key:value format.

File output may exceed terminal width (editors have horizontal scroll).

## Content Delivery for Copy-Paste

Do NOT put copy-paste content in chat as code-fenced blocks. Instead:
1. **clip.exe** for short content: `echo -n "content" | clip.exe`
2. **temp .md file + xdg-open** for long/formatted content

Does NOT apply when content is sent directly via API (e.g., `glab api`).

## CI/CD and Testing Philosophy

- CI/CD is just orchestration - everything must be reproducible everywhere
- Tests that "only run in CI" indicate a design problem
- Never create CI-specific test logic or separate test suites

## Documenting Workarounds Protocol

When applying version-incompatibility workarounds:
1. **Code Comments**: Error message, version context, TODO with migration path, WORKAROUND vs API-ADAPTATION
2. **Commit Message**: ERROR messages, files modified, when/how to remove
3. **Triggers**: "option 'X' does not exist", "unexpected argument", "attribute missing", "deprecated option"

## Session Workflow Protocol

**ONE TASK PER SESSION** for multi-phase **user-plans** (`.claude/user-plans/`) - complete one plan task per session then stop with continuation prompt.

**Scope**: Applies to plan tasks spread across sessions, NOT to executing an approved plan within a single session. When user approves a plan ("implement this plan"), execute all tasks in sequence.

**Correct Protocol (multi-session plans)**:
1. Complete ONE plan task
2. Update memory (project and user-global if learnings occurred)
3. Update plan files with task status
4. Commit changes
5. Pipe continuation prompt to clipboard via `clip.exe` (see Continuation Prompt Protocol below)
6. STOP - wait for user to start new session

**Exception**: User explicitly grants permission to continue.

## Plan File Conventions

**Location**: `.claude/user-plans/` with numbered prefix (`001-name.md`)

**Format**: Progress table with `TASK:PENDING`/`TASK:COMPLETE`, Definition of Done per task.

**CRITICAL: Plan files must be self-contained** - save the FULL plan to disk, not a summary. New sessions cannot access previous session's chat. Every specification needed to execute remaining tasks MUST be in the plan file. Test: Could a new session execute the next task using ONLY the plan file + CLAUDE.md + codebase?

**Continuation Prompt**: Must be self-contained - merge task summary (what was done, commits, artifacts, what was NOT done) directly into the prompt. Deliver via `cat <<'CONT' | clip.exe` (or `/tmp/continuation.md` + `claude-browse` for >4KB). Never reference "previous session context".

## Continuation Prompt Protocol (MANDATORY - NEVER SKIP)

**EVERY session that works on a plan MUST end with a continuation prompt on the clipboard.** This is non-negotiable - treat it like committing code. A session without a continuation prompt is incomplete work.

1. Update memory and plan files with task status
2. Pipe continuation prompt to clipboard: `cat <<'CONT' | clip.exe` (or write `/tmp/continuation.md` + `claude-browse` if >4KB)
3. Print a short confirmation: "Continuation prompt copied to clipboard (topic: <brief>)"
4. Do NOT print the continuation prompt inline in chat - it clutters output

The prompt must be **self-contained** - include: (1) memory file path, (2) plan file path, (3) which task to resume, (4) enough context that the next session starts without questions. Task summaries go INSIDE the prompt, not as a separate chat section. Never reference "previous session context".

## Long-Running Task Strategy

Long-running tasks (>5 min) are allowed but require management:
- Poll ~once/minute, monitor process output for progress and errors
- Continue other work while waiting, engage user interactively
- Patterns: background + periodic monitoring, sub-agent delegation, fire-and-forget, user runs separately

## Universal Technical Learnings

### WSL Process Termination and Mount Preservation (CRITICAL)
- **Signal priority**: SIGTERM (15) > SIGINT (2) > SIGQUIT (3) > SIGHUP (1) > SIGKILL (9)
- SIGKILL bypasses trap handlers - leaves 9p mounts broken if kas-build has them unmounted
- **Recovery**: `nix run '.#wsl-remount'` or `wsl --shutdown` from PowerShell
- When killing stuck processes: `kill -TERM <pid>; sleep 5; kill -INT <pid>` - SIGKILL only as last resort

### WIC Generation Hang Issue (ROOT CAUSE)
- **Symptom**: Build hangs at 96% during `do_image_wic` in WSL2
- **Root cause**: `sgdisk` calls global `sync()` which iterates ALL mounted filesystems including WSL2's 9p mounts
- **Fix**: `kas-build` wrapper unmounts `/mnt/[a-z]` drives before building. Leaves `/usr/lib/wsl/drivers` (read-only, no sync hang).

### Git Worktree Workflow
- **Use case**: Parallel work across Claude accounts without interference
- **Setup**: `git worktree add ~/src/project-pro feature/foo-pro`
- **Cleanup**: `git worktree remove`, `git branch -d`

### Claude Task Runner Artifacts
- `.claude-task-logs/` and `.claude-task-state` are local session state - should be gitignored

### Multi-Account Memory Architecture (2026-03-01)
- `~/.claude` symlink removed - bare `claude` is now a wrapper that sets `CLAUDE_CONFIG_DIR` directly
- Each account has independent CLAUDE.md (`.claude-max/`, `.claude-pro/`, etc.)
- Per-account symlinks (`~/.claude-max`, `~/.claude-pro`) remain as convenience
- Slash commands are on-demand: content loaded only when invoked, costs nothing in context
