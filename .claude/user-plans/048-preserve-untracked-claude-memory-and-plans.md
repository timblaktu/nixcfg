# Plan 048: Preserve gitignored Claude memory and user-plan files (history + backup)

## Status: PENDING (authored 2026-08-12, Tim + assistant during an n3x session)

Mode: A (attended). T1 is an owner decision (Interactive). Not burndown-eligible until T1 is decided.

Related prior work: `040-claude-memory-system-analysis.md`, `041-claude-memory-system-fix.md`
(the auto-memory system itself), `026-team-sharing-refactoring.md`,
`043-ai-attribution-history-scrub.md` (public-repo hygiene precedent).

## Problem

Claude Code's persistent memory files and the user-plan files are important, high-value
context that accretes over months of work, but they are **gitignored runtime state**: they
persist on disk yet are NOT version-controlled, backed up, or synced across machines.
"Persistent" is not "preserved" - if the runtime dir is regenerated, the disk fails, or a
directory is deleted by mistake, there is no history to recover and no remote copy.

This plan captures the storage topology (so no future session re-derives it) and lands a
durable preservation mechanism that keeps history + backup WITHOUT leaking internal project
detail into the public `nixcfg` repo.

## Findings: where these files physically live (verified 2026-08-11/12)

A common misconception is that memory/plan files live inside a project git worktree and are
lost when that worktree is deleted. They are not. The real layout:

- **Claude memory (per project, shared across that project's worktrees):**
  `~/src/nixcfg/claude-runtime/.claude-max/projects/<project-slug>/memory/`
  (e.g. slug `-home-tim-src-n3x`). These are REAL directories (no symlinks in the path),
  keyed to the project's MAIN path, so every worktree of that project shares one memory
  store. Corpus is small (n3x memory ~1.7M). Contains `MEMORY.md` (the loaded index) plus
  one file per memory.

- **User-plans (per project, shared across worktrees):**
  A worktree's `.claude/user-plans` is a symlink to the main worktree's
  `.../.claude/user-plans`, which itself resolves to a dedicated external dir
  (for n3x: `/home/tim/src/n3x-plans`). So plan files live OUTSIDE every worktree; deleting
  a worktree removes only the symlink. An `archive/` subdir convention already exists there.

- **Truly per-worktree, intentionally ephemeral (safe to lose):**
  `.claude/HANDOFF.md` and `.claude/active-plan` are real files in each worktree's `.claude/`.
  They are session-resume breadcrumbs by design and do not need long-term preservation.

- **Gitignore status:** the memory corpus is ignored inside `nixcfg` via
  `claude-runtime/.gitignore` (rule `**/projects/`). The n3x plan dir is a separate,
  currently-unmanaged directory. Neither is under version control today.

## Hard constraint: nixcfg is PUBLIC

`nixcfg` is a public GitHub repo (`github.com/timblaktu/nixcfg`). Memory and plan files
contain internal project detail (ticket IDs, internal hostnames/cluster names, MR numbers,
architecture specifics). Therefore:

- Do NOT simply narrow `claude-runtime/.gitignore` and commit memory/plans into `nixcfg`.
  That would leak internal detail publicly - the same risk class the CLAUDE.md AI-attribution
  rule guards against.
- The preservation target MUST be private (private repo or local backup), never public nixcfg.

## Options considered

1. **Dedicated PRIVATE git repo for the corpus (recommended).** A private repo
   (e.g. private GitHub `claude-memory`, or a private GitLab repo). The project memory dir(s)
   and the plan dir(s) live in it (or are symlinked into it). Gives full git history + remote
   backup + cross-machine sync. Small (~single-digit MB). No public exposure.

2. **Automatic snapshot commit (pairs with 1).** A `SessionEnd`/`Stop` hook or a
   systemd-user timer / cron that runs `git add -A && git commit` in that private repo on a
   schedule or at session end. Makes durability hands-off. This repo already uses Claude hooks,
   so the mechanism is familiar.

3. **Archive completed plans explicitly.** Move finished plans into the existing `archive/`
   subdir so history is legible; the snapshot in (1)+(2) then captures them durably.

4. **Backup-only fallback (no git).** rsync/restic the memory + plan dirs into the existing
   backup regime. Simpler, but no diff history or easy cross-machine sync.

**Recommendation:** 1 + 2 + 3 - a private `claude-memory` repo holding the memory and plan
dirs, an automatic snapshot at session end (or daily), and the archive-on-complete habit for
plans. Private-safe, versioned, backed up, multi-machine, near-zero ongoing effort.

## Progress tracking

| Task | Status | Date |
|---|---|---|
| T1 decide preservation target (private GH repo / private GL / backup-only) | TASK:PENDING | |
| T2 create the private store + wire the memory & plan dirs into it (idempotent) | TASK:PENDING | |
| T3 automatic snapshot (SessionEnd/Stop hook or systemd-user timer) | TASK:PENDING | |
| T4 adopt archive-on-complete for finished plans | TASK:PENDING | |
| T5 document the topology + preservation design (nixcfg docs) | TASK:PENDING | |

## Tasks

### T1 - Decide the preservation target `TASK:PENDING` (Interactive - Tim decides)

Choose the private store: private GitHub repo (`timblaktu/claude-memory`, private), a private
GitLab repo, or backup-only (rsync/restic, no git). Record the choice + rationale here.

**DoD:** one target chosen and written here; the others explicitly ruled out with reasons.
Consider: does the corpus ever need to be shared with teammates (argues for a repo with access
control), or is single-user durability enough (backup-only is simplest)? Cross-machine sync
need? Sensitivity (must stay private regardless).

### T2 - Create the private store and wire the dirs into it `TASK:PENDING`
Depends on: T1.

Create the chosen private store. Move (or symlink) into it: (a) the per-project memory dir(s)
under `claude-runtime/.claude-max/projects/*/memory/`, and (b) the plan dir(s) (for n3x:
`/home/tim/src/n3x-plans`). Preserve the existing symlink chain so Claude Code still reads/writes
the same paths. Make the wiring idempotent (check-before-create; re-running converges).

**DoD:** the memory and plan corpora are contained in the private store; Claude Code still
reads/writes memory + plans at their original paths (verify a memory write and a plan read still
land correctly); an initial commit/backup exists in the private store. Nothing internal committed
to public `nixcfg`.

### T3 - Automatic snapshot mechanism `TASK:PENDING`
Depends on: T2.

Add a hook or timer that snapshots the private store automatically (SessionEnd/Stop hook that
commits, or a systemd-user timer / cron running a commit on a schedule). Manage it declaratively
in `nixcfg` home-manager where possible (the mechanism/config can live in public nixcfg; the DATA
stays in the private store).

**DoD:** a snapshot fires automatically (demonstrate: make a memory edit, trigger the hook/timer,
observe a new commit/backup in the private store) without manual steps.

### T4 - Archive-on-complete for finished plans `TASK:PENDING`

Adopt moving completed plans into the existing `archive/` subdir (both this nixcfg plan dir and
the n3x plan dir). Optionally add a tiny helper/skill. This keeps active plan lists short and marks
history clearly for the snapshot to capture.

**DoD:** the convention is written down (in nixcfg docs or CLAUDE.md), and at least one completed
plan is archived as the worked example.

### T5 - Document the topology + preservation design `TASK:PENDING`
Depends on: T2/T3.

Add a short doc in `nixcfg` (public is fine - it describes MECHANISM/paths, not internal data)
recording: where memory and plans physically live, that they are shared across a project's
worktrees, that per-worktree HANDOFF/active-plan are ephemeral, and how the private preservation
store + snapshot works. This prevents future sessions from re-deriving the layout.

**DoD:** the doc exists and is linked from the relevant CLAUDE.md / memory-system plan (040/041).

## Notes
- Keep ALL internal memory/plan content out of public `nixcfg` history (see "Hard constraint").
- The mechanism/config (hooks, symlink setup, home-manager modules) MAY live in public nixcfg;
  only the DATA must stay private.
- This plan file itself is generic infrastructure design and is safe to keep in public nixcfg.
