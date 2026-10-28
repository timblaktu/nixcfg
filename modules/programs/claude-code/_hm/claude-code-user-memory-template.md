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
- **The Bash tool shell is zsh** - emit data with `printf '%s\n'`, NEVER `echo "$var"`, whenever the value may contain backslashes/escapes/control chars (JSON, regexes, serialized blobs, Windows UNC paths). zsh's builtin `echo` interprets backslash escapes by default and silently corrupts the data (e.g. collapses `\\` to `\`), which can misdirect a diagnosis. When reproducing a production script, match its interpreter/primitives (run under `bash -c`, or use shell-neutral `printf`).
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
- **Opening content - Firefox is for MARKDOWN ONLY; EVERYTHING ELSE uses `xdg-open`**: The ONE and ONLY reason we use Firefox is the `xicilion`/docu.md Markdown Viewer (mermaid 11.x). So Firefox is used EXCLUSIVELY to render MARKDOWN the user reviews - local `.md` files AND remote `.md` URLs - and for nothing else. For ALL OTHER content - general web pages, GitLab/GitHub MR/PR pages, pipeline/CI/job URLs, dashboards, issue links, ANY non-`.md` URL - use `xdg-open "<url>"`, which opens **Edge**, the user's Windows DEFAULT browser (kept for OTHER purposes). **NEVER open a non-markdown URL in Firefox** (this was a real mistake: an MR link was sent to Firefox - MR/PR/pipeline pages are web pages, so `xdg-open`). When you DO open markdown in Firefox, call `firefox.exe` directly (NOT `xdg-open`, which would hand it to Edge and not render it). Never assume Firefox is the default.
  - **CRITICAL (corrected 2026-10-28): `wslpath` is NOT installed in the Claude Bash-tool shell** (`command -v wslpath` => not found). The old recipe `firefox.exe "$(wslpath -w "$p")"` therefore expands to `firefox.exe ""` (EMPTY arg) and opens NOTHING - and since Firefox is already running the call still exits 0, so the failure is SILENT. DO NOT use `wslpath`. There is ONE way to open a WSL `.md` in Firefox - build a FIVE-slash `file://` URI directly and pass it as the firefox.exe argument:
    ```
    FF="/mnt/c/Program Files/Mozilla Firefox/firefox.exe"
    distro="$(printf '%s' "${WSL_DISTRO_NAME:-$WSL_DISTRO}" | tr '[:upper:]' '[:lower:]')"   # nixos
    p=/home/tim/src/<...>/doc.md          # absolute WSL path (keeps its leading /)
    timeout 25 "$FF" "file://///wsl.localhost/${distro}${p}" >/dev/null 2>&1   # FIVE slashes after file:
    ```
  - **firefox.exe ARGUMENT (to actually OPEN the file): the 5-slash `file://///wsl.localhost/<distro>/<abs-path>` form.** The 2-slash `file://wsl.localhost/...` gets its authority stripped (mangled to `file:///...`) and opens nothing; the 5-slash form preserves `wsl.localhost`. (This 5-slash URL is also a valid clickable/embedded link.)
  - **Chat clickable link (for the user to click in the terminal)**: `file://wsl.localhost/<distro>/<abs-path-without-leading-slash>` (2-slash form) - this is a DISPLAY link only, never needs opening by us.
  - If docu.md cannot read a `file://`-opened local file, serve over `http://localhost` instead.

## Nix and Git Safety

- **NEVER run nix commands concurrently** - no background nix tasks, no multiple nix Bash calls in same response. Concurrent nix evaluations cause OOM kills. A `nix-guarded` flock wrapper exists as safety net, but always serialize explicitly. Bypass with `NIX_NO_GUARD=1` if needed.
- **PROTECTED BRANCHES ARE PR/MR-ONLY - in EVERY repo (local or remote, public GitHub or internal GitLab), `main` and `master` receive changes ONLY through a pull/merge request.** NEVER `git push` directly to a protected branch; NEVER `git merge`/fast-forward a feature branch into local `main`/`master`. When a task, handoff, or user says "merge to main", that MEANS "open a PR/MR against main" - it is NOT authorization to push or to ff-merge. The only legal path: do the work on a feature branch, push the BRANCH, open the PR/MR, let review land it. **NEVER present pushing or merging directly to a protected branch as an option** (e.g. in an `AskUserQuestion`) - a forbidden action is not a choice; the PR is the only route, so just take it without asking. The gitSafety hook that blocks commit/push on `main` is the BACKSTOP, not the rule - do not rely on it to catch you.
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

The user's dev environment is Terminal + Browser. Proactively open content that would naturally need viewing, routed by TYPE (see "Opening content" under WSL Interop):
- **MARKDOWN the user reviews -> Firefox** (call `firefox.exe` directly; docu.md renders it). WSL-native local `.md` files go via the 5-slash `file://///wsl.localhost/<distro><abs-path>` recipe in WSL Interop (`wslpath` is NOT installed - never use it); remote `.md` URLs pass straight to `firefox.exe`.
- **EVERYTHING ELSE -> `xdg-open "<url>"`** (opens Edge, the user's default): MR/PR links after creation, pipeline/CI/job URLs, diagram images, dashboards, any non-`.md` URL the user needs next. **NEVER send a non-markdown URL to Firefox.**

**Always open automatically**: PR/MR links after creation, pipeline URLs, diagram files after editing, docs after substantial rewriting, URLs user needs to visit next.

**Do not open automatically**: Files with small edits, build logs, the same URL twice, more than 3 items in quick succession.

**Reviewing rendered images (PNGs)**: Put all in ONE folder, zero-padded names for sort order, open the FOLDER in Explorer: `explorer.exe 'C:\path\to\dir'`. Regenerate to a fresh folder name to bust Explorer's thumbnail cache. (zsh: arrays are 1-indexed.)

## Terminal-Width-Aware Output Formatting

All markdown tables in chat MUST fit within terminal width.

**Width detection**: `echo "$CLAUDE_TERMINAL_WIDTH"` (set by wrapper scripts).

**Strategy**: Calculate available width -> estimate table width -> if too wide, compress in order: abbreviate headers -> truncate cells -> remove columns -> split table -> switch to vertical key:value format.

File output may exceed terminal width (editors have horizontal scroll).

**Display-width discipline (HARD requirement, always):** in ANY fixed-width / columnar / aligned output to the user, reason in terminal DISPLAY CELLS, never in bytes or character count. Most emoji and many CJK/multibyte glyphs occupy 2 cells; a `U+FE0F` variation selector can flip a 1-cell symbol to 2 cells. `column -t` counts characters, not cells, so it silently MISALIGNS any field containing emoji - do not trust it there. Always sanity-check alignment by cell width.

**Emoji-set width (SOFT requirement):** when emoji carry meaning in aligned output, pick a set whose members ALL render the SAME display width - prefer default-emoji-presentation glyphs that are 2 cells wide WITHOUT a variation selector. Do not mix 2-cell emoji with 1-cell symbols or `U+FE0F`-dependent glyphs (e.g. ⚠️ ➡️ ⏭️); mixed widths break the column math.

## Annotated Stack/Runtime Tree Diagrams (for complex explanations)

For layered systems (runtime stacks, call paths, build pipelines), LEAD WITH a small ASCII tree annotating each layer, THEN prose. This is a strongly-held user preference. Format: `├─ layer  ──► role`; CAPS/emphasis on the layer being discussed. Use proactively for complex cases; skip for simple one-layer answers.

## Content Delivery for Copy-Paste

Do NOT put copy-paste content in chat as code-fenced blocks. Instead:
1. **clip.exe** for short content: `printf '%s' "content" | clip.exe` (use `printf`, not `echo` - see the zsh-echo rule under Critical Rules)
2. **temp .md file opened in Firefox** for long/formatted content: `firefox.exe "file://///wsl.localhost/${distro}${f}"` (5-slash form, see WSL Interop; `wslpath` is unavailable; NOT `xdg-open`, which opens Edge)

Does NOT apply when content is sent directly via API (e.g., `glab api`).

**ALWAYS print WSL paths as clickable `file://` URIs.** Any time a real filesystem path appears in a response (a temp file, plan, doc, script, artifact, memory file), render it as `file://wsl.localhost/<distro>/<abs-path-without-leading-slash>` so the user can click to open it - literal host `wsl.localhost`, distro LOWERCASE (resolve via `${WSL_DISTRO_NAME:-$WSL_DISTRO}`), forward slashes, NO leading slash, NO `\\`, NO `$`. The three-slash `file:///home/...` form is NOT clickable in MS Terminal - do not use it. (To OPEN a file in firefox.exe, use the 5-slash `file://///wsl.localhost/<distro><abs-path>` form - see WSL Interop; `wslpath` is unavailable, and the `\\wsl.localhost\...` backslash UNC form is NOT used by us.) This is not limited to close-out - it applies to every path printed.

## Presenting Decisions to the User (MANDATORY - single rule, supersedes any earlier decision-format guidance)

When you need the user to DECIDE something, the weight of the decision picks the format. There are exactly two modes; do not invent a third, and do not mix them.

**COMPLEX / CONSEQUENTIAL decisions** (a design gate, an architectural fork, a "which approach?" with real trade-offs, anything where the user must understand a mechanism to choose well): write a STANDALONE, easy-to-read markdown file and OPEN IT IN FIREFOX (call `firefox.exe` directly with the 5-slash form - `"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" "file://///wsl.localhost/${distro}<abs-path>.md"`, see WSL Interop; `wslpath` is unavailable - NOT `xdg-open`, which opens Edge, the user's system default) - do NOT explain inline in chat, and NEVER bury the explanation inside the `AskUserQuestion` prompt. The document, in this order:
1. **The problem, in plain language, lead with a concrete picture** - an ASCII sketch, a small table, or a worked example the user can grasp in seconds. Gloss every acronym on first use.
2. **The proposed fix** - what you want to do, in one or two plain sentences.
3. **Why THIS over the alternatives** - name the options you considered AND rejected, each with the reason. This is the part that earns trust; never hide the roads not taken.
4. **Before / after** - show the concrete change (diff, generated-output delta, config line) where one exists.
5. **Things to know / consequences** - side effects, blast radius, what becomes redundant, cost.
6. **What is NOT in scope / what still gates closure** - so the decision's boundaries are explicit.
7. **The question, last** - state it plainly, then list the options with your RECOMMENDATION FIRST and a one-line rationale each.
Then tell the user exactly which Firefox tab to look at plus the clickable `file://wsl.localhost/<distro>/...` link (the chat-link form, NOT the exe argument), and COLLECT THE DECISION via the `AskUserQuestion` tool (short option labels - the real explanation already lives in the doc). This markdown-in-browser treatment (Firefox + docu.md, not Edge) is the standard the user explicitly called "essentially perfect"; use it for every non-trivial decision, automatically, without being asked.

**QUICK / LOW-STAKES choices** (a naming nit, an obvious default, a yes/no with no hidden trade-off): a short paragraph of context in chat followed by the `AskUserQuestion` tool is fine. Do not manufacture a document for these.

Two hard rules across BOTH modes: (1) explain BEFORE asking, in plain language - the user must understand what you are talking about from prose/doc FIRST, then see a clean short decision; (2) actually USE the `AskUserQuestion` tool to collect the decision - do not narrate options in prose and move on. Keep it jargon-light.

## Task/Session Close-Out (MANDATORY)

End every completed task - and at minimum every working session - with a COMPACT, SCANNABLE status block, NOT prose. It REPLACES any multi-paragraph "What I did / Why / Evidence / Goal" essay. Depth belongs in the plan file + `.session-state/HANDOFF.md`, never in this block.

Format = fixed-field columns `<icon> <LABEL padded to 8> <content>` (content column = cell 12), NO table/box-drawing characters. One logical row per label, most important first; content MAY wrap onto continuation lines indented to the content column. All labels are <=8 cells so the column is uniform. Omit a row only if genuinely N/A.

GROUP A - session narrative (always):

```
✅ DONE      what changed (the deliverable, in plain terms)
🔎 EVIDENCE  the proof it works: a test passed / command output / observation
🟡 UNPROVEN  use INSTEAD of EVIDENCE when not yet proven - what's unconfirmed + why
👉 NEXT      the immediate next step
💡 WHY       one line, ONLY if the rationale isn't self-evident (usually omit)
```

GROUP B - task state (one row per reported task; icons mirror the user-plans state machine 1:1):

```
✅ COMPLETE  DoD met + committed                             (TASK:COMPLETE)
🔄 ONGOING   started / partial, resuming next                (TASK:IN_PROGRESS)
⏳ WAITING   a dependency / external work isn't done yet      (BLOCKED-BY-DEP)
🙋 DECISION  needs YOUR decision / approval before proceeding (USER_INPUT_REQUIRED / Interactive)
🚫 CANT-RUN  wrong host / missing toolchain here              (ENVIRONMENT_NOT_CAPABLE)
⛔ FAILED    hard error: build regression / crash / missing non-dep prereq (BLOCKING-FAILURE)
```

WAITING vs DECISION (NOT the same - do not double-report): WAITING = the blocker clears WITHOUT your input (another in-plan task, a running job/build); the ball is not in your court. DECISION = nothing clears until YOU act (a choice, approval, credential, manual step). If a WAITING chain bottoms out in a human decision, report only the DECISION (the actionable root) and drop the WAIT it causes - collapse to the single state that tells you what, if anything, YOU must do.

Icons: all are default 2-cell emoji with NO variation selector so columns align (see the display-width + emoji-set requirements under Terminal-Width-Aware Output Formatting). Gloss any acronym/tool/file name on first use. Definition-of-Done requirement.

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

**BATCH INDEPENDENT TASKS; SERIALIZE DEPENDENT ONES.** For multi-phase **user-plans**
(`user-plans/`), the unit of a session is the **independent frontier**, not a single task.
When several actionable tasks are mutually independent (no dependency edge between them) and
each task's declared dependencies are all `TASK:COMPLETE`, execute them **together in one
session** - concurrently, without asking - and fall back to one-at-a-time only for tasks that
genuinely depend on each other.

- **Independent + deps-satisfied => run concurrently now.** Fan out parallel sub-agents; when
  tasks mutate files that would collide, give each its own git worktree (see Git Worktree
  Workflow), then integrate. No permission needed - independence is the license.
- **Dependent => serialize.** A task whose declared dep is not yet `TASK:COMPLETE` yields
  BLOCKED-BY-DEP and is left until its dependency lands; never attempt it early.
- **Per-task semantics stay individual.** Each task in a batch is completed, marked
  `TASK:COMPLETE` with today's date, and committed on its own; `Interactive`/USER_INPUT_REQUIRED,
  ENVIRONMENT_NOT_CAPABLE, and BLOCKED-BY-DEP are decided per task, not per batch.

**Scope**: Applies to plan tasks spread across sessions. When the user approves a plan
("implement this plan"), execute all tasks respecting dependencies (independent ones in parallel).

**Correct Protocol (multi-session plans)**:
1. Identify the actionable frontier: all `TASK:IN_PROGRESS` (resume first) plus every
   `TASK:PENDING` whose declared deps are all COMPLETE.
2. Group the mutually-independent members; execute each group concurrently (sub-agents / worktrees).
3. For each finished task: update memory if learnings occurred, set `TASK:COMPLETE` + today's
   date, commit that task's changes.
4. When the frontier is exhausted (only dependency-blocked or Interactive tasks remain),
   checkpoint the handoff to per-worktree files (see Session Handoff Protocol) and STOP.

**Exception**: none needed for parallelism - independence is self-authorizing. Stop early only if
the user asks, or the remaining frontier is empty/blocked/Interactive.

## Plan File Conventions

**Location**: `user-plans/` with numbered prefix (`001-name.md`)

**Format**: Progress table with `TASK:PENDING`/`TASK:COMPLETE`, Definition of Done per task.

**CRITICAL: Plan files must be self-contained** - save the FULL plan to disk, not a summary. New sessions cannot access previous session's chat. Every specification needed to execute remaining tasks MUST be in the plan file. Test: Could a new session execute the next task using ONLY the plan file + CLAUDE.md + codebase?

**Handoff**: Must be self-contained - merge task summary (what was done, commits, artifacts, what was NOT done) directly into the handoff. Write it to the per-worktree `$CLAUDE_PROJECT_DIR/.session-state/HANDOFF.md` and update `$CLAUDE_PROJECT_DIR/.session-state/active-plan` (see Session Handoff Protocol below). Never reference "previous session context".

## Unattended Burndown Contract

Plans opt in with these two header lines (driver refuses if absent or if current branch is main/master):
```
Burndown: SAFE
Working branch: plan-NNN-some-feature
```
Outcomes: COMPLETE, BLOCKED-BY-DEP, ENVIRONMENT_NOT_CAPABLE, USER_INPUT_REQUIRED, BLOCKING-FAILURE.
BLOCKING-FAILURE stops the entire run; author plans so it is unreachable (checkable DoD, declared deps, no-workaround rule, idempotent tasks). Non-blocking states: BLOCKED-BY-DEP (dep not COMPLETE), ENVIRONMENT_NOT_CAPABLE (wrong host/toolchain), USER_INPUT_REQUIRED (Interactive tasks).
Run: `run-tasks-<account> <plan.md> --burndown`. Resume: re-run the same command (plan `TASK:` cursor is the state).
Invoke `/burndown-contract` skill for the full spec when authoring a burndown-eligible plan or debugging a run.

## Session Handoff Protocol (MANDATORY - NEVER SKIP)

**EVERY session that works on a plan MUST end by writing to per-worktree files** (concurrent sessions share the clipboard - cross-contamination hazard). At session end:
1. **Update the plan doc.** `user-plans/NNN-*.md` task status + fold what was done/remains into the task block.
2. **Point at the active plan.** Write the plan file's path to `$CLAUDE_PROJECT_DIR/.session-state/active-plan`.
3. **Write `$CLAUDE_PROJECT_DIR/.session-state/HANDOFF.md`** - self-contained: worktree/branch, commits, what was NOT done, next concrete step, blockers. Never reference "previous session context".
4. Print "Handoff written: .session-state/active-plan -> NNN-name.md, .session-state/HANDOFF.md updated".

Last resort only (no `$CLAUDE_PROJECT_DIR`): `clip.exe` (short) or Firefox temp `.md` (long). NEVER on a multi-session node.

## Memory Index Compaction (MEMORY.md auto-memory)

When MEMORY.md is flagged too big: (1) DROP stale entries first (DONE/LANDED/MERGED with no lasting lesson; per-plan status/NEXT=/cursor lines do NOT belong here - move to plan files), (2) MERGE near-duplicates, (3) ONLY THEN move long active entries to topic files. NEVER shave active entries by word-trimming - drop inactive entries instead. 200-line count binds before bytes, so fewer entries is the lever. When unsure if stale, KEEP it.

## Long-Running Task Strategy

Long-running tasks (>5 min) are allowed but require management:
- Poll ~once/minute, monitor process output for progress and errors
- Continue other work while waiting, engage user interactively
- Patterns: background + periodic monitoring, sub-agent delegation, fire-and-forget, user runs separately

## Memory Index Curation (memory/MEMORY.md)

The file-based memory store is **SHARED across all worktrees of a repo** - it is keyed by the
git common-dir (the main worktree), NOT by the current directory. Every worktree of the same
repo (e.g. `repo`, `repo-featureA`, `repo-featureB`) reads and writes the SAME `memory/MEMORY.md`.
Entries must therefore be **worktree-agnostic and repo-general**; anything specific to one
worktree, branch, or plan does NOT belong here. The harness loads MEMORY.md in full every session,
capped at 25 KB / 200 lines (whichever first) - NOT user-configurable. Curate MEMORY.md as a
working set, not an archive:

**SCOPE - what MEMORY.md is FOR (and NOT for).** It holds only GENERAL, cross-plan, repo-wide
knowledge: durable behavioral feedback (`feedback`), reusable technical facts and external pointers
(`reference`), and genuinely cross-plan project constraints not derivable from any single plan file
or the code (`project`). **It is NOT a per-plan tracker. Do NOT index per-plan status, task cursors,
`NEXT=` pointers, or branch/MR/pipeline state here.** That state has a purpose-built, per-worktree,
durable home in the plan file `user-plans/NNN-*.md`, which the SessionStart resume hook and
`/next-task` read first; duplicating it here overflows the ONE shared index (every worktree of the
repo appends to the same file - the diagnosed cause of MEMORY.md overflow). Keep a `project` entry
only for a constraint that spans plans (e.g. "this repo's CI must stay reproducible outside CI"),
never for "where plan NNN stands right now".

- **ONE line per entry** - a title link + a short hook, never a paragraph. All detail lives in the topic file (recalled on demand), not the index. Write the one-liner from the start; do not draft a paragraph and then shave it.
- **Demote, don't shave.** Under size pressure, DROP or collapse entries for COMPLETED / merged / superseded work (the topic file persists for on-demand recall) rather than word-trimming live entries. The 200-line count usually binds before bytes, so fewer entries - not shorter ones - is the real lever.
- **Link liberally with `[[slug]]`; merge near-duplicates; delete entries proven wrong.** Orphaned topic files (no index line and no inbound `[[link]]`) are dead weight - drop or re-link them.
- **Bulk curation is cohesive + signed-off, never silent.** A single-entry update as you work is routine. But a periodic sweep that drops/merges MANY entries: analyze -> classify (keep/merge/drop) -> get owner sign-off -> then apply. No silent mass-deletes; the auto-memory has no review gate (unlike git-tracked files), so accretion and reactive shaving are the owner's diagnosed cause of signal loss.

