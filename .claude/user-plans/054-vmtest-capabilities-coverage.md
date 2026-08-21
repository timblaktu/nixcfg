# Plan 054 — VMTest suite audit & refactor (nixcfg + nixcfg-work)

Status: ACTIVE (VMTest workstream; follows 053's nspawn backend enablement)
Owner: Tim
Created: 2026-08-20
Parent: `.claude/user-plans/052-dev-team-sharing-superplan.md` (M-E testing family; enabler for M-B CI)
Working branch: **TBD (P0)** — 053's nspawn work landed on `main`; decide `main` vs `feat/vmtest-refactor`.

## Goal (reframed 2026-08-20 — Tim)
NOT "add tests to raise host coverage." The goal is to **fully analyze the tests we already have —
focusing on actual CODE / FEATURE coverage, not just host coverage — and refactor everything (nothing
is sacred) toward a single cohesive, effective set of NixOS VMTests built from BOTH `nodes` (QEMU) and
`containers` (nspawn) constructs.** Deleting, merging, and rewriting existing tests is in scope.
Per-host smoke and QEMU→nspawn migration are *outcomes* of the analysis, not the objective.

## Method — phased (analysis before surgery)
- **P1 Inventory:** enumerate EVERY check across both repos and record what each actually asserts.
- **P2 Coverage map:** map tests → the modules/features they exercise. Surface the real picture:
  which features are well-covered, thinly-covered, untested, or only eval-gated. This is the heart.
- **P3 Assessment:** per test — value (real / redundant / weak / obsolete), correct backend
  (node vs container vs eval-only / drop), overlaps to merge. "Nothing is sacred."
- **P4 Target design:** the redesigned suite — keep/merge/rewrite/drop/add, with a backend assignment
  and a feature-coverage rationale. Agreed with Tim before execution.
- **P5 Execute:** implement the target (incl. nspawn conversions, new tests for real gaps, deletions).
- **P6 CI + nixcfg-work:** wire the redesigned suite into CI (matrix + nspawn runner config) and carry
  the cohesive approach into nixcfg-work's corp hosts.

## Progress tracking
| ID | Task | Kind | Status |
|----|------|------|--------|
| P0 | Decide working branch (main vs feat/vmtest-refactor) | Interactive | TASK:PENDING |
| P1 | Full test inventory (both repos) — every check + what it asserts | 1 · analysis | TASK:PENDING |
| P2 | Feature/code coverage map — tests → modules/features; gaps + redundancy | 1 · analysis | TASK:PENDING (dep P1) |
| P3 | Per-test assessment — value + correct backend + overlaps (nothing sacred) | Interactive (collaborative) | TASK:PENDING (dep P2) |
| P4 | Target suite design — keep/merge/rewrite/drop/add + backend + rationale | Interactive (collaborative) | TASK:PENDING (dep P3) |
| P5 | Execute the refactor (conversions, new tests, deletions) | 1 · portable | TASK:PENDING (dep P4) |
| P6 | CI wiring + carry into nixcfg-work corp hosts | 1 · CI / nixcfg-work | TASK:PENDING (dep P5) |

## Inputs already gathered this session (feed P1-P3)
- **Backend capability (053 T6, DONE):** `mkVmTest` (QEMU) + `mkContainerTest` (nspawn, proven,
  daemon-path verified, ~5-7× faster). Guide + caveats in `docs/TESTING-NSPAWN.md` (service-unit
  differences e.g. `sshd.socket` not `sshd.service`; networking; fidelity limits).
- **Current surface (nixcfg):** 22 `vm-*` tests, all composing MODULES not host configs; plus
  `eval-*`, `build-*-dryrun`, integration (`tests/integration/*`), unit (`tests/{sops-*,ssh-*}`),
  `cross-module-*`, `module-*-integration`, `lint-*`, `skill-injection-*`. Full enumeration = P1.
- **Full-host-in-container = conflict cascade** (`nixpkgs.hostPlatform` read-only + `systemd-resolved`
  assertion + more) — so host-level tests are layer+settings compositions or QEMU, not literal hosts.
- **Host classification (see table below):** most per-host container smoke would be REDUNDANT with
  existing layer tests; the one clear untested feature-set is **`nuc-apt-repo`** (aptly + apt-cacher-ng).
  This is a P2/P3 input, not a standalone task anymore.
- **nixcfg-work:** ~zero VMTests of its own (re-exports 1 nixcfg check); nixpkgs `331800d` has nspawn;
  container tests there couple with T8b (pin bump → 26.05 uplift) unless done self-contained.

### Host classification (2026-08-20) — feature-coverage lens
| Host | Distinct runtime content | Already covered by | Note |
|---|---|---|---|
| **nuc-apt-repo** | `aptly-repo` + `apt-cacher-ng` (UNIQUE services) | nothing | real feature gap |
| nixos-dev-team | `dev-team` layer | `vm-dev-team-stack` | layer covered |
| nixos-dev-team-ec2/-graviton/-vm | dev-team + image | layer + image-build checks (+ `vm-dev-team-vm-smoketest`) | image=build/boot |
| nixos-wsl-dev-team / -minimal | WSL | `Test-WslImport.ps1` (shipped image) | WSL=image test |
| potato | `system-default` (aarch64 SBC) | `vm-system-type-default` | HW=real SBC |
| mbp | `system-cli` | `vm-system-type-cli` | layer covered |
| thinky-nixos | personal + WSL | (personal) | skip / WSL image |

## Guardrails
Serialize nix. No AI attribution. Analysis (P1-P4) before deletion/rewrite. Container tests need the
nspawn nix config on the builder (053 T6). nixcfg-work container work couples with T8b unless
self-contained. Confirm any merge to `main` / nixcfg-work pin bump with Tim. "Nothing is sacred" means
tests CAN be dropped/rewritten — but only with a recorded rationale (P3/P4), never silently.

## Session log
- 2026-08-20 (authoring + reframe): created after 053 T6. Probed full-host-in-container → conflict
  cascade. Tim first picked per-host smoke (#3) + review-then-migrate (#1), then **reframed the whole
  effort**: not coverage-adding but a full AUDIT + REFACTOR of the VMTest suite around code/feature
  coverage, nothing sacred, both nodes+containers. Restructured the plan into phases P1-P6. Next: P1
  inventory.
