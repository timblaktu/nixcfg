# Re-orient to the active plan's objective, where we are, what remains, and whether we're still on track

Produce a clear, scannable overview of THIS worktree/branch/plan/session's DURABLE objective, where
the work stands now, what remains, and an honest self-audit of whether recent activity still serves
the objective or has drifted into the weeds. This is a cold-start re-orientation for a user who juggles
many concurrent sessions and has lost context on this one.

This command is READ-ONLY: do NOT edit code, do NOT edit the plan, do NOT change any `TASK:` status,
do NOT commit, do NOT write a HANDOFF. Orient only.

Optional argument (a specific plan file to orient against instead of auto-resolving): $ARGUMENTS

## Why this command exists (the two trails that reveal the objective)

The "objective" of a session is almost never the newest task - it is the reason the BRANCH exists, which
is only visible by tracing two parallel histories back to their root. Most drift-blindness comes from
reading the latest task and skipping these:

1. **The git lineage.** Trace the active branch back to `main`. An integration/staging branch is usually
   `main` + hundreds/thousands of commits carrying several merged dev workstreams; the merge commits and
   the branch's distance from `main` ARE the big picture. Never state the objective without walking this.
2. **The plan/session-history trail.** The numbered `user-plans/NNN-*.md` plans plus the
   `.session-state/` handoffs are a PARALLEL trail that shadows the git history. It is gitignored, so it
   takes deliberate collection - but it records the WHY (pivots, owner decisions, deferrals) that git alone
   does not. Read the plan sequence, not just the active plan.

## Plan selection (identical precedence to /next-task)

FIRST, the explicit per-worktree pointer (highest precedence):
- If `$CLAUDE_PROJECT_DIR/.session-state/active-plan` exists and is non-empty, read its first line as the
  active plan file path. Resolve it the way the SessionStart resume hook does: if the path is absolute
  (starts with `/`) use it as-is; otherwise resolve it relative to the worktree root `$CLAUDE_PROJECT_DIR`.
  If the resolved file exists, use that plan and SKIP the auto-detection below.

OTHERWISE, fall back to CLAUDE.md auto-detection:
1. Check the project's CLAUDE.md for active plans with plan file paths.
2. Prefer the plan with an IN_PROGRESS task; if several, the most recent session date.
3. If none IN_PROGRESS, prefer the most recent session date among PENDING tasks.
4. If no dates, use git log modification time of plan files as the tiebreak.
5. If still ambiguous, STOP and ask which plan to orient against (do not guess silently).

If an argument was given, use that plan file directly and say so.

## Gather (read-only - use rg/fd/git; never mutate)

Collect BOTH trails plus current state. Budget your effort here - this is where accuracy comes from.

- **Git lineage to main (factor 1 - do this, do not skip):**
  - current branch + HEAD: `git rev-parse --abbrev-ref HEAD` and `git log -1 --format='%h %s (%cr)'`
  - distance from trunk: `git merge-base main HEAD` and `git log --oneline main..HEAD | wc -l` (how far this
    branch has carried the integration)
  - what was merged in: `git log --oneline --merges -n 40 HEAD` (merge messages name the dev workstreams)
    and `git log --oneline --graph --decorate -n 20`
  - sibling branches that fed this line: `git branch -a` (note governance / test / vte / staging /
    integration-named branches). Remote refs reflect the last fetch if offline - say so, don't overstate.
  - working-tree state: `git status --short` (clean vs dirty; staged/untracked scratch).
- **Plan/session-history trail (factor 2 - gitignored, takes diligence):**
  - the full plan sequence: `fd . "$CLAUDE_PROJECT_DIR/user-plans" -e md` - read the TITLES of the
    numbered plans (the sequence traces how the objective evolved) and the header/objective of the active
    one and a couple of its predecessors.
  - the active plan's "Progress Tracking" table: every `TASK:` row + status (PENDING/IN_PROGRESS/COMPLETE/
    DEFERRED/BLOCKED) + dates, and each task's Definition-of-Done.
  - `$CLAUDE_PROJECT_DIR/.session-state/HANDOFF.md` if present - the distilled last-session nuance (what was
    just done, commits, what was NOT done, the next concrete step, pending blockers, dead-ends).
- Cross-check the objective against the repo CLAUDE.md "Architecture" section and any `docs/` that describe
  the branch/integration strategy.

## Output - use exactly this structure, in this order

LEAD WITH AN ANNOTATED ASCII TREE (always required). Show the lineage/stack as a small left-hand tree with
right-hand annotations, and make the layer we are CURRENTLY on visually pop (CAPS / "WE ARE HERE"). Adapt
to the real lineage you found - e.g.:

```
main                          ──► product trunk; the durable product line
 ├─► dev workstreams           ──► the efforts that fed the integration line (name them)
 ▼
 integration/staging branch    ──► where they converge + get validated before merge
 ▼
 HEAD (THIS)                   ──► **WE ARE HERE** - <branch>@<short-sha>, <clean|dirty>
 ▼
 TARGET                        ──► the MR/release this is all staged for
```

Then, in prose below the tree, the four fixed sections:

**(a) OBJECTIVE** - the durable goal the branch/plan serves, in one or two plain sentences, WITH its lineage
context (what larger journey it is a step of, drawn from BOTH trails). Not the newest task - the reason the
branch exists. Gloss every acronym on first use.

**(b) WHERE WE ARE** - what is DONE and VALIDATED vs merely attempted: completed-task count over total
(e.g. 7/12), named milestones reached, current HEAD, working-tree state. Call out anything claimed done but
not actually proven.

**(c) WHAT REMAINS** - the actionable frontier (next PENDING/IN_PROGRESS tasks whose deps are met), THEN the
deferred/blocked set honestly: which tasks are BLOCKED-BY-DEP, ENVIRONMENT-not-capable, or awaiting a user
decision, and on what. Name real blockers; do not pad.

**(d) ON-TRACK / IN-THE-WEEDS SELF-AUDIT** - the point of this command. Explicitly ARGUE whether the most
recent activity (last few commits + HANDOFF "what was just done" + current dirty state) still advances the
OBJECTIVE in (a), or has drifted. Be adversarial with yourself:
  - Does recent work map to a frontier task in the plan, or is it off-plan churn?
  - Are we polishing/yak-shaving something the objective doesn't need yet (gold-plating)?
  - Is there scope creep - work that belongs in a different plan/branch?
  - Did a side-quest displace the actual next step?
State a one-line verdict: **ON TRACK**, or **DRIFTING** (and name the drift + the single corrective step to
get back on the objective). If genuinely on track, say so plainly - do not manufacture drift.

Keep it tight and scannable - plain language, no fluff, no walls of text; call out the important things.
Respect `$CLAUDE_TERMINAL_WIDTH` for any table. End by naming the resolved plan file and the resume command
(`/next-task`) so the user can act immediately. Do not write a HANDOFF or touch any file.
