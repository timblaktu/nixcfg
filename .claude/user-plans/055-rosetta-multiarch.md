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
- **Operator / corp decision** (USER_INPUT_REQUIRED, lands in nixcfg-work): fleet inventory, §7 adoption. → P0, P9.

## Progress tracking
| ID | Task | Kind · Home | Ref §·Q | Status |
|----|------|------|------|--------|
| P1 | Code-verification pass: confirm/refute reference §4 + §6 `[UNVERIFIED]` claims vs actual nixpkgs + our flakes/tests/CI; answer Q7, Q9; edit reference + Changelog | analysis · nixcfg | §4,§6 · Q7,Q9 | TASK:COMPLETE (2026-08-31) |
| PM | Portable module sketch (public): design a declarative `linux-builder-vz` enablement + cross-arch-build / VM-test-backend option that could supersede `boot.binfmt.emulatedSystems`; reusable by nixcfg-work. Design + eval-gate only — NO adoption, gated on P9 | portable module · nixcfg | §4.5,§6.5 | TASK:PENDING (dep P1; design-only until P9) |
| P8 | Confirm Linux-VM Rosetta path status in current Apple docs (Q10); keep reference §2.2/§4 current | research · nixcfg | §2.2 · Q10 | TASK:PENDING |
| P0 | Fleet inventory: M-generation + macOS version for every dev machine | Interactive · **→ nixcfg-work** (052 M-A / 001) | §8.1 · Q1 | TASK:PENDING |
| P2 | Baseline the build win: stand up `linux-builder-vz`, time a representative `x86_64-linux` build vs QEMU binfmt; confirm/refute 2.5× | Apple-Silicon | §8.2 | TASK:PENDING (dep P0) |
| P3 | **Highest-value experiment:** does a Rosetta-translated `qemu-system-x86_64` run TCG at all? Smallest x86_64 NixOS VM test on the vz builder; record exact failure mode | Apple-Silicon · **→ 054** | §8.3 · Q2,Q3 | TASK:PENDING (dep P2) |
| P4 | aarch64 VM test under nested virt (M3+/macOS 15+): enable `vz.nestedVirtualization`, run a representative aarch64 test, compare vs native aarch64 runner | Apple-Silicon (M3+) · **→ 054** | §8.4 | TASK:PENDING (dep P2) |
| P5 | Scheduling behaviour: what does Nix do when a builder advertises `kvm` for an arch it can't accelerate? Test §6.5 dual-`buildMachines`; answer Q4, Q5 | Apple-Silicon + code · **→ 054 / 004** | §8.5 · Q4,Q5 | TASK:PENDING (dep P3) |
| P6 | binfmt-in-sandbox: (a) verify `virtualisation.rosetta` registers with `fixBinary` in nixpkgs source [code]; (b) confirm x86_64 builds work under `nix build` in the sandbox [Mac]; answer Q6 | (a) code nixcfg / (b) Apple-Silicon | §8.6 · Q6 | TASK:PENDING (dep P2 for b) |
| P7 | Vendor toolchain smoke test: run the team's amd64-only vendor ELF under Rosetta in-guest; surface AVX/JIT caveats (§3); answer Q8. Reconcile with nixcfg-work Colima `rosetta=true` path | Apple-Silicon · **→ nixcfg-work 001** | §8.7 · Q8 | TASK:PENDING (dep P2) |
| P9 | **Decision:** adopt a reference §7 option (A/B/C/D) for build-side and test-side separately | Interactive DECISION · **→ nixcfg-work** | §7 | TASK:PENDING (dep P1-P7 findings) |

## Definition of Done (per task)
- **P1** — every reference §4/§6 `[UNVERIFIED]` claim is either upgraded to `[RESEARCH]` (confirmed vs cited code) or
  corrected in place with a Changelog line; Q7 (NixOS-guest vs arbitrary embedded image under test) and Q9
  (`cpick/nix-rosetta-builder` referenced anywhere? `rg` proof — note the survey already found ZERO `linux-builder-vz`/
  `vzvm` usage; confirm for `cpick` too) answered and struck from §9. No Mac needed.
- **PM** — a design note (in this plan or a `docs/`-adjacent `.claude/` file) for the portable option, with an
  eval-gate (`nix flake check --no-build` green) proving the option *evaluates* on a darwin config; **no host adopts
  it** until P9. Must not presuppose a §7 choice (reference §0 rule 4).
- **P8** — reference §2.2/§4 reconciled with current Apple docs; Q10 struck.
- **P0** — a recorded fleet table partitioning machines into nested-virt-capable (M3+/macOS 15+) vs not; captured in
  nixcfg-work 001/052 M-A. Nothing in reference §6 can be planned without it.
- **P2** — wall-clock: representative `x86_64-linux` build, vz backend vs QEMU binfmt, on named hardware; 2.5×
  confirmed or refuted in reference §4.4.
- **P3** — definitive yes/no on whether Rosetta-translated QEMU TCG runs, exact failure mode if no; reference §6.4
  upgraded from `[UNVERIFIED]`; finding handed to 054.
- **P4** — aarch64 VM test wall-clock on M3+ vs native aarch64 runner; reference §6.3 confirmed; handed to 054.
- **P5** — observed Nix scheduler behaviour for the mis-advertised-`kvm` case; verdict on whether duplicate-`hostName`
  `buildMachines` composes with nix-darwin's `linux-builder` module; handed to 054/004.
- **P6** — (a) cite the `fixBinary`/`F`-flag registration line (or its absence) in nixpkgs `rosetta.nix`;
  (b) demonstrate an x86_64 `nix build` succeeding through the sandbox on a Mac.
- **P7** — pass/fail per vendor binary, any AVX/JIT fault recorded; reconciled with 001's Colima-rosetta result.
- **P9** — an explicit, dated `[DECISION]` in reference §1 for each of build-side and test-side, recorded in
  nixcfg-work (001 ADR or a new ADR), only after supporting tasks are done. Until then reference §7 stays "options, none adopted."

## Guardrails
- Serialize nix (no concurrent/background nix). No AI attribution in commits/PRs.
- `git commit --no-verify` (pre-commit flake-check exceeds the 2-min tool timeout).
- Do NOT generate config/CI/ADR that presupposes an unmade §7 choice (reference §0 rule 4).
- Apple-Silicon tasks yield **ENVIRONMENT_NOT_CAPABLE** on this Linux host — leave PENDING, do not fabricate results.
  Operator/corp-decision tasks yield **USER_INPUT_REQUIRED** and are executed in nixcfg-work.

## Session log
- 2026-08-31 (P1 COMPLETE) — Code-verification pass (host-independent, no Mac). Verified against live
  nixos-unstable (mcp-nixos) + both repos. **Confirmed upstream:** `darwin.linux-builder-vz` + `vzvm`
  v1.0.0 exist (§4.2); `virtualisation.rosetta.{enable,mountTag}` exist (§4.1); `nix.linux-builder.*`
  config shape exists (§4.5). **Flagged discrepancy:** `virtualisation.vz.*` option paths (§4.5/§6.3)
  not in the options index → downgraded to `[UNVERIFIED]`, source confirmation handed to P6a/PM.
  **Q7 CLOSED:** systems-under-test are NixOS guests (19 `nixosTest`/`runNixOSTest`, 26
  `self.modules.nixos.*`; zero embedded/cross-arch guests). **Q9 CLOSED:** zero `cpick`/rosetta-builder
  refs anywhere. **New findings:** our nixpkgs pin (2026-01-30) predates the Aug-2026 merge (mechanism
  not in our lock; adoption needs a bump); §6.4 x86-on-Mac pathology not currently triggered (all tests
  host-arch; aarch64 gate on KVM-metal runner); §6.3 KVM premise already true for us
  (`vm-dev-team-vm-smoketest` needs hardware `/dev/kvm`). Reference §4.1/§4.2/§4.5/§6.3/§6.4/§6.6 edited,
  §9 Q7+Q9 struck, Changelog v1.2 added. Empirical benchmark/TCG claims (§4.4/§6.3/§6.4) correctly remain
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
