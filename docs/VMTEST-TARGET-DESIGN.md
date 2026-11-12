# VMTest Suite Target Design

> **Backend split.** The as-built backend split is 13 nspawn / 8 QEMU across the 21 `vm-*` checks - see [`TESTING-NSPAWN.md`](TESTING-NSPAWN.md). NixOS-integrated Home Manager activation runs on nspawn via the read-only-store recipe baked into `mkHmContainerTest` / `hmNspawnNode` (`build-users-group = ""` + a daemon-free `load-db` of the HM closure), so the HM-activation family runs on nspawn; only boot/kernel/hardware/real-network/graphics/image tests stay on QEMU. The authoritative live check list is `nix eval '.#checks.x86_64-linux' --apply builtins.attrNames`.

This document describes the target design of the VMTest suite and the rules that place each test on one of its two machine backends: QEMU (full virtual-machine emulation, needs KVM) or systemd-nspawn (a lightweight container that shares the host kernel, no KVM). For the live check inventory and tier model see [`../tests/README.md`](../tests/README.md); for the mechanism behind the backend difference see [`nix-store-model-and-vmtest-backends.md`](nix-store-model-and-vmtest-backends.md).

Source of truth for what each check does: [`VMTEST-AUDIT.md`](VMTEST-AUDIT.md). This document describes the design of the suite; the audit is the inventory of what it contains.

## The 2-tier model

- **Tier 0 - eval-regression gate ("nix checks, not tests").** Pure evaluation. Batched where possible.
  Runs in the fast `nix flake check --no-build` commit gate. Catches wiring/type/assertion regressions in
  every host + module without booting anything. Target: a handful of batched checks replacing ~40 today.
- **Tier 1 - behavioral tests.** Boot/activate and assert runtime behavior. `nodes` (QEMU) where boot/kernel/hardware/real-network/systemd-target semantics are the point; `containers` (nspawn) everywhere the assertion is boot-independent (userspace, config content).

Fidelity rule for QEMU->nspawn migration (from `vm-nspawn-smoke`): a test runs on nspawn **iff** none of its assertions depend on boot/kernel/hardware, real multi-node networking, kernel-capability semantics (setcap, netfilter/NET_ADMIN), or a `*.service` unit that nspawn socket-activates instead (`sshd.service` -> `sshd.socket`). Home Manager activation is NOT a blocker - the read-only-store recipe in `mkHmContainerTest` / `hmNspawnNode` lets `home-manager-<user>.service` activate on nspawn. Where only the ssh assertion blocks a move, the socket-form assertion is used rather than keeping the whole test on QEMU.

---

## Tier 0 - eval-regression gate

### The regression-test eval batch
`regression-test` is the single host/config eval batch. It absorbs **12** standalone host/config evals: it inherits `nixos-wsl-dev-team.stateVersion` + `home.username` (HM parity) in its attrs, which replaces the 12 standalone checks.

Replaces: `eval-thinky-nixos`, `eval-potato`, `eval-mbp`, `eval-nixos-wsl-minimal`, `eval-nixos-dev-team`, `eval-nixos-dev-team-ec2`, `eval-nixos-dev-team-graviton`, `eval-nixos-wsl-dev-team`, `eval-hm-thinky-nixos`, `eval-hm-thinky-ubuntu`, `eval-hm-mbp`, `eval-hm-nixvim-minimal`.

### The eval-hm-modules gate
`eval-hm-modules` is a single multi-module Home Manager eval gate. It replaces the **20** `eval-hm-module-*` isolation evals with one gate that forces every HM module to evaluate standalone against `home-minimal`. Same coverage (catches breakage in modules no tested host enables, e.g. corp-only), far less boilerplate; Nix names the broken module on failure.

Replaces all 20 `eval-hm-module-*` (verified against `builtins.attrNames`): claude-code, development-tools, esp-idf, files, git, git-auth-helpers, github-auth, gitlab-auth, neovim, onedrive, opencode, podman, secrets-management, shell, shell-utils, system-tools, terminal, tmux, windows-terminal, yazi.

### The eval-nixos-modules gate
`eval-nixos-modules` is a single multi-module NixOS layer eval gate. It consolidates the **6** `eval-nixos-module-*` system-layer evals into one gate, mirroring `eval-hm-modules`.

Replaces: `eval-nixos-module-system-minimal`, `-system-default`, `-system-cli`, `-system-desktop`, `-wsl`, `-secrets-management`. Each layer's required assertion setup travels with its entry as per-module `extraConfig` (system-default needs `systemDefault.userName != ""`; wsl needs `hostname`/`defaultUser`/`sshPort` + a `system-cli` import for `containerRuntime.enablePodman`; secrets-management needs the sops-nix NixOS module imported). Nix names the broken layer on failure. Same standalone-eval coverage, less boilerplate.

### Toplevel / tarball / image eval-forcers
These force a *deeper* eval (toplevel/tarball/images attrset) than `regression-test`'s stateVersion, so they remain as per-host deep-eval gates; only the misleading `build-*` prefix changes.

| Today | Rename to | Keeps |
|---|---|---|
| `build-thinky-nixos-dryrun` | `eval-thinky-nixos-toplevel` | forces `system.build.toplevel` |
| `build-nixos-wsl-minimal-dryrun` | `eval-nixos-wsl-minimal-toplevel` | forces toplevel |
| `build-nixos-dev-team-dryrun` | `eval-nixos-dev-team-toplevel` | forces toplevel |
| `build-tarball-dev-team-dryrun` | `eval-nixos-wsl-dev-team-tarball` | forces `tarballBuilder` |
| `build-tarball-thinky-dryrun` | `eval-thinky-nixos-tarball` | forces `tarballBuilder` |
| `build-images-dev-team-dryrun` | `eval-images-dev-team` | forces images + asserts `hasProxmox` |
| `build-images-ec2-dryrun` | `eval-images-ec2` | forces images + asserts `hasAmazon` |
| `build-images-graviton-dryrun` | `eval-images-graviton` | forces images + asserts `hasAmazon` |

### The merged wsl-settings eval
`ssh-service-configured` (renamed `eval-wsl-settings-ssh-port`), `cross-module-wsl-base`, and `module-wsl-settings-integration` all assert `wsl-settings.sshPort == 2223`. They merge into one eval that keeps the distinct invariants worth having (openssh port == wsl sshPort; base userName == wsl defaultUser).

### `build-*` package builds
`build-docling`, `build-marker-pdf`, `build-markitdown`, `build-nixvim-anywhere`, `build-termux-claude-scripts`, `build-tomd` are bare package derivations. They are kept as-is (they build packages, not eval); they are skipped by `--no-build` and belong in the full-build CI lane. No rename.

### `activate-hm-thinky-nixos`
The only check that builds an activation script and asserts on the artifact (catches the claude-code jq_args shell-quoting bug class). It is kept, and the pattern widens to a second host: `activate-hm-nixvim-minimal` (cheap), plus the corp Tier-A HM configs in nixcfg-work. This family is build-tier, so it is skipped by `nix flake check --no-build` and belongs in the full-build CI lane.

### Lint family
`lint-deadnix`, `lint-statix`, `lint-format`, `ps1-encoding`, and the version/`flake` lints are kept unchanged. They are out of scope for the behavioral refactor.

### Weak / no-op eval checks
The pure no-ops are removed; the salvageable ones are rewritten to actually assert; exactly one real files-module test is kept.

| Check | Disposition | Rationale |
|---|---|---|
| `flake-validation` | Removed | pure `echo + touch`, asserts nothing; `nix flake check` is the real validator |
| `validated-scripts-module` | Removed | tautological `echo + touch`, references no code |
| `ssh-public-keys-registry` | Removed | tests an inline copy of a regex, not any module (no such module exists) |
| `opencode-config-validation` | Removed | no failing assertion; `opencode-json-syntax`/`-mcp-structure` keep the real asserts |
| `cross-module-home-manager` | Removed | only checks a homeConfigurations key exists; subsumed by regression-test + activate-hm |
| `cross-module-sops-base` | Removed | no SOPS integration; user-exists overlaps `user-configured` |
| `config-snapshot-validation` | Folded into `regression-test` | its only assert is `stateVersion=="24.11"`; that equality is added to the batch and the standalone dropped |
| `tmux-picker-syntax` | Rewritten | actually runs `bash -n` on the picker script (today it never does) |
| `files-module-test` | Rewritten (salvaged) | becomes the one real files-module test - asserts a specific generated `home.file` exists with expected content |
| `unified-files-diagnostic-test` | Removed | diagnostic-only, stale narrative |
| `hybrid-files-module-test` | Removed | asserts only module shape + that nixpkgs' own writeBashBin works |
| `module-base-integration` | Rewritten | asserts `userGroups` (and keeps the `userName` check) instead of the single near-constant |

The no-ops and two of the three files-family checks are removed; `files-module-test` is salvaged into one genuine files-module assertion (a real generated `home.file` with expected content); `tmux-picker-syntax` (`bash -n`) and `module-base-integration` (`userGroups`) are rewritten. The `files` module also stays exercised behaviorally by `vm-dev-team-stack`.

---

## Tier 1 - behavioral tests

Backend column: **Q** = QEMU (boot/kernel/hardware/real-net/service semantics), **N** = nspawn (boot-independent).

> **Home Manager activation note.** The backend column reflects empirical findings (`TESTING-NSPAWN.md` "Constraints & caveats"). A naive HM-activation migration first failed under nspawn - nix's `LocalStore` chowns the read-only shared store on open - but the read-only-store recipe (`nix.settings.build-users-group = ""` to skip that chown, plus a daemon-free `nix-store --load-db` of the HM generation's `closureInfo` before `home-manager-<user>.service`) makes activation succeed with no writable store and no upstream change. That recipe is baked into the `mkHmContainerTest` / `hmNspawnNode` helpers, so every test that waits on `home-manager-<user>.service` runs on nspawn, including `vm-shell-env`, `vm-development-tools`, `vm-git-advanced`, `vm-neovim`, `vm-tmux`, and the `vm-hm-*` tests. sops-nix activation and multi-node `start_all` are also nspawn-safe (the latter needs hostname-valid node names, no underscores). QEMU is reserved for boot/kernel/hardware/real-network/graphics/image semantics.

### Backend placement per policy

| Test | Today | Backend | Why |
|---|---|---|---|
| `vm-boot-minimal` | Q | **Q** | the one genuine minimal-boot reference gate |
| `vm-system-type-default` | Q | **N** | user/wheel/locale/timezone/shell/pkgs - all userspace, no HM activation |
| `vm-system-type-cli` | Q | **Q** | QEMU twin of `vm-nspawn-smoke`; waits `sshd.service` |
| `vm-system-type-desktop` | Q | **Q** | X/display-manager/GPU/fonts - graphics semantics |
| `vm-nspawn-smoke` | N | **N** | the nspawn reference; unchanged |
| `vm-user-config` | Q | **Q** | passwordless sudo/groups/env plumbing - imports only `system-default`, runs on a QEMU node |
| `vm-shell-env` | Q | **N** | waits on `home-manager-<user>.service`; activates via the read-only-store recipe |
| `vm-development-tools` | Q | **N** | waits on `home-manager-<user>.service`; activates via the read-only-store recipe |
| `vm-git-advanced` | Q | **N** | waits on `home-manager-<user>.service`; activates via the read-only-store recipe |
| `vm-neovim` | Q | **N** | waits on `home-manager-<user>.service`; activates via the read-only-store recipe |
| `vm-tmux` | Q | **N** | waits on `home-manager-<user>.service`; activates via the read-only-store recipe |
| `vm-hm-activation` | Q | **N** | HM activation is the whole point; proven on nspawn via `mkHmContainerTest` |
| `vm-hm-composition-pairs` | Q | **N** | HM activation nodes; nspawn with hostname-valid (hyphenated) container names |
| `vm-hm-module-isolation` | Q | **N** | HM activation nodes; nspawn with hostname-valid (hyphenated) container names |
| `vm-sops-secrets` | Q | **N** | sops-nix `/run/secrets` activation is nspawn-safe: mode/owner/content preserved |
| `vm-ssh-service` | Q | **Q** | real two-node key auth + hardened `sshd.service` + cross-node network |
| `vm-dev-team-vm-smoketest` | Q | **Q** | shipped-image regression gate, `sshd.service`; re-exported into nixcfg-work CI |

### Merge / drop

| Test | Disposition | Rationale |
|---|---|---|
| `vm-ssh-management` | Removed, with `tests/integration/ssh-management.nix` | mock rbw + inline openssh; real path is `vm-ssh-service` |
| `vm-sops-deployment` | Removed, with `tests/integration/sops-deployment.nix` | hand-driven sops/age CLI; real path is `vm-sops-secrets` |
| `vm-yazi` | Merged, then removed | redundant with `node_yazi` in `vm-hm-module-isolation`; its `init.lua`+`keymap.toml` asserts fold there, then it is deleted |
| `vm-full-cli-stack` + `vm-dev-team-stack` | Merged into one | collapse into one parameterized compose test `vm-compose-stack` with a param selecting `system-cli` layer vs real `nixos-dev-team` host module; the union of asserts (incl. `files`, `podman`, no-conflict compose, delta/alias/toolchain checks) runs per parameterization. Backend: **Q** - it composes the real host module over `system-cli` (boot/host-layer semantics) and runs nightly in CI on QEMU; the HM activation it also exercises is not itself the reason it stays on QEMU |

### Add (Tier-1 behavioral coverage for Tier-A hosts)
Tier-A shipped/daily-driver hosts lack *behavioral* coverage. Daily drivers cannot
QEMU-boot (WSL/Darwin), so their Tier-1 coverage is module-composition stand-ins on nspawn/QEMU:

- **`vm-wsl-dev-team-layers` (QEMU):** QEMU compose of `system-cli` + `monitoring` + `mss-clamp` - the carrier of the exact layer stack the development host ships, standing in for the WSL box that can't boot. First behavioral coverage of `monitoring`/`mss-clamp` ("live-but-unguarded"). It stays on QEMU because `monitoring` asserts `security.wrappers` (setcap file capabilities) and `mss-clamp` installs an iptables TCPMSS rule (netfilter/NET_ADMIN) - kernel-capability semantics the unprivileged nspawn container cannot provide.
- **`activate-*` for corp HM (nixcfg-work):** build-dryrun of `corp-dev-team + tim-corp-personal` activation for the Tier-A Darwin/WSL HM configs (shared-module-on-Linux proxy).

(nuc-apt-repo `aptly-repo`/`apt-cacher-ng`, enterprise layers, jfrog/monitoring standalone, darwin samples,
and a real rbw->SSH test are out of scope for this design.)

---

## Coverage-preservation ledger (nothing dropped silently)
Every removal above is justified by a surviving check that covers the same real code, or by the target being a proven no-op:

- mocks (`vm-ssh-*management`, `vm-sops-deployment`) -> real twins (`vm-ssh-service`, `vm-sops-secrets`).
- `eval-*` / `eval-hm-*` standalone -> `regression-test` batch (+ `home.username`, + `nixos-wsl-dev-team`).
- `eval-hm-module-*` (20) -> `eval-hm-modules` (same standalone-eval property).
- `cross-module-home-manager` -> `regression-test` + `activate-hm-thinky-nixos`.
- weak no-ops (`flake-validation`, `validated-scripts-module`, `ssh-public-keys-registry`,
  `opencode-config-validation`) -> nothing lost (they asserted nothing).
- files-family / `config-snapshot-validation` -> folded or covered by `vm-dev-team-stack` (`files`) /
  `regression-test` (stateVersion).

## Net effect (approximate)
- Tier 0: ~40 eval/no-op checks -> ~4 batched gates (`regression-test`, `eval-hm-modules`, `eval-nixos-modules`, merged wsl-settings eval) + 8 renamed toplevel/tarball/image forcers + kept builds/lints; ~7 weak checks removed, 3 rewritten-to-assert.
- Tier 1: 22 `vm-*` -> the as-built 21 `vm-*` checks split **13 nspawn / 8 QEMU** (after dropping the 2 mocks `vm-ssh-management`/`vm-sops-deployment` + `vm-yazi`, merging the 2 stacks into `vm-compose-stack`, and adding `vm-wsl-dev-team-layers`). nspawn hosts both the HM-free userspace tests (`vm-system-type-default`, `vm-sops-secrets`, `vm-nspawn-smoke`) and the whole Home Manager activation family (`vm-hm-activation`, `vm-shell-env`, `vm-development-tools`, `vm-git-advanced`, `vm-neovim`, `vm-tmux`, `vm-claude-code-safety-hooks`, `vm-monitoring`, and the multi-node `vm-hm-composition-pairs`/`vm-hm-module-isolation`), which activate via the read-only-store recipe. QEMU keeps only the boot/kernel/hardware/real-network/graphics/image and kernel-capability gates (`vm-boot-minimal`, `vm-system-type-cli`, `vm-system-type-desktop`, `vm-user-config`, `vm-wsl-dev-team-layers`, `vm-ssh-service`, `vm-compose-stack`, `vm-dev-team-vm-smoketest`). The ~5-7x nspawn speedup therefore applies to most of the Tier-1 behavioral suite, on top of the Tier-0 win.
