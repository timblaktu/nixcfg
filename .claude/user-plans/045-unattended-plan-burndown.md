# 045 - Unattended Long-Running Plan Burndown (Mode B)

Status: PLANNED (stub - depends on 044). Created: 2026-06-20
Owner: nixcfg Claude Code config (`modules/programs/claude-code/`)
Depends on: `044-paste-free-session-resumption.md` (the shared substrate)

---

## 1. Problem / goal

044 makes a *human-attended* loop paste-free: end a session, start a fresh one, it auto-rehydrates the active plan's next task (Mode A). 045 removes the human from the loop (Mode B): a **driver autonomously burns down a pre-defined plan task-by-task, unattended, over a long run**, each task in a fresh clean context, until the plan is complete (or a stop condition trips).

This is the same `checkpoint → fresh session → rehydrate` cycle as 044, with a different DRIVER and additional guardrails. It reuses 044's substrate unchanged:
- plan file as source of truth (`TASK:PENDING/IN_PROGRESS/COMPLETE` cursor),
- per-worktree `$CLAUDE_PROJECT_DIR/.claude/active-plan` + `HANDOFF.md`,
- the `next-task` status-transition discipline (flip→commit→execute→mark→commit).

## 2. What 045 adds beyond 044 (the orthogonal hard parts)

- **Loop driver.** Repeatedly launch a fresh headless `claude -p "work the next PENDING task in plan X; update its status; commit"` until no PENDING remains. Likely a `--burndown <plan>` flag on the `claude*`/`opencode*` wrappers, or a small orchestrator (systemd-user unit / wrapper script). NB: the repo already has a SEED — the `run-tasks`/`/l` headless batch automation (`task_prompt` variant in `_hm/task-automation.nix`) — harden/promote that onto 044's substrate rather than greenfield.
- **Headless first-turn mechanism.** Verify the robust way to auto-fire the first turn unattended. `claude -p "<prompt>"` (explicit launch arg) is the safe default. RE-VERIFY `initialUserMessage` (044 §10 finding 7: schema-present but did not auto-fire a turn empirically on 2.1.158/2.1.183 — confirm whether it fires in `-p` mode before depending on it).
- **Stop conditions.** No-PENDING-tasks (success); per-run budget (tokens/time/iterations); consecutive-failure circuit breaker; explicit pause/abort marker file.
- **Autonomous-commit safety / permission posture.** Unattended sessions write git without a human gate — define an allowlist/permission mode, branch isolation (never main), and a dry-run/review mode. Reconcile with the project rule "NEVER work on main; always ask which branch" (for unattended runs, require a pre-designated working branch in the plan/marker).
- **Runaway + cost protection.** Lean on existing nix-eval cgroup guard + systemd-oomd + earlyoom; add iteration/cost caps and logging.
- **Per-task isolation under concurrency.** One burndown per worktree; separate concurrent burndowns belong in separate worktrees (044 §5). Guard against stale `index.lock` from a crashed iteration freezing siblings.
- **Observability.** Per-run log of task transitions, commits, failures; a way to inspect/resume a partially-completed burndown.

## 3. Open questions
- Driver home: wrapper flag vs systemd-user timer vs in-repo orchestrator script?
- How to express a plan as "safe to auto-burn-down" (opt-in marker in the plan file? a dedicated branch?).
- Interaction with 044's SessionStart hook (the hook should be a no-op or lean in headless `-p` runs to avoid double-driving).
- Failure handling: stop the whole run, or skip the failing task and continue?

## 4. References
- Parent substrate + prior-art research: `044-paste-free-session-resumption.md` (§10).
- Existing seed: `modules/programs/claude-code/_hm/task-automation.nix` (`run-tasks`/`task_prompt`).
- Concurrency isolation rules: `044` §5; CLAUDE.md nix/git safety rules.

## 5. Tasks
`TASK:PENDING` — flesh out this stub into a full self-contained plan once 044 lands (do not start before 044's substrate is implemented and validated).
