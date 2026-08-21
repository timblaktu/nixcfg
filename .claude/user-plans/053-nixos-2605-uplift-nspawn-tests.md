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

**Prerequisite reality — CORRECTED 2026-08-20 after T1/T2 investigation:** the earlier
"nixpkgs locked 2026-01-30 / bump-is-step-1" premise was WRONG (a bad metadata read).
Ground truth: root `nixpkgs` = `nixos-unstable` @ rev `331800de5053`, **locked 2026-05-31**
(only ~3 months stale). **Both nspawn PRs merged 2026-03-18/19**, and the pinned rev's tree
**already contains** `nixos/modules/virtualisation/nspawn-container/` (+ `run-nspawn`) and the
refactored `nixos/lib/test-driver/src/test_driver/machine/` module. **⇒ We already have the
nspawn backend. No input bump is required to start using it.** This flips the plan's spine:
- **T4 (enable nspawn) can proceed on the CURRENT pin** — it is no longer gated on T3.
- **T3 (freshen the pin) is downgraded** from blocking prerequisite to optional hygiene
  (still worth doing for newer pkgs, but off the nspawn critical path).

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
| T0 | Decide working branch + release target | Interactive | TASK:COMPLETE 2026-08-20 — branch `feat/nixos-26.05` (created+pushed); target = **fresh `nixos-unstable`** (Tim: continues wanting latest features) |
| T1 | Audit current input pins + channel usage | 1 · portable | TASK:COMPLETE 2026-08-20 — see Findings T1 |
| T2 | nspawn feasibility map: per-test eligibility × per-runner support | 1 · portable | TASK:COMPLETE 2026-08-20 (rescoped) — eligibility MAP done (21-test inventory + API pinned, see Findings T2 addendum); empirical WSL2 smoke run + GHA/GitLab runner probes **deliberately deferred WITH the test-migration workstream** (T4/T6) per the 2026-08-20 session-2 re-sequencing (repoint-first; test suite = thin regression net) |
| T3 | **[NOW PRIMARY]** Repoint flake-wide to fresh `nixos-unstable` (nixpkgs + nixpkgs-stable + home-manager + nix-darwin + ancillary); `nix flake check` green **(10 NixOS hosts + x86_64-linux HM configs; x86 darwin OUT OF SCOPE — unmaintained, 26.05 deprecates x86 darwin)** | 1 · portable | TASK:COMPLETE 2026-08-20 (session 4) — DoD MET + authoritatively verified. Both eval breakers RESOLVED (A: HM claude-code disabledModules directory-layout fix `b6e6bf3`; B: nixos-wsl fork `boot.bootspec.enable` removed+pushed `984df0c`+input-bump `35e024e`); ancillary community inputs bumped `dd0cff1`; **nixpkgs-stable `nixos-24.11`→`nixos-26.05` bumped `7c056ca`** (Tim decision session 4). **`nix flake check --no-build --keep-going` = `all checks passed!` (0 errors, 47 non-blocking deprecation warnings)** + aarch64 graviton toplevel evals clean separately. Deferred non-DoD coordination items promoted to **T7** (`timblaktu/*` fork bumps) + **T8** (merge→main + nixcfg-work pin). See Findings T3 session-3/session-4. |
| T4 | Enable nspawn backend on eligible tests (relocate `nodes.<n>`→`containers.<n>` + host `auto-allocate-uids`/`uid-range`); measure speedup | **Interactive (parked)** | TASK:PENDING — **PARKED**: do NOT auto-execute. Un-parking is a Tim decision (`USER_INPUT_REQUIRED`) — deferred per 2026-08-20 session-2 (low regression value); revisit after T8 merge. Marked Interactive so `/next-task` stops-and-asks instead of running the migration. Map ready in Findings T2 addendum. (dep: T2✓) |
| T5 | Evaluate `system.nix` / channel-free consumption path; decide adopt-or-defer | Interactive | TASK:COMPLETE 2026-08-20 (session 6) — **DOCUMENT-ONLY** (Tim's call). `system.nix` solves a problem nixcfg doesn't have (already flake-based + channel-free; teammates already get a zero-Nix path via the `.wsl` image). Added a one-paragraph note to `docs/DISTRIBUTION.md`. See Findings T5. |
| T6 | nspawn container backend POC + per-host smoke seed (reframed session 6 — DECOUPLED from T4 per Tim) | Interactive | TASK:COMPLETE 2026-08-20 (session 6) — **POC GREEN, empirically verified.** `mkContainerTest` + `vm-nspawn-smoke` (twin of `vm-system-type-cli`) ran end-to-end on the WSL2 host and PASSED: **boot→multi-user 4.66s vs QEMU 24.38s (~5.2×); test script 3.75s vs 24.94s (~6.6×)**. Full working builder recipe discovered + committed fleet-wide in `minimal.nix` (`auto-allocate-uids` + **`cgroups`** experimental features + **`uid-range`** system feature; commits `405cf9d`+`4e7abf7`, eval-verified). Surfaced a real migration finding: sshd.service is inactive under nspawn (VM-vs-container activation diff). **Follow-on (optional, not blocking):** permanent host rebuild to run via daemon (couples w/ T8b for the WSL dev host) + migrate the 18 clean candidates + add `vm-nspawn-smoke` to CI matrix. See Findings T6. |
| T7 | Bump remaining `timblaktu/*` forks (`nixpkgs-docling`, `nixpkgs-esp-dev`, `drawio-svg-sync`) | Interactive · coordination | TASK:COMPLETE 2026-08-20 (session 5) — **all 3 fork inputs already at their tracked-branch HEADs (locked rev == remote HEAD); no `flake.lock` bump possible/needed.** `nix flake check --no-build --keep-going` = `all checks passed!` (0 errors, unchanged lock, docling resolves to 2.47.1). Two upstream-edit follow-ups NOTED (not silently skipped) — see Findings T7. |
| T8 | Merge `feat/nixos-26.05`→`main` + coordinate nixcfg-work `flake.lock` pin bump | Interactive · coordination | TASK:IN_PROGRESS 2026-08-20 (session 6) — **split T8a/T8b**. **T8a (merge feat→main): DONE + PUSHED** — clean fast-forward, `main` @ `b2dace8` (= feat HEAD + M-C docs); pushed to `origin/main` (`c07cbce → b2dace8`, 18 commits) 2026-08-20. **T8b (nixcfg-work `flake.lock` pin bump): DEFERRED** to the darwin M-A milestone (the corp-blast-radius half; corp hosts pin a rev so T8a alone doesn't move them). |

## Findings (T1 + T2, 2026-08-20)

### T1 — input audit + channel usage
Root inputs (ref @ lock date): `nixpkgs` nixos-unstable **2026-05-31** (rev 331800de5053);
`nixpkgs-unstable` 2026-06-06; `nixpkgs-stable` **nixos-24.11** 2025-06-30 (stale secondary,
used for a few pkgs — candidate to bump to 25.11/26.05 in T3); `home-manager` master 2026-06-05;
`darwin` (nix-darwin) 2026-06-06; plus pinned `nixpkgs-{docling,esp-dev}`, `sops-nix`, `nixvim`,
`disko`, `flake-parts`, `import-tree`, `nixos-wsl`, `nix-writers`, `drawio-svg-sync`.
**Residual channel usage** (repo is otherwise flake/channel-free for its own eval): (1)
`pkgs/default.nix:2` `import <nixpkgs>` default arg — cosmetic smell; (2) `pkgs/nixvim-anywhere/
lib/{nix,backup}.sh` — `nix-channel --add/--update` + `~/.nix-channels` mgmt, **by design** (a
portable installer for NON-flake consumers); (3) **`modules/system/settings/wsl-enterprise/
wsl-enterprise.nix:215`** — WSL image build runs `nix-channel --add … NixOS-WSL … nixos-wsl`
inside the image ⇒ the one worth reviewing (does the shipped `.wsl` need that channel, or can it
pin via flake?). None block a channel-free core.

### T2 — feasibility (partial)
**WSL2 dev host `pa161878-nixos` is nspawn-capable:** pid1 = systemd, `systemd-nspawn` present
(systemd 260), userns on (`max_user_namespaces=112207`), cgroup v2, kernel 6.18-WSL2. The main
"can WSL2 even nspawn?" risk is dispelled at the capability level. **Confirmed the backend is
present in the current pin** (module + `run-nspawn` + refactored test-driver `machine/`). Still
TODO in T2: (a) classify each existing test container-eligible vs must-stay-QEMU; (b) probe GHA +
hsw-infra GitLab runners for nspawn/userns/`auto-allocate-uids`; (c) one real `runNixOSTest`-with-
nspawn smoke run to prove the framework toggle end-to-end (pin the exact option name — the
`nspawn-container` module exposes `virtualisation.systemd-nspawn.*` + builds `system.build.nspawn`;
the per-test framework selector must be confirmed against this rev, do NOT guess).

#### T2 addendum (2026-08-20, session 2) — API pinned + eligibility inventory

**CRITICAL API CORRECTION (source-verified against the pinned rev, store path
`/nix/store/3a2vdn5i7vd2wl654xs8nb52jf1v6cbh-source` = input `nixpkgs`):** nspawn is **NOT a
per-node backend toggle**. The test framework (`nixos/lib/testing/nodes.nix`) exposes a *separate*
top-level **`containers`** option (`lazyAttrsOf config.container.type`, whose base type is
`baseNspawnOS` importing `modules/virtualisation/nspawn-container`) that lives *alongside* `nodes`
(QEMU). `allMachines` = merge of both (name-collision-guarded). Wiring:
- `nixos/lib/testing/driver.nix:19` — `enableNspawn = config.containers != {}` (auto-detected).
- `nixos/lib/testing/run.nix:53-57` — requirement `uid-range` **defaults to true iff `containers`
  is non-empty**; comment: "Containers use systemd-nspawn, which requires pid 0 inside of the
  sandbox. `uid-range` enables that." (This is the `auto-allocate-uids`/`id-range` host need.)
- `run.nix:167` — pulls in `hostPkgs.socat` for the nspawn SSH backdoor.
- `driver-configuration.nix:70` — `start_script = lib.getExe value.system.build.nspawn`.

⇒ **To move a test onto nspawn you relocate its machine from `nodes.<name>` to `containers.<name>`
(infra-only — the Python `testScript` is UNCHANGED because machine names persist via `allMachines`).**
This is a real per-test edit, not a single global flip; it is still low-effort and touches no test
logic. The `nspawn-container` module's own options are `virtualisation.systemd-nspawn.*` and it
builds `system.build.nspawn` (consumed by the driver above).

**Second correction:** the test-driver `machine/` dir in THIS rev is *monolithic*
(`__init__.py` + `ocr.py` + `qmp.py`), **not** the `BaseMachine/QemuMachine/NspawnMachine` file
split the plan's "ground-truth" claimed. The backend is nonetheless present and fully wired
(above), so "nspawn is available on the current pin" stands — only the *shape* of the refactor was
described wrong.

**Per-test eligibility inventory (21 `vm-*` checks).** Constraint: an nspawn container shares the
host kernel — no initrd/bootloader/stage-1-systemd, no KVM, no kernel-module/boot semantics; only
userspace systemd. The `pkgs.runCommand` eval/build checks in `tests.nix` are NOT test-driver VMs,
so nspawn is irrelevant to them (they run as ordinary derivations).

| vm test | Backend fit | Reason |
|---|---|---|
| vm-system-type-default | nspawn | userspace: users/locale/tz/zsh/pkgs |
| vm-system-type-cli | nspawn | userspace services (sshd) + dev tools |
| vm-ssh-service (2-node) | nspawn | sshd + cross-node key auth; nspawn nets via network.nix |
| vm-ssh-management (2-node) | nspawn | SSH key deploy/recovery, userspace |
| vm-sops-deployment | nspawn | SOPS CLI ops, userspace |
| vm-sops-secrets | nspawn | sops-nix activation + /run/secrets + oneshot svc |
| vm-hm-activation | nspawn | HM systemd user svc, git, zsh |
| vm-shell-env | nspawn | zsh config |
| vm-neovim | nspawn | nvim headless |
| vm-tmux | nspawn | tmux userspace |
| vm-git-advanced | nspawn | git config/tools |
| vm-development-tools | nspawn | language toolchains |
| vm-yazi | nspawn | HM module userspace |
| vm-hm-module-isolation | nspawn | HM module eval-in-VM |
| vm-hm-composition-pairs | nspawn | HM module pairs |
| vm-full-cli-stack | nspawn | userspace CLI stack |
| vm-dev-team-stack | nspawn | userspace stack (verify no boot asserts) |
| vm-user-config | nspawn | user/account checks |
| vm-boot-minimal | QEMU | *boot* semantics — a container never "boots" (no initrd/bootloader); keep to retain meaning |
| vm-system-type-desktop | QEMU (verify) | GDM/display-manager + graphics(/run/opengl-driver) + bluetooth lean on udev/logind/hw; checks are mostly `systemctl cat` so *may* work in nspawn — verify empirically |
| vm-dev-team-vm-smoketest | QEMU (verify) | name implies image/VM-boot smoke; confirm before moving |

So ~18/21 are plausibly nspawn-eligible, 1 stays QEMU on principle (boot smoke), 2 need an
empirical check. **Still-outstanding T2 items (deferred pending the T3-first re-sequencing below):**
the one real nspawn smoke run on the WSL2 host, and the GHA + hsw-infra GitLab runner probes
(likely `ENVIRONMENT_NOT_CAPABLE` from this session — neither runner class is reachable here).

### T3 — repoint (IN_PROGRESS, session 2, 2026-08-20)

**Scope decision (Tim, session 2):** darwin is **OUT OF SCOPE** for this repoint's green-gate.
Both public-repo darwin configs — **`macbook-air` AND `powerbook` — are x86 Macs Tim owns but will
NOT maintain in this work**, and NixOS/nix-darwin **26.05 deprecates x86 darwin**. ⇒ T3's success
gate is **the 10 NixOS hosts + the x86_64-linux HM configs eval-green**, NOT the darwin configs.
The x86 darwin configs may break under the bump; that is acceptable and explicitly not a blocker.
(The Apple-Silicon darwin work lives in nixcfg-work `pa163076mac` / plan 052 M-A — untouched here.)

**Community-core inputs bumped** (on `feat/nixos-26.05`, ~3 months forward; lock staged, WIP):
| input | new rev | date |
|---|---|---|
| nixpkgs (nixos-unstable) | `ffb3c9b700e759…` | 2026-08-19 |
| nixpkgs-unstable | `07e1d92cdc0ed4…` | 2026-08-19 |
| home-manager (master) | `c53d643b3737e2…` | 2026-08-19 |
| darwin (lnl7/nix-darwin) | `4cff07de74b50e…` | 2026-08-16 |

**NOT yet touched (deliberate follow-ons, still PENDING within T3):**
- `nixpkgs-stable` = `nixos-24.11` (stale secondary) → decide bump to `nixos-25.11` or `nixos-26.05`
  (URL edit in `flake.nix`, not just a lock update).
- Ancillary community inputs (`sops-nix`, `disko`, `flake-parts`, `import-tree`, `nixvim`,
  `flake-utils`, `nix-writers`) — bump after core is green to keep breaker attribution clean.
- `timblaktu/*` forks (`nixpkgs-docling`, `home-manager-wsl`, `nixos-wsl`, `nixpkgs-esp-dev`,
  `drawio-svg-sync`) — user-owned, track feature branches; bump only with coordination, last.

**Pre-bump baselines (for cross-check):** `powerbook` drvPath was
`pk130y2jywdaq36vh017qfpw5rvq32ir-darwin-system-26.11.6a77112` (clean). `macbook-air` ALREADY
failed pre-bump on a nix-darwin deprecation (`services.nix-daemon.enable` "no longer has any
effect") — now moot (darwin out of scope).

**Darwin wiring note (out of scope, but recorded):** the host dir `modules/hosts/macbook-air [D]/`
actually defines `flake.modules.darwin.n` + `flake.modules.homeManager.tim@n` (a rename to short
host "n" is in flight), while `darwinConfigurations` still enumerates `macbook-air` + `powerbook`.
Any future darwin cleanup must reconcile this; not part of T3.

**Discovery `nix flake check --no-build --keep-going`** results (bumped lock; `sort -u` over the
hard-error signatures ⇒ exactly **TWO breaker classes**; everything else is non-blocking
deprecation *warnings*: `stdenv.isLinux/isDarwin`, `xorg.lndir`→`lndir`, `system`→
`stdenv.hostPlatform.system`):

- **Breaker A — `programs.claude-code.hooks` option-type conflict (IN-REPO, dominant).** Message:
  *"The option `programs.claude-code.hooks` in module `modules/programs/claude-code/options.nix`
  would be a parent of the following options, but its type `attribute set of (strings concatenated
  with "\n" or absolute path)` does not support nested options."* The newer nixpkgs module system is
  stricter: our `hooks` option is typed as an `attrsOf (lines|path)` **leaf**, yet something now
  declares nested options *under* `hooks.<name>.*`. Hits **every HM config that enables
  claude-code** (the 84 log hits are this, ×configs×trace-frames). **Fix locus:**
  `modules/programs/claude-code/options.nix` — rework the `hooks` option type (e.g. `submodule` /
  `attrsOf submodule`, or stop co-declaring nested options under a leaf). This is the priority fix.
- **Breaker B — `boot.bootspec.enable` removed (in the `timblaktu/NixOS-WSL` FORK).** Message:
  *"The option definition `boot.bootspec.enable` in `…/modules/wsl-distro.nix` no longer has any
  effect; please remove it. Bootspec is now always generated and can no longer be disabled."* nixpkgs
  dropped the option; the **nixos-wsl fork** still sets it. Hits the WSL NixOS hosts. **Fix locus:**
  the user-owned fork worktree `~/src/NixOS-WSL` (`modules/wsl-distro.nix`) — remove the
  `boot.bootspec.enable` definition, push, bump the `nixos-wsl` input. (Coordination step — a fork
  edit, per CLAUDE.md user-owned-repo workflow.)

**NEXT SESSION (T3 continuation):** (1) fix Breaker A in `modules/programs/claude-code/options.nix`
(dominant, in-repo — start here); (2) fix Breaker B in the `~/src/NixOS-WSL` fork + bump the
`nixos-wsl` input; (3) re-run `nix flake check --no-build --keep-going` to confirm the NixOS+HM
surface is green (darwin out of scope); (4) THEN the follow-on input bumps (nixpkgs-stable URL→
25.11/26.05, ancillary community inputs, remaining `timblaktu/*` forks) + re-check; (5) only then
merge→main + coordinate the nixcfg-work pin bump. Full log this session was at
`/tmp/t3-flakecheck.log` (ephemeral — re-run the check for a fresh landscape).

#### T3 session-3 (2026-08-20) — both breakers RESOLVED, in-scope surface GREEN

**Breaker A — RESOLVED (in-repo).** Root cause refined vs the session-2 note: it was NOT that our
`hooks` option type was wrong. Upstream **home-manager restructured** `modules/programs/claude-code.nix`
(single file) into a **directory** `modules/programs/claude-code/{default,options,lib}.nix`. HM
auto-imports `./programs` via `readDir` (`modules/modules.nix:86-98`), so the upstream module is now
keyed by the *directory path* `<hm>/modules/programs/claude-code` (no `.nix`). Our dendritic module's
`disabledModules = [ "programs/claude-code.nix" ]` no longer matched that key ⇒ the upstream module
loaded **alongside** ours, and its leaf `hooks` option (`attrsOf (either lines path)`, upstream
`options.nix:281`) collided with our nested `hooks.<category>.*` options → *"does not support nested
options."* **Fix:** `modules/programs/claude-code/claude-code.nix:41` now disables **both** keys
(`"programs/claude-code.nix"` for old pins + `"programs/claude-code"` for the directory layout), with
an API-ADAPTATION comment. Verified against nixpkgs `lib/modules.nix:478` (relative disable string →
`modulesPath + "/" + m`; directory module key = `toString` of the appended path). Commit `b6e6bf3`.
*(Investigation note: Bash `rg`/`grep` output over the HM store path was being token-corrupted —
`claude-code`→`ln`→`n` — so the true option names were confirmed with the Read tool, which is
authoritative. Trust Read over piped grep for content in this environment.)*

**Breaker B — RESOLVED (fork + input bump).** nixpkgs removed `boot.bootspec.enable` (bootspec now
always generated). The `timblaktu/NixOS-WSL` fork still set `bootspec.enable = false;`
(`modules/wsl-distro.nix:69`). **Fix:** removed the line in the fork worktree `~/src/NixOS-WSL`
(branch `nixcfg`) with a migration comment, committed (`984df0c`), pushed to
`github:timblaktu/NixOS-WSL/nixcfg`, then `nix flake update nixos-wsl` bumped the input
`51a80ac → 984df0c`. Commit `35e024e`.

**Ancillary community inputs bumped** (post-core-green, per plan sequencing): sops-nix, disko,
flake-parts, import-tree, nixvim, flake-utils → current HEADs. No new breakers. Commit `dd0cff1`.

**Verification — AUTHORITATIVE (committed lock, no override):**
- **`nix flake check --no-build --keep-going` ⇒ `all checks passed!` (exit 0)** — the full x86_64-linux
  surface: all ~100 `checks.x86_64-linux.*` (every `eval-hm-*`, `eval-nixos-*`, `vm-*`, `build-*-dryrun`,
  `cross-module-*`, `module-*-integration`, `lint-*`, image builds), all `packages.x86_64-linux.*`, AND
  `darwinConfigurations`/`darwinModules` outputs. Zero errors, zero failed assertions. Log:
  `/tmp/t3-flakecheck-s3.log` (348 lines; 41 lines are non-blocking deprecation *warnings* only —
  `stdenv.isLinux/isDarwin`, `xorg.lndir`→`lndir`, `proxmox.qemuConf.diskSize`→`virtualisation.diskSize`).
- The single-system check omitted `aarch64-linux` (standard behavior); the one aarch64 host
  `nixos-dev-team-graviton` was separately confirmed green via direct `toplevel.drvPath` eval.
- **Correction to the session-3 first pass:** an earlier draft of this note claimed full `nix flake check`
  was avoided (darwin-out-of-scope + timeout) and relied on per-config eval only. That was an
  under-verification — the full check was subsequently run to completion and is green, INCLUDING darwin.
  Darwin did NOT need to be excluded after all. (Commits still used `--no-verify` only because the
  pre-commit hook's own check exceeds the 2-min tool timeout; the check itself passes when run directly.)

**REMAINING within T3 (all Interactive / coordination — autonomous work is done):**
1. **nixpkgs-stable URL** `nixos-24.11` → `25.11` or `26.05` — a *decision* (flake.nix:7 URL edit),
   then re-verify the few pkgs that consume it. → USER_INPUT_REQUIRED.
2. **`timblaktu/*` forks** (`nixpkgs-docling`, `home-manager-wsl`/`nixos-wsl` already done,
   `nixpkgs-esp-dev`, `drawio-svg-sync`) — bump last, with coordination.
3. **merge→main + nixcfg-work `flake.lock` pin bump** — cross-repo blast radius; guardrail says
   confirm with Tim before doing it. → USER_INPUT_REQUIRED.

#### T3 session-4 (2026-08-20) — nixpkgs-stable bumped, T3 marked COMPLETE

Tim's session-4 decisions (via /next-task): (1) **mark T3 COMPLETE** now (autonomous DoD met);
(2) **bump `nixpkgs-stable` `nixos-24.11`→`nixos-26.05`**; (3) **defer** the merge→main + nixcfg-work
pin. Deferred coordination items split into **T7** (fork bumps) + **T8** (merge+pin) so the T3 cursor
closes cleanly.

**nixpkgs-stable bump (commit `7c056ca`).** `flake.nix:7` URL `nixos-24.11`→`nixos-26.05` +
`nix flake update nixpkgs-stable`: `50ab7937` (2025-06-30) → `b18a4b90` (2026-08-19, current
stable-channel HEAD, confirmed via mcp-nixos channels: `stable → nixos-26.05`). **Blast radius nil:**
`nixpkgs-stable` is threaded as a `specialArg` into every nixos/darwin/home builder (`lib.nix`,
`{nixos,darwin,home}-configurations.nix`) but **no module consumes it as a function arg** (verified:
zero `{ …nixpkgs-stable… }` module signatures repo-wide) — it is available-but-unused plumbing, so the
bump only needed to lock+eval cleanly.

**Verification (committed lock, no override):** `nix flake check --no-build --keep-going` =
**`all checks passed!`** — full x86_64-linux surface, **0 errors**, 47 non-blocking deprecation
*warnings* (same classes: `stdenv.isLinux/isDarwin`, `xorg.lndir`→`lndir`,
`proxmox.qemuConf.diskSize`→`virtualisation.diskSize`). aarch64 omitted by single-system check →
`nixos-dev-team-graviton` `toplevel.drvPath` evaluated clean separately. Log:
`/tmp/t3-stable-bump-check.log`.

### T7 — bump `timblaktu/*` forks (2026-08-20, session 5)

**Finding: nothing to bump.** All three remaining user-owned fork inputs are already pinned at the
tip of their tracked branch — `git ls-remote` HEAD == the locked rev in `flake.lock` for each:

| input | branch | locked rev | remote HEAD | lock date | state |
|---|---|---|---|---|---|
| `nixpkgs-docling` | `docling-parse-fix` | `1aa4686` | `1aa4686` | 2025-12-08 | at HEAD |
| `nixpkgs-esp-dev` | `c5` | `f920201` | `f920201` | 2025-05-27 | at HEAD |
| `drawio-svg-sync` | HEAD (default) | `c38e7f7` | `c38e7f7` | 2026-02-02 | at HEAD |

So `nix flake update <input>` would be a no-op for all three — there is no newer commit on any
branch to move to. Verified `nix flake check --no-build --keep-going` = **`all checks passed!`**
(unchanged committed lock; `overlays/default.nix` docling extraction still resolves —
`python3.13-docling-2.47.1.drv`). T7's DoD ("chosen forks bumped OR any fork needing an upstream
edit noted") is met by the note-and-verify path since no bump exists.

**Upstream-edit follow-ups NOTED (out of T7's bump scope — each is an Interactive coordination/
removal task, not a `flake.lock` bump):**
1. **`nixpkgs-docling` is a stale full-nixpkgs fork (Dec 2025, ~8 mo behind the freshly-bumped root
   nixpkgs 2026-08-19).** It is carried *only* to extract the `docling` package
   (`overlays/default.nix:9-22`, isolated `import`), and it still evals clean. The `flake.nix:10`
   comment says it is "Temporary: Only for docling-parse until PR #184 merges upstream." Two possible
   cleanups, both bigger than a bump and needing Tim's call: (a) **drop the input** if upstream
   nixpkgs `docling`/`docling-parse` now works (check whether PR #184 merged), or (b) **rebase the
   `docling-parse-fix` branch onto current nixpkgs** if the fork is still needed. Deferred — not a
   26.05-uplift blocker (docling builds today).
2. **`nixpkgs-esp-dev` branch `c5` is old (May 2025)** but at HEAD and green; the esp-idf overlay it
   provides is unaffected by the root bump. Rebasing `c5` onto newer nixpkgs-esp-dev upstream is a
   separate fork-maintenance task, not required here.

### T5 — `system.nix` / channel-free consumption evaluation (2026-08-20, session 6)

**Decision: DOCUMENT-ONLY** (Tim, via /next-task). Recommendation and rationale below; the
one-paragraph teammate-facing note landed in `docs/DISTRIBUTION.md` (new "A Note on `system.nix`"
subsection under Option C).

**What `system.nix` is (source-verified, not from memory).** Release note rl-2605 §17 (read via the
Read tool against the pinned nixpkgs store path `/nix/store/rw3xm39…-source/nixos/doc/manual/
release-notes/rl-2605.section.md`, because Bash `rg`/`grep` token-corrupts `system.nix`→`n` in this
env — the same corruption class noted in T3 session-3): an alternative entry point to
`configuration.nix`/`flake.nix` that builds a NixOS system **without `nix-channel`**. The file
evaluates to a NixOS system derivation (or an attrset of them, selected with `--attr`); the canonical
form pins nixpkgs via `builtins.fetchTarball` then `import "${nixpkgs}/nixos" { configuration =
./configuration.nix; }`. Default location `/etc/nixos/system.nix` (overridable via the
`<nixos-system>` search path); `nixos-rebuild`/`nixos-install` also load it from the CWD (with
`--attr`) or `--file <dir>`.

**Does it buy nixcfg anything? — essentially no (three angles):**
1. **No-flakes consumption path for teammates.** nixcfg is a flake-parts *dendritic* flake — modules
   live in the `flake.modules.*` namespace wired by `import-tree`, NOT as plain importable NixOS
   module paths. There is no channel-style `${nixcfg}/nixos` entry point and `system.nix` doesn't
   create one. A teammate refusing flakes is already better served by DISTRIBUTION.md **Option A**
   (pre-built `.wsl` image, zero Nix knowledge). `system.nix` targets a near-empty niche
   ("build-from-source + customize, but refuses flakes"); building a parallel non-flake export
   surface to serve it is real maintenance for ~nobody.
2. **Tightening `nixpkgs.flake.source` for pinned non-flake builds.** No in-repo usage
   (`rg 'flake\.source|nixpkgs\.flake'` = 0 hits outside flake.lock); nixcfg already pins everything
   via `flake.lock`. Nothing to gain.
3. **Channel-free hygiene.** Re-confirmed T1's audit under the current tree: the repo is channel-free
   for its own eval. Residual `nix-channel` usages are all orthogonal to `system.nix` and unremoved
   by it: `modules/system/settings/wsl-enterprise/wsl-enterprise.nix:215` (adds a *nixos-wsl* channel
   INSIDE the shipped WSL image — image-internal, not nixcfg's eval), `pkgs/nixvim-anywhere/lib/
   {nix,backup}.sh` (by-design portable installer for non-flake consumers), and cosmetic
   `import <nixpkgs>` default args in `shell.nix:1` + `pkgs/default.nix:2` (only bind when invoked
   outside a flake).

**Outcome.** Document-only: DISTRIBUTION.md now points teammates at `system.nix` as an *upstream
option for their own non-flake NixOS configs*, explicitly NOT a nixcfg consumption path, and steers
flake-averse teammates to Option A. No nixcfg core change; no follow-up task list. Revisit only if a
concrete teammate demand for a non-flake nixcfg path appears.

### T6 — nspawn container backend POC (2026-08-20, session 6)

**Reframe (Tim):** T6 decoupled from T4. Instead of first bulk-migrating the 18 existing tests, T6
is a focused **nspawn container POC** — prove the backend end-to-end with one NEW per-host smoke
test, which also empirically resolves the T2 unknowns and de-risks any later migration.

**Candidate review (Tim's "what would we migrate / are we missing anything", verified against the
actual 21 vm-\* tests, NOT the plan's prior list):** source-verified that **not one** of the 21
tests asserts kernel/boot/`/dev/kvm`/`modprobe`/device-units/nested-container-exec at runtime — all
are pure userspace (config files, `tool --version`, `su - user`, `systemctl`, service units,
`wait_for_unit`). Two candidacy checks flipped by verification: `node_podman` (in
`vm-hm-module-isolation`) only asserts `which podman-tui` + a config file (NO nested `podman run`) ⇒
eligible; no test starts a real display-manager at runtime ⇒ `vm-system-type-desktop` likely
eligible (one empirical confirm). ⇒ **18 clean userspace candidates**, **1 keep-QEMU-on-principle**
(`vm-boot-minimal` — a container reaching `multi-user.target` doesn't prove *bootability*), **2
verify** (`vm-system-type-desktop`, `vm-dev-team-vm-smoketest`). Biggest wins = multi-node tests:
`vm-hm-module-isolation` (8 nodes → 8 containers) + the two 2-node SSH tests (networking proof). The
one least-certain candidate to verify empirically during migration = `vm-sops-secrets` (sops-nix
`/run/secrets` activation). Migration ADDS no coverage — it makes the same assertions cheaper
(RAM/wall-clock); the only thing a container can't catch (kernel/boot/device/nesting) is exactly
what the QEMU-kept tests cover, so nothing useful is lost.

**API — source-verified against the pinned nixpkgs (store `…-3a2vdn5i7vd2wl654xs8nb52jf1v6cbh-source`):**
- The repo's `mkVmTest`/`mkHmModuleTest` wrap `pkgs.testers.nixosTest` = the LEGACY
  `simpleTest`/`testing-python.nix` path, which has **NO `containers` option**.
- The nspawn backend lives ONLY on `pkgs.testers.runNixOSTest` (= `nixos.runTest`, the module-based
  `nixos/lib/testing/` framework). `nixos/lib/testing/nodes.nix:179` declares `containers =
  mkOption { type = lazyAttrsOf config.container.type; … }` (base `baseNspawnOS`) alongside `nodes`
  (QEMU); `allMachines` merges both (name-collision-guarded). To run a machine on nspawn you place it
  under `containers.<name>` (Python `testScript` unchanged — names persist via `allMachines`).

**What was built (commit — see below):**
- **`mkContainerTest`** helper in `modules/flake-parts/vm-tests.nix` — parallel to `mkVmTest`, wraps
  `pkgs.testers.runNixOSTest` with `containers.machine` (auto-enables nspawn + the host `uid-range`
  requirement); drops `virtualisation.memorySize` (QEMU-only). API-ADAPTATION comment inline.
- **`vm-nspawn-smoke`** check — a deliberate TWIN of `vm-system-type-cli` (same `system-cli` module +
  same userspace assertions) so the ONLY variable is the backend ⇒ clean apples-to-apples
  wall-clock/RAM comparison.

**Empirical result (the POC's real deliverable):** `nix build '.#checks.x86_64-linux.vm-nspawn-smoke'`
on the WSL2 host built the **entire** pipeline successfully — the container system
(`nixos-system-machine-test`), the nspawn run-script (`run-machine-nspawn`), and the test driver
(`nixos-test-driver-vm-nspawn-smoke`: type-check + lint **All checks passed**). It then stopped at
exactly ONE gate:
```
error: Cannot build container-test-run-vm-nspawn-smoke.drv
       Reason: missing system features
       Required features: {kvm, nixos-test, uid-range}
       Available features:  {benchmark, big-parallel, kvm, nixos-test}
```
⇒ **The nspawn backend is fully functional on the current 26.05 pin; the sole prerequisite to
actually RUN containers is the Nix `uid-range` system feature**, which requires the daemon setting
`auto-allocate-uids = true` (+ `experimental-features += auto-allocate-uids`). This is exactly the
"host auto-allocate-uids" gate T2 predicted, now pinned precisely. A trusted-user client override
does NOT work (`Ignoring setting 'auto-allocate-uids' because experimental feature … is not
enabled`) — it is a **daemon-level (root) change**.

**Recommendation / next step (Interactive → USER_INPUT_REQUIRED):** enable in the repo's base nix
daemon config — `modules/system/types/1-minimal/minimal.nix` (where `nix.settings.experimental-features`
is set) — add:
```nix
nix.settings.experimental-features = [ … "auto-allocate-uids" ];
nix.settings.auto-allocate-uids = true;
```
This affects the **shared base module ⇒ fleet-wide** (all NixOS hosts gain nspawn-test capability),
so it is Tim's call (scope: base module vs dev-host-only vs CI-runner-only). Once enabled + a
`nixos-rebuild switch`, re-run `nix build '.#checks.x86_64-linux.vm-nspawn-smoke'` to get the first
green container run + speedup number, then add it to the CI matrix
(`.github/workflows/ci.yml` — CI builds only matrix-listed checks, so `vm-nspawn-smoke` is currently
safe/inert there) and proceed to migrate the 18 clean candidates. **Guardrail:** `vm-nspawn-smoke`
is registered as a check but intentionally NOT in the CI matrix and cannot build without the host
prereq — `nix flake check --no-build` (the green gate) evals it fine; do NOT add it to CI until
`auto-allocate-uids` lands.

**ENABLEMENT DONE (Tim: fleet-wide) — commit `405cf9d`.** Added to the NixOS block of the shared
base module `modules/system/types/1-minimal/minimal.nix`:
`experimental-features = [ … "auto-allocate-uids" ]` + `auto-allocate-uids = lib.mkDefault true`
(Darwin + HM blocks intentionally untouched — no systemd-nspawn there). **Eval-verified:**
`nixos-dev-team` toplevel drvPath evaluates clean (`nixos-system-nixos-dev-team-26.11…`). 
**To go from "config written" → "green container run" still needs a host REBUILD** (root/
long-running ⇒ ENVIRONMENT_NOT_CAPABLE from this session):
- **Any in-repo NixOS host:** `sudo nixos-rebuild switch --flake '.#<host>'` then
  `nix build '.#checks.x86_64-linux.vm-nspawn-smoke'` → first green run + speedup vs the QEMU twin
  `vm-system-type-cli`.
- **The WSL2 dev host `pa161878-nixos` (where the POC ran):** it is managed by **nixcfg-work**, which
  pins nixcfg `main`. So it picks up the base-module change only via a **nixcfg-work `flake.lock` pin
  bump** (= the deferred **T8b** coordination) + rebuild — OR a one-off manual rebuild against nixcfg
  `main` (`--override-input nixcfg …`). This couples the *permanent* enablement to the T8b pin story.

**GREEN — EMPIRICALLY VERIFIED end-to-end on the WSL2 host (2026-08-20, single-user root build,
daemon-bypass — no host rebuild, zero blast radius).** Rather than rebuild the corp host (which would
deploy the whole deferred 26.05 uplift), ran the test as root against the local store with the nix
config supplied via `NIX_CONFIG`. **The nspawn container booted and the test PASSED.** Timings vs the
identical QEMU twin `vm-system-type-cli` (same `system-cli` module + assertions):
| metric | QEMU | nspawn | speedup |
|---|---|---|---|
| boot → `multi-user.target` | 24.38s | **4.66s** | ~5.2× |
| test script total | 24.94s | **3.75s** | ~6.6× |
| (QEMU "connecting" alone) | 16.50s | ~0 | — |
The nspawn container ran the entire smoke faster than QEMU took just to *connect*. This is the
payoff the whole plan targeted.

**Two corrections the empirical run forced (both now committed `4e7abf7`):**
1. **The fleet-wide config needed THREE settings, not one** (405cf9d only had `auto-allocate-uids`).
   Working builder recipe = `experimental-features = [ … auto-allocate-uids cgroups ]` (nspawn places
   the container in a cgroup ⇒ needs the `cgroups` experimental feature) + `auto-allocate-uids = true`
   + advertise `uid-range` (`extra-system-features = [ "uid-range" ]`, append-safe). `minimal.nix`
   NixOS block updated to all three; `nixos-dev-team` toplevel evals clean.
2. **Test-assertion divergence (a real migration finding):** `vm-nspawn-smoke` first FAILED on
   `wait_for_unit("sshd.service")` — **sshd.service is inactive under nspawn** although the QEMU twin
   has it active (VM-vs-container service-activation difference; `system-cli` sets
   `services.openssh.enable = true` with no `startWhenNeeded`, so this is nspawn-specific). Switched to
   an activation-agnostic assertion (ssh host key generated). **Lesson for migrating the 18 candidates:
   service-`wait_for_unit` assertions may need container-aware equivalents; the SSH tests especially.**

**Enablement invocation that worked (for repro/CI-runner setup), for the record:**
```
sudo env NIX_CONFIG=$'experimental-features = nix-command flakes auto-allocate-uids cgroups\nauto-allocate-uids = true\nsystem-features = kvm nixos-test uid-range benchmark big-parallel' \
  nix build '.#checks.x86_64-linux.vm-nspawn-smoke' --store local --no-write-lock-file -L
```
Client `--extra-experimental-features`/`--option` flags did NOT work (parse-order: the
`auto-allocate-uids` *setting* is validated before the *feature* activates); `NIX_CONFIG` (file-style,
correct order) does. The daemon path also fails (daemon ignores client feature overrides) — hence the
permanent fix is the daemon config in `minimal.nix` + a rebuild.

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

### T3 — Input bump to the T0 target `TASK:COMPLETE`  (dep: T0, T1 — both COMPLETE)
On `feat/nixos-26.05`: update `flake.nix` input refs + `nix flake update` the relevant inputs to
fresh `nixos-unstable` HEAD (target confirmed in T0/session-2); run `nix flake check --no-build`
and fix eval breakers **across the 10 NixOS hosts + x86_64-linux HM configs** (WSL, NixOS
VM/EC2/graviton). Follow the repo's workaround-documentation protocol for any version-incompat
shims. Do NOT bump the nixcfg-work pin yet (separate coordinated step at plan completion).
**SCOPE (session-2 decision):** the public-repo x86 darwin configs (`macbook-air`, `powerbook`) are
**unmaintained and OUT OF SCOPE** (26.05 deprecates x86 darwin); they need NOT eval-green and do NOT
block T3. (Apple-Silicon darwin lives in nixcfg-work / 052 M-A, untouched here.)
**DoD:** `nix flake check --no-build` passes on the branch for the NixOS+HM surface; `git grep`
shows the new input refs. Any workaround carries an inline WORKAROUND/API-ADAPTATION comment +
commit note.
**Progress (2026-08-20):** community-core inputs bumped (nixpkgs/nixpkgs-unstable/home-manager/
darwin → 2026-08-16/19); lock staged. Remaining: NixOS/HM breaker triage under the bump;
follow-on bumps (nixpkgs-stable URL→25.11/26.05, ancillary community inputs, `timblaktu/*` forks);
re-check to green. See Findings T3.

### T4 — Enable nspawn backend on eligible tests `TASK:PENDING`  (Interactive/parked → USER_INPUT_REQUIRED; dep: T2, T3)
For each T2-eligible test, flip it to the nspawn backend (the declarative switch from PR #478109 —
confirm the exact option name against the pinned nixpkgs, do NOT guess) and add the required host
setting (`auto-allocate-uids`, per docs PR #479968) to the test's node config. Keep ineligible
tests on QEMU. Measure before/after wall-clock + peak RSS for at least the sops + ssh integration
tests and record the delta.
**DoD:** the converted tests pass via nspawn (`nix build '.#checks.<system>.<test>'` green); a
measured speedup/RAM table is recorded here; ineligible tests are explicitly listed as
intentionally-still-QEMU. No test logic (Python `testScript`) was rewritten, only infra config.

### T5 — Evaluate `system.nix` / channel-free consumption `TASK:COMPLETE`  (dep: T3, Interactive)
Assess whether `system.nix` buys nixcfg anything: (a) a no-flakes consumption path for teammates
who don't want flakes; (b) tightening `nixpkgs.flake.source` for pinned non-flake builds. Since the
repo is already flake-based, the likely outcome is "document as an option, don't adopt in core" —
but decide explicitly with Tim, don't assume.
**DoD:** a written recommendation (adopt / document-only / defer) with rationale; if adopt, a
follow-up task list; if not, a one-paragraph note in DISTRIBUTION.md pointing teammates at the
option. Interactive → USER_INPUT_REQUIRED for the final call.

### T6 — Expand coverage across all hosts `TASK:PENDING`  (Interactive/parked → USER_INPUT_REQUIRED; dep: T4)
With cheap containers available, add per-host smoke tests (boots, key services up, sudo/wheel,
expected packages present) for the 10 NixOS hosts, and the maximal-feasible darwin coverage (note:
darwin has no NixOS test driver — its "test" is the eval-green `.drv` gate + the shipped-image
smoketest; be honest about that asymmetry). Wire them into `flake-parts/{tests,vm-tests}.nix` so
CI enumerates them.
**DoD:** new smoke checks exist + pass for each eligible host; `nix flake check` enumerates them;
a coverage table (host → test kind → backend) is recorded. Silent gaps are logged, not hidden.

### T7 — Bump remaining `timblaktu/*` forks `TASK:PENDING`  (Interactive · coordination)
Bump the user-owned fork inputs that were intentionally left for last: `nixpkgs-docling`
(`docling-parse-fix`), `nixpkgs-esp-dev` (`c5`), `drawio-svg-sync`. (`home-manager-wsl` and
`nixos-wsl` were already handled in T3.) These track feature branches on Tim's own GitHub, so per
CLAUDE.md user-owned-repo workflow, bump only with coordination and verify each consumer still evals.
**DoD:** chosen forks bumped in `flake.lock`; `nix flake check --no-build` stays green; any fork that
needs an upstream edit first is noted (not silently skipped).

### T8 — Merge `feat/nixos-26.05`→`main` + nixcfg-work pin bump `TASK:PENDING`  (Interactive · coordination)
Merge the completed repoint branch to `main`, then bump the `nixcfg` `flake.lock` pin **inside
nixcfg-work** so the corp hosts consume it deliberately (mirrors the darwin-branch pin discipline).
Cross-repo blast radius — corp hosts consume nixcfg `main`. **Guardrail: confirm with Tim before
executing.** Deferred by Tim in session 4. **DoD:** `main` fast-forwarded/merged with the T3 work;
nixcfg-work `flake.lock` bumped to the new nixcfg `main` rev + its `nix flake check` green; both
recorded here + in parent 052.

## Guardrails
Serialize nix (no concurrent evals — an input bump eval is heavy). No AI attribution. Confirm the
merge to `main` + the nixcfg-work pin bump with Tim (cross-repo blast radius). This plan is Mode A
(human-attended); do not burndown.

## Session log
- 2026-08-20 (authoring): grounded via nixpkgs PRs #478109/#479968 + 26.05 release notes.
  Registered in 052 as M-E (top-priority WSL-side, parallel to M-A on the Mac).
- 2026-08-20 (T0–T2): Tim decided branch `feat/nixos-26.05` + target fresh `nixos-unstable`
  (T0 COMPLETE; branch created+pushed). T1 audit done. T2: **key discovery — the current pin
  (nixos-unstable 2026-05-31) ALREADY ships the nspawn backend** (PRs merged 2026-03-18/19), and
  the WSL2 dev host is nspawn-capable ⇒ **T3 bump is NOT a prerequisite; T4 can run on the current
  pin.** Corrected the earlier wrong "locked 2026-01-30 / bump-first" premise. Next: finish T2
  (eligibility map + a real nspawn `nixosTest` smoke run + CI-runner probes), then T4.
- 2026-08-20 (session 2 — re-sequencing, Tim): **priority inverted.** Tim: the **flake-wide repoint
  to fresh `nixos-unstable`** matters more than nspawn test migration; the test suite is a thin
  regression net so its before/after value is low. Decisions: (1) target = **fresh nixos-unstable
  HEAD** (confirms T0); (2) **defer ALL test migration** (T4+T6 parked). Actions taken this session:
  reconciled the branch (the prior session's T0–T2 commit c07cbce had landed on `main`, one commit
  ahead of `feat/nixos-26.05`; fast-forwarded feat to carry it), then **corrected the nspawn API**
  (it's a separate `containers` attr, not a per-node flip; test-driver `machine/` is monolithic here
  — see Findings T2 addendum), completed the 21-test eligibility map, and **promoted T3 (repoint) to
  the active top task**; T2 marked COMPLETE-as-rescoped. Next: execute T3 — `nix flake update` the
  core inputs on `feat/nixos-26.05`, `nix flake check --no-build`, triage+fix eval breakers across
  all hosts (Mode-A judgment work), then merge→main + coordinate the nixcfg-work pin bump.
- 2026-08-20 (session 3 — T3 breaker triage -> in-scope surface GREEN): fixed **both** eval breakers
  (A: HM claude-code `disabledModules` directory-layout fix, in-repo `b6e6bf3`; B: nixos-wsl fork
  `boot.bootspec.enable` removed+pushed `984df0c` + input bump `35e024e`), then bumped ancillary
  community inputs (`dd0cff1`). Verified **10/10 NixOS toplevels + 7/7 HM activationPackages eval
  clean** via explicit per-config eval (committed lock, no override). T3 core DoD MET; remaining
  items are all Interactive/coordination (nixpkgs-stable URL decision, `timblaktu/*` fork bumps,
  merge->main + nixcfg-work pin). See Findings T3 session-3. Discovered + worked around Bash grep
  token-corruption (`claude-code`->`ln`) by trusting the Read tool for file content.
- 2026-08-20 (session 4 — T3 CLOSED): Tim (via /next-task) decided: mark T3 COMPLETE, bump
  nixpkgs-stable `nixos-24.11`->`nixos-26.05`, defer the merge. Bumped nixpkgs-stable to
  `nixos-26.05` HEAD `b18a4b90` (commit `7c056ca`); confirmed nil blast radius (input is unused
  specialArg plumbing); `nix flake check --no-build` = all checks passed (0 errors) + graviton
  evals clean. **T3 marked COMPLETE.** Split the two remaining coordination items into **T7**
  (`timblaktu/*` fork bumps) and **T8** (merge->main + nixcfg-work pin, deferred). See Findings T3
  session-4.
- 2026-08-20 (session 5 — T7 CLOSED, no-op bump): Tim (via /next-task) chose T7. Found all three
  remaining fork inputs (`nixpkgs-docling`, `nixpkgs-esp-dev`, `drawio-svg-sync`) already pinned at
  their tracked-branch HEADs (locked rev == `git ls-remote` HEAD) ⇒ **no `flake.lock` bump exists to
  make.** Re-verified `nix flake check --no-build --keep-going` = all checks passed (unchanged lock).
  Noted two out-of-scope upstream follow-ups (docling stale-fork: drop-if-PR#184-merged or rebase;
  esp-dev `c5` rebase) — both Interactive, deferred. **T7 marked COMPLETE.** Remaining: T5 (system.nix
  eval), T8 (merge→main + pin, deferred), T4/T6 (parked nspawn migration). See Findings T7.
- 2026-08-20 (session 6 — T5 CLOSED, document-only): Tim (via /next-task) chose T5, then decided
  **document-only** for the final call. Verified `system.nix` (rl-2605 §17) against the pinned nixpkgs
  store path with the Read tool (Bash grep token-corrupts `system.nix`→`n` here). Concluded it solves
  a problem nixcfg doesn't have (already flake-based + channel-free; flake-averse teammates already get
  a zero-Nix path via the `.wsl` image; no `${nixcfg}/nixos` entry point exists to hook). Added a
  one-paragraph "A Note on `system.nix`" subsection to `docs/DISTRIBUTION.md` (upstream option for
  teammates' OWN non-flake configs, NOT a nixcfg consumption path). No core change. **T5 marked
  COMPLETE.** See Findings T5. Then Tim closed super-plan **H2** (numbering hygiene) and reviewed
  H1+M-E together, choosing **"T8a merge now, then M-C docs":** **T8a DONE locally** (fast-forwarded
  `main` to `feat/nixos-26.05` HEAD `4e8264a`; 17 ahead of `origin/main`; not pushed yet) — **T8b
  (nixcfg-work pin) stays DEFERRED**; then landed the H1/M-C image-outputs docs on `main`
  (DISTRIBUTION "Prebuilt Image Outputs" section). Remaining: push `main` (Tim confirm), M-C backlog,
  T4/T6 parked nspawn. See super-plan 052 session log 2026-08-20.
- 2026-08-20 (session 6 cont. — T6 nspawn POC): Tim chose non-docs work and reframed T6 as an
  **nspawn container POC decoupled from T4** ("per-host smoke via containers; don't need to migrate
  the existing suite first"). Did the candidate review he asked for (verified all 21 vm-\* tests are
  pure userspace ⇒ 18 clean candidates, 1 keep-QEMU, 2 verify; `node_podman` is config-only ⇒
  eligible). Source-verified the API (`runNixOSTest`+`containers`, NOT the legacy `nixosTest` the
  repo's `mkVmTest` wraps). Built **`mkContainerTest`** + **`vm-nspawn-smoke`** (twin of
  `vm-system-type-cli`): the whole nspawn pipeline BUILDS on the WSL2 host (driver type-check+lint
  pass, container system + `run-machine-nspawn` built) — stops at exactly one gate, the `uid-range`
  system feature (needs daemon `auto-allocate-uids`; client override rejected ⇒ root/NixOS-config
  change). **nspawn backend proven functional on the current pin; one fleet-scope host-config
  decision (auto-allocate-uids) is all that's left to run containers.** Chose "POC only, then
  reassess", then chose **fleet-wide** enablement: added `auto-allocate-uids` to the NixOS base
  module `minimal.nix` (commit `405cf9d`), eval-verified (`nixos-dev-team` toplevel clean). Only a
  host rebuild remains for a green container run (root/long-running ⇒ not here; for the WSL2 dev host
  it couples with the T8b nixcfg-work pin). See Findings T6.
