# User-specific Claude Code Configuration for User's Anthropic MAX Account

## Critical Rules

- **MANDATORY RESPONSE ENDING**: EVERY response MUST end with a ready-to-paste prompt for the next session after context is cleared. NO EXCEPTIONS.
- NEVER clutter this user-global CLAUDE.md with project- or session-specific content
- **NEVER include AI attribution in commit messages** - NO "Generated with Claude Code", NO "Co-Authored-By: Claude", NO emoji robots. Commit messages must appear entirely human-authored.
- ALWAYS use timestamp format: `date +%Y-%m-%d\ %H:%M:%S\ %Z`
- ALWAYS use rg and fd for file searching (never grep/find or Search/Find tools)
- ALWAYS ensure shell commands support both bash AND zsh
- ALWAYS properly escape or quote special shell characters
- **Screenshots (WSL)**: Find dynamically with `fd -t f -e png -e jpg -e jpeg . '/mnt/c/Users/'*/OneDrive*/Pictures/Screenshots* -d 1 --exec stat --printf='%Y %n\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-`
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
- **COMMIT DIAGRAM CHANGES IMMEDIATELY** - `.drawio.svg` files with uncommitted pages can be lost if `git checkout` is used; commit after each significant diagram edit

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

## glab Credential Helper Username Mismatch (2026-02-13, RESOLVED)

**Problem**: `git push` to `https://git.panasonic.aero/blackt1/hsw.git` failed because
glab's `auth git-credential` helper validates the incoming git username against its own
internal user (`tim` from whoami fallback) and rejects mismatches.

**Root cause**: glab (unlike gh) enforces username matching in credential helper.
When git pre-fills `username=X`, glab compares X against its own user and rejects if different.

**Fix**: Set `gitAuth.gitlab.git.userName = null` in pa161878-nixos.nix (nixcfg commit `d1ae2d9`).
This removes `credential.*.username` from git config entirely. Without a pre-filled username,
glab skips the comparison and provides credentials directly. GitLab PAT auth is token-based,
so the username glab returns (`tim`) is irrelevant.

**Same commit also added**: `programs.git.includes` with `hasconfig:remote.*.url` conditional
to set `user.email = timothy.black@panasonic.aero` for repos with Panasonic Aero remotes.

## Embedded Linux Tools Document Revision (2026-01-29)

**Project**: Simplifying ADR-001 from ~17,000 words across 18 files to ~4,000-5,000 words single document

**Progress**: 8 of 12 tasks complete, 3 skipped (Sessions 2-9)
- ✓ TASK:001-analyze-structure (Session 2): Content outline created
- ✓ TASK:002-draft-introduction-context (Session 3): Introduction + Context (~1,100 words)
- ✓ TASK:003-write-requirements (Session 4): Requirements table with 4 hard constraints (~180 words)
- ✓ TASK:004-write-evaluation-criteria (Session 5): All 11 criteria with weights and definitions (~850 words)
- ✓ TASK:005-write-options-overview (Session 6): Debian/Nix/Yocto descriptions (~530 words)
- ✓ TASK:006-create-comparison-matrix (Session 7): Full comparison matrix for all 11 criteria (~1,500 words)
- ✓ TASK:007-write-scoring-recommendation (Session 8): Yocto/Isar recommendation with rationale (~450 words)
- ✗ TASK:008-add-implementation-guidance (Session 9): SKIPPED - implementation guidance ≠ ADR
- ✗ TASK:009-handle-edge-case-content (Session 9): SKIPPED - operational docs, not decision content
- ✗ TASK:010-simplify-appendices (Session 9): SKIPPED - main body has adequate explanations
- ✓ TASK:011-visual-aids (Session 9): Added Pipeline Implementation Comparison + Isar vs Yocto diagrams

**ADR Core Messages** (for final review cohesion check):
1. **Framing**: Universal pipeline concept—tools differ in implementation
2. **Comparison**: 11-criterion matrix comparing Debian/Nix/Yocto
3. **Recommendation**: Yocto/Isar for team alignment, embedded ops maturity, strategic flexibility

**Current document state** (`embedded-linux-tools-DRAFT.md`):
- Total: ~4,230 words
- Sections complete: Introduction, Context, Requirements, Evaluation Criteria, Options Overview, Comparison Matrix (with Pipeline Implementation diagram), Scoring and Recommendation (with Isar vs Yocto diagram)
- 3 diagrams: Universal Pipeline, Pipeline Implementation Comparison, Isar vs Yocto

**Next task**: TASK:013-integrate-elxr (NEW - Session 10 decision)
- Add Wind River eLxr as 4th evaluated option
- Score against all 11 criteria
- Update comparison matrix
- Revise recommendation section if needed

**Session 10 Insights** (2026-01-30):
- eLxr analysis exists: `docs/wind-river-elxr-analysis.md` (~2,600 words)
- Initial assessment: eLxr appeared to fail Target Platform Support requirement
- **User clarification**: "Not validated" ≠ "won't work"
  - AMD V3000: Standard x86_64, will work despite no explicit validation
  - Jetson Orin Nano: Same T234 SoC family as AGX Orin, same JetPack 6
  - NVIDIA/Debian gap exists for ALL options equally (L4T is Ubuntu-based)
- **Decision**: eLxr DOES meet hard requirements; evaluate as 4th option
- eLxr represents distinct architectural point: binary assembly + OSTree + edge-purpose-built

## Buildroot Binary Package Architecture (2026-01-31)

**Key Learning**: Buildroot CAN install pre-built binaries on a per-package basis, but lacks systematic binary package workflow abstraction.

**What Buildroot CAN do:**
- Individual packages can override `_BUILD_CMDS` and `_INSTALL_TARGET_CMDS` to download/install binaries
- Custom `.mk` files can work with pre-built tarballs or even .deb files
- See [Ken Muse guide](https://www.kenmuse.com/blog/creating-a-custom-buildroot-package-for-binaries/)

**What Buildroot CANNOT do** (vs Yocto/Isar):
- Systematically substitute binary package operations for source compilation across entire build
- Provide package format abstraction layer (what enables Isar to use .deb within BitBake)
- Cache build artifacts between builds: ["does not implement any mechanism to 'cache' build results"](https://www.yoctoproject.org/wp-content/uploads/sites/32/2023/10/belloni-petazzoni-buildroot-oe_0-min.pdf)
- Provide runtime package manager on target (no apt/dpkg): ["does not have a package manager like Ubuntu's apt-get"](https://trac.gateworks.com/wiki/buildroot)

**The Critical Distinction**:
- Yocto/BitBake: Task-based infrastructure where entire task chains can be replaced (what Isar exploits)
- Buildroot: Assumes source-to-rootfs; per-package overrides possible but unsupported workarounds
- Output characterized as ["a root filesystem image, nothing more; firmware generator"](https://blog.conan.io/2019/08/27/Creating-small-Linux-images-with-Buildroot.html)

**Correct Framing**: "Buildroot's architecture prioritizes simplicity over systematic binary package workflows" (not "Buildroot cannot install binaries")

## Session Workflow Protocol (CRITICAL - 2026-01-31)

**ONE TASK PER SESSION is mandatory** - violated in session 2026-01-31 by completing 4 tasks without stopping

**The Problem**:
- Completed 4 tasks in single session (Buildroot research, Task E0 update, cleanup, plan 002 completion)
- Did not stop after each task to ask user what to do next
- Created long response instead of clean task completion handoffs

**Why This Matters**:
- **Context management**: Each task completion is natural breaking point for context refresh
- **User control**: User should direct work between tasks, not Claude autodeciding
- **Plan integrity**: Plans are designed with task boundaries for review/approval points
- **Quality**: Fresh context per task reduces accumulated errors

**Correct Protocol**:
1. **Complete ONE task** (research, implementation, cleanup, etc.)
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

**Exception**: User explicitly grants permission to continue ("continue to next task", "keep going", etc.)

**Added to**: `/home/tim/src/converix-hsw/.claude/CLAUDE.md` with full protocol details

