# Plan 057 — Relocate plan & session-state storage OUT of `.claude/`

Status: ACTIVE (phased implementation; human-attended)
Owner: Tim
Created: 2026-09-15
Working branch: **plan-057-relocate-plan-state-storage** (worktree `/home/tim/src/nixcfg-session-hooks`, continued from the completed plan-056 branch)
Mode: **A only (human-attended `/next-task`).** NOT burndown-eligible — no `Burndown: SAFE` marker. Tasks alter machine-wide git config, move tracked files, and require a live `home-manager switch` + human observation of a permission prompt, so autonomous stop-the-run execution is inappropriate.

---
## ▶ RESUME POINTER — read FIRST

Fresh session: run `/next-task`. `active-plan` points here. The next actionable task is the first
`TASK:PENDING` whose dependencies are all `TASK:COMPLETE` — currently **T1** (add the two new global git
excludes to `git.nix`). Tasks run as a linear chain T1→T2→T3→T4/T5→T6; each has a checkable DoD.

**One-line goal:** move numbered plan files to `user-plans/` (repo root) and the two per-worktree runtime
files (`active-plan`, `HANDOFF.md`) to `.session-state/` (repo root), so NOTHING the session-workflow writes
lives under `.claude/` anymore — because Claude Code 2.1.x fires a permission prompt on EVERY write under
`.claude/`, which no allow-rule or permission mode can suppress (only `bypassPermissions`). The relocation is
the only durable fix. T6 is the real success test: edit a relocated plan and confirm ZERO permission prompt.

**Self-referential caution:** this plan file currently lives at `.claude/user-plans/057-relocate-plan-state-storage.md`.
T3 moves it to `user-plans/057-...md` and repoints `active-plan`. After T3, `/next-task` resolves this plan
from the NEW location. Do the move with `git mv` (history-preserving) and update `active-plan` in the SAME task.
---

## Core idea / root cause (settled)

Claude Code 2.1.x **hard-guards every write under `.claude/`** as a protected path. This is a path-prefix
guard, independent of the symlink guard that plan 056 P8 addressed (P8 de-symlinked all cwd-escaping
`.claude/user-plans` links; that fixed a DIFFERENT prompt and its 0-escaping-symlinks result still holds).
No `permissions.allow` rule and no `acceptEdits`/`default` permission mode overrides the `.claude/` guard —
only launching with `bypassPermissions`, or clicking the per-session "allow Claude to edit its own settings"
button. Consequently, every routine session-workflow write (updating a plan's `TASK:` status, writing
`HANDOFF.md`, repointing `active-plan`) triggers a permission prompt. The fix is to stop writing under
`.claude/` at all: relocate plan files and session-state to sibling top-level directories.

**Key reframe (settled this cycle):** in nixcfg, plan files are NOT ignored — the repo's local `.gitignore`
force-includes them (`.claude/*` then `!.claude/user-plans/`, since plan 017), so ~55 plan files are TRACKED
and PUBLIC on `main`. Only `HANDOFF.md` + `active-plan` are gitignored (via the machine-wide
`programs.git.ignores` entries `**/.claude/active-plan` + `**/.claude/HANDOFF.md`). **Tim confirmed nixcfg
keeps plans public/tracked.** So the relocation must PRESERVE nixcfg's tracked-and-public plans while keeping
the two runtime files per-worktree and untracked.

## Locked design decisions (Tim, 2026-09-15)

- **New homes:** `user-plans/` (repo root) for the numbered plan `.md` files; `.session-state/` (repo root)
  for the two per-worktree runtime files (`HANDOFF.md` + `active-plan`).
- **Governance = DEFAULT-IGNORE machine-wide** via global git excludes (`programs.git.ignores` in
  `modules/programs/git/git.nix` → the user's `core.excludesFile`): add `**/user-plans/` and
  `**/.session-state/`. Every repo on the machine (nixcfg, nixcfg-work, all internal GitLab repos) then
  ignores plans/state by default — Tim's rule: internal repos gitignore plans "for now", zero per-repo work.
- **Per-repo opt-OUT for tracking:** nixcfg re-tracks plans via a LOCAL `.gitignore` negation `!user-plans/`
  (mirrors the inverse-safe `!.claude/user-plans/` pattern it uses today). Default is safe (ignored);
  tracking is an explicit, per-repo opt-in. `.session-state/` is NEVER re-tracked (stays per-worktree).
- **Suspenders:** a `gitSafety` guard (new sub-hook in the plan-056 hook set) blocks `git add` of
  `.session-state/**`, so the untracked runtime files can never be accidentally committed even in a repo
  that opts plans back in.

## Functional reference map (touch-points found 2026-09-15 — the authoritative T2 worklist)

Behavior-affecting references to the old paths (must be rewritten in T2):
- `modules/programs/git/git.nix` ~L108-122 — the `ignores` list (global excludes). **T1** edits this.
- `modules/programs/claude-code/_hm/hooks.nix` — planIntegrity matchers at ~L1043 & ~L1064
  (`case "$fp" in */.claude/user-plans/*.md)`), plus path-referencing comments/logic at ~L428, L454, L484, L596.
- `modules/programs/claude-code/_hm/resume-hook.sh` — reads `.claude/active-plan` + `.claude/HANDOFF.md`
  (L7, L10, L75, L92); the SessionStart rehydration source.
- `modules/programs/claude-code/_hm/task-automation.nix` — the `/next-task` skill text (L12, L34) AND the
  burndown driver's active-plan/HANDOFF writes+reads (L263, L296, L353, L437, L441, L449, L458, L636, L649,
  L652, L671, L1360, L1506).
- `modules/flake-parts/lib.nix` L419 — plan discovery `fd ... .claude/user-plans/`.
- `modules/programs/claude-code/_hm/commands/planning/burndownify.md` L36,L38 and `.../plans.md` L5,L6 — command skills that read `active-plan` / list plan dir.
- `modules/programs/claude-code/_hm/claude-code-user-memory-template.md` — the GLOBAL per-account CLAUDE.md
  template (many references, L97-L277): update the protocol prose to the new paths.
- `CLAUDE.md` (this repo's project instructions) L5, L43-46, L190 — session-workflow prose.
- `modules/programs/claude-code/claude-code.nix` L131 — comment referencing the old symlink pattern.

Documentary-only references (historical citations of specific plan paths; update for link-accuracy but they
do NOT affect behavior — fold into T2's cleanup pass, non-gating): `docs/ai-tool-feature-comparison.md`,
`docs/claude-code-codecompanion-parity-verdict.md`, `docs/nix-store-model-and-vmtest-backends.md`,
`docs/claude-code-session-guardrails.md` L54, the mikrotik skill REFERENCE/SKILL plan-013 cites,
`modules/system/settings/wsl-enterprise/wsl-enterprise.nix` L56.

## nixcfg local `.gitignore` (the opt-in-tracking anchor)

Today (L139-142): `.claude/*` → `!.claude/settings.json` → `!.claude/user-plans/`. After T1's global
`**/user-plans/` default-ignore, nixcfg re-tracks the relocated plans by adding `!user-plans/` (and, if the
trailing-slash dir re-include needs it, `!user-plans/**`) to this local `.gitignore`. Keep `!.claude/settings.json`
(the web-session file stays). The old `!.claude/user-plans/` line is removed once T3 moves the dir.

---

## Progress Tracking

| ID | Task | Type | Depends on | Status |
|----|------|------|-----------|--------|
| T1 | **Global git excludes.** In `modules/programs/git/git.nix` `ignores`, ADD `"**/user-plans/"` and `"**/.session-state/"`; update the plan-044 comment to explain the new default-ignore-with-per-repo-opt-in scheme. Keep `**/.claude/active-plan` + `**/.claude/HANDOFF.md` for now (removed in T3 once state relocates) to avoid a coverage gap mid-migration. | impl | — | TASK:PENDING |
| T2 | **Module path rewrites.** Rewrite every FUNCTIONAL reference in the map above from `.claude/user-plans/`→`user-plans/`, `.claude/active-plan`→`.session-state/active-plan`, `.claude/HANDOFF.md`→`.session-state/HANDOFF.md` (hooks.nix matchers, resume-hook.sh, task-automation.nix, lib.nix, planning command skills, the global CLAUDE.md template, this repo's CLAUDE.md, claude-code.nix comment). Do the documentary-link cleanup pass too (non-gating). | impl (artifact → Present/STOP) | T1 | TASK:PENDING |
| T3 | **nixcfg move + re-track.** `git mv .claude/user-plans user-plans` (history-preserving, all ~55 files incl. `archive/`); move THIS plan file with it and repoint `active-plan`. Add `!user-plans/` negation to the local `.gitignore`; drop the old `!.claude/user-plans/` line. Create `.session-state/`, `git mv` (or move, since untracked) `active-plan` + `HANDOFF.md` there. Now that state lives under `.session-state/`, drop the `**/.claude/{active-plan,HANDOFF.md}` global excludes from git.nix (superseded by `**/.session-state/`). | impl (artifact → Present/STOP) | T2 | TASK:PENDING |
| T4 | **Machine-wide worktree migration** (like 056 P8). For EVERY worktree/repo on the machine that has a real `.claude/user-plans` dir and/or `.claude/{active-plan,HANDOFF.md}`, migrate to `user-plans/` + `.session-state/`. Idempotent (skip already-migrated). | migration (artifact → Present/STOP) | T3 | TASK:PENDING |
| T5 | **Suspenders hook + VM test.** Add a `gitSafety` sub-hook blocking `git add` of `.session-state/**` (block-with-message, `CLAUDE_HOOKS_BYPASS` escape, FALSE-POSITIVE analysis). Add/extend a VM test asserting the block fires and does NOT false-positive on a normal `git add`. | impl (artifact → Present/STOP) | T2 | TASK:PENDING |
| T6 | **Live verification** (the real success criterion). `home-manager switch` on `tim@pa161878-nixos`; then edit a relocated `user-plans/*.md` plan and confirm ZERO permission prompt; confirm `/next-task` + the SessionStart resume hook resolve plans/state from the new paths; confirm nixcfg still tracks `user-plans/` and `.session-state/` is untracked+ignored. | Interactive verification | T3, T4, T5 | TASK:PENDING |

---

## Task detail & Definition of Done

### T1 — Global git excludes `TASK:PENDING`
Edit `modules/programs/git/git.nix`: append `"**/user-plans/"` and `"**/.session-state/"` to the `ignores`
list and expand the comment to describe the new scheme (default-ignore machine-wide; per-repo opt-in tracking
via a local `!user-plans/` negation). Leave the two existing `**/.claude/{active-plan,HANDOFF.md}` lines in
place for now (T3 removes them once state has physically moved — avoids a window where new state is untracked
by neither guard).
**DoD:** `nix flake check --no-build` passes. `git show :modules/programs/git/git.nix` (staged) contains both
new patterns. No behavior change yet (nothing lives at those paths).

### T2 — Module path rewrites `TASK:PENDING`
Depends on T1. Rewrite the FUNCTIONAL references in the map above. Rules: `.claude/user-plans/`→`user-plans/`;
`.claude/active-plan`→`.session-state/active-plan`; `.claude/HANDOFF.md`→`.session-state/HANDOFF.md`. Include
the `$CLAUDE_PROJECT_DIR/.claude/...` forms (→ `$CLAUDE_PROJECT_DIR/.session-state/...`). Then a non-gating
documentary-link cleanup pass over the docs/skills citations.
**DoD:** `nix flake check --no-build` passes. A re-run of the T2 search (python scan for `.claude/user-plans`,
`.claude/active-plan`, `.claude/HANDOFF.md` across `modules/` + `CLAUDE.md`) returns ZERO functional hits
(documentary citations in `docs/`/skills may remain if deferred, but note any left behind). This is an
artifact-producing task: Present the diff + get Tim's sign-off before marking COMPLETE.

### T3 — nixcfg move + re-track `TASK:PENDING`
Depends on T2. Perform, in this worktree:
1. `git mv .claude/user-plans user-plans` (moves all numbered plans + `archive/`, history-preserving). This
   moves THIS plan file to `user-plans/057-relocate-plan-state-storage.md`.
2. Edit the local `.gitignore`: add `!user-plans/` (and `!user-plans/**` if a `git check-ignore` test shows
   the dir-form re-include is insufficient); remove the now-stale `!.claude/user-plans/` line.
3. Create `.session-state/`; move `active-plan` + `HANDOFF.md` there; rewrite `active-plan`'s contents to the
   new plan path `user-plans/057-relocate-plan-state-storage.md`.
4. Edit `modules/programs/git/git.nix`: remove the `**/.claude/active-plan` + `**/.claude/HANDOFF.md` lines
   (now covered by `**/.session-state/`).
**DoD:** `git status` shows `user-plans/057-...md` TRACKED (renamed) and the rest of `user-plans/**` tracked;
`git check-ignore -v .session-state/active-plan .session-state/HANDOFF.md` shows BOTH ignored by
`**/.session-state/`; `git check-ignore user-plans/056-...md` returns nonzero (NOT ignored). `nix flake check
--no-build` passes. Present/STOP for Tim before COMPLETE (irreversible-ish move of tracked public files).

### T4 — Machine-wide worktree migration `TASK:PENDING`
Depends on T3. Enumerate every worktree/repo under `~/src` (and any other checkout) with a real
`.claude/user-plans` dir or `.claude/{active-plan,HANDOFF.md}` file; for each, move to `user-plans/` +
`.session-state/` (idempotent: skip if already migrated; never touch a repo lacking these). Mirror 056 P8's
batch approach; this is throwaway migration tooling — remove it after cases==0.
**DoD:** a re-scan (`fd -td user-plans -H -p '.claude/user-plans$'` or python walk) reports 0 remaining
`.claude/user-plans` dirs and 0 `.claude/{active-plan,HANDOFF.md}` files across scanned checkouts. Report the
list migrated. Present/STOP before COMPLETE.

### T5 — Suspenders `gitSafety` hook + VM test `TASK:PENDING`
Depends on T2. Add a `gitSafety` sub-hook (in `hooks.nix`, same pattern as the plan-056 `blockAddForce` etc.):
PreToolUse Bash, jq-stdin `.tool_input.command`, block a `git add` that targets `.session-state/` (or a path
under it), `exit 2`, `continueOnError=false`, `CLAUDE_HOOKS_BYPASS` escape, four-part block message (WHY /
PROCEED-NOW / AVOID-FUTURE / docs link) per the 056 P11 contract. FALSE-POSITIVE analysis: must NOT block
`git add user-plans/...` or unrelated adds. Add/extend a VM test asserting the block fires and a clean add passes.
**DoD:** `nix flake check --no-build` passes; the VM test (or shell harness) proves block-fires + no-FP.
Present/STOP before COMPLETE.

### T6 — Live verification `TASK:PENDING`
Depends on T3, T4, T5. On `tim@pa161878-nixos`: `home-manager switch` carrying the T1-T5 changes (via the
nixcfg-work local-pin or a lock bump, per the 056 rollout precedent). Then:
1. Edit a relocated `user-plans/*.md` plan (e.g. mark a scratch line) and CONFIRM the CC permission prompt
   does NOT appear — the primary success criterion.
2. Start a fresh session and confirm the SessionStart resume hook + `/next-task` resolve the active plan and
   next task from `.session-state/active-plan` → `user-plans/...`.
3. Confirm `git status` in nixcfg still tracks `user-plans/` and that `.session-state/` is untracked+ignored.
**DoD:** all three confirmed (the no-prompt observation is the gate). Interactive — requires the live host and
human observation; yields USER_INPUT_REQUIRED under headless `/next-task`.

---

## Notes carried from plan 056 (context, not tasks)
- Plan 056 is COMPLETE and public (hook set merged to nixcfg `main` at merge `3cf33b6`). 057 builds directly
  on that hook set (T5 adds a new `gitSafety` sub-hook to it).
- Backlog to fold in opportunistically: `blockAttribution` FALSE POSITIVE on read-only git commands that merely
  grep the marker strings (e.g. `git log | grep 'co-authored-by:'`) — exclude read-only subcommands
  (log/show/diff/grep) or inspect only commit-message inputs. RTK output-corruption was ACTIVE in this worktree
  (mangles rg/grep flags) — prefer python3/Read for exact content until RTK is confirmed OFF here.
