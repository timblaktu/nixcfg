# Plan 053 — NixOS 26.05 uplift + nspawn container test backend

Status: ACTIVE (top-priority WSL-side workstream; sub-plan of 052)
Owner: Tim
Created: 2026-08-20
Parent: `.claude/user-plans/052-dev-team-sharing-superplan.md` (registered there as milestone **M-E**)
Burndown: NOT ELIGIBLE (Mode A / human-attended — contains Interactive decisions + an input
bump whose eval-regression fixes need judgment; individual migration tasks have checkable DoD)
Working branch: **`feat/nixos-26.05`** (proposed — see T0; this work is repo-wide, orthogonal
to the darwin `feat/darwin-support` branch)

## Why this plan exists (the goal)
Two NixOS **26.05 "Yarara"** capabilities are worth adopting in `nixcfg` *before* the big
"validate every shared host/image for the first time" push that the super-plan (052) needs:

1. **systemd-nspawn container backend for the NixOS test driver** — the headline. Lets most
   integration tests run in lightweight containers on the host kernel instead of full QEMU
   VMs: much faster boot, far less RAM (run "hundreds at once"), ~25%+ wall-clock in practice.
   Migration is low-effort ("flip a switch in the declarative infra part" — test *logic* is
   unchanged). This is the enabler for **massively ramping up test coverage across all 10 NixOS
   + 2 Darwin hosts and every shared derivation in less run-time** — exactly what 052's
   validation story needs. (nixpkgs PR #478109; docs PR #479968.)
2. **`system.nix` entry point** — configure NixOS without channels *and without flakes* (pin
   nixpkgs via `fetchTarball`/niv). Lower relevance here (nixcfg is already flake-based +
   channel-free), but potentially a **no-flakes consumption path** for teammates, and a reason
   to audit/kill any residual channel usage. Evaluate, don't assume adopt.

**Prerequisite reality:** the repo is NOT on 26.05 yet. `flake.lock` pins primary `nixpkgs` to
`nixos-unstable` **locked 2026-01-30** (~7 months stale, predates both features), a second
`nixpkgs-unstable` at 2026-06-06, and `home-manager` on `master`. So an input uplift is step 1.

## How this fits the super-plan / priorities
Tim's realization (2026-08-20): keep the **WSL session as the driver** while the **Mac work
(052 M-A) happens in the browser on the MacBook**. That gives a clean split of parallel work:
- **On the Mac:** 052 **M-A** — first `darwin-rebuild switch` of `pa163076mac` (hardware).
- **On WSL (here):** **this plan (053 / M-E)** is the top-priority active work — it does not need
  a Mac and is the highest-leverage thing to build while M-A runs on hardware.
- **Blocked-time fallback everywhere:** 052 **M-C** docs polish.

053 is an **enabler** for 052's M-B (CI unification) and general validation: cheap fast tests make
"gate every artifact/host in CI" affordable. It does NOT block M-A.

## Ground-truth references (verified 2026-08-20)
- nspawn backend PR: https://github.com/NixOS/nixpkgs/pull/478109 (BaseMachine → QemuMachine/
  NspawnMachine; `run-nspawn` pkg; shared `guest-networking-options.nix`; examples
  `test-containers.nix`, `test-containers-bittorrent.nix`).
- nspawn docs PR: https://github.com/NixOS/nixpkgs/pull/479968 (when to pick VM vs container;
  host `auto-allocate-uids`; how to write/debug container tests).
- 26.05 release notes: https://nixos.org/manual/nixos/stable/release-notes.html ; announcement
  https://nixos.org/blog/announcements/2026/nixos-2605/
- `system.nix`: alternative entry point (no channels, no flakes) → evaluates to a system
  derivation (or attrset, select with `--attr`); relates to `nixpkgs.flake.source`.
- Repo test surface today: `modules/flake-parts/{tests,vm-tests}.nix`; integration tests
  `tests/integration/{sops-deployment,ssh-management,bitwarden-mock}.nix`,
  `tests/{sops-nix,sops-simple,ssh-auth}.nix`. Hosts: `nixos-configurations.nix` (10 NixOS) +
  `darwin-configurations.nix` (2 Darwin).

## Key risks / open questions (resolve as tasks, do not assume)
- **CI/host nspawn support.** nspawn needs the host to allow `systemd-nspawn` + user namespaces +
  cgroups + `auto-allocate-uids`. Confirm this works in EACH environment the repo runs tests in:
  the **WSL2 dev host**, **GitHub Actions** runners, and the **hsw-infra GitLab runners**. If a
  given runner can't do nspawn, that test target stays QEMU there. (This is T2 — a real gate.)
- **Eligibility.** Tests that need their own kernel/initrd/bootloader/stage-1-systemd, kernel
  modules, or WSL/darwin-specific boot behavior CANNOT be containers — they stay QEMU. Classify,
  don't force.
- **Input-bump blast radius.** Moving nixpkgs 7 months forward (+ hm/nix-darwin aligned) may
  surface eval breakers across all hosts (darwin included). This is expected and is the point of
  the `nix flake check` gate; fixing them is judgment work (hence Mode A).
- **26.05 stable vs fresh unstable.** The nspawn feature is in 26.05 stable AND current unstable.
  Stable = predictable; unstable = newer packages the repo already tracks. Decision in T0/T1.
- **Cross-repo.** `nixcfg-work` pins nixcfg `main`. A 26.05 input bump on a nixcfg branch is only
  consumed by nixcfg-work via a deliberate `flake.lock` pin bump — do NOT surprise the corp hosts;
  coordinate the merge-to-main + re-pin (mirrors the darwin-branch pin discipline).

## Progress tracking
| ID | Task | Kind | Status |
|----|------|------|--------|
| T0 | Decide working branch + release target (26.05 stable vs fresh unstable) | Interactive | TASK:PENDING |
| T1 | Audit current input pins + channel usage; write the uplift decision record | 1 · portable | TASK:PENDING |
| T2 | nspawn feasibility map: per-test eligibility × per-runner (WSL2/GHA/GitLab) support | 1 · portable | TASK:PENDING |
| T3 | Bump nixpkgs/home-manager/nix-darwin to the T0 target; get `nix flake check` green (all hosts) | 1 · portable | TASK:PENDING (dep: T0,T1) |
| T4 | Enable nspawn backend on eligible tests (flip switch + host `auto-allocate-uids`); measure speedup | 1 · portable | TASK:PENDING (dep: T2,T3) |
| T5 | Evaluate `system.nix` / channel-free consumption path; decide adopt-or-defer | Interactive | TASK:PENDING (dep: T3) |
| T6 | Expand coverage: per-host smoke tests across 10 NixOS + 2 Darwin hosts now that tests are cheap | 1 · portable | TASK:PENDING (dep: T4) |

## Task definitions (self-contained)

### T0 — Decide working branch + release target `TASK:PENDING`  (Interactive → USER_INPUT_REQUIRED)
Two coupled decisions for Tim:
1. **Branch:** recommend a dedicated **`feat/nixos-26.05`** (repo-wide migration, orthogonal to
   `feat/darwin-support`; merge→main + coordinate nixcfg-work pin at completion). Alternative:
   do it on `main` directly (eval-gated). Pick one.
2. **Release target:** `nixos-26.05` stable (predictable, security-supported) vs a fresh
   `nixos-unstable` (newer pkgs the repo already tracks; nspawn feature present either way).
   Consider that darwin/`nix-darwin` and `home-manager` must be release-aligned.
**DoD:** both choices recorded in this file (T0 note) + the parent 052 branch/priority note updated.

### T1 — Audit input pins + channel usage `TASK:PENDING`
Enumerate every flake input + its lock date; grep the repo for any residual channel reliance
(`nix-channel`, `<nixpkgs>`, `NIX_PATH`, `nixPath`, `channel:` URLs) — a flake repo should be
channel-free already; document any exceptions (bootstrap scripts, WSL/darwin installers that
enable flakes but might touch channels). Produce a short "current state → target" record.
**DoD:** a written audit (in this file or `docs/`) listing every input's current vs target pin and
a definitive yes/no on residual channel usage with file:line evidence. `rg` commands exit cleanly.

### T2 — nspawn feasibility map `TASK:PENDING`
Build a 2-axis map: **(each existing test) × (each runner: WSL2 dev host, GitHub Actions,
hsw-infra GitLab)**. For each test decide container-eligible vs must-stay-QEMU (kernel/initrd/
bootloader/WSL/darwin reasons). For each runner, empirically confirm whether `systemd-nspawn` +
`auto-allocate-uids` + userns work (a tiny throwaway `runNixOSTest` with the nspawn switch is the
probe). Record gaps (e.g. "WSL2 host can't nspawn → those run QEMU locally, nspawn in CI").
**DoD:** a table in this file (test × runner → VM|nspawn|blocked+reason) backed by at least one
real probe result per runner class (or an explicit ENVIRONMENT_NOT_CAPABLE note where a runner
class isn't reachable from the current session).

### T3 — Input bump to the T0 target `TASK:PENDING`  (dep: T0, T1)
On the T0 branch: update `flake.nix` input refs + `nix flake update` the relevant inputs to the
chosen 26.05-aligned revisions; run `nix flake check --no-build` and fix eval breakers across ALL
hosts (WSL, NixOS VM/EC2/graviton, both darwin). Follow the repo's workaround-documentation
protocol for any version-incompat shims. Do NOT bump the nixcfg-work pin yet (separate coordinated
step at plan completion).
**DoD:** `nix flake check --no-build` passes on the branch; `git grep` shows the new input refs;
darwin configs still eval to a real `.drv` (`nix eval '.#darwinConfigurations.pa163076mac...
toplevel.drvPath'` — cross-check against 052's recorded value, expecting a new hash, same shape).
Any workaround carries an inline WORKAROUND/API-ADAPTATION comment + commit note.

### T4 — Enable nspawn backend on eligible tests `TASK:PENDING`  (dep: T2, T3)
For each T2-eligible test, flip it to the nspawn backend (the declarative switch from PR #478109 —
confirm the exact option name against the pinned nixpkgs, do NOT guess) and add the required host
setting (`auto-allocate-uids`, per docs PR #479968) to the test's node config. Keep ineligible
tests on QEMU. Measure before/after wall-clock + peak RSS for at least the sops + ssh integration
tests and record the delta.
**DoD:** the converted tests pass via nspawn (`nix build '.#checks.<system>.<test>'` green); a
measured speedup/RAM table is recorded here; ineligible tests are explicitly listed as
intentionally-still-QEMU. No test logic (Python `testScript`) was rewritten, only infra config.

### T5 — Evaluate `system.nix` / channel-free consumption `TASK:PENDING`  (dep: T3, Interactive)
Assess whether `system.nix` buys nixcfg anything: (a) a no-flakes consumption path for teammates
who don't want flakes; (b) tightening `nixpkgs.flake.source` for pinned non-flake builds. Since the
repo is already flake-based, the likely outcome is "document as an option, don't adopt in core" —
but decide explicitly with Tim, don't assume.
**DoD:** a written recommendation (adopt / document-only / defer) with rationale; if adopt, a
follow-up task list; if not, a one-paragraph note in DISTRIBUTION.md pointing teammates at the
option. Interactive → USER_INPUT_REQUIRED for the final call.

### T6 — Expand coverage across all hosts `TASK:PENDING`  (dep: T4)
With cheap containers available, add per-host smoke tests (boots, key services up, sudo/wheel,
expected packages present) for the 10 NixOS hosts, and the maximal-feasible darwin coverage (note:
darwin has no NixOS test driver — its "test" is the eval-green `.drv` gate + the shipped-image
smoketest; be honest about that asymmetry). Wire them into `flake-parts/{tests,vm-tests}.nix` so
CI enumerates them.
**DoD:** new smoke checks exist + pass for each eligible host; `nix flake check` enumerates them;
a coverage table (host → test kind → backend) is recorded. Silent gaps are logged, not hidden.

## Guardrails
Serialize nix (no concurrent evals — an input bump eval is heavy). No AI attribution. Confirm the
merge to `main` + the nixcfg-work pin bump with Tim (cross-repo blast radius). This plan is Mode A
(human-attended); do not burndown.

## Session log
- 2026-08-20: Authored. Research grounded via nixpkgs PRs #478109/#479968 + 26.05 release notes.
  Confirmed repo is pre-26.05 (primary nixpkgs `nixos-unstable` locked 2026-01-30). Registered in
  052 as M-E (top-priority WSL-side workstream, parallel to M-A on the Mac). T0 is the first
  actionable step (branch + release-target decision — Interactive).
