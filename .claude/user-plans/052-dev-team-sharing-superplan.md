# Plan 052 — Super-plan: Share nixcfg nix-darwin + NixOS VM/WSL configs with the dev team

Status: PLANNING (coordinating meta-plan; milestone ordering = first open decision)
Owner: Tim
Created: 2026-08-20
Kind: **Coordinating meta-plan** — it TRACKS and sequences sub-plans that live in two
repos; it does NOT duplicate their task detail. Detailed tasks stay in their home plans.

## PUBLIC-SAFETY CONSTRAINT (read first)
This plan lives in **public `nixcfg`** (github.com/timblaktu/nixcfg). It MUST NOT contain
corporate secrets, internal URLs, GitLab hostnames, tokens, CIDs, or runner names. It
references the private `nixcfg-work` sub-plans **by number/name only**. Any secret-bearing
detail belongs in the corresponding `~/src/nixcfg-work/.claude/user-plans/` plan, not here.

## Super-goal
Make it turnkey for a dev-team colleague to run Tim's nixcfg-derived environment on their
own machine, across BOTH delivery shapes:
- **NixOS VM/WSL images** (the mostly-working half): WSL `.wsl`, Proxmox, EC2/Graviton AMI,
  and the aarch64 **Mac-VM qcow2** (UTM/QEMU on Apple Silicon).
- **Native nix-darwin** (the frontier half): a shared `corp-darwin-dev-team` config a
  colleague activates directly on an Apple-Silicon Mac.
…unified under one delivery + consumption + validation story, warm-cached for practical use.

## Two-repo / two-layer architecture
- **`nixcfg` (public) = shared substrate.** 47+ reusable modules, the distributable-image
  builders (WSL/Proxmox/EC2/Graviton/Mac-VM qcow2), the VM-test tiers (`mkVmTest`), and the
  distribution mechanism + docs. This is where the portable, secret-free work lands.
- **`nixcfg-work` (private, corporate GitLab) = deployment layer.** The real corp hosts
  (`corp-wsl-dev-team`, `corp-darwin-dev-team`, Tim's `pa163076mac`), the GitLab CI release
  pipeline, IT/compliance values. Consumes `nixcfg` as a flake input (currently pins nixcfg
  `main`). Cross-repo: several nixcfg changes only go LIVE via a nixcfg-work `flake.lock` bump.

## Constituent sub-plans (source of truth for detail)

### ACTIVE — in scope
| Plan | Repo | What | State (2026-08-20) |
|---|---|---|---|
| **026** team-sharing-refactoring | nixcfg | made the repo a shareable library + CrowdStrike module | DONE **except T6** (IT/Falcon demo — human/IT-gated) |
| **001** darwin-support | nixcfg-work | shared `corp-darwin-dev-team` nix-darwin config | Advanced WIP: **eval-green, NEVER activated on real Apple Silicon**; remaining tasks all hardware/Interactive/parked |
| **004** machine-image-ci-release | nixcfg-work | one GitLab pipeline for every distributable artifact | Active WIP: qcow2 build+publish already live; darwin-cache + macOS runner + metal-KVM gate not stood up; 5 T0 decisions open |

### CLOSED — context only (do NOT resurface in "what's active" searches)
| Plan | Repo | Why closed |
|---|---|---|
| 023 distributable-wsl-images | nixcfg `archive/` | DONE — established the 4-layer `wsl-enterprise→dev-team→host→personal` model (foundational) |
| 020 vm-test-infrastructure | nixcfg `archive/` | DONE — the `mkVmTest` CI test substrate |
| 018 nixcfg-modularization | nixcfg `archive/` | SUPERSEDED — the two-repo split idea was abandoned (single-repo won); do NOT resurrect |
| 013 distributed-nix-binary-caching | nixcfg `archive/` | DEFERRED — Attic cache, blocked on office Mikrotik/NUC hardware; a productivity multiplier, not on the sharing critical path |
| 002 corp-wsl-distribution | nixcfg-work `archive/` | DONE — a `.wsl` was built, security-checked, imported, validated end-to-end |
| 003 corp-wsl-ci-release | nixcfg-work `archive/` | SUPERSEDED — absorbed into 004 T4 (the WSL slice of the unified pipeline) |

Numbering-collision note (housekeeping H2 below): nixcfg-work still has a second, unrelated
`002-vte-eks-auth-scoping.md` (AWS EKS auth, DONE) colliding with the archived corp-wsl 002.

## Current shipped state (what already works today)
- **Shared module library:** 47+ exports consumable via `github:timblaktu/nixcfg` (bundle or
  cherry-pick); layer model `system-{minimal,default,cli,desktop}`, `wsl-{base,enterprise,dev-team}`,
  platform-neutral `dev-team` NixOS module + `home-dev-team` HM bundle; CrowdStrike Falcon module.
- **NixOS images (builders work):** `nixos-wsl-dev-team` → `.wsl` (validated end-to-end);
  `nixos-dev-team` → Proxmox; `nixos-dev-team-ec2`/`-graviton` → AMI; **`nixos-dev-team-vm`
  (aarch64) → Mac-VM qcow2** (`image-vm-dev-team`). VM-test gate + shipped-image sudo/wheel
  smoketest wired.
- **CI (partial):** nixcfg-work `.gitlab-ci.yml` already builds+publishes the Mac-VM qcow2 on
  the aarch64 Graviton runner and wires the VMTest smoketest (opt-in / non-blocking).
- **Native darwin (eval-only):** two real host configs (`corp-darwin-dev-team` colleague,
  `pa163076mac` Tim's), full Model A system+HM, `bootstrap-darwin.sh`, colleague quickstart —
  all eval-green from Linux, none activated on a Mac.

## Open frontier — the four candidate milestones
The super-plan drives these. **Ordering is the first decision (task M0).** Each points at
sub-plan tasks for detail.

- **M-A — First real Mac (nix-darwin) hardware bring-up.** The biggest unknown; everything
  darwin is eval-only until a Mac boots the shared config. Drives nixcfg-work **001** T7/T8b/T18b;
  uses `bootstrap-darwin.sh` + `docs/darwin/RESUME-mac-nix-bringup.md`. Gate: physical Mac.
- **M-B — CI/delivery unification.** One GitLab pipeline building/gating/publishing every
  artifact (qcow2 + darwin cache + `.wsl`). Drives nixcfg-work **004** T0–T5 (absorbs 003).
  Gates: macOS aarch64-darwin build runner (doesn't exist yet), hsw-infra metal-KVM runner
  (offline), + 5 budget/infra decisions (004 T0). Insight (004 design doc): WSL ships a `.wsl`
  FILE asset; darwin ships NO file — deliverable = green build gate + warm cache consumed via
  substituter + `darwin-rebuild switch`.
- **M-C — Consumption & docs polish (lowest-gate, fastest team value).** Make TODAY's working
  artifacts cleanly self-serviceable: refresh `docs/DISTRIBUTION.md` + `docs/SHARED-MODULES.md`
  (both predate the Mac-VM qcow2 / EC2-Graviton / Darwin additions; export counts drifted
  47↔54), write the Mac-VM qcow2 consumption path + darwin onboarding path, reconcile numbering.
  No hardware/budget gates.
- **M-D — IT/CrowdStrike compliance.** The Falcon/IT demo (nixcfg **026** T6) that unlocks
  production security compliance on the shared WSL image. Human/IT-gated.

## Cross-cutting housekeeping
- **H1 — doc refresh:** `DISTRIBUTION.md`/`SHARED-MODULES.md` to cover Mac-VM qcow2, EC2/Graviton,
  darwin exports; reconcile the 47 vs 54 module count.
- **H2 — numbering hygiene:** resolve the nixcfg-work `002` collision (archive the done
  vte-eks `002`, or renumber); note nixcfg also has a `013-L1.0-*` pair distinct from the
  archived `013-distributed-nix-binary-caching`.
- **H3 — private deployment-values overlay:** the shared modules are deliberately
  deployment-agnostic; real values live in nixcfg-work. Keep that boundary as more sharing lands.

## Progress tracking (this super-plan's OWN coordination tasks)
| ID | Task | Kind | Status |
|----|------|------|--------|
| M0 | Decide milestone ordering (A/B/C/D) + define "done" for the near-term milestone | Interactive | TASK:PENDING |
| M-A | Drive first Mac hardware bring-up (→ nixcfg-work 001 T7/T8b/T18b) | gated: hardware | TASK:PENDING |
| M-B | Drive CI/delivery unification (→ nixcfg-work 004 T0–T5) | gated: infra/budget | TASK:PENDING |
| M-C | Consumption & docs polish (nixcfg docs + onboarding paths) | 1 · portable | TASK:PENDING |
| M-D | IT/CrowdStrike compliance demo (→ nixcfg 026 T6) | Interactive: IT | TASK:PENDING |
| H1 | Refresh DISTRIBUTION.md + SHARED-MODULES.md for the new image/darwin outputs | 1 · portable | TASK:PENDING |
| H2 | Resolve plan-number collisions (nixcfg-work 002; note nixcfg 013 pair) | chore | TASK:PENDING |

## How to resume (for the next session)
1. This is the active plan (`.claude/active-plan` → this file). Read it + the two active
   sub-plans (`~/src/nixcfg-work/.claude/user-plans/001-darwin-support.md`,
   `004-machine-image-ci-release.md`) and nixcfg `026` T6.
2. Start with **M0**: get Tim to pick the near-term milestone. Recommendation absent other
   signal: **M-C** (no gates, fastest team value) runs in parallel while M-A/M-B wait on
   hardware/infra; M-A is the highest-learning but needs a physical Mac; M-B is the backbone
   but budget/infra-gated.
3. Do NOT put corporate detail in this file (see PUBLIC-SAFETY CONSTRAINT). Corporate work is
   tracked in nixcfg-work's plans; this file only rolls up status + sequences milestones.

## Guardrails
Serialize nix. No AI attribution. Coordinating plan = human-attended (Mode A); NOT
burndown-eligible (too many Interactive / hardware / budget gates). Confirm any merge to a
`main` (either repo) with Tim; never auto-merge.
