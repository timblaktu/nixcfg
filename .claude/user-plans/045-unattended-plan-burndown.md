# 045 - Unattended Long-Running Plan Burndown (Mode B)

Status: IN_PROGRESS (fleshed out from stub 2026-06-21; ready for task execution)
Owner: nixcfg Claude Code config (`modules/programs/claude-code/`)
Depends on: `044-paste-free-session-resumption.md` (the shared substrate) — **SATISFIED**
(044 COMPLETE + permanently deployed + hook verified, 2026-06-21).
Working branch for execution: TBD per-task; **never main** (see T4). Suggested: `plan-045-unattended-burndown`.

---

## 1. Problem / goal

044 makes a *human-attended* loop paste-free: end a session, start a fresh one, it auto-rehydrates
the active plan's next task (Mode A). 045 removes the human from the loop (Mode B): a **driver
autonomously burns down a pre-defined plan task-by-task, unattended, over a long run**, each task in a
fresh clean context, until the plan is complete (or a stop condition trips).

Same `checkpoint → fresh session → rehydrate` cycle as 044, different DRIVER + guardrails. Reuses
044's substrate unchanged: plan file as source of truth (`TASK:PENDING/IN_PROGRESS/COMPLETE` cursor),
per-worktree `.claude/active-plan` + `HANDOFF.md`, the `next-task` status-transition discipline
(flip→commit→execute→mark→commit).

**Central design tenet (user directive 2026-06-21):** the failure policy is *stop-the-whole-run*, but
that is only safe if **"failure" is well-defined and a plan is authored so that only a TRULY-BLOCKING
condition counts as a failure.** Therefore 045's first deliverable is a **plan-authoring contract**
(embedded in the plan-generating context), not a driver tweak. A well-authored plan should almost
never hit a "blocking failure"; ordinary "can't proceed" situations must be expressed as explicit
dependencies, non-blocking sentinels, or Interactive markers — NOT as crashes.

## 2. Current state (researched 2026-06-21) — what already exists vs the gaps

The seed is much further along than the stub implied. `modules/programs/claude-code/_hm/task-automation.nix`
already ships **two** pieces:

**(a) `/next-task` slash command (`nextTaskMd`)** — the interactive/attended pull half. Already (044 T4)
honors `.claude/active-plan` first, then CLAUDE.md auto-detection. Emits sentinels
`ENVIRONMENT_NOT_CAPABLE`, `USER_INPUT_REQUIRED`, `ALL_TASKS_DONE`. Has the "no workarounds /
prerequisites-unmet ⇒ ENVIRONMENT_NOT_CAPABLE" rule.

**(b) `run-tasks-<account>` script (`mkRunTasksScript`, ~900 lines)** — the unattended driver SEED. Already:
- Loops `claudeAccount -p --output-format json --permission-mode bypassPermissions "<prompt>"`.
- Modes: `single` (default), `-n N` (count), `-a/--all`, `-c/--continuous`, `--task ID`, `--list` (fzf), `--dry-run`.
- Safety limits (Nix options under `taskAutomation.safetyLimits`): `maxIterations=100`, `maxRuntimeHours=8`,
  `maxConsecutiveRateLimits=5`, `rateLimitWaitSeconds=300`, `maxRetries=3`, `delayBetweenTasks=10`.
- Status tokens recognized: `TASK:PENDING|IN_PROGRESS|COMPLETE` plus `SKIPPED|BLOCKED|DEFERRED`.
- Protocol sentinels (anchored `^TOKEN` matching): `ALL_TASKS_DONE`, `ENVIRONMENT_NOT_CAPABLE`,
  `USER_INPUT_REQUIRED`, `TASK_ALREADY_COMPLETE`, `TASK_NOT_FOUND`.
- Rate-limit detection (JSON subtype + text) + consecutive-rate-limit circuit breaker; per-run state
  file (`.claude-task-state`) + per-task logs (`.claude-task-logs/`); Ctrl+C trap with summary.

**Gaps 045 must close (the orthogonal hard parts):**
1. **Failure semantics contradict the chosen policy.** Main loop generic-failure branch
   (`task-automation.nix` ~line 1075-1079, `*)` case) prints `"Continuing despite failure..."` and
   loops on — i.e. *skip-and-continue*. User policy is *stop-the-whole-run*. And a generic non-zero
   exit / `is_error` falls into this branch undifferentiated → "failure" is not well-defined.
2. **No plan-authoring contract for burndown.** Nothing teaches plan authors what makes a task
   "blocking-failure-proof" (checkable DoD, dependencies-not-crashes, Interactive markers, opt-in).
   This is the user's central ask and lives in the plan-generating context
   (`claude-code-user-memory-template.md` → CLAUDE.md "Plan File Conventions").
3. **No opt-in gate.** The driver will burn down ANY plan file handed to it. A plan must explicitly
   declare itself burndown-safe before an unattended run is allowed.
4. **Not integrated with 044's substrate.** `run-tasks` requires an explicit `<plan-file>` arg (no
   `.claude/active-plan` fallback like `next-task` has); it never writes `.claude/HANDOFF.md` on
   stop/finish (so a halted run leaves no rehydration breadcrumb for the human or the SessionStart hook).
5. **No branch isolation.** `--permission-mode bypassPermissions` + autonomous `git commit` with no
   guard could commit on `main`/`master`, violating the project's "NEVER work on main" rule.
6. **Prompt duplication / drift.** The inline `PROMPT`/`task_prompt` strings duplicate `nextTaskMd`'s
   logic but with a DIFFERENT sentinel vocabulary and no `active-plan` awareness — they can drift.
7. **First-turn mechanism unconfirmed for headless.** 044 §10 #7 left `initialUserMessage` disproven
   *interactively* but unconfirmed for `-p` mode; `claude -p "<prompt>"` (explicit arg) is the safe
   default but should be re-verified as the committed mechanism.

## 3. Design decisions (resolved during drafting)

- **D1 — Driver home: HARDEN the existing `run-tasks-<account>` script** (in-repo, Nix-generated), NOT
  a greenfield systemd unit or new wrapper flag. Rationale: it already implements 90% of Mode B
  (loop, limits, sentinels, rate-limit handling, state/logs). A thin optional `--burndown <plan>`
  alias and/or a systemd-user oneshot can wrap it LATER (T6, optional) once semantics are correct.
  (Resolves §3-stub "driver home" open question.)
- **D2 — Failure policy: STOP-THE-WHOLE-RUN on a blocking failure** (user directive). On a blocking
  failure: leave the task `TASK:IN_PROGRESS`, write `.claude/HANDOFF.md` with the failure context,
  print the summary, exit non-zero. Do NOT advance. (Resolves §3-stub "failure handling".)
- **D3 — "Failure" is defined by a TAXONOMY (see §4), and the contract pushes authors to make blocking
  failures rare.** Non-blocking outcomes (wrong host, needs-human, unmet-dependency) are first-class
  sentinels that exit/῾skip CLEANLY, never "failure".
- **D4 — Opt-in marker.** A plan is burndown-eligible only if it carries an explicit machine-readable
  marker (proposed: a line `Burndown: SAFE` in the plan header, plus a required `Working branch:`
  line naming a non-main branch). The driver refuses (exit non-zero, no work) if the marker is absent
  or the working branch is main/master. (Resolves §3-stub "safe to auto-burn-down".)
- **D5 — Branch isolation.** Driver asserts `git rev-parse --abbrev-ref HEAD` ∉ {main, master} AND
  matches the plan's declared `Working branch:` before running. Refuse otherwise.
- **D6 — First-turn mechanism: `claude -p "<prompt>"`** is the committed mechanism (already what
  `run-tasks` uses). `initialUserMessage` is re-verified in `-p` mode in T5 but NOT depended upon.
- **D7 — SessionStart hook interaction.** 044's resume hook should be LEAN/no-op under headless `-p`
  burndown to avoid double-driving (the driver already injects the task via its prompt). Verify the
  hook's `source` discrimination; if `-p` runs surface as a matcher the hook fires on, gate it.

## 4. The Unattended Burndown Contract (outcome taxonomy) — the heart of 045

Every per-task outcome MUST resolve to exactly one of these. The driver maps each to an action; the
**plan-authoring contract** (T1) teaches authors to design tasks so the "blocking failure" bucket is
essentially unreachable for a well-formed plan.

| Outcome | Meaning | Driver action | How authors avoid misuse |
|---|---|---|---|
| **COMPLETE** | DoD met, changes committed | mark `TASK:COMPLETE`+date, advance | give every task a checkable DoD |
| **BLOCKED-BY-DEP** | a declared dependency is not yet COMPLETE | skip to next actionable; not a failure | express ordering as explicit deps, not assumptions |
| **ENVIRONMENT_NOT_CAPABLE** | wrong host/toolchain | exit run cleanly, leave PENDING | tag host-specific tasks; never workaround |
| **USER_INPUT_REQUIRED** | needs a human decision | exit run cleanly, leave PENDING | mark decision tasks `Interactive` |
| **BLOCKING-FAILURE** | task attempted, DoD unmet due to a hard error (build regression, crash, prerequisite that is NOT a declared dep) | **STOP whole run**, leave `IN_PROGRESS`, write HANDOFF, exit non-zero | author so this is unreachable: checkable DoD + deps + no-workaround rule |

**Authoring rules the contract must state (T1 writes these into the plan-generating context):**
1. **Checkable DoD per task.** "Done" must be objectively verifiable (a command, a file state, a test).
   No prose-only "should work".
2. **Order via dependencies, not luck.** If task B needs A's output, declare A as B's dependency so the
   driver yields BLOCKED-BY-DEP instead of letting B fail.
3. **No-workaround rule (inherited from `next-task`).** If prerequisites aren't met, emit the proper
   non-blocking sentinel; never invent alternative approaches. Unmet prereq that *should* have been a
   dependency is an AUTHORING bug, surfaced as a blocking failure precisely so it's fixed.
4. **Mark human-decision tasks `Interactive`.** Anything needing a choice/approval ⇒ `USER_INPUT_REQUIRED`,
   not an autonomous guess.
5. **Opt-in + working branch.** Header must carry `Burndown: SAFE` and `Working branch: <non-main>` for
   the driver to touch it.
6. **Idempotent / resumable tasks.** A task re-run after an interrupted attempt (status still
   `IN_PROGRESS`) must converge, not double-apply.

## 5. Tasks (Progress Tracking)

| Task | Name | Status | Date | Model |
|------|------|--------|------|-------|
| T1 | Author the Unattended Burndown Contract in the plan-generating context | TASK:COMPLETE | 2026-06-21 | |
| T2 | Reconcile driver failure semantics with stop-the-whole-run + taxonomy | TASK:PENDING | | |
| T3 | Add opt-in gate + branch isolation to the driver | TASK:PENDING | | |
| T4 | Integrate driver with 044 substrate (active-plan fallback + HANDOFF on stop) | TASK:PENDING | | |
| T5 | Re-verify headless first-turn mechanism; gate 044 hook under `-p` | TASK:PENDING | | |
| T6 | Observability + resume; optional `--burndown` alias / systemd-user oneshot | TASK:PENDING | | |
| T7 | End-to-end validation on a throwaway burndown-safe fixture plan | TASK:PENDING | | |

### T1 — Author the Unattended Burndown Contract `TASK:COMPLETE` (2026-06-21)
Write §4's taxonomy + authoring rules into the **plan-generating context** so every future plan is
authored burndown-safe. Primary file: `modules/programs/claude-code/_hm/claude-code-user-memory-template.md`
(the source of CLAUDE.md "Plan File Conventions" / "Session Handoff Protocol"). Add a new
"Unattended Burndown Contract" subsection: the outcome taxonomy table, the 6 authoring rules, the
`Burndown: SAFE` + `Working branch:` header markers, and a worked example of a blocking-failure-proof
task. Cross-reference `next-task`'s no-workaround rule. Also extend the `commands/planning/plans.md`
summary command to surface each plan's `Burndown:` eligibility.
**DoD:** template renders (regenerated CLAUDE.md contains the new section verbatim); `nix flake
check --no-build` passes; a human can read the section and author a burndown-safe task without seeing
this plan. NOT in scope: changing the driver (that's T2-T4).

**Findings / what was done (2026-06-21):**
- Added the **"Unattended Burndown Contract"** subsection to
  `modules/programs/claude-code/_hm/claude-code-user-memory-template.md`, placed between
  "Plan File Conventions" and "Session Handoff Protocol". Contents: Mode-A/Mode-B framing, the
  stop-the-whole-run rationale, the 5-row outcome taxonomy table (COMPLETE / BLOCKED-BY-DEP /
  ENVIRONMENT_NOT_CAPABLE / USER_INPUT_REQUIRED / BLOCKING-FAILURE), the 6 authoring rules
  (checkable DoD, deps-not-luck, no-workaround [cross-refs `/next-task`], `Interactive` markers,
  opt-in+working-branch, idempotent/resumable), the `Burndown: SAFE` + `Working branch:` header
  marker spec, and a worked blocking-failure-proof task example with an explanation of why it's safe.
- Extended `modules/programs/claude-code/_hm/commands/planning/plans.md`: the summary command now
  reads each plan's `Burndown:` line (`rg -m1 '^Burndown:'`) + `Working branch:`, and annotates the
  plan row with a `⏩`/`[BD]` marker so eligibility is visible at a glance.
- **DoD verification:** rendered the template through the exact activation transform
  (`builtins.replaceStrings ["{{ACCOUNT}}"] ["MAX"] (readFile template)`) → built store path
  `…-claude-memory-max.md`; confirmed 9 matching lines for the new section and 0 residual
  `{{ACCOUNT}}` tokens (verbatim render). `nix flake check --no-build` → `all checks passed!`
  (exit 0). The section is self-contained and authorable without reading this plan.
- NOTE: the live runtime files (`claude-runtime/.claude-*/CLAUDE.md`) are gitignored generated
  artifacts produced on the next `home-manager switch`; this host's home config lives in the work
  flake, so they were not regenerated in-place here. The committed template is the source of truth
  and the faithful render was verified above.
- **Marker convention decided** (resolves part of §6 bikeshed): plain header lines
  `Burndown: SAFE` and `Working branch: <branch>` in the Status/Owner block. Simple, greppable,
  no fenced metadata block. T2-T3 consume these. Note: THIS plan (045) does not yet carry the
  markers because Mode B is not functional until T2-T6 land; add them once the driver enforces
  them, when 045 itself could be burned down.

### T2 — Reconcile driver failure semantics `TASK:PENDING`
In `task-automation.nix` `mkRunTasksScript`: replace the generic `*)` "Continuing despite failure..."
branch with the §4 mapping. Introduce a distinct return code for BLOCKING-FAILURE that triggers
stop-the-whole-run: print summary, `save_state ... "blocking_failure"`, leave the task `IN_PROGRESS`,
exit non-zero. Keep BLOCKED-BY-DEP (advance) and the existing clean-exit sentinels. Add a
`--on-failure {stop|skip}` flag defaulting to `stop` (so the legacy skip behavior is opt-in, not lost).
Unify the inline `PROMPT`/`task_prompt` sentinel vocabulary with `nextTaskMd` (gap §2.6) so authoring
contract ↔ driver agree on tokens.
**DoD:** `nix flake check --no-build` passes; dry-run shows the new flag; a fixture task that exits
non-zero halts the run (verified in T7) instead of continuing. Document the return-code table inline.

### T3 — Opt-in gate + branch isolation `TASK:PENDING`
Driver pre-flight: refuse to run unless the plan header has `Burndown: SAFE` (exit non-zero, clear
message) AND the current branch is the plan's declared `Working branch:` AND that branch ∉
{main, master}. Add `--force` to bypass the opt-in gate for interactive/testing use only (never the
branch guard).
**DoD:** `nix flake check --no-build` passes; running against a plan without the marker, or on main,
exits non-zero with a clear reason and does NO work (verified in T7).

### T4 — Integrate with 044 substrate `TASK:PENDING`
(a) When no `<plan-file>` arg is given, resolve `.claude/active-plan` first (mirror `nextTaskMd`'s
precedence) then fall back. (b) On any stop (blocking failure, limits, all-done, interrupt), write/refresh
`$CLAUDE_PROJECT_DIR/.claude/HANDOFF.md` with: branch, last task + status, why it stopped, next concrete
step, log path — so the SessionStart hook and a human both rehydrate. (c) Keep `.claude/active-plan`
pointed at the burndown plan for the run's duration.
**DoD:** `nix flake check --no-build` passes; a halted fixture run leaves a HANDOFF.md that a fresh
session's 044 hook injects (verified in T7).

### T5 — Re-verify headless first-turn + gate 044 hook `TASK:PENDING`
Empirically re-test on the installed claude-code: does `claude -p "<prompt>"` reliably fire the first
turn unattended (expected yes)? Does `initialUserMessage` fire in `-p` mode (044 §10 #7 — unconfirmed)?
Record results in this plan. Confirm the 044 SessionStart resume hook is lean/no-op under `-p` (D7): if
`-p` invocations present a `source` the hook matches, add a guard so it doesn't double-inject.
**DoD:** findings recorded here with the exact probe commands + outputs; if a hook guard is needed, it's
implemented and `nix flake check --no-build` passes; the committed first-turn mechanism is stated.

### T6 — Observability + resume; optional convenience `TASK:PENDING`
Ensure the per-run log captures every task transition, commit SHA, and outcome bucket. Document how to
inspect a partial burndown (state file + logs) and resume it (re-run; IN_PROGRESS task resumes first).
OPTIONAL (only if T2-T5 land cleanly): a `--burndown <plan>` alias (sets `--all --on-failure stop`,
asserts opt-in) and/or a `systemd --user` oneshot template for detached long runs (gets journald +
the existing cgroup/oomd guards).
**DoD:** `nix flake check --no-build` passes; a written "inspect & resume" runbook section here; the
optional pieces are clearly marked done-or-deferred (no silent scope creep).

### T7 — End-to-end validation `TASK:PENDING`
Create a throwaway burndown-safe fixture plan (`Burndown: SAFE`, `Working branch: <fixture>`) with 2-3
trivial idempotent tasks (e.g. touch a file + commit) plus one task engineered to produce a
BLOCKING-FAILURE. On a dedicated fixture branch/worktree (never main): (1) run unattended → asserts it
burns the trivial tasks down to COMPLETE and commits each; (2) hits the engineered failure → asserts it
STOPS, leaves that task IN_PROGRESS, writes HANDOFF.md, exits non-zero, and did NOT advance; (3) assert
it refused to run on main and without the opt-in marker (T3). Tear down the fixture afterward (per the
untracked-files discipline; `git add <path>`, never `-A`).
**DoD:** all three assertions demonstrated with captured output recorded here; `nix flake check
--no-build` passes; fixture removed; this plan marked COMPLETE.

## 6. Open questions (remaining)
- Marker syntax bikeshed: `Burndown: SAFE` header line vs a fenced metadata block vs a dedicated branch
  naming convention. T1 proposes; revisit if it feels brittle.
- systemd-user oneshot vs leaving long runs to tmux/`-c` continuous mode — deferred to T6 (optional).
- Per-task model selection (the existing Model column) interaction with burndown cost caps — out of
  scope unless T7 surfaces a need.

## 7. References
- Parent substrate + prior-art research: `044-paste-free-session-resumption.md` (esp. §10).
- Seed implementation: `modules/programs/claude-code/_hm/task-automation.nix`
  (`nextTaskMd` = pull half; `mkRunTasksScript` = driver seed; `safetyLimits` options).
- Plan-authoring context to harden: `modules/programs/claude-code/_hm/claude-code-user-memory-template.md`;
  `modules/programs/claude-code/_hm/commands/planning/plans.md`.
- Concurrency/branch safety: `044` §5; project + global CLAUDE.md nix/git rules.
