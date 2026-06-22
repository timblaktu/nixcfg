Audit a user-plan against the Unattended Burndown Contract and, only once it
genuinely complies, opt it in for autonomous task-by-task burndown.

This command is the companion to `/plans` (which reports burndown eligibility) and
`/next-task` (which executes the cursor). It makes a plan *eligible* — safely.

## What "burndown-ready" means (the standard)

The canonical source of truth is the **"Unattended Burndown Contract"** section in the
user-global CLAUDE.md. The driver (`run-tasks-<account> <plan> --burndown`) refuses any
plan that lacks the opt-in markers, and its failure policy is *stop-the-whole-run*. That
is only safe when the plan is authored so a BLOCKING-FAILURE is essentially unreachable.
Adding `Burndown: SAFE` is therefore an **attestation**, not a formatting flag: it asserts
the plan meets all six authoring rules below. Never stamp it on a plan that does not.

The six authoring rules every task must satisfy:

1. **Checkable DoD.** "Done" is objectively verifiable — a command that exits zero, a file
   that exists with known content, a test that passes. No prose-only "should work".
2. **Order via declared dependencies.** If task B needs task A's output, B carries a
   `Depends on: A` line so a premature run yields BLOCKED-BY-DEP instead of attempt-and-fail.
3. **No-workaround rule.** Unmet prerequisites emit a non-blocking sentinel
   (`ENVIRONMENT_NOT_CAPABLE` / `USER_INPUT_REQUIRED` / BLOCKED-BY-DEP), never an invented
   alternative. A prerequisite that should have been a declared dependency is an authoring bug.
4. **Human-decision tasks tagged `Interactive`.** Anything needing a choice/approval/judgment
   ⇒ `USER_INPUT_REQUIRED`, never an autonomous guess.
5. **Opt-in + working branch headers** present in the plan header block:
   `Burndown: SAFE` and `Working branch: <non-main-branch>`.
6. **Idempotent / resumable tasks.** Re-running a task whose status is still `IN_PROGRESS`
   converges (check-before-create, append-if-absent, `mkdir -p`), never double-applies.

## Arguments

- `$ARGUMENTS` may name a plan file (path or number, e.g. `027` or a full path).
- `--audit` — report-only mode: produce the readiness report and STOP. Make no edits.
- If no plan is given, resolve the target like `/next-task` does: read `.claude/active-plan`
  (its one line is the plan path, possibly relative to the worktree root); if absent, list
  active plans via `fd -t f -e md . .claude/user-plans/ --max-depth 1` and ASK which one.

## Procedure

### 1. Resolve and read the plan
Resolve the plan file per the argument rules above. Read it in full. If the file does not
exist, report that and STOP.

### 2. Detect the working branch (branch guard preview)
Run `git rev-parse --abbrev-ref HEAD`. If the result is `main` or `master`, WARN that the
burndown driver's branch guard will refuse to run here regardless of markers, and that the
`Working branch:` you stamp must be the branch the run will actually execute on. Do not
abort the audit, but do not stamp a `Working branch:` value that names main/master.

### 3. Audit every task against the six rules
Parse the Progress Tracking table / `###` task headings. For EACH non-COMPLETE task, classify:

- **DoD:** Does it have an objectively checkable Definition of Done (a command, a file
  check, a passing test)? Flag prose-only criteria.
- **Dependencies:** If the task consumes another task's output, is there an explicit
  `Depends on:` line? Flag implicit ordering.
- **Interactive:** Does it need a human decision/approval/judgment? If so, is it tagged
  `Interactive`? Flag untagged decision tasks.
- **Idempotency:** Would re-running a half-done attempt double-apply or fail? Flag
  non-convergent steps.
- **Parseability:** Does the task have a stable ID / heading the driver can target, and a
  `TASK:PENDING/IN_PROGRESS/COMPLETE` cursor?

Also check the header for the two markers (rule 5) and whether a Progress Tracking table exists.

### 4. Emit the readiness report
Present a concise per-task table: `Task | DoD | Deps | Interactive | Idempotent | Verdict`,
using ✅ / ⚠ / ✖. Conclude with one of:

- **READY** — all tasks pass; only the header markers are missing (or already present).
- **NEEDS WORK** — list the specific tasks and which rule each fails, with a concrete fix
  for each (the exact DoD command to add, the `Depends on:` edge, the `Interactive` tag, the
  idempotency guard).

If `--audit` was passed, STOP here. Make no edits.

### 5. Propose and apply rewrites (only when not --audit)
For each NEEDS WORK item, draft the concrete edit:
- Replace prose DoDs with checkable ones (prefer `nix flake check --no-build`, `nix eval`,
  `test -f`, a named test — exit-zero commands).
- Add `Depends on:` lines.
- Add `Interactive` tags to decision tasks.
- Add idempotency guards to task instructions.

Show the proposed edits and **ask for confirmation** before writing them. You MAY draft DoDs,
but you MUST NOT fabricate a checkable criterion you cannot justify from the task's intent —
if a task's success genuinely cannot be made machine-checkable, say so and recommend it stay
human-attended (it is a reason NOT to stamp SAFE).

### 6. Stamp the opt-in (only when truly compliant)
ONLY after every non-COMPLETE task has a checkable DoD (and deps/Interactive/idempotency are
satisfied) do you add the two header lines to the plan's Status/Owner header block:

```
Burndown: SAFE
Working branch: <current branch from step 2, never main/master>
```

If the markers already exist and the audit passes, report "already burndown-ready" and make
no change (idempotent). If the audit does NOT pass, DO NOT stamp `Burndown: SAFE` — report
what remains and STOP. Faking the attestation is the one outcome this command must never produce.

### 7. Validate and report
Confirm the edits parse: `rg -m1 '^Burndown:' <plan>` prints `SAFE` and `rg -m1 '^Working branch:' <plan>`
prints the branch. Summarize what changed, the working branch, and the exact command to run
the burndown: `run-tasks-<account> <plan> --burndown` (from that branch). Commit the plan
edits if the project workflow expects it.

## Safety invariants (do not violate)

- Never write `Burndown: SAFE` unless every non-COMPLETE task has a checkable DoD.
- Never stamp a `Working branch:` of `main`/`master`.
- `--audit` makes zero edits.
- Re-running on a compliant plan is a no-op.
- When in doubt about a task's checkability, leave the plan human-attended and say why.
