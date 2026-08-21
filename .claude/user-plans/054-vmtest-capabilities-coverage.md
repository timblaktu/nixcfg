# Plan 054 — VMTest capabilities & coverage expansion (nixcfg + nixcfg-work)

Status: ACTIVE (VMTest workstream; follows 053's nspawn backend enablement)
Owner: Tim
Created: 2026-08-20
Parent: `.claude/user-plans/052-dev-team-sharing-superplan.md` (M-E testing family; enabler for M-B CI)
Working branch: **TBD (T0)** — this session's nspawn work landed on `main`; decide whether to continue
on `main` (additive test infra, eval-gated) or cut a `feat/vmtest-coverage` branch.

## Goal
Improve BOTH the **capabilities** (test infrastructure) and the **coverage** (how much of the config
surface is actually exercised) of the VMTest suite across `nixcfg` (public) and `nixcfg-work`
(private). Builds directly on 053 T6, which proved + enabled the systemd-nspawn container backend
(`mkContainerTest`, `docs/TESTING-NSPAWN.md`, daemon path proven, ~5-7× faster than QEMU).

## Current state (measured 2026-08-20)
- **nixcfg capabilities:** `mkVmTest` (QEMU) + `mkContainerTest` (nspawn, proven). Multi-node works.
  Networking-topology patterns documented (`docs/TESTING-NSPAWN.md`) but not built.
- **nixcfg coverage:** 22 `vm-*` tests, all composing **modules** (`system-cli`, HM modules) — NOT
  host configs. The 10 NixOS hosts are **eval'd but never run** → no per-host runtime smoke. Biggest gap.
- **nixcfg-work coverage:** ~zero VMTests of its own; re-exports exactly one nixcfg check
  (`vm-dev-team-vm-ln`). Its 2 NixOS + 2 Darwin corp hosts get eval only. Its nixpkgs is also
  `331800d` (has the nspawn backend), so container tests are possible there without a pin bump.

## KEY FINDING (this session's probe) — full host config ≠ container-runnable
Importing a full host module (`self.modules.nixos.nixos-dev-team`) into `containers.<n>` fails a
**cascade** of test-environment conflicts:
1. `_hardware-config.nix` sets `nixpkgs.hostPlatform` (mkDefault), which the test framework declares
   **read-only** → "set multiple times". The line is REDUNDANT (the builder's `nixosSystem { system }`
   already sets platform); removing it keeps normal builds green. Trivial, but only unblocks step 2.
2. Then: `Failed assertions: Using host resolv.conf is not supported with systemd-resolved` — and
   likely more behind it.
⇒ **Per-host smoke via containers is inherently a LAYER + host-settings composition, not a literal
full-host boot.** Hosts whose value is in boot/hardware/WSL/image behavior belong on QEMU or the
shipped-image smoketest, not nspawn. This shapes T1's design (below).

## Progress tracking
| ID | Task | Kind | Status |
|----|------|------|--------|
| T0 | Decide working branch (main vs feat/vmtest-coverage) | Interactive | TASK:PENDING |
| T1 | **Per-host smoke coverage** (the #3 pick) — design + implement | Interactive (design decision) | TASK:IN_PROGRESS 2026-08-20 — **Option C (Hybrid) chosen by Tim.** Container LAYER smoke for userspace hosts + QEMU/image smoke for boot/hw/WSL/image hosts. Classifying hosts → backends (see Findings T1). |
| T2 | **Review + curate + migrate existing tests to nspawn** (the #1 pick) — see Tim's requirement below | Interactive (collaborative) | TASK:PENDING (Tim: do AFTER T1) |
| T3 | nspawn → CI: configure a runner with the nspawn nix config + add container tests to the matrix | 1 · CI | TASK:PENDING |
| T4 | Corp-host VMTest coverage in nixcfg-work (`corp-wsl-dev-team`, `pa161878-nixos`) | 1 · portable (nixcfg-work) | TASK:PENDING (soft-gated: needs nspawn config on its runner/host, or QEMU) |
| T5 | Networking-topology tests (VLAN/partition/netem per `docs/TESTING-NSPAWN.md`) | advanced capability | TASK:PENDING |

## Findings T1 — host classification (2026-08-20) → most per-host container smoke is REDUNDANT
Classified the 10 NixOS hosts by their layer chain + nature. **Key insight: a host's *runtime
userspace* is mostly defined by its LAYER, and the existing `vm-*` layer tests already cover those
layers** — so a per-host container smoke for most hosts would just re-test `dev-team`/`system-cli`/
`system-default`. The genuinely NEW coverage is where a host adds **unique services**, plus the
boot/image/WSL hosts whose distinct value is *not* userspace.

| Host | Distinct runtime content | Already covered by | T1 backend (Option C) |
|---|---|---|---|
| **nuc-apt-repo** | `aptly-repo` + `apt-cacher-ng` services (UNIQUE) | nothing | **container smoke (NEW — prime target)** |
| nixos-dev-team | `dev-team` layer | `vm-dev-team-stack` | (redundant) — image build check covers proxmox |
| nixos-dev-team-ec2 | dev-team + EC2 image | `vm-dev-team-stack` + image build | image build check; boot = QEMU/AMI |
| nixos-dev-team-graviton | dev-team + Graviton image (aarch64) | dev-team layer + image build | image build check (aarch64) |
| nixos-dev-team-vm | dev-team + qcow2 | `vm-dev-team-vm-smoketest` (exists) | Mac-VM smoketest (exists) |
| nixos-wsl-dev-team | wsl-dev-team + WSL | `Test-WslImport.ps1` (shipped-image) | WSL shipped-image test |
| nixos-wsl-minimal | minimal + WSL | `Test-WslImport.ps1` | WSL shipped-image test |
| thinky-nixos | personal + WSL | (personal) | WSL image / skip |
| potato | `system-default` (aarch64 SBC) | `vm-system-type-default` | (redundant) — HW = real SBC |
| mbp | `system-cli` | `vm-system-type-cli` | (redundant) |

**⇒ T1 focus refined:** (1) add a **`nuc-apt-repo` container smoke** (real new coverage: aptly +
apt-cacher-ng); (2) confirm the image hosts are covered by their image-build checks + existing boot
smoketests; (3) record the coverage table honestly (existing layer tests ARE the per-host coverage for
the layer-only hosts — not a gap, just already covered). This avoids adding ~8 redundant tests and
puts effort where coverage is actually missing.

## Task definitions

### T1 — Per-host smoke coverage `TASK:PENDING` (Interactive: design decision first)
Close the "hosts eval'd but never run" gap. **Design decision required (see KEY FINDING):**
- **Option A — per-host LAYER smoke (container, no host-config surgery):** for each host, compose its
  distinctive layer module + a container-friendly base, assert its key services/users/packages. Fast,
  clean, but tests the layer composition, not the literal host wrapper/settings.
- **Option B — make full hosts container-runnable:** resolve the conflict cascade (drop the redundant
  `nixpkgs.hostPlatform` line; fix the systemd-resolved/resolv.conf assertion; +whatever follows) so
  real host configs run in containers. Most faithful; whack-a-mole touching shared `_hardware-config`/
  layer modules; ongoing maintenance as configs drift.
- **Option C — hybrid (recommended default):** container LAYER smoke (Option A) for the userspace hosts,
  + QEMU/image-boot smoke for the boot/hardware/WSL/image hosts (nixos-wsl-*, -ec2, -graviton, -vm,
  potato). Honest about which hosts a container can and cannot validate.
**DoD:** the chosen approach implemented for at least a representative subset; a coverage table
(host → test kind → backend) recorded; `nix flake check --no-build` green; each test passes on its
backend. Silent gaps logged, not hidden.

### T2 — Review + curate + migrate existing tests to nspawn `TASK:PENDING` (Interactive — Tim's requirement)
**Tim's explicit process (do this, do NOT blind-migrate):**
1. **Illustrate the tests to migrate** — enumerate the current `vm-*` tests with what each asserts.
2. **Evaluate value as-is TOGETHER** — for each test, assess whether it earns its keep at all (vm OR
   container, regardless of backend): is it testing something real/useful, redundant, or weak?
3. **Decide keep / improve / modify / drop** — curate before converting; improve weak assertions.
4. **THEN migrate** the keepers that are container-eligible (nodes→containers, drop `virtualisation.*`,
   fix service-unit assertions per `docs/TESTING-NSPAWN.md` — e.g. `sshd.socket` not `sshd.service`).
Highest-value migration targets once curated: the 8-node `vm-hm-module-isolation` (biggest RAM win) +
the 2 SSH tests (also prove multi-container networking). `vm-boot-minimal` stays QEMU on principle.
**DoD:** a per-test keep/improve/migrate decision table (agreed with Tim); the kept+eligible tests
converted and green on nspawn; a measured speedup note; no test logic silently lost.

### T3 — nspawn → CI `TASK:PENDING`
Configure a CI runner with `auto-allocate-uids` + `cgroups` + `uid-range` (the 053 T6 recipe; base
module supplies it fleet-wide when a runner is built from this repo), then add container tests to the
`.github/workflows/ci.yml` matrix (CI builds only matrix-listed checks; `vm-nspawn-smoke` is currently
kept OUT precisely because runners aren't configured yet). **DoD:** a CI runner builds a container test
green; the matrix includes it.

### T4 — Corp-host VMTest coverage (nixcfg-work) `TASK:PENDING` (soft-gated)
Add smoke coverage for `corp-wsl-dev-team` + `pa161878-nixos`. Options mirror T1 (layer vs full).
Container tests need the nspawn nix config on the nixcfg-work build host/runner (self-contained, or via
the T8b pin bump that lets nixcfg-work consume `mkContainerTest`). QEMU host-boot smoke is possible now.
Darwin hosts have no test driver — their "test" stays eval + shipped-image smoketest (be honest about
the asymmetry). **DoD:** at least one corp NixOS host has a passing smoke test; approach recorded.

### T5 — Networking-topology tests `TASK:PENDING` (advanced)
Build real multi-node network tests (VLAN-filtering bridge, LAG via bond-to-bond or OVS, `netem`
impairment, asymmetric partitions for quorum/RAFT) using the `ip netns` + `--network-namespace-path`
patterns in `docs/TESTING-NSPAWN.md`. **DoD:** at least one topology test exists + passes; documents
the fidelity limits it does/doesn't cover.

## Sequencing (Tim, 2026-08-20)
T1 (per-host smoke) FIRST, then T2 (review+migrate) — Tim wants to evaluate the migration candidates
together before converting. T3/T4/T5 after. T0 (branch) resolve up front.

## Guardrails
Serialize nix. No AI attribution. Container tests require the nspawn nix config on the builder (053
T6). nixcfg-work container work couples with T8b (pin bump → 26.05 uplift to corp hosts) unless done
self-contained. Confirm any merge to `main` / any nixcfg-work pin bump with Tim.

## Session log
- 2026-08-20 (authoring): created after 053 T6 (nspawn proven+enabled). Probed full-host-in-container →
  found the conflict cascade (platform pin + systemd-resolved). Tim picked T1 (#3) first, then T2 (#1)
  with the explicit review-then-migrate process. Next: resolve T1's design decision (A/B/C).
