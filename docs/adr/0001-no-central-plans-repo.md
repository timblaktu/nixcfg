# ADR 0001: Do not use a central plans repository; enforce plan audience via the repository remote

## Status

Accepted

Recorded by plan 058 (unified plan governance), task T10. The broader always-track posture and the
local-mirror-of-server-push-rules design that this decision enables are elaborated by plan 058 and its
forthcoming design ADR (058 T2); this ADR is scoped to recording why a central plans repository was
considered and rejected.

## Context

Planning documents (numbered `NNN-*.md` files) drive multi-session work. Two properties are in tension:

- **Audience appropriateness.** A plan's content must be appropriate for whoever can read where it lives.
  Historically this was handled by a "trackable vs not-trackable" split, but that split was never about two
  kinds of plan - it was a governance proxy for *"I'm not sure this content fits the audience it would be
  exposed to."*
- **Co-location with code.** Plan 057 relocated plans to `user-plans/` at each repo root (and per-worktree
  runtime state to `.session-state/`), keeping each plan in the git repository whose code it concerns. That
  co-location preserves plan-to-code atomicity: a single commit both advances a task and changes the code that
  satisfies it, so the "which commit satisfied which task" audit trail lives in one history.

A natural alternative surfaces repeatedly: put **all** plans in a **single central plans repository** that every
session references (with global read/write), decoupled from any one code repo. This ADR records that
alternative, the analysis, and why it is superseded - so it is not re-proposed without new information.

The chosen direction instead is: **every plan is tracked in the code repo it concerns, and the repository's
remote defines and enforces the audience** (public plans in a `kyosaku-kai` repo, whose org enforces
server-side push rules + mandatory PR review + protected/immutable history; internal plans in the private
counterpart; personal plans in a personal repo).

## Decision

**We will not stand up a central plans repository.** Plans stay co-located with the code they concern, in
`user-plans/` per repository, and the repository's remote is the audience boundary. A central shared-write
plans repo is explicitly rejected as the default model.

This decision is **not irreversible**: because `.session-state/active-plan` supports an absolute path to a plan
file, a narrow future use case could still point sessions at a plan in a separate repository without
re-architecting anything. We choose not to adopt it now.

## Consequences

### Positive

- **Preserves plan-to-code atomicity and the audit trail.** The commit that advances a task and the commit that
  changes the code can be the same commit, in one history - not split across two repos.
- **Avoids reintroducing the out-of-cwd write-permission friction** that plan 057 was created to escape (Claude
  Code prompts on writes outside the working tree / under guarded paths). A central repo would put every plan
  write outside the session's cwd again.
- **Reuses existing, stronger enforcement.** The `kyosaku-kai` org already enforces server-side push rules,
  mandatory PR review, and protected history - a guardrail that is server-side and unbypassable, stronger than a
  hand-maintained central-repo convention, and already operated.
- **Keeps public plans public where they belong** (e.g. nixcfg plans stay in nixcfg), rather than relocating
  them into a separate shared repo.

### Negative

- **No single browsable index of all plans.** Plans are scattered across the repos they concern; discovering
  "all my plans" requires enumerating repos rather than reading one place.
- **Requires a cross-audience plan policy.** Plans that span public + internal audiences need an explicit
  convention (public shell + private detail split, or restrict-to-private). Plan 058 T9 defines it.
- **Audience correctness now rides on remote enforcement + the local mirror**, not on a human remembering not
  to commit a plan. That enforcement must actually be in place before flipping to always-track (plan 058's
  gating invariant: tracking must never outrun enforcement).
