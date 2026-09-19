# Plan 058 — Unified plan governance: always-track plans behind the kyosaku-kai enforced boundary (+ local mirror of server push rules)

Status: CANDIDATE → ACTIVE (design + phased implementation; human-attended)
Owner: Tim
Created: 2026-09-17
Working branch: **plan-058-unified-plan-governance** (to be created off `main` when work starts; this stub was
authored in worktree `/home/tim/src/nixcfg-session-hooks` on the `plan-057-relocate-plan-state-storage` branch).
Mode: **A only (human-attended `/next-task`).** NOT burndown-eligible — several tasks require Tim's org-admin
access, irreversible history/remote decisions, and human judgment; they yield USER_INPUT_REQUIRED, not autonomous
execution. No `Burndown: SAFE` marker.
Depends on: **Plan 057** (relocate plan/state out of `.claude/`). 057 provides the working-tree layout
(`user-plans/` + `.session-state/`) this plan builds on; 058 flips the *default posture* from opt-in-tracking to
always-track and adds the enforcement that makes always-track safe.

---
## ▶ RESUME POINTER — read FIRST

This is a design-heavy, human-attended plan. Fresh session: run `/next-task`; the first actionable task is the
first `TASK:PENDING` whose dependencies are `TASK:COMPLETE`. The linchpin ordering is **T1 (enumerate the server
rules) → T2 (design the local mirror + SSOT) → T3 (implement local hooks) → T8 (flip default posture)**; the
migration tasks (T5/T6/T7) and policy tasks (T9/T10) branch off. Nothing here is started yet — all tasks PENDING.

**One-line goal:** make *every* plan tracked in git by default, with the public/private audience boundary
enforced by the repository's remote (kyosaku-kai's server-side push rules for public plans; a private counterpart
for internal plans), and **mirror those server-side push rules into locally-enforced git hooks** so leaks are
caught at commit time, not only at push time. Success = the track/no-track bifurcation is deleted and no plan
content can reach a public tree that shouldn't.

---

## Problem / root cause (SETTLED this design cycle, 2026-09-16..17)

Historically nixcfg plans were split into "trackable" (public, committed) vs "not trackable" (kept untracked as
an escape hatch). That split was never about two kinds of plan — it was a **governance proxy**: "untracked" meant
"I'm not sure this content is appropriate for the audience it would be exposed to." The real, singular requirement
is: *a plan's content must be appropriate for the audience of wherever it lives.* Because the **repository (its
remote) already defines the audience** (nixcfg = public; nixcfg-work = corp-internal; a personal repo = just Tim),
there is no inherently-untrackable plan — only a plan not yet placed in the repo whose audience matches its
content. The bifurcation can therefore collapse into a single rule: **always track; the remote enforces
appropriateness.**

## Key decisions (SETTLED, Tim, 2026-09-17)

- **Collapse to always-track.** Eliminate the "untracked" tier. Every plan is tracked in a git repo. "Personal /
  scratch" becomes "tracked in a repo whose audience is just me," not "untracked."
- **Audience boundary = the remote.** Public plans live in a **kyosaku-kai** repo; internal plans live in the
  private counterpart (internal fork / corp repo). The remote — not a per-plan flag — decides and enforces audience.
- **kyosaku-kai is the enforced public boundary.** Verified via the GitHub API (see below): the org applies an
  org-wide branch ruleset to every repo (mandatory pull-request review, no force-push, no history rewrite, no
  branch deletion; only org admins bypass). Tim confirmed (admin-only, not API-visible) that the org additionally
  runs **server-side push rules with custom pattern-matching on internal identifiers** — the automated catch that
  blocks internal wording from reaching the public tree. So the content guardrail this design needs already exists,
  one layer up, stronger than a hand-built local hook (server-side, unbypassable, already maintained).
- **Central-plans-repo alternative: CONSIDERED and SUPERSEDED.** A single separate git repo holding all plans that
  every session references was evaluated (T10 records the full analysis). Rejected because it (a) reintroduces the
  exact out-of-cwd-write permission friction 057 escaped, (b) splits plan↔code atomicity and the "which commit
  satisfied which task" audit trail across repos, and (c) conflicts with keeping nixcfg plans public *in nixcfg*.
  kyosaku-kai reuses existing enforcement instead of standing up a new shared-write repo.
- **Local mirror of the server push rules is REQUIRED (Tim, explicit).** Server-side and client-side rule sets on
  GitHub/Bitbucket are **disjoint** — nothing syncs them automatically. The server rules fire at *push*, so
  sensitive content can enter *local* history and only be rejected at push (forcing a painful history cleanup). We
  must mirror the server patterns into locally-enforced git hooks (fail-fast at commit) AND actively prevent the
  two rule sets from drifting apart. This is a major, first-class element of this plan (T2/T3/T4).

## What was verified via the GitHub API (2026-09-17)

Inspected with `gh` (token scopes `read:org`, `repo`, `gist` — NOT org-admin, so security-feature *config* was
not readable; those facts came from Tim):
- Org `kyosaku-kai` has 3 **public** repos: `n3x` (not a fork), `isar` (fork of upstream), `raft-l2-oracle` (not a
  fork).
- An **org-level branch ruleset** ("Main branch protection", identical id 13200731 across all repos, source =
  Organization, enforcement = active) enforces on the default branch: `deletion` block, `non_fast_forward` block,
  `required_linear_history`, `pull_request` required. Bypass = OrganizationAdmin only.
- `n3x` adds a repo-level ruleset ("n3x CI checks") requiring ~22 CI status checks + a `commit_message_pattern`
  rule (evidence the team already enforces content-pattern rules, on commit messages).
- NOT API-visible at this token level (admin-gated, all returned null / "not accessible"): per-repo
  `security_and_analysis`, secret-scanning alerts, org security defaults, the custom push-rule patterns themselves.
  **Tim confirmed the custom internal-identifier push patterns exist and are enforced server-side.**

Residual honest limits (do not block the design; carried as backstops): the server catch is pattern-based, so
prose that is confidential *without* a matching pattern still relies on the mandatory PR-review human gate; and the
server rule fires at push, which the local mirror (T3) exists to front-run.

## The collapsed target model (end state)

1. Every plan is tracked in a git repo; there is no untracked tier.
2. A plan lives in the repo whose remote audience matches its content (public → kyosaku-kai; internal → private
   counterpart; personal → a personal repo).
3. The public remote enforces appropriateness three ways at once: automated server-side push-rule pattern match,
   mandatory PR review (human semantic backstop), protected/immutable history.
4. A **local mirror** of the server push rules (shipped via the shared nixcfg claude-code hook module, so
   colleagues get identical enforcement) fails fast at commit time, and a drift guard keeps the local and server
   rule sets in sync.
5. The 057 opt-in machinery (machine-wide `**/user-plans/` default-ignore + per-repo `!user-plans/` negation) is
   retired in favour of always-track — gated on the local mirror being live (tracking-follows-enforcement).

**Gating principle (INVARIANT):** never flip a repo or the machine to always-track until the local mirror (T3) is
live in that context. Tracking must never outrun enforcement.

---

## Progress Tracking

| ID | Task | Type | Depends on | Status |
|----|------|------|-----------|--------|
| T1 | **Enumerate & canonicalize the server-side push rules.** With Tim's org-admin view (or an admin-scoped token / exported config), capture the exact kyosaku-kai custom push-rule patterns + push-protection/secret-scanning config into a single documented, version-controlled Source Of Truth (SSOT) pattern spec. | discovery (Interactive — needs admin access) | — | TASK:PENDING |
| T2 | **Design the local-mirror mechanism + SSOT + drift strategy (ADR).** Decide where the pattern SSOT lives, how client hooks consume it, pre-commit vs pre-push (or both), false-positive & bypass policy, and — since server/client are disjoint — the concrete drift-detection approach. Output an ADR. | design (artifact → Present/STOP) | T1 | TASK:PENDING |
| T3 | **Implement the local mirror as client-side git hooks** in the shared claude-code `gitSafety` hook family (nixcfg, public), reading the T2 SSOT. Fail-fast at commit on a pattern hit; four-part block message + `CLAUDE_HOOKS_BYPASS`. Ships to colleagues via nixcfg. | impl (artifact → Present/STOP) | T2 | TASK:PENDING |
| T4 | **Drift guard between local & server rule sets.** Add a check (CI and/or scheduled) that detects divergence between the local SSOT and the server config and fails/alerts. Since the server config may not be API-readable without admin, define the most automatable approach available and document the manual fallback. | impl (artifact → Present/STOP) | T1, T3 | TASK:PENDING |
| T5 | **Establish the public home for public plans in kyosaku-kai.** Decide and execute: move/fork nixcfg into the org, or create a dedicated public repo for public plans. Confirm the org ruleset + push rules apply to it. | migration decision (Interactive) | T2 | TASK:PENDING |
| T6 | **Clean the AI-attribution leak in nixcfg public history** at the migration moment (memory `project_ai_attribution_leak`: 11 commits carry Co-Authored-By). Coordinate with the nixcfg-work `flake.lock` pin constraint. History rewrite ⇒ force-push ⇒ Tim-authorized. | migration (Interactive — auth/irreversible) | T5 | TASK:PENDING |
| T7 | **Repoint nixcfg-work `flake.lock`** (and any other consumers) to the new nixcfg remote/home after migration; verify builds. | impl | T5 | TASK:PENDING |
| T8 | **Flip default posture to always-track; retire the 057 opt-in machinery.** Change the machine-wide git excludes + per-repo negations so plans are tracked by default; remove the now-unnecessary `**/user-plans/` default-ignore + `!user-plans/` gymnastics. Gated on T3 (mirror live) per the invariant. | impl (artifact → Present/STOP) | T3, T5 | TASK:PENDING |
| T9 | **Cross-audience plan policy (the 052 pattern).** Define + document the convention for plans that span public + internal (public shell + private detail split, or restrict-to-private). Apply it to plan 052 as the worked example. | policy (artifact → Present/STOP) | T2 | TASK:PENDING |
| T10 | **Record the central-plans-repo alternative as considered-and-superseded** (short ADR / design note capturing the analysis + why kyosaku-kai supersedes it). | doc | — | TASK:PENDING |

---

## Task detail & Definition of Done

### T1 — Enumerate & canonicalize the server-side push rules `TASK:PENDING`
Interactive — requires org-admin visibility Claude's token lacks. With Tim: enumerate, from the kyosaku-kai org
security settings, the exact custom push-rule patterns (the internal-identifier regexes/terms), whether secret
scanning + push protection are on, and which repos they apply to. Capture them verbatim into a single documented,
version-controlled **SSOT pattern spec** (location decided in T2 but the content is captured here). Redact nothing
that is itself an internal secret — if a *pattern* is itself sensitive, record it in the private counterpart, not a
public file (this task must itself obey the boundary it is documenting).
**DoD:** a reviewed artifact exists listing every server-enforced pattern + the push-protection/secret-scanning
on/off state per repo, stored in an audience-appropriate repo; Tim confirms it matches the live org config.
Under headless `/next-task` this yields USER_INPUT_REQUIRED (needs admin access).

### T2 — Design the local-mirror mechanism + SSOT + drift strategy (ADR) `TASK:PENDING`
Depends on T1. Produce an ADR answering: (a) **SSOT location** — one canonical pattern file both server and client
derive from (and how the server side is fed from it, or, if the server is authored independently, how they are
reconciled); (b) **client enforcement point** — pre-commit (fail-fast, spares rejected-push history cleanup) vs
pre-push (matches the server's actual gate) vs both, with the trade-offs; (c) **false-positive & bypass policy** —
`CLAUDE_HOOKS_BYPASS` escape, and how a legitimate mention is allowed; (d) **drift detection** — the disjoint-rule
problem: how we detect and alarm when local and server patterns diverge (CI diff against an exported server config,
a versioned checksum, a periodic admin export, etc.), including the manual fallback if the server config is not
API-readable. Use the `adr-writer` skill.
**DoD:** ADR committed under `docs/adr/` (audience-appropriate repo); Present/STOP sign-off from Tim before COMPLETE.

### T3 — Implement the local mirror as client-side git hooks `TASK:PENDING`
Depends on T2. Implement in the shared claude-code `gitSafety` hook family (`modules/programs/claude-code/_hm/hooks.nix`,
same contract as the 056/057 sub-hooks): a PreToolUse/`git` hook (and/or a real repo `pre-commit`/`pre-push` hook —
per T2's decision) that scans staged content / commit range against the SSOT patterns and blocks on a hit with the
four-part message (WHY / PROCEED-NOW / AVOID-FUTURE / docs link) + `CLAUDE_HOOKS_BYPASS`. FALSE-POSITIVE analysis
required (must not block legitimate mentions or unrelated files). Ships to colleagues through nixcfg (public).
**DoD:** `nix flake check --no-build` passes; a VM/shell test proves the hook BLOCKS a planted internal-identifier
in a staged plan file and does NOT false-positive on a clean plan; Present/STOP before COMPLETE.

### T4 — Drift guard between local & server rule sets `TASK:PENDING`
Depends on T1, T3. Add an automated check that flags divergence between the local SSOT and the server config
(ideally CI comparing an exported/queried server config to the SSOT; if the server config is admin-only and not
CI-accessible, define the least-manual reconciliation — e.g. a periodic admin export committed to the SSOT repo, with
a check that fails if the export is stale). Document the chosen mechanism and its assumptions.
**DoD:** the check fails on an intentional local/server mismatch and passes when aligned (demonstrated); mechanism
documented. Present/STOP before COMPLETE. NOTE: may be partly BLOCKED-BY-DEP on T1's access outcome — if the server
config cannot be read programmatically, this task delivers the manual-export fallback, not a live automated diff.

### T5 — Establish the public home for public plans in kyosaku-kai `TASK:PENDING`
Depends on T2. Decide (Interactive) between: fork/move nixcfg into kyosaku-kai; or create a dedicated public repo
for public plans; considering the upstream relationship, existing consumers, and the public presence. Execute the
decision; confirm the org branch ruleset + custom push rules apply to the resulting repo.
**DoD:** decision recorded with rationale; if executed, the repo exists in kyosaku-kai with the org ruleset active
(verify via `gh api .../rulesets`) and push rules confirmed by Tim. USER_INPUT_REQUIRED under headless.

### T6 — Clean the AI-attribution leak in nixcfg history `TASK:PENDING`
Depends on T5. At the migration moment, remove the Co-Authored-By / AI-attribution markers from the 11 public
nixcfg commits (memory `project_ai_attribution_leak`). This is a history rewrite ⇒ force-push ⇒ breaks the
nixcfg-work `flake.lock` pin — must be sequenced with T7 and authorized by Tim (authentication + irreversible).
**DoD:** public history free of AI-attribution markers (`git log --all --grep` returns none) OR an explicit,
recorded decision to defer with rationale. USER_INPUT_REQUIRED under headless (force-push authorization).

### T7 — Repoint nixcfg-work flake.lock (and other consumers) `TASK:PENDING`
Depends on T5. After the nixcfg home/remote changes (and any T6 rewrite), update the nixcfg-work `flake.lock` pin
(and any other repos pinning nixcfg) to the new source; verify they still evaluate/build.
**DoD:** `nix flake check` (or the consumer's equivalent) passes against the new pin; the change is committed on a
feature branch in the consumer repo; documented.

### T8 — Flip default posture to always-track; retire 057 opt-in machinery `TASK:PENDING`
Depends on T3, T5 (and the gating invariant: mirror live before flipping). Change `modules/programs/git/git.nix`
and the per-repo `.gitignore` so plans are tracked by default rather than default-ignored-with-opt-in: remove/invert
the machine-wide `**/user-plans/` default-ignore and the per-repo `!user-plans/` negation introduced by 057. Keep
`.session-state/` always-untracked (unchanged). Update the CLAUDE.md/template prose to the always-track model.
**DoD:** a fresh repo/worktree tracks its `user-plans/` by default (no per-repo negation needed); `.session-state/`
still ignored; `nix flake check --no-build` passes; docs updated. Present/STOP before COMPLETE.

### T9 — Cross-audience plan policy (the 052 pattern) `TASK:PENDING`
Depends on T2. Define and document the convention for plans spanning public + internal audiences: the recommended
default (public shell that coordinates + private detail plan in the internal repo, linked but not leaking), and when
to instead restrict the whole plan to the private repo. Apply the convention to plan 052 (dev-team sharing
super-plan) as the worked example.
**DoD:** policy documented in an audience-appropriate location; 052 restructured or annotated to conform; Present/STOP.

### T10 — Record the central-plans-repo alternative (considered & superseded) `TASK:PENDING`
Short ADR / design note capturing: the proposal (one separate repo holding all plans, referenced by all sessions
with global r/w), its pros (single browsable source, branch-decoupled, natural cross-repo home), and the reasons it
was superseded by the kyosaku-kai approach (reintroduces out-of-cwd write-permission friction, splits plan↔code
atomicity + audit trail, conflicts with public-plans-in-nixcfg, and the absolute-path support in `.session-state/
active-plan` means it can still be adopted later for a narrow case without re-architecting now).
**DoD:** ADR/note committed under `docs/adr/`; no code change.

---

## Notes / open items (context, not tasks)
- **Relationship to 057:** 057 (working-tree layout: `user-plans/` + `.session-state/`, plus the plan-056 hook set)
  is the substrate and is unaffected. Finish 057 first (its T4/T5/T6 remain). 058 flips 057's *default posture* and
  adds enforcement; it does not undo 057.
- **Gating invariant restated:** tracking-follows-enforcement. Do not execute T8 (flip to always-track) in any
  context before T3 (local mirror) is live there.
- **Backstops that remain by design:** mandatory PR review is the semantic-confidentiality human gate the
  pattern-matchers cannot replace; keep it. The local mirror is fail-fast convenience + defense-in-depth, the server
  rule is the authoritative gate.
- **Provenance caveat for T1:** Claude's current `gh` token is not org-admin; the custom-pattern *config* is not
  API-readable at that level. T1 must source it from Tim's admin view or an elevated token.
