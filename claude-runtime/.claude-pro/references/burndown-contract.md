# Unattended Burndown Contract - Full Reference

Read this file when AUTHORING a new burndown-eligible plan or debugging a stopped run.
The inline summary in CLAUDE.md covers the required header markers and outcome types.

## Overview

An **unattended burndown** is the `run-tasks-<account>` driver running a plan until COMPLETE or a stop condition. "Mode B" (driver loop); "Mode A" is the human-attended `/next-task` loop. Both use the same substrate: `TASK:PENDING/IN_PROGRESS/COMPLETE` cursor in the plan file, `.session-state/active-plan`, `.session-state/HANDOFF.md`.

**Layer model**: Each driver iteration runs ONE orchestrating `claude -p` over the whole independent FRONTIER. It fans out sub-agents for mutually-independent tasks, commits each individually, edits `TASK:` markers itself, then the driver re-reads the plan for the next layer. This keeps concurrent work safe in a single worktree.

**Failure policy**: A single BLOCKING-FAILURE in a layer stops the whole run (the independent tasks already committed stay done). Author plans so BLOCKING-FAILURE is essentially unreachable.

## Outcome taxonomy

| Outcome | Meaning | Driver action |
|---|---|---|
| **COMPLETE** | DoD met, changes committed | mark `TASK:COMPLETE` + date, advance to next |
| **BLOCKED-BY-DEP** | declared dependency not yet COMPLETE | skip to next actionable task; NOT a failure |
| **ENVIRONMENT_NOT_CAPABLE** | wrong host / missing toolchain | exit cleanly, leave task PENDING |
| **USER_INPUT_REQUIRED** | needs human decision/approval | exit cleanly, leave task PENDING |
| **BLOCKING-FAILURE** | hard error (build regression, crash, unmet prerequisite NOT a declared dep) | STOP the whole run, leave task IN_PROGRESS, write HANDOFF, exit non-zero |

## Authoring rules (make blocking failures unreachable)

1. **Checkable DoD per task.** "Done" = objectively verifiable: a command exits zero, a file exists with known content, a test passes. No prose-only "should work".
2. **Order via dependencies, not luck.** If task B needs task A's output, declare A as B's dependency. A premature run yields BLOCKED-BY-DEP, not a crash.
3. **No-workaround rule.** If prerequisites aren't met, emit the correct non-blocking sentinel; never invent an alternative approach. An unmet prerequisite that should have been a declared dep is an AUTHORING bug.
4. **Mark human-decision tasks `Interactive`.** Anything needing choice, approval, or judgment => `USER_INPUT_REQUIRED`, never an autonomous guess.
5. **Required header markers** (driver refuses if absent or if current branch is main/master):
   ```
   Burndown: SAFE
   Working branch: plan-NNN-some-feature
   ```
6. **Idempotent / resumable tasks.** A task re-run after an interrupted `IN_PROGRESS` attempt must converge. Use check-before-create, append-if-absent, `mkdir -p`.

## Worked example - blocking-failure-proof task

```
### T3 — Add the foo widget to the bar module `TASK:PENDING`
Depends on: T2 (the bar module must exist and export `widgets`).
Edit `modules/bar.nix` to register a `foo` widget under `widgets`. The edit is idempotent:
if a `foo` entry already exists, leave it unchanged.
**DoD:** `nix flake check --no-build` passes AND `nix eval '.#bar.widgets.foo' --raw` prints
a non-empty string. If T2 is not COMPLETE, this task yields BLOCKED-BY-DEP. If the toolchain
is missing `nix`, it yields ENVIRONMENT_NOT_CAPABLE. No prose-only success criterion.
```

## Running a burndown

```bash
run-tasks-<account> <plan.md> --burndown   # opt-in asserted, on-failure stop
```

## Run artifacts (all gitignored)

| Artifact | Path | Contents |
|---|---|---|
| Event journal | `.claude-task-logs/events.jsonl` | One JSONL line per layer transition |
| Per-layer logs | `.claude-task-logs/<ts>_<anchor>.{log,json,stderr}` | Full orchestrator response + stderr |
| Run state | `.claude-task-state` | Latest snapshot (`STATUS=` = stop bucket) |
| Handoff | `.session-state/HANDOFF.md` | Resume breadcrumb |

## Inspecting a stopped run

```bash
cat .claude-task-state                                  # STATUS= tells you the stop bucket
jq -c . .claude-task-logs/events.jsonl                  # full per-layer history
jq -r 'select(.head_moved) | "\(.task) +\(.completed) \(.sha_before)->\(.sha_after) \(.status)"' \
    .claude-task-logs/events.jsonl                      # per layer: anchor, tasks, SHA span
ls -t .claude-task-logs/*.log | head -1 | xargs cat     # most recent layer output
```

## Resuming

Re-run the same command. The `TASK:` cursor in the plan file is the state. An `IN_PROGRESS` task (blocking failure bucket) is re-attempted first; idempotent authoring means it converges. If stopped for `ENVIRONMENT_NOT_CAPABLE` or `USER_INPUT_REQUIRED`, handle that one task interactively with `/next-task`, then re-launch.
