# User-specific Claude Code Configuration for User's Anthropic MAX Account

## Critical Rules

- **MANDATORY RESPONSE ENDING**: EVERY response MUST end with a ready-to-paste prompt for the next session after context is cleared. NO EXCEPTIONS. The continuation prompt must be **self-contained** — merge the task summary (what was done, commits, artifacts, what was NOT done) directly into the prompt block. No separate summary section above. The user copies ONE block into the next session and nothing is lost.
- NEVER clutter this user-global CLAUDE.md with project- or session-specific content
- **NEVER include AI attribution in commit messages** - NO "Generated with Claude Code", NO "Co-Authored-By: Claude", NO emoji robots. Commit messages must appear entirely human-authored.
- ALWAYS use timestamp format: `date +%Y-%m-%d\ %H:%M:%S\ %Z`
- ALWAYS use rg and fd for file searching (never grep/find or Search/Find tools)
- ALWAYS ensure shell commands support both bash AND zsh
- ALWAYS properly escape or quote special shell characters
- **WSL interop**: Windows executables are callable directly from WSL (e.g., `usbipd.exe list`, `powershell.exe -c "command"`). NEVER tell user to "open PowerShell" or "run from Windows" — call the `.exe` directly from the current shell. Windows PATH is on `$PATH` via `appendWindowsPath` (wsl module default).
- **Opening files and URLs**: Use `claude-browse <path-or-url>` to open files or URLs in the user's browser. Session opens are grouped into a single browser window automatically (first open = new window, subsequent = tabs). Falls back to xdg-open if claude-browse is not available.
- **Screenshots (WSL)**: Find dynamically with `fd -t f -e png -e jpg -e jpeg . '/mnt/c/Users/'*/OneDrive*/Pictures/Screenshots* -d 1 --exec stat --printf='%Y %n\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-`
- NEVER create files unless absolutely necessary - prefer editing existing files
- ALWAYS add documentation to existing markdown files - ASK where if ambiguous
- **ALWAYS ASK FOR HELP WITH AUTHENTICATION ISSUES** - GitHub, GitLab, Bitwarden, SOPS, SSH, etc.
- **ALWAYS single-quote Nix derivation references**: `nix build '.#thing'` (zsh glob expansion)
- **Use mcp-nixos MCP tools** to verify NixOS/Home Manager options BEFORE making changes
- NEVER sudo long-running commands with timeout (causes Claude Code EPERM crashes)
- **NEVER run nix commands concurrently** — do not use background tasks for nix commands, do not issue multiple Bash calls with nix in the same response. Always serialize nix invocations (`nix build`, `nix run`, `nix flake check`, `nix eval`). Concurrent nix evaluations cause OOM kills. This applies within a single session — other sessions may also be running nix, compounding the problem. A flock-based guard (`nix-guarded`) is prepended to PATH in agent wrappers as a safety net, but agents should not rely on it — always serialize explicitly. Bypass with `NIX_NO_GUARD=1` if needed.
- **NEVER run parallel git commands in the same worktree** — do not issue multiple Bash calls containing git operations in the same response. Git's `index.lock` is per-worktree; parallel `git status` + `git diff` (or any two index-touching commands) will race on the lock, especially on WSL2 where 9p latency widens the timing window. Always serialize git operations within a worktree. Cross-worktree git operations are safe in parallel (different index files).
- **NEVER resolve merge conflicts automatically** - show conflicted files, let user decide
- **NEVER use `git add -f`** - respect .gitignore patterns
- **ALWAYS pass `-f` to `rm`** in non-interactive Bash tool calls (`rm -f`, `rm -rf`). The user's shell aliases `rm` to `rm -i`, which prompts for confirmation and hangs forever in non-interactive subshells, leaving orphaned zsh processes. Same applies to `cp -i`, `mv -i` if those aliases are added later — always use the non-interactive form. Also prefer the `Bash` tool's working-dir-aware operations over destructive shell commands when possible.
- **VERIFY PROCESS PROVENANCE BEFORE KILLING** - Multiple Claude/opencode sessions run concurrently in different cwds. Before `kill`-ing any PID you didn't directly spawn in the current session, walk the parent chain (`pstree -p -s PID` or `ps -o ppid= -p PID` repeatedly) up to the owning `claude`/`opencode` process and check `/proc/<claude-pid>/cwd`. If the cwd is not your session's cwd, the process belongs to another session — DO NOT kill it. This applies especially to long-running `nix` evaluations and pre-commit hooks.
- **ALL github.com/timblaktu repos are USER-OWNED** - work in local worktrees, not flake input changes
- Use `echo "$WSL_DISTRO_NAME"` to determine WSL instance; access others at `/mnt/wsl/$WSL_DISTRO_NAME/`
- **ONE TASK PER SESSION** for multi-phase **user-plans** (`.claude/user-plans/`) - stop after completing one plan task and provide continuation prompt. Does NOT apply when executing an approved plan within a single session (user said "implement this plan" = execute all tasks). The boundary is between plan tasks across sessions, not within approved plan execution.
- **ALWAYS stage changes before nix commands** - Nix only sees staged/committed changes
- **Task summaries are INSIDE the continuation prompt** - Do NOT produce a separate summary section followed by a separate continuation prompt. Merge them: the continuation prompt IS the summary. Include scope, commits, artifacts, what was NOT done — all inside the single paste-ready block.
- **UPDATE MEMORY BEFORE CONTINUATION PROMPT** - update project memory first, then provide the combined summary+prompt
- **COMMIT DIAGRAM CHANGES IMMEDIATELY** - `.drawio.svg` files with uncommitted pages can be lost if `git checkout` is used; commit after each significant diagram edit
- **LOCAL-FIRST RESEARCH** - When researching topics involving source code or repositories, ALWAYS start by looking in `~/src/` for existing clones. Most upstream repos are already cloned there. If a repo is not yet cloned locally, `git clone` it into `~/src/` rather than using web searches or WebFetch. Read source code directly from local checkouts — it's faster, more accurate, and avoids token-heavy web fetching. Web search is a last resort for non-code information (release notes, mailing list discussions, etc.).
- **NEVER hard-wrap lines in files** - Do NOT insert newlines to enforce any column width in markdown, docs, prose, YAML comments, code comments, or any file. Let lines run as long as they naturally are. Editors/renderers handle wrapping. Hard wraps cause ugly reflow diffs.

## Terminal-Width-Aware Output Formatting

**CRITICAL: All markdown tables in chat responses MUST fit within the current terminal width.**

**Width Detection** (use $CLAUDE_TERMINAL_WIDTH set by wrapper):
```bash
echo "$CLAUDE_TERMINAL_WIDTH"
```
Note: The wrapper scripts (claudemax, claudepro, etc.) capture the real terminal width before launching Claude Code. Claude's subprocesses cannot detect terminal dimensions directly (no real PTY), so this environment variable is the authoritative source.

**Decision Framework for Tables**:

1. **Calculate available width**: `terminal_width - 2` (margin safety)
2. **Estimate table width**: Count columns × avg content + separators (`|` = 1 char each)
3. **If table fits**: Use table format
4. **If table doesn't fit**: Apply compression strategies in order:

**Compression Strategies** (apply in order until table fits):
1. **Abbreviate headers**: Use acronyms, drop articles (`Description` → `Desc`, `Status` → `St`)
2. **Truncate cell content**: Use `...` for content that can be inferred from context
3. **Remove low-value columns**: Drop columns that don't add essential information
4. **Split table**: Multiple narrower tables with shared key column

**When to switch to vertical format** (key: value lists):
- Content is **inherently detailed** (full sentences, paths, multi-line values)
- Truncation would **destroy meaning** (UUIDs, checksums, URLs)
- Only 2-3 items to display (table overhead not worth it)
- Content requires **exact reproduction** (commands, code snippets)

**When to keep table format** (even if tight):
- Comparing multiple items across same attributes
- Scanning/sorting is the primary use case
- Content is **naturally terse** (statuses, counts, short names)
- Pattern recognition benefits from alignment

**File output**: May exceed terminal width since files are viewed in editors/renderers with horizontal scroll.

## Proactive Browser Integration

The user's dev environment is Terminal + Browser. Proactively `claude-browse` content that the user would naturally want to view or review. Do not ask or announce -- just open it.

**Always open automatically:**
- URLs produced as output of an action: PR/MR links after creation, pipeline URLs after triggering, GitHub/GitLab pages after interaction
- Diagram files (`.drawio.svg`, rendered Mermaid) after creating or significantly editing them
- Documentation files after creating or substantially rewriting them (not minor edits)
- Any URL the user would need to visit as a next step (e.g., "approve this MR")

**Do not open automatically:**
- Files you only read or made small edits to (the user is already in the terminal)
- Build logs, test output, or other transient operational output
- The same URL/file twice in one session
- More than 3 items in quick succession: list them and let the user choose which to open. Exception: a single action producing multiple related URLs (e.g., MR link + pipeline link) counts as one logical open.

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

**CRITICAL: Plan files must be self-contained** (learned 2026-02-12):
- Save the FULL plan to disk, not a summary. New sessions cannot access previous session's chat input.
- Every specification needed to execute remaining tasks MUST be in the plan file: file structure trees, rename tables, exclusion lists, documentation content specs, task DoDs.
- The continuation prompt should reference ONLY files on disk, never "the original plan input from the previous session".
- Test: Could a new Claude session execute the next task using ONLY the plan file + CLAUDE.md + codebase? If not, the plan file is incomplete.

**Continuation Prompt Template**:
```
Continue Plan NNN: [Plan Name].

Current status: Tasks 0-N complete. Tasks N+1-M pending.
Last completed: [what was just finished]
Next task: Task N+1: [task description]

Persistent files:
- Plan: .claude/user-plans/NNN-name.md (FULL specs for all remaining tasks)
- Project memory: CLAUDE.md
- [any other relevant files]
```
- NEVER reference "previous session context" or "original plan input"
- The plan file path IS the context -- new session reads it to get all specs

## Universal Technical Learnings

### WSL Process Termination
- **Signal priority**: SIGTERM (15) > SIGINT (2) > SIGQUIT (3) > SIGHUP (1) > SIGKILL (9)
- SIGKILL bypasses trap handlers - leaves 9p mounts broken if kas-build has them unmounted
- **Recovery**: `nix run '.#wsl-remount'` or `wsl --shutdown` from PowerShell

### Long-Running Task Strategy

Long-running tasks (>5 minutes expected duration) ARE allowed but require careful management:

**Monitoring Approach**:
- Poll for completion **infrequently** - approximately once per minute for tasks >5 minutes
- Monitor **process output** (not just completion status) to track progress and detect issues early
- Use `BashOutput` with filtering to capture meaningful progress indicators
- Context cost: BashOutput polling consumes 500-2000 tokens per poll, so infrequent checks are essential

**While Waiting**:
- **Continue working** on other aspects of the same task (parallel subtasks, documentation, planning)
- **Engage the user interactively** - explain what's happening, provide status updates, ask for feedback
- User should understand exactly what's running and have opportunity to intervene if needed
- Offer options: "The build is running. Would you like me to check on X while we wait?"

**Execution Patterns**:
- **Pattern 1**: Background process with periodic output monitoring (~1 min intervals)
- **Pattern 2**: Sub-agent delegation - agent monitors and returns ONLY summary
- **Pattern 3**: Fire-and-forget with user notification when likely complete
- **Pattern 4**: User runs in separate terminal, reports results back

**Avoid**:
- Polling every 30-60s for short tasks (wasteful)
- Silent waiting without user communication
- Assuming completion without checking output for errors

### Git Worktree Workflow
- **Use case**: Parallel work across Claude accounts (Pro/Max) without interference
- **Setup**: `git worktree add ~/src/project-pro feature/foo-pro`
- **Integration**: Merge, rebase, or cherry-pick between worktrees
- **Cleanup**: `git worktree remove`, `git branch -d`

### Claude Task Runner Artifacts
- `.claude-task-logs/` and `.claude-task-state` are local session state
- Should be gitignored (pattern `**/.claude` doesn't match `.claude-task-*`)
- ALWAYS stage flake changes before nix commands

### Claude Code Multi-Account Memory Architecture (2026-03-01)

**`~/.claude` symlink removed** (2026-03-01): Previously a home-manager `mkOutOfStoreSymlink` → `claude-runtime/.claude-{defaultAccount}/`, causing Claude Code to load CLAUDE.md twice (via `$CLAUDE_CONFIG_DIR` and `~/.claude` fallback). Fixed by making bare `claude` a wrapper (like `claudemax`/`claudepro`) that sets `CLAUDE_CONFIG_DIR` directly. No more `~/.claude` symlink needed.

**Each account has independent CLAUDE.md**: `.claude-max/CLAUDE.md`, `.claude-pro/CLAUDE.md`, `.claude-work/CLAUDE.md` are separate files with different content. The activation script preserves existing CLAUDE.md files and only creates from template if missing.

**Per-account symlinks still exist**: `~/.claude-max`, `~/.claude-pro`, etc. remain as convenience symlinks to `claude-runtime/.claude-{account}/`.

**Slash commands are on-demand**: Command content (`.claude/commands/*.md`) is only loaded when invoked via `/command`. The system-reminder lists all command NAMES (short descriptions), but the full content stays out of context until invoked. Do NOT remove commands to save context — they cost almost nothing until used.

## Session Workflow Protocol (CRITICAL - 2026-01-31)

**ONE TASK PER SESSION applies to user-plans only** — when working through `.claude/user-plans/` plan files across multiple sessions, complete one plan task per session then stop with a continuation prompt. This was violated in session 2026-01-31 by completing 4 unrelated tasks without stopping.

**Scope clarification (2026-04-03)**: This rule applies to **plan tasks spread across sessions**, NOT to executing an approved plan within a single session. When the user approves a plan (via ExitPlanMode or explicit "implement this plan") and the session has sufficient context, execute all plan tasks in sequence. The rule prevents Claude from autonomously deciding to start unrelated work after finishing a task — it does NOT prevent completing an approved multi-task plan the user asked to be implemented.

**Why This Matters**:
- **Context management**: Each task completion is natural breaking point for context refresh *across sessions*
- **User control**: User should direct work between *unrelated* tasks, not Claude autodeciding
- **Plan integrity**: Plans are designed with task boundaries for review/approval points *when spanning sessions*
- **Quality**: Fresh context per task reduces accumulated errors *for large plans*

**Correct Protocol (multi-session plans)**:
1. **Complete ONE plan task** (research, implementation, cleanup, etc.)
2. **Update memory** (project and user-global CLAUDE.md if learnings occurred)
3. **Update plan files** with task status
4. **Commit changes** with clear message
5. **Provide continuation prompt** in this format:
   ```
   Continue work on [project/task].

   Current status: [brief status]
   Last completed: [what was just finished]
   Next task: [what should happen next]

   [Context/blockers if any]
   ```
6. **STOP** - wait for user to start new session

**Approved plan execution (same session)**: When user says "implement this plan" → execute all tasks → commit → provide final summary+continuation prompt at end.

**Exception**: User explicitly grants permission to continue ("continue to next task", "keep going", etc.)

**Added to**: `/home/tim/src/converix-hsw/.claude/CLAUDE.md` with full protocol details

