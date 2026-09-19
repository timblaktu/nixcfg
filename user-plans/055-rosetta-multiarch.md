# Plan 055 — Rosetta 2 / Apple-Virtualization multi-arch Nix tooling investigation

Status: ACTIVE (investigation; interactive, multi-session)
Owner: Tim
Created: 2026-08-31
Working branch: **plan-055-rosetta-multiarch** (worktree `/home/tim/src/nixcfg-rosetta`)
Mode: **A only (human-attended `/next-task`).** NOT burndown-eligible — no `Burndown: SAFE` marker.
Most tasks are either operator-gated (fleet decisions, §7 options) or require Apple Silicon hardware
that this Linux dev host does not have, so autonomous stop-the-run execution is inappropriate.

### Cross-repo relationships (surveyed 2026-08-31)
- **Parent:** `.claude/user-plans/052-dev-team-sharing-superplan.md` (nixcfg, public) — multi-arch dev-team enablement; M-A Mac bring-up, M-B CI unification, Mac-VM qcow2 distribution.
- **Feeds (does NOT fork):** `.claude/user-plans/054-vmtest-capabilities-coverage.md` (nixcfg) — 054 remains the single owner of "which backend runs which test on which host"; 055 §6 answers the Rosetta/nested-virt/TCG feasibility questions and hands them to 054 as inputs.
- **Delegates corp decisions to (nixcfg-work, private):**
  - `nixcfg-work .claude/user-plans/001-darwin-support.md` — native nix-darwin (Model A, ADR 0001), `bootstrap-darwin.sh`, Colima-for-containers with `rosetta=true` (x86 Linux *containers*), remote aarch64-darwin builder template (`hosts/pa161878-nixos/local-darwin-builder.nix`), NixOS-in-Lima (Model B) researched + kept as backup.
  - `nixcfg-work .claude/user-plans/004-machine-image-ci-release.md` — Mac-VM qcow2 build+publish (`build-mac-vm-image`/`dev-team-mac-vm`), VM-test smoketest gate (T6) + KVM runners, darwin build-runner sourcing decision (T0/T2).

## Collaboration model (DECIDED 2026-08-31 — Tim)
Split along the existing public/private seam (nixcfg = portable mechanism; nixcfg-work = corp consumer/decision,
per plan 052's sharing model). This plan does **not** move wholesale into nixcfg-work and does **not** fork 054/001/004.

- **This plan (nixcfg, public) owns:** the investigation (verify the reference doc's `[UNVERIFIED]` claims against
  real code) and any **reusable, secret-free** module wiring — a declarative `linux-builder-vz` enablement + a
  cross-arch-build / VM-test-backend option that could supersede today's `boot.binfmt.emulatedSystems`
  (`modules/system/settings/dev-team/dev-team.nix`) and the "must build the qcow2 on native aarch64" workaround
  (`modules/hosts/nixos-dev-team-vm [N]/`).
- **nixcfg-work (private) owns:** the §7 A/B/C/D **adoption decision**, fleet inventory (Q1), vendor amd64
  toolchains under Rosetta (Q8 ≈ 001's Colima-`rosetta=true` HW-VERIFY), darwin runner sourcing (004 T0/T2),
  mac-vm smoketest routing (004 T6). 055 tasks tagged `→ nixcfg-work` record the question; the decision/impl lands there.
- **Plan 054 (nixcfg) owns:** the redesigned VM-test suite + backend/host assignment. 055 P3/P4/P5 tagged
  `→ 054` produce feasibility findings that 054 absorbs.

### Sequencing directive (Tim, 2026-09-04)
Finish EVERYTHING off-Mac first, and THOROUGHLY: P1 (done) → then **PM + P8 + P6a** here on Linux. Before ANY
Apple-Silicon testing, research and **DISCUSS with Tim how the off-Mac findings could change HOW we do the darwin
integration and validation** - the explicit goal is to NOT test twice. Only after that discussion do the Mac-gated
experiments (P2-P7 → P9); those are the **front of the nixcfg-work `feat/darwin-support` work** (they define the
build / test / virtualization substrate), not a prerequisite runnable beforehand. Completing rosetta's off-Mac
portion is the priority to close out in nixcfg before pivoting to the Mac.

### What the survey found already exists (feeds P1; NOT the new mechanism)
- **Cross-arch builds today = QEMU binfmt**, not Rosetta (`dev-team.nix` `boot.binfmt.emulatedSystems`; x86_64 host
  emulates aarch64). This is the slow path reference §4.4 claims `linux-builder-vz` beats ~2.5×.
- **Mac-VM today = aarch64 NixOS qcow2 under UTM/QEMU**, not vzvm/Rosetta (`nixos-dev-team-vm [N]` → `image-vm-dev-team`;
  nixcfg-work CI builds+publishes it). Plain native-aarch64 virtualization.
- **Remote builder exists but inverted:** `pa161878-nixos` offloads aarch64-**darwin** builds *to* a Mac (same
  `nix.buildMachines` machinery reference §6.5 worries about, opposite direction).
- **Rosetta-into-a-Linux-guest already used once:** nixcfg-work Colima `rosetta=true` for x86_64 Linux *containers*
  (kas-container images) — reference §2.2's mechanism, via Lima/Colima rather than nixpkgs `linux-builder-vz`.
- **`linux-builder-vz` / `vzvm` / `virtualisation.vz` / `virtualisation.rosetta`: ZERO occurrences in either repo.**
  The mechanism this plan investigates is genuinely new to us.

## Seed / living reference (READ FIRST every session)
`.claude/user-plans/055-rosetta-multiarch-reference.md` — the compiled reference + session prompt.
Treat it as **mutable working state, not fixed instructions** (per its §0):
- Verify `[UNVERIFIED]` claims against actual code (nixpkgs, our flakes, our NixOS test defs, our CI).
- When a claim is wrong, edit the reference section directly AND add a Changelog (§11) line.
- Preserve provenance tags (`[STATED]`/`[RESEARCH]`/`[UNVERIFIED]`/`[DECISION]`).
- Do NOT escalate assumptions: nothing in reference §7 is adopted; generate no config/CI/ADR that presupposes an unmade choice.
- Close reference §9 open questions explicitly: move the answer into the body, strike it from §9.

## Core question (from reference §0)
What portion of a multi-architecture embedded Linux workflow can actually move onto Apple Silicon developer
machines, and where is the hard boundary Rosetta does not cross? Evaluate **build-side** (well-established,
low-risk) and **test-side** (architecturally constrained, generation-gated, and for x86_64 possibly nonexistent)
as **two separate decisions**, not one.

## Capability tiers (what needs what)
- **In-repo / code-only** (doable on THIS Linux host now): read nixpkgs + our flakes/tests/CI to confirm-or-refute
  reference claims; grep our configs. → P1, PM, P6a, P8.
- **Apple-Silicon-required** (ENVIRONMENT_NOT_CAPABLE here): standing up `linux-builder-vz`, running builds/VM tests
  on the vz builder, nested-virt. → P2, P3, P4, P5b, P6b, P7. Needs an M-series Mac (P4/P5 need **M3+ / macOS 15+**).
- **Operator / corp decision** (USER_INPUT_REQUIRED, lands in nixcfg-work): the off-Mac→Mac discussion gate, fleet
  inventory, §7 adoption. → PD, P0, P9.

## Progress tracking

**Row order = `/next-task` execution order.** All OFF-MAC work is grouped first (PM → P8 → P6a), followed by the
**PD discussion gate** (a deliberate STOP: `/next-task` yields USER_INPUT_REQUIRED there). Everything below PD is
Apple-Silicon or corp-decision and stays blocked on this Linux host. So a fresh session in this worktree can run
`/next-task` repeatedly to sweep the entire off-Mac set, then it halts at PD for the darwin-approach discussion.
IDs are stable (never renumbered); only order changed and P6 was split into P6a (off-Mac) / P6b (Mac).

| ID | Task | Kind · Home | Ref §·Q | Status |
|----|------|------|------|--------|
| P1 | Code-verification pass: confirm/refute reference §4 + §6 `[UNVERIFIED]` claims vs actual nixpkgs + our flakes/tests/CI; answer Q7, Q9; edit reference + Changelog | analysis · nixcfg | §4,§6 · Q7,Q9 | TASK:COMPLETE (2026-08-31) |
| PM | Portable module sketch (public): design a declarative `linux-builder-vz` enablement + cross-arch-build / VM-test-backend option that could supersede `boot.binfmt.emulatedSystems`; reusable by nixcfg-work. Design + eval-gate only — NO adoption, gated on P9 | OFF-MAC · nixcfg | §4.5,§6.5 | TASK:COMPLETE (2026-09-04) |
| P8 | Confirm Linux-VM Rosetta path status in current Apple docs (Q10); keep reference §2.2/§4 current | OFF-MAC research · nixcfg | §2.2 · Q10 | TASK:COMPLETE (2026-09-04) |
| P6a | Code half of P6: verify `virtualisation.rosetta` registers with `fixBinary` in nixpkgs source — cite the line (or its absence) in `rosetta.nix`; answer the code half of Q6 | OFF-MAC code · nixcfg | §8.6 · Q6 | TASK:COMPLETE (2026-09-04) |
| PD | **Discussion gate (Interactive):** with PM+P8+P6a done, DISCUSS with Tim how the off-Mac findings change HOW we do the darwin integration/validation, BEFORE any Mac testing ("don't test twice"). Output a recorded go-plan for the Mac phase (which of P2-P7, in what order, + any 054/001/004 adjustments) | Interactive GATE · nixcfg | §7 | TASK:COMPLETE (2026-09-04) |
| P0 | Fleet inventory: M-generation + macOS version for every dev machine | Interactive · **→ nixcfg-work** (052 M-A / 001) | §8.1 · Q1 | TASK:PENDING (dep PD — USER_INPUT_REQUIRED) |
| P2 | Baseline the build win: stand up `linux-builder-vz`, time a representative `x86_64-linux` build vs QEMU binfmt; confirm/refute 2.5× | Apple-Silicon | §8.2 | TASK:PENDING (dep P0 — ENVIRONMENT_NOT_CAPABLE here) |
| P3 | **Highest-value experiment:** does a Rosetta-translated `qemu-system-x86_64` run TCG at all? Smallest x86_64 NixOS VM test on the vz builder; record exact failure mode | Apple-Silicon · **→ 054** | §8.3 · Q2,Q3 | TASK:PENDING (dep P2 — ENVIRONMENT_NOT_CAPABLE here) |
| P4 | aarch64 VM test under nested virt (M3+/macOS 15+): enable `vz.nestedVirtualization`, run a representative aarch64 test, compare vs native aarch64 runner | Apple-Silicon (M3+) · **→ 054** | §8.4 | TASK:PENDING (dep P2 — ENVIRONMENT_NOT_CAPABLE here) |
| P5 | Scheduling behaviour: what does Nix do when a builder advertises `kvm` for an arch it can't accelerate? Test §6.5 dual-`buildMachines`; answer Q4, Q5 | Apple-Silicon + code · **→ 054 / 004** | §8.5 · Q4,Q5 | TASK:PENDING (dep P3 — ENVIRONMENT_NOT_CAPABLE here) |
| P6b | Mac half of P6: confirm x86_64 builds work under `nix build` in the sandbox on a Mac; answer the Mac half of Q6 | Apple-Silicon | §8.6 · Q6 | TASK:PENDING (dep P2 — ENVIRONMENT_NOT_CAPABLE here) |
| P7 | Vendor toolchain smoke test: run the team's amd64-only vendor ELF under Rosetta in-guest; surface AVX/JIT caveats (§3); answer Q8. Reconcile with nixcfg-work Colima `rosetta=true` path | Apple-Silicon · **→ nixcfg-work 001** | §8.7 · Q8 | TASK:PENDING (dep P2 — ENVIRONMENT_NOT_CAPABLE here) |
| P9 | **Decision:** adopt a reference §7 option (A/B/C/D) for build-side and test-side separately | Interactive DECISION · **→ nixcfg-work** | §7 | TASK:PENDING (dep P1-P7 findings — USER_INPUT_REQUIRED) |

## Definition of Done (per task)
- **P1** — every reference §4/§6 `[UNVERIFIED]` claim is either upgraded to `[RESEARCH]` (confirmed vs cited code) or
  corrected in place with a Changelog line; Q7 (NixOS-guest vs arbitrary embedded image under test) and Q9
  (`cpick/nix-rosetta-builder` referenced anywhere? `rg` proof — note the survey already found ZERO `linux-builder-vz`/
  `vzvm` usage; confirm for `cpick` too) answered and struck from §9. No Mac needed.
- **PM** — a design note (in this plan or a `docs/`-adjacent `.claude/` file) for the portable option, with an
  eval-gate (`nix flake check --no-build` green) proving the option *evaluates* on a darwin config; **no host adopts
  it** until P9. Must not presuppose a §7 choice (reference §0 rule 4).
- **P8** — reference §2.2/§4 reconciled with current Apple docs; Q10 struck.
- **PD** (gate) — a dated record, written to this plan's session log AND **exported to a COMMITTED nixcfg-work location
  so the MacBook has it** (see "Continuity" below), capturing: the consolidated off-Mac findings (PM+P8+P6a) and Tim's
  decision on how they change the darwin approach — which of P2-P7 to run, in what order, and any 054/001/004
  adjustments. No Mac task (P0/P2-P7) starts until PD is recorded. Purpose: the Mac phase runs once, deliberately.
- **P0** — a recorded fleet table partitioning machines into nested-virt-capable (M3+/macOS 15+) vs not; captured in
  nixcfg-work 001/052 M-A. Nothing in reference §6 can be planned without it.
- **P2** — wall-clock: representative `x86_64-linux` build, vz backend vs QEMU binfmt, on named hardware; 2.5×
  confirmed or refuted in reference §4.4.
- **P3** — definitive yes/no on whether Rosetta-translated QEMU TCG runs, exact failure mode if no; reference §6.4
  upgraded from `[UNVERIFIED]`; finding handed to 054.
- **P4** — aarch64 VM test wall-clock on M3+ vs native aarch64 runner; reference §6.3 confirmed; handed to 054.
- **P5** — observed Nix scheduler behaviour for the mis-advertised-`kvm` case; verdict on whether duplicate-`hostName`
  `buildMachines` composes with nix-darwin's `linux-builder` module; handed to 054/004.
- **P6a** — cite the `fixBinary`/`F`-flag registration line (or its absence) in nixpkgs `rosetta.nix` (P1 previewed
  `rosetta.nix:77 fixBinary=true` — confirm + contextualize vs Q6's code half). No Mac needed.
- **P6b** — demonstrate an x86_64 `nix build` succeeding through the sandbox on a Mac (Q6's Mac half).
- **P7** — pass/fail per vendor binary, any AVX/JIT fault recorded; reconciled with 001's Colima-rosetta result.
- **P9** — an explicit, dated `[DECISION]` in reference §1 for each of build-side and test-side, recorded in
  nixcfg-work (001 ADR or a new ADR), only after supporting tasks are done. Until then reference §7 stays "options, none adopted."

## Guardrails
- Serialize nix (no concurrent/background nix). No AI attribution in commits/PRs.
- `git commit --no-verify` (pre-commit flake-check exceeds the 2-min tool timeout).
- Do NOT generate config/CI/ADR that presupposes an unmade §7 choice (reference §0 rule 4).
- Apple-Silicon tasks yield **ENVIRONMENT_NOT_CAPABLE** on this Linux host — leave PENDING, do not fabricate results.
  Operator/corp-decision tasks yield **USER_INPUT_REQUIRED** and are executed in nixcfg-work.
- **Present/STOP gate for artifact-producing tasks (learned 2026-09-04).** `/next-task` runs a task
  autonomously, but this project's CLAUDE.md workflow is `Research → Present (STOP for confirmation) → Approve
  → Execute → Validate`, and `CONSERVATIVE TASK COMPLETION` says err toward NOT self-certifying. **When a task
  produces a reviewable artifact (a new/edited module, a design choice with baked-in defaults, an ADR/decision) —
  e.g. PM — present the design + any defaults and STOP for Tim's sign-off BEFORE marking COMPLETE and committing.**
  The project's Present/STOP gate wins over `/next-task`'s autonomy for these. Pure research / code-confirmation
  tasks (P8, P6a) are lower-stakes and closer to safe-autonomous, but still surface findings for a quick check
  before COMPLETE since they feed the PD decision. (PM was initially self-certified COMPLETE without this gate;
  the review then caught a hardcoded `ephemeral=true` that deviated from upstream, and a tracked/untracked doc
  defect — see the 2026-09-04 session-log entry.)
- **Full-green DoD needs a backgrounded flake check.** When a DoD literally requires `nix flake check --no-build`
  green (not just `nix eval`), it runs ~8 min here (> the 2-min tool timeout). Run it with `run_in_background`
  and poll the log for `error:` count + an exit marker; do NOT conclude from a timed-out foreground run.
- **`$CLAUDE_PROJECT_DIR` is NOT set in the Bash tool shell.** Use the absolute worktree path
  (`/home/tim/src/nixcfg-rosetta/.claude/...`) when writing `active-plan` / `HANDOFF.md`, not `$CLAUDE_PROJECT_DIR`.

## Continuity across worktrees and to the MacBook
Off-Mac work runs in THIS worktree (`/home/tim/src/nixcfg-rosetta`, Linux). The Mac experiments (P2-P7) run on the
**MacBook**, from the **nixcfg-work `feat/darwin-support`** worktree; their findings feed 054 (nixcfg, test substrate)
and 001/004 (nixcfg-work, adoption). Two hard facts govern how state travels:

1. **This plan + the reference doc do NOT reach the MacBook via git** — never assume a Mac session can read them.
   (CORRECTED 2026-09-04: an earlier revision claimed these are "UNTRACKED (gitignored)". That is FALSE in this
   worktree — `git check-ignore` shows `.claude/user-plans/*.md` are **tracked** here. The operative reason they
   don't reach the Mac is different: they live only on the **local, unpushed** feature branch
   `plan-055-rosetta-multiarch`, and the Mac phase runs from the **nixcfg-work** clone, which never pulls this
   branch. Net conclusion is unchanged; the premise is now stated correctly.)
2. **The MacBook only has nixcfg + nixcfg-work via git.** Anything the Mac phase needs MUST be committed into a repo
   the Mac clones: **nixcfg-work** (private, darwin-facing — 001/004) for the go-plan/decision, and **nixcfg** (054 or
   a committed `docs/` note) for test-substrate findings that 054 owns.

**The PD gate is the bridge.** Its DoD requires exporting the consolidated off-Mac findings + the Mac-phase go-plan
(distilled from the untracked reference doc's confirmed, non-`[UNVERIFIED]` findings) into a COMMITTED nixcfg-work
location — append to `nixcfg-work .claude/user-plans/001-darwin-support.md` is untracked too, so prefer a **tracked**
target: a `docs/` note or ADR in nixcfg-work (and a `docs/` note in nixcfg for the 054-owned pieces). Net: the Mac
session picks up ONE committed go-plan, not this worktree. When the Mac experiments finish, their findings flow back
the same way — committed into 054 (nixcfg) and 001/004 (nixcfg-work), not into this untracked plan.

**Worktree map:** off-Mac → `/home/tim/src/nixcfg-rosetta` (here) · Mac-phase → MacBook + `nixcfg-work`
`feat/darwin-support` · findings sinks → nixcfg `054` + committed docs, nixcfg-work `001`/`004`.

## Session log
- 2026-09-04 (PD COMPLETE — discussion gate held with Tim; go-plan exported) — Ran the discussion gate
  live. Tim clarified goals: (1) Mac devs build locally, (2) run tests on Macs incl. **full emulated
  Intel VMs** for routine/CI + interactive; Intel vendor binaries nice-to-have only. **Key reframe
  surfaced + confirmed against the vzvm README** (at Tim's request, reading Nix Freaks #40's links):
  vzvm/Rosetta do NOT provide full Intel VMs (vzvm = headless build appliance, no Intel guest; Rosetta
  translates x86_64 *code in an ARM guest*, not a VM) — so the operator's primary goal is a separate
  **software-emulation** track (UTM/qemu-TCG), unaccelerated by Rosetta, and the macOS-27 Rosetta risk
  is largely irrelevant to it. **Decision (exported to a COMMITTED target so the MacBook can pick it up):
  nixcfg-work `docs/darwin/0002-multiarch-build-test-apple-silicon.md`** (branch `feat/darwin-support`,
  commit `fc91782`; needs a push by Tim to reach the Mac). Build-side ACCEPTED (adopt linux-builder-vz
  for build-locally; aarch64-native durable, x86_64-via-Rosetta a caveated convenience). Test-side / Intel
  VMs DEFERRED — measure-then-decide, honest expectation that routine CI on emulated Intel may be too slow,
  with an ARM-native (nested-virt on M4) fast fallback. **Mac-phase experiment order set:** (1) GATING —
  measure emulated x86_64 VM speed on a Mac (interactive smell test + one automated x86 NixOS VM test vs
  Intel Linux) = P3 reframed around plain emulation; (2) confirm build-locally = P2/P6b; (3) ARM-native
  test path = P4; de-prioritized P7 (vendor) + P5 (scheduler). Reference §4.8 updated with vzvm scope
  (Changelog v1.6). **Off-Mac phase of plan 055 is now fully COMPLETE (P1, PM, P8, P6a, PD).** Remaining
  tasks (P0, P2-P7, P6b, P9) are Apple-Silicon / corp-decision and run on the MacBook from nixcfg-work
  `feat/darwin-support`, driven by ADR 0002 — not from this worktree. P9 (final adopt) updates ADR 0002
  to Accepted after experiment #1.
- 2026-09-04 (P6a COMPLETE — rosetta.nix fixBinary confirmed, Q6 code half closed) — Read
  `nixos/modules/virtualisation/rosetta.nix` in our pinned nixpkgs (`ffb3c9b`, store
  `/nix/store/jpnpv93s5ppfb1kbvfp8qa763vfb4fjb-source`). **Q6 code half = YES:**
  `boot.binfmt.registrations.rosetta` sets **`fixBinary = true` (rosetta.nix:77)** — the binfmt `F` flag,
  which pre-opens the interpreter fd at registration so translation works inside the Nix build sandbox's
  mount namespace — alongside `matchCredentials`/`preserveArgvZero`/`wrapInterpreterInShell=false`, AND the
  module explicitly extends the sandbox for x86_64 (`nix.settings.extra-platforms=["x86_64-linux"]`@65,
  `extra-sandbox-paths=["/run/binfmt", mountPoint]`@66-69). Confirms P1's incidental preview and is richer
  than just the one line (purpose-built for sandboxed x86_64 builds). **Q6 Mac half (P6b) stays open** —
  demonstrating an x86_64 `nix build` through the sandbox needs a Mac. Reference §4.1 gains a P6a block,
  §9 Q6 code-half struck, Changelog v1.5 added. No code, no Mac. **Off-Mac set for plan 055 is now COMPLETE
  (P1, PM, P8, P6a) → next actionable is the PD discussion gate (deliberate STOP, USER_INPUT_REQUIRED).**
- 2026-09-04 (P8 COMPLETE — Apple-docs recheck, Q10 closed) — Verified reference §2.2 against Apple's
  live deprecation notice ("Upcoming changes to Rosetta support for Intel-based macOS apps",
  `developer.apple.com/news/?id=w5ngl9k2`) + developer docs. **Confirmed:** the deprecation is scoped to
  Intel *macOS apps* only (macOS 26.4 user notifications → macOS 27 final general-purpose Rosetta → beyond
  = unmaintained-games-only subset); it makes NO mention of the Linux/VM path, which stays a separately
  published feature (VZLinuxRosettaDirectoryShare + update-binfmts in an aarch64 guest); Apple DTS confirms
  the two are distinct use cases. **Corrected (material):** the earlier confident claim that Apple "is *not*
  sunsetting" the Linux path, and the "macOS 27 built-in / no separate install / availability always reports
  installed" statement — both unverifiable and overstated. Apple DTS explicitly declined to commit whether
  Linux-VM Rosetta survives past macOS 27, so **post-27 availability is now recorded as an OPEN RISK** that
  feeds §7 / the PD gate (build-side reliance on Rosetta-translated x86_64 has undetermined shelf life beyond
  macOS 27; the aarch64-native path does not). Reference §2.2 rewritten, §9 Q10 struck, §10 refs + §11
  Changelog v1.4 added. Research task (no code); finding surfaced for the PD discussion. **Next actionable
  off-Mac:** P6a (`rosetta.nix` `fixBinary` confirm), then the PD gate (STOP).
- 2026-09-04 (PM review with Tim; ephemeral made an option; doc defect fixed) — Post-completion review
  conversation (Tim flagged that PM was self-certified COMPLETE without the CLAUDE.md Present/Approve gate).
  Outcome: (1) **`ephemeral` promoted from a hardcoded `true` to a proper option defaulting to `false`**
  (matches upstream nix-darwin = persistent builder / warm cache; operators opt into wipe-on-restart). It was
  the only knob the module hardcoded AND it silently deviated from the upstream default — inappropriate for a
  module nixcfg-work reuses verbatim. Module + design-note option table + eval-gate re-run
  (proof (a) now shows `"ephemeral":false`; `nix flake check --no-build` re-verified exit 0, zero errors,
  13:15 PDT). (2) **Doc defect corrected:** the plan+handoff claimed the plan/reference docs are
  "UNTRACKED (gitignored)" — `git check-ignore` proves they are **tracked** in this worktree; the real reason
  they don't reach the Mac is that they live only on the local, unpushed `plan-055-rosetta-multiarch` branch
  (the Mac runs from nixcfg-work). Continuity conclusion unchanged; premise now correct. PM remains COMPLETE.
- 2026-09-04 (PM COMPLETE) — Eval-gate DoD executed and green on this x86_64-linux dev host
  (no Mac needed). Deliverables already present: the dendritic darwin module
  `modules/system/settings/linux-builder-vz/linux-builder-vz.nix` (provides
  `flake.modules.darwin.linux-builder-vz`, `linuxBuilderVz.*`, `enable` default false, imported by
  no host) and the design note `055-pm-portable-module-design.md`. **Proof (a):** a throwaway
  `aarch64-darwin` `darwinSystem` importing the module with `enable = true; nestedVirtualization =
  true;` evaluates cleanly — `{"enable":true,"packageName":"create-builder","systems":
  ["aarch64-linux","x86_64-linux"],"trustedUsersHasAdmin":true}` (the `create-builder` package name
  confirms `pkgs.darwin.linux-builder-vz` resolved from our pinned nixpkgs). **Proof (b):**
  `nix flake check --no-build` exit 0, zero `error:` lines (only the standard "omitted aarch64-linux"
  note + a pre-existing unrelated `proxmox.qemuConf.diskSize` warning). Confirmed the design note's
  stated boundary: reading guest-side leaves (`nix.linux-builder.config.virtualisation.*`) via the
  host eval fails ("attribute 'virtualisation' missing") because `config` is a deferred guest module,
  not force-evaluated — exactly as §4 "Boundary" documents; validated only on a Mac (P2/P4). No host
  adopts the module; §7 choice not presupposed (reference §0 rule 4). Design note updated with the
  verified timestamp. **Next actionable off-Mac:** P8 (Apple-docs Rosetta-for-Linux recheck), then
  P6a (`rosetta.nix` `fixBinary` confirm), then the PD discussion gate (STOP).
- 2026-09-04 (plan restructured for off-Mac continuity — Tim) — Reordered the progress table so `/next-task`
  sweeps the off-Mac set consecutively: **PM → P8 → P6a**, then halts at the new **PD** discussion gate
  (USER_INPUT_REQUIRED). Split P6 into P6a (off-Mac code) / P6b (Mac); IDs stable. Added the **PD gate** whose DoD
  is the cross-machine bridge: export consolidated off-Mac findings + the Mac-phase go-plan into COMMITTED targets
  (nixcfg-work docs/ADR for the decision; nixcfg 054/docs for test-substrate findings) so the MacBook — which only
  has the repos via git and CANNOT see this untracked plan/reference — picks up one committed go-plan. Added the
  "Continuity across worktrees and to the MacBook" section. No task status changed; next actionable remains PM.
- 2026-08-31 (P1 COMPLETE) — Code-verification pass (host-independent, no Mac). Verified against live
  nixos-unstable (mcp-nixos) + both repos. **Confirmed upstream:** `darwin.linux-builder-vz` + `vzvm`
  v1.0.0 exist (§4.2); `virtualisation.rosetta.{enable,mountTag}` exist (§4.1); `nix.linux-builder.*`
  config shape exists (§4.5). **Option paths confirmed in source:** `virtualisation.vz.{rosetta.enable,
  nestedVirtualization}` are real (`vz-vm.nix:81,100`); they were merely absent from search.nixos.org
  (index lag), NOT a discrepancy. **Q7 CLOSED:** systems-under-test are NixOS guests (19
  `nixosTest`/`runNixOSTest`, 26 `self.modules.nixos.*`; zero embedded/cross-arch guests). **Q9 CLOSED:**
  zero `cpick`/rosetta-builder refs anywhere. **New findings:** our top-level `inputs.nixpkgs` = rev
  `ffb3c9b`/2026-08-19 (post-merge) **already contains** the mechanism — no bump needed (self-corrected:
  an initial note wrongly cited a transitive `62c8382`/Jan-30 lock node as our root nixpkgs); §6.4
  x86-on-Mac pathology not currently triggered (all tests host-arch; aarch64 gate on KVM-metal runner);
  §6.3 KVM premise already true for us (`vm-dev-team-vm-smoketest` needs hardware `/dev/kvm`); incidental
  P6a preview — `rosetta.nix:77` sets `fixBinary = true`. Reference §4.1/§4.2/§4.5/§6.3/§6.4/§6.6 edited,
  §9 Q7+Q9 struck, Changelog v1.2 + v1.3 (self-correction) added. Empirical benchmark/TCG claims (§4.4/§6.3/§6.4) correctly remain
  `[UNVERIFIED]` — they need a Mac and are delegated to P2/P3/P4, not P1's scope.
  **Next in-repo:** PM (portable module sketch, dep P1 met — design + eval-gate only), then P6a
  (nixpkgs `rosetta.nix` `fixBinary`) and P8 (Apple-docs recheck). All are host-independent.
- 2026-08-31 — Plan created; worktree `/home/tim/src/nixcfg-rosetta` + branch `plan-055-rosetta-multiarch` cut from
  `main`; reference doc imported. **Cross-repo survey done** (nixcfg + nixcfg-work, all worktrees/branches): mapped
  existing darwin/Mac-VM/cross-arch work; found the vz/Rosetta-linux-builder mechanism is new to us, with real overlap
  onto 052/054/001/004. **Collaboration model decided (Tim):** split public/private, feed 054 (don't fork). Plan
  reframed accordingly (added PM portable-module task; tagged P0/P7/P9 → nixcfg-work, P3/P4/P5 → 054).
  Next actionable in-repo work: **P1** (code-verification pass), then **PM** (portable module design) and **P6a**
  (nixpkgs `rosetta.nix` `fixBinary` check); **P8** (Apple-docs recheck) is also host-independent. All Apple-Silicon
  tasks await a Mac + P0 fleet inventory (tracked in nixcfg-work).
