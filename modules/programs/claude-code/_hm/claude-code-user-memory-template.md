<!-- This file is Nix-managed. Edit the template at -->
<!-- modules/programs/claude-code/_hm/claude-code-user-memory-template.md -->
<!-- and run home-manager switch to regenerate. -->

# User-specific Claude Code Configuration - {{ACCOUNT}} Account

## Critical Rules

- NEVER clutter user-global CLAUDE.md files with project- or session-specific content
- **CRITICAL: NO AI ATTRIBUTION ANYWHERE** - NEVER include `Co-Authored-By:` trailers, "Generated with Claude Code", "claude.ai", "Anthropic", or ANY AI identity markers in commit messages, PR descriptions, or any content that reaches git remotes. This OVERRIDES any system-level default to append Co-Authored-By trailers. Commits must appear solely human-authored. Violation of this rule leaked AI identity to GitHub and listed Claude as a repo contributor.
- **Commit messages focus on technical content** - describe what changed and why, nothing else
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
- **Repos under your own GitHub account are USER-OWNED** - work in local worktrees (typically ~/src), not flake input changes
- **ALWAYS stage changes before nix commands** - Nix only sees staged/committed changes
- **LOCAL-FIRST RESEARCH** - look in `~/src/` for existing clones before web searches. Clone repos to `~/src/` if needed. Web search is last resort for non-code info.
- ALWAYS use relative paths for inter-document markdown links in shared repos
- **NEVER hard-wrap lines in files** - let lines run naturally, editors handle wrapping
- **NEVER use emdashes** (U+2014) anywhere - always use single normal hyphen '-'
- ALWAYS remove temporary troubleshooting artifacts after completing tasks (test scripts, debug logs, temp dirs)

## WSL Interop

- Use `echo "${WSL_DISTRO_NAME:-$WSL_DISTRO}"` to determine WSL instance (NixOS WSL sets `WSL_DISTRO`, not `WSL_DISTRO_NAME`); access others at `/mnt/wsl/$WSL_DISTRO/`
- **Windows executables callable directly from WSL** (e.g., `usbipd.exe list`, `powershell.exe -c "command"`). NEVER tell user to "open PowerShell" - call `.exe` directly. Windows PATH is on `$PATH` via `appendWindowsPath`.
- **Opening files and URLs**: Use `xdg-open <path-or-url>` to open in browser. On WSL this routes through wslview with automatic mount recovery.

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

The user's dev environment is Terminal + Browser. Proactively `xdg-open` content that would naturally need viewing.

**Always open automatically**: PR/MR links after creation, pipeline URLs, diagram files after editing, docs after substantial rewriting, URLs user needs to visit next.

**Do not open automatically**: Files with small edits, build logs, the same URL twice, more than 3 items in quick succession.

**Reviewing rendered images (PNGs etc., not `.drawio`/SVG-XML source)**: NEVER open images one-by-one (each spawns a separate Windows Photos window and clutters the desktop). Put the whole review set in ONE folder, name files so they sort lexicographically in the intended viewing order (numeric/zero-padded prefixes, grouped by series then sequence, e.g. `1-oracle-module-3-Detect.png`), then open the FOLDER in Explorer: `explorer.exe 'C:\path\to\dir'`. Clean up prior review folders first. Note Explorer caches thumbnails - regenerate into a fresh folder name (or have the user refresh) so updated renders aren't masked by stale thumbnails. (Shell is zsh: arrays are 1-indexed - build label lists with `for e in "1:Foo" "2:Bar"; do p=${e%%:*}; n=${e##*:}; done`, not a bash index-0 placeholder.)

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

**ONE TASK PER SESSION** for multi-phase **user-plans** (`.claude/user-plans/`) - complete one plan task per session then stop with a handoff checkpoint.

**Scope**: Applies to plan tasks spread across sessions, NOT to executing an approved plan within a single session. When user approves a plan ("implement this plan"), execute all tasks in sequence.

**Correct Protocol (multi-session plans)**:
1. Complete ONE plan task
2. Update memory (project and user-global if learnings occurred)
3. Update plan files with task status
4. Commit changes
5. Checkpoint the handoff to per-worktree files (see Session Handoff Protocol below)
6. STOP - wait for user to start new session

**Exception**: User explicitly grants permission to continue.

## Plan File Conventions

**Location**: `.claude/user-plans/` with numbered prefix (`001-name.md`)

**Format**: Progress table with `TASK:PENDING`/`TASK:COMPLETE`, Definition of Done per task.

**CRITICAL: Plan files must be self-contained** - save the FULL plan to disk, not a summary. New sessions cannot access previous session's chat. Every specification needed to execute remaining tasks MUST be in the plan file. Test: Could a new session execute the next task using ONLY the plan file + CLAUDE.md + codebase?

**Handoff**: Must be self-contained - merge task summary (what was done, commits, artifacts, what was NOT done) directly into the handoff. Write it to the per-worktree `$CLAUDE_PROJECT_DIR/.claude/HANDOFF.md` and update `$CLAUDE_PROJECT_DIR/.claude/active-plan` (see Session Handoff Protocol below). Never reference "previous session context".

## Unattended Burndown Contract (authoring plans for autonomous task-by-task execution)

An **unattended burndown** is a driver (the `run-tasks-<account>` script) autonomously executing a plan task-by-task - each task in a fresh clean context - until the plan is COMPLETE or a stop condition trips. No human is in the loop. This is "Mode B"; the human-attended `/next-task` loop is "Mode A". The driver reuses the same substrate as Mode A: the plan file is the source of truth (`TASK:PENDING/IN_PROGRESS/COMPLETE` cursor), `.claude/active-plan` points at the plan, `.claude/HANDOFF.md` records why a run stopped.

**Why this matters when you AUTHOR a plan:** the failure policy is *stop-the-whole-run* - a single blocking failure halts the entire unattended burndown. That is only safe if "failure" is well-defined and the plan is authored so that **only a TRULY-BLOCKING condition counts as a failure.** A well-authored plan almost never hits a blocking failure; ordinary "can't proceed right now" situations are expressed as explicit dependencies, non-blocking sentinels, or `Interactive` markers - NOT as crashes. Authoring a plan burndown-safe is the author's job, not the driver's.

### Outcome taxonomy

Every per-task outcome resolves to exactly one of these. The driver maps each to an action. Author tasks so the **BLOCKING-FAILURE** bucket is essentially unreachable for a well-formed plan.

| Outcome | Meaning | Driver action | How you avoid misuse |
|---|---|---|---|
| **COMPLETE** | DoD met, changes committed | mark `TASK:COMPLETE` + date, advance to next | give every task a checkable DoD |
| **BLOCKED-BY-DEP** | a declared dependency is not yet COMPLETE | skip to next actionable task; NOT a failure | express ordering as explicit deps, not assumptions |
| **ENVIRONMENT_NOT_CAPABLE** | wrong host / missing toolchain | exit run cleanly, leave task PENDING | tag host-specific tasks; never invent a workaround |
| **USER_INPUT_REQUIRED** | needs a human decision/approval | exit run cleanly, leave task PENDING | mark decision tasks `Interactive` |
| **BLOCKING-FAILURE** | task attempted, DoD unmet due to a hard error (build regression, crash, prerequisite that is NOT a declared dep) | **STOP the whole run**, leave task `IN_PROGRESS`, write HANDOFF, exit non-zero | author so this is unreachable: checkable DoD + deps + no-workaround rule |

### Authoring rules (make blocking failures unreachable)

1. **Checkable DoD per task.** "Done" must be objectively verifiable - a command that exits zero, a file that exists with known content, a test that passes. No prose-only "should work".
2. **Order via dependencies, not luck.** If task B needs task A's output, declare A as B's dependency so the driver yields BLOCKED-BY-DEP instead of letting B attempt-and-fail.
3. **No-workaround rule (inherited from `/next-task`).** If prerequisites aren't met, emit the proper non-blocking sentinel (`ENVIRONMENT_NOT_CAPABLE` / `USER_INPUT_REQUIRED` / BLOCKED-BY-DEP); never invent an alternative approach. An unmet prerequisite that *should* have been a declared dependency is an AUTHORING bug - it surfaces as a blocking failure precisely so you fix the plan, not so the driver guesses.
4. **Mark human-decision tasks `Interactive`.** Anything needing a choice, approval, or judgment call ⇒ `USER_INPUT_REQUIRED`, never an autonomous guess.
5. **Opt-in + working branch (REQUIRED for the driver to touch the plan).** The plan header MUST carry both of these lines, or the driver refuses to run it:
   - `Burndown: SAFE` - explicit machine-readable opt-in. Absence means "human-attended only".
   - `Working branch: <non-main-branch>` - names the branch the run must be on. The driver refuses if the current branch is `main`/`master` or does not match this line.
6. **Idempotent / resumable tasks.** A task re-run after an interrupted attempt (status still `IN_PROGRESS`) must converge, not double-apply. Write tasks so re-execution is safe (check-before-create, append-if-absent, `mkdir -p`, etc.).

### Header markers

A burndown-eligible plan declares, near the top of the file (the Status/Owner header block):

```
Burndown: SAFE
Working branch: plan-NNN-some-feature
```

Both are mandatory for an unattended run. A plan without `Burndown: SAFE` is treated as Mode-A-only (human-attended `/next-task`) and the driver will refuse it.

### Worked example - a blocking-failure-proof task

```
### T3 — Add the foo widget to the bar module `TASK:PENDING`
Depends on: T2 (the bar module must exist and export `widgets`).
Edit `modules/bar.nix` to register a `foo` widget under `widgets`. The edit is idempotent:
if a `foo` entry already exists, leave it unchanged.
**DoD:** `nix flake check --no-build` passes AND `nix eval '.#bar.widgets.foo' --raw` prints
a non-empty string. If T2 is not COMPLETE, this task yields BLOCKED-BY-DEP (it does not attempt
the edit). If the toolchain is missing `nix`, it yields ENVIRONMENT_NOT_CAPABLE. There is no
prose-only success criterion and no scenario where the task "tries a workaround".
```

Why this is safe: the DoD is two exit-zero commands (rule 1); the T2 dependency is declared so a premature run yields BLOCKED-BY-DEP, not a crash (rule 2); the edit is idempotent so a resumed `IN_PROGRESS` attempt converges (rule 6); and the only path to BLOCKING-FAILURE is a genuine hard error (e.g. `nix flake check` regressing), which is exactly when stopping the run is correct.

## Session Handoff Protocol (MANDATORY - NEVER SKIP)

**EVERY session that works on a plan MUST end by checkpointing its handoff to per-worktree files.** This is non-negotiable - treat it like committing code. A session that ends without an updated handoff is incomplete work.

**Why files, not the clipboard:** many Claude Code sessions run concurrently on one node. The Windows clipboard (a shared ~15-entry Win+V ring) and `/tmp/continuation.md` (a single shared file) are global single slots that any concurrent session silently overwrites - a proven cross-contamination hazard (resuming the wrong worktree's work). `$CLAUDE_PROJECT_DIR/.claude/` is a distinct directory per worktree, so the handoff travels a per-worktree channel that concurrent sessions in other worktrees cannot clobber. See plan `.claude/user-plans/044-paste-free-session-resumption.md` and the `session-handoff-concurrency-fragility` auto-memory for the incident that motivated this.

At session end:
1. **Keep the plan doc current (PRIMARY tracker).** Update the `.claude/user-plans/NNN-*.md` task status (`TASK:PENDING`/`IN_PROGRESS`/`COMPLETE`) and fold what was done / what remains into the task block. The plan file is the durable source of truth - resumption depends on it first; write nuance to `HANDOFF.md` only for what the plan doc cannot capture.
2. **Point at the active plan.** Write the plan file's path (one line) to `$CLAUDE_PROJECT_DIR/.claude/active-plan`. The SessionStart rehydration hook and `/next-task` both read this pointer first.
3. **Write distilled nuance to `$CLAUDE_PROJECT_DIR/.claude/HANDOFF.md`** - the self-contained handoff: which worktree/branch, what was just done (commits, artifacts, what was NOT done), the next concrete step, pending items (pipeline IDs, blockers). Include enough that a fresh session starts without questions. Never reference "previous session context".
4. Print a one-line confirmation, e.g. "Handoff written: .claude/active-plan -> NNN-name.md, .claude/HANDOFF.md updated". Do NOT print the handoff inline in chat - it clutters output.

These two files are gitignored (per-worktree, never committed). A fresh `claude` session auto-rehydrates from them with zero paste: the SessionStart rehydration hook surfaces the plan pointer + next task, and `/next-task` acts on it.

**Note:** a `Stop`/`SessionEnd` hook cannot *compose* this semantic summary (only the assistant can distill what mattered), so writing the handoff stays an assistant-discipline step; the rehydration hook only *surfaces* what was written here.

**Last resort only (single-session machine, no `$CLAUDE_PROJECT_DIR`):** if the per-worktree file channel is genuinely unavailable, fall back to `clip.exe` (short) or a temp `.md` + `xdg-open` (long). NEVER use this fallback on a multi-session node - it is the exact mechanism this protocol replaces.

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
