# Plan 055 — Rosetta 2 / Apple-Virtualization multi-arch Nix tooling investigation

Status: ACTIVE (investigation; interactive, multi-session)
Owner: Tim
Created: 2026-08-31
Working branch: **plan-055-rosetta-multiarch** (worktree `/home/tim/src/nixcfg-rosetta`)
Parent: `.claude/user-plans/052-dev-team-sharing-superplan.md` (multi-arch dev-team enablement)
Related: `.claude/user-plans/054-vmtest-capabilities-coverage.md` (§6 VM-test analysis intersects the suite refactor)
Mode: **A only (human-attended `/next-task`).** NOT burndown-eligible — no `Burndown: SAFE` marker.
Most tasks are either operator-gated (fleet decisions, §7 options) or require Apple Silicon hardware
that this Linux dev host does not have, so autonomous stop-the-run execution is inappropriate.

## Seed / living reference (READ FIRST every session)
`.claude/user-plans/055-rosetta-multiarch-reference.md` — the compiled reference + session prompt.
Treat it as **mutable working state, not fixed instructions** (per its §0):
- Verify `[UNVERIFIED]` claims against actual code (nixpkgs, our flakes, our NixOS test defs, our CI).
- When a claim is wrong, edit the reference section directly AND add a Changelog (§11) line.
- Preserve provenance tags (`[STATED]`/`[RESEARCH]`/`[UNVERIFIED]`/`[DECISION]`).
- Do NOT escalate assumptions: nothing in reference §7 is adopted; generate no config/CI/ADR that
  presupposes an unmade choice.
- Close reference §9 open questions explicitly: move the answer into the body, strike it from §9.

## Core question (from reference §0)
What portion of a multi-architecture embedded Linux workflow can actually move onto Apple Silicon
developer machines, and where is the hard boundary Rosetta does not cross? Evaluate **build-side**
(well-established, low-risk) and **test-side** (architecturally constrained, generation-gated, and for
x86_64 possibly nonexistent) as **two separate decisions**, not one.

## Capability tiers (what needs what)
- **In-repo / code-only** (doable on THIS Linux host now): read nixpkgs + our flakes/tests/CI to
  confirm-or-refute reference claims; grep our configs. → P1, P6a, P8a.
- **Apple-Silicon-required** (ENVIRONMENT_NOT_CAPABLE here): anything standing up `linux-builder-vz`,
  running builds/VM tests on the vz builder, nested-virt. → P2, P3, P4, P5b, P6b, P7. Needs an M-series
  Mac (P4/P5 need **M3+ / macOS 15+**). These stay PENDING until run on a Mac.
- **Operator decision** (USER_INPUT_REQUIRED): fleet inventory, adopting a §7 option. → P0, P9.

## Progress tracking
| ID | Task | Kind | Reference §·Q | Status |
|----|------|------|------|--------|
| P0 | Fleet inventory: M-generation + macOS version for every dev machine | Interactive (operator) | §8.1 · Q1 | TASK:PENDING |
| P1 | Code-verification pass: confirm/refute reference §4 + §6 `[UNVERIFIED]` claims vs actual nixpkgs + our flakes/tests/CI; answer Q7, Q9; edit reference + Changelog | 1 · analysis (in-repo) | §4,§6 · Q7,Q9 | TASK:PENDING |
| P2 | Baseline the build win: stand up `linux-builder-vz`, time a representative `x86_64-linux` build vs QEMU binfmt; confirm/refute 2.5× | Apple-Silicon | §8.2 | TASK:PENDING (dep P0) |
| P3 | **Highest-value experiment:** does a Rosetta-translated `qemu-system-x86_64` run TCG at all? Smallest x86_64 NixOS VM test on the vz builder; record exact failure mode | Apple-Silicon | §8.3 · Q2,Q3 | TASK:PENDING (dep P2) |
| P4 | aarch64 VM test under nested virt (M3+/macOS 15+): enable `vz.nestedVirtualization`, run a representative aarch64 test, compare vs native aarch64 runner | Apple-Silicon (M3+) | §8.4 | TASK:PENDING (dep P2) |
| P5 | Scheduling behaviour: what does Nix do when a builder advertises `kvm` for an arch it can't accelerate? Test §6.5 dual-`buildMachines` approach; answer Q4, Q5 | Apple-Silicon + code | §8.5 · Q4,Q5 | TASK:PENDING (dep P3) |
| P6 | binfmt-in-sandbox: (a) verify `virtualisation.rosetta` registers with `fixBinary` in nixpkgs source [code]; (b) confirm x86_64 builds work under `nix build` in the sandbox [Mac]; answer Q6 | (a) code / (b) Apple-Silicon | §8.6 · Q6 | TASK:PENDING (dep P2 for b) |
| P7 | Vendor toolchain smoke test: run the team's amd64-only vendor ELF under Rosetta in-guest; surface AVX/JIT caveats (§3); answer Q8 | Apple-Silicon | §8.7 · Q8 | TASK:PENDING (dep P2) |
| P8 | Confirm Linux-VM Rosetta path status in current Apple docs (Q10); keep reference §2.2/§4 current | 1 · research | §2.2 · Q10 | TASK:PENDING |
| P9 | **Decision:** adopt a reference §7 option (A/B/C/D) for build-side and test-side separately | Interactive (DECISION) | §7 | TASK:PENDING (dep P1-P7 findings) |

## Definition of Done (per task)
- **P0** — a recorded table (in this plan) partitioning the fleet into nested-virt-capable (M3+/macOS 15+)
  vs not. Nothing in reference §6 can be planned without it.
- **P1** — every reference §4/§6 `[UNVERIFIED]` claim is either upgraded to `[RESEARCH]` (confirmed vs
  cited code) or corrected in place with a Changelog line; Q7 (NixOS-guest vs arbitrary embedded image
  under test) and Q9 (`cpick/nix-rosetta-builder` referenced in any of our configs? `rg` proof) answered
  and struck from §9. No Mac needed.
- **P2** — a wall-clock number: representative `x86_64-linux` build, vz backend vs QEMU binfmt, on named
  hardware; 2.5× confirmed or refuted in reference §4.4.
- **P3** — a definitive yes/no on whether Rosetta-translated QEMU TCG runs, with the exact failure mode
  captured if no; reference §6.4 upgraded from `[UNVERIFIED]`.
- **P4** — aarch64 VM test wall-clock on M3+ vs a native aarch64 runner; reference §6.3 confirmed.
- **P5** — observed Nix scheduler behaviour for the mis-advertised-`kvm` case; verdict on whether
  duplicate-`hostName` `buildMachines` composes with nix-darwin's `linux-builder` module.
- **P6** — (a) cite the `fixBinary`/`F`-flag registration line (or its absence) in nixpkgs
  `rosetta.nix`; (b) demonstrate an x86_64 `nix build` succeeding through the sandbox on a Mac.
- **P7** — pass/fail per vendor binary, with any AVX/JIT fault recorded.
- **P8** — reference §2.2/§4 reconciled with current Apple docs; Q10 struck.
- **P9** — an explicit, dated `[DECISION]` in reference §1 for each of build-side and test-side, only
  after the supporting tasks are done. Until then reference §7 stays "options, none adopted."

## Guardrails
- Serialize nix (no concurrent/background nix). No AI attribution in commits/PRs.
- `git commit --no-verify` (pre-commit flake-check exceeds the 2-min tool timeout).
- Do NOT generate config/CI/ADR that presupposes an unmade §7 choice (reference §0 rule 4).
- Apple-Silicon tasks yield **ENVIRONMENT_NOT_CAPABLE** on this Linux host — leave PENDING, do not
  fabricate results. Operator-decision tasks yield **USER_INPUT_REQUIRED**.

## Session log
- 2026-08-31 — Plan created; worktree `/home/tim/src/nixcfg-rosetta` + branch `plan-055-rosetta-multiarch`
  cut from `main`; reference doc imported to `055-rosetta-multiarch-reference.md`; active-plan repointed.
  Next actionable in-repo work: **P1** (code-verification pass) and the code half of **P6a**; **P8**
  (Apple-docs recheck) is also host-independent. All Apple-Silicon tasks await a Mac + P0 fleet inventory.
