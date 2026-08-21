# VMTest Suite Target Design (plan 054 P4)

Status: **AGREED 2026-08-21** — Tim signed off on the four open decisions (Q1-Q4, resolved inline below and
recorded in the plan's "P4 decisions" log). This is the target the P5 execution implements. No code changes
happen in P4; P5 executes this table.

Source of truth for what each check does: [`docs/VMTEST-AUDIT.md`](VMTEST-AUDIT.md). This doc is the
*forward* design (what the suite becomes); the audit is the *backward* inventory (what it is today).

## The 2-tier model

- **Tier 0 — eval-regression gate ("nix checks, not tests").** Pure evaluation. Batched where possible.
  Runs in the fast `nix flake check --no-build` commit gate. Catches wiring/type/assertion regressions in
  every host + module without booting anything. Target: a handful of batched checks replacing ~40 today.
- **Tier 1 — behavioral tests.** Boot/activate and assert runtime behavior. `nodes` (QEMU) where boot/
  kernel/hardware/real-network/systemd-target semantics are the point; `containers` (nspawn) everywhere the
  assertion is boot-independent (userspace, HM activation, config content) — the **aggressive-nspawn**
  policy from P3(b). Tier-A hosts first.

Fidelity rule for QEMU→nspawn migration (from `vm-nspawn-smoke`, P3): a test may move to nspawn **iff**
none of its assertions depend on boot/kernel/hardware, real multi-node networking, or a `*.service` unit
that nspawn socket-activates instead (`sshd.service` → `sshd.socket`). Where only the ssh assertion blocks
a move, rewrite that one assertion (socket form) rather than keeping the whole test on QEMU.

---

## Tier 0 — eval-regression gate

### T0.1 `regression-test` (EXPAND — the single host/config eval batch)
Absorbs **12** standalone host/config evals (P3(d)). P5 first ADDS `nixos-wsl-dev-team.stateVersion` +
`home.username` (HM parity) to its inherited attrs, THEN drops the 12 standalone checks.

DROP (folded in): `eval-thinky-nixos`, `eval-potato`, `eval-mbp`, `eval-nixos-wsl-minimal`,
`eval-nixos-dev-team`, `eval-nixos-dev-team-ec2`, `eval-nixos-dev-team-graviton`, `eval-nixos-wsl-dev-team`,
`eval-hm-thinky-nixos`, `eval-hm-thinky-ubuntu`, `eval-hm-mbp`, `eval-hm-nixvim-minimal`.

### T0.2 `eval-hm-modules` (NEW — one multi-module HM eval gate)
Replaces the **20** `eval-hm-module-*` isolation evals (P3(e)) with one gate that forces every HM module to
evaluate standalone against `home-minimal`. Same coverage (catches breakage in modules no tested host
enables, e.g. corp-only), far less boilerplate; Nix names the broken module on failure.

DROP (folded in): all 20 `eval-hm-module-*` — verified against `builtins.attrNames` (2026-08-21):
claude-code, development-tools, esp-idf, files, git, git-auth-helpers, github-auth, gitlab-auth, neovim,
onedrive, opencode, podman, secrets-management, shell, shell-utils, system-tools, terminal, tmux,
windows-terminal, yazi.

### T0.3 `eval-nixos-modules` (NEW — one multi-module NixOS layer eval gate) — **Q4: CONSOLIDATE**
Consolidate the **6** `eval-nixos-module-*` system-layer evals into one gate, mirroring T0.2.

DROP (folded in): `eval-nixos-module-system-minimal`, `-system-default`, `-system-cli`, `-system-desktop`,
`-wsl`, `-secrets-management`. Each layer's required assertion setup travels with its entry as per-module
`extraConfig` (system-default needs `systemDefault.userName != ""`; wsl needs `hostname`/`defaultUser`/
`sshPort` + a `system-cli` import for `containerRuntime.enablePodman`; secrets-management needs the sops-nix
NixOS module imported). Nix names the broken layer on failure. Same standalone-eval coverage, less
boilerplate.

### T0.4 Renamed toplevel / tarball / image eval-forcers (KEEP, RENAME — P3(c))
These force a *deeper* eval (toplevel/tarball/images attrset) than `regression-test`'s stateVersion, so they
stay as per-host deep-eval gates; only the misleading `build-*` prefix changes.

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

### T0.5 SSH-2223 triple → one wsl-settings eval (MERGE — P2/P3(c))
`ssh-service-configured` (rename target: `eval-wsl-settings-ssh-port`), `cross-module-wsl-base`,
`module-wsl-settings-integration` all assert `wsl-settings.sshPort == 2223`. Merge into ONE eval that keeps
the distinct invariants worth having (openssh port == wsl sshPort; base userName == wsl defaultUser).

### T0.6 `build-*` package builds (KEEP — Tier 0 build subset)
`build-docling`, `build-marker-pdf`, `build-markitdown`, `build-nixvim-anywhere`,
`build-termux-claude-scripts`, `build-tomd` — bare package derivations. Keep as-is (they build packages,
not eval); they're skipped by `--no-build` and belong in the full-build CI lane (P6). No rename.

### T0.7 `activate-hm-thinky-nixos` (KEEP + WIDEN — P3/audit)
The only check that BUILDS an activation script and asserts on the artifact (catches the claude-code
jq_args shell-quoting bug class). Keep. Widen the pattern to a second host: add `activate-hm-nixvim-minimal`
(cheap) in P5, and the corp Tier-A HM configs in P6/nixcfg-work. (Note: this family is build-tier, so it is
skipped by `nix flake check --no-build` and belongs in the full-build CI lane.)

### T0.8 Lint family (KEEP as-is)
`lint-deadnix`, `lint-statix`, `lint-format`, `ps1-encoding`, version/`flake` lints — keep. Out of scope
for the behavioral refactor.

### T0.9 Weak / no-op eval checks — DELETE the no-ops, salvage one files test (**Q3: chosen**)
Delete the pure no-ops; rewrite the salvageable ones to actually assert; keep exactly ONE real files-module
test.

| Check | Proposed | Rationale |
|---|---|---|
| `flake-validation` | **DELETE** | pure `echo + touch`, asserts nothing; `nix flake check` is the real validator |
| `validated-scripts-module` | **DELETE** | tautological `echo + touch`, references no code |
| `ssh-public-keys-registry` | **DELETE** | tests an inline copy of a regex, not any module (no such module exists) |
| `opencode-config-validation` | **DELETE** | no failing assertion; `opencode-json-syntax`/`-mcp-structure` keep the real asserts |
| `cross-module-home-manager` | **DELETE** | only checks a homeConfigurations key exists; subsumed by regression-test + activate-hm |
| `cross-module-sops-base` | **DELETE** | no SOPS integration; user-exists overlaps `user-configured` |
| `config-snapshot-validation` | **FOLD** into `regression-test` | its only assert is `stateVersion=="24.11"`; add that equality to the batch, drop the standalone |
| `tmux-picker-syntax` | **REWRITE** | actually run `bash -n` on the picker script (today it never does) |
| `files-module-test` | **REWRITE→salvage** | Q3: this becomes the ONE real files-module test — assert a specific generated `home.file` exists with expected content |
| `unified-files-diagnostic-test` | **DELETE** | diagnostic-only, stale narrative |
| `hybrid-files-module-test` | **DELETE** | asserts only module shape + that nixpkgs' own writeBashBin works |
| `module-base-integration` | **REWRITE** | Q3: assert `userGroups` (and keep the `userName` check) instead of the single near-constant |

**Q3 resolved:** delete the no-ops + 2 of the 3 files-family checks; salvage `files-module-test` into one
genuine files-module assertion (a real generated `home.file` with expected content); rewrite
`tmux-picker-syntax` (`bash -n`) and `module-base-integration` (`userGroups`). The `files` module also stays
exercised behaviorally by `vm-dev-team-stack`.

---

## Tier 1 — behavioral tests

Backend column: **Q**=stays QEMU (boot/kernel/hardware/real-net/service semantics), **N**=migrate to
nspawn (boot-independent), **N?**=migrate but verify in P5 (activation/systemd nuance).

### Keep, migrate backend per policy

| Test | Today | Target | Why |
|---|---|---|---|
| `vm-boot-minimal` | Q | **Q** | the one genuine minimal-boot reference gate |
| `vm-system-type-default` | Q | **N** | user/wheel/locale/timezone/shell/pkgs — all userspace |
| `vm-system-type-cli` | Q | **Q** | QEMU twin of `vm-nspawn-smoke`; waits `sshd.service` |
| `vm-system-type-desktop` | Q | **Q** | X/display-manager/GPU/fonts — graphics semantics |
| `vm-nspawn-smoke` | N | **N** | the nspawn reference; keep unchanged |
| `vm-user-config` | Q | **N** | passwordless sudo/groups/env plumbing — userspace |
| `vm-shell-env` | Q | **N** | zsh login shell/aliases/.zshrc — userspace |
| `vm-development-tools` | Q | **N** | toolchain presence + negative kubectl assert — userspace |
| `vm-git-advanced` | Q | **N** | git config values + functional git — userspace |
| `vm-neovim` | Q | **N** | nvim headless/plugins/treesitter — userspace |
| `vm-tmux` | Q | **N** | tmux server lifecycle/options — userspace |
| `vm-hm-activation` | Q | **N?** | HM `home-manager-$user.service` activation path — verify nspawn hosts the unit |
| `vm-hm-composition-pairs` | Q | **N?** | 4 nodes × HM pairs — verify nspawn multi-container |
| `vm-hm-module-isolation` | Q | **N?** | 8 nodes × single HM module — verify nspawn multi-container |
| `vm-sops-secrets` | Q | **N?** (Q1: migrate, verify P5) | sops-nix activation + secret perms + permission-boundary; P5 verifies nspawn hosts the sops-nix activation path before the move is committed — if fidelity fails, it stays QEMU |
| `vm-ssh-service` | Q | **Q** | real two-node key auth + hardened `sshd.service` + cross-node network |
| `vm-dev-team-vm-smoketest` | Q | **Q** | shipped-image regression gate, `sshd.service`; re-exported into nixcfg-work CI |

### Merge / drop

| Test | Proposed | Rationale |
|---|---|---|
| `vm-ssh-management` | **DELETE** + `tests/integration/ssh-management.nix` | mock rbw + inline openssh; real path is `vm-ssh-service` (P2) |
| `vm-sops-deployment` | **DELETE** + `tests/integration/sops-deployment.nix` | hand-driven sops/age CLI; real path is `vm-sops-secrets` (P2) |
| `vm-yazi` | **MERGE→drop** (Q2) | redundant with `node_yazi` in `vm-hm-module-isolation`; fold its `init.lua`+`keymap.toml` asserts there, then delete |
| `vm-full-cli-stack` + `vm-dev-team-stack` | **MERGE→one** (Q2) | collapse into one parameterized compose test `vm-compose-stack` with a param selecting `system-cli` layer vs real `nixos-dev-team` host module; the union of asserts (incl. `files`, `podman`, no-conflict compose, delta/alias/toolchain checks) runs per parameterization. Backend: **N?** (HM-activation compose — verify nspawn) except the `sshd.service` assert on the dev-team parameterization uses the socket form |

### Add (Tier-1 behavioral for Tier-A hosts — the active gap)
The P2/P3 active gap is "Tier-A shipped/daily-driver hosts lack *behavioral* coverage." Daily drivers can't
QEMU-boot (WSL/Darwin), so their Tier-1 coverage is module-composition stand-ins on nspawn/QEMU:

- **`vm-wsl-dev-team-layers` (N, NEW):** nspawn compose of `system-cli + wsl-dev-team + wsl-enterprise` +
  `monitoring` + `mss-clamp` — the exact layer stack `pa161878-nixos` ships, standing in for the WSL box
  that can't boot. First behavioral coverage of `monitoring`/`mss-clamp` (P3 "live-but-unguarded").
- **`activate-*` for corp HM (P6/nixcfg-work):** build-dryrun of `corp-dev-team + tim-corp-personal`
  activation for the Tier-A Darwin/WSL HM configs (shared-module-on-Linux proxy).

(nuc-apt-repo `aptly-repo`/`apt-cacher-ng`, enterprise layers, jfrog/monitoring standalone, darwin samples,
real rbw→SSH test remain **P7 backlog**, not P4/P5.)

---

## Coverage-preservation ledger (nothing dropped silently)
Every DELETE above is justified by a surviving check that covers the same real code, or by the target being
a proven no-op:

- mocks (`vm-ssh-*management`, `vm-sops-deployment`) → real twins (`vm-ssh-service`, `vm-sops-secrets`).
- `eval-*` / `eval-hm-*` standalone → `regression-test` batch (+ `home.username`, + `nixos-wsl-dev-team`).
- `eval-hm-module-*` (20) → `eval-hm-modules` (same standalone-eval property).
- `cross-module-home-manager` → `regression-test` + `activate-hm-thinky-nixos`.
- weak no-ops (`flake-validation`, `validated-scripts-module`, `ssh-public-keys-registry`,
  `opencode-config-validation`) → nothing lost (they asserted nothing).
- files-family / `config-snapshot-validation` → folded or covered by `vm-dev-team-stack` (`files`) /
  `regression-test` (stateVersion).

## Net effect (approximate)
- Tier 0: ~40 eval/no-op checks → ~4 batched gates (`regression-test`, `eval-hm-modules`,
  `eval-nixos-modules`, merged wsl-settings eval) + 8 renamed toplevel/tarball/image forcers + kept
  builds/lints; ~7 weak checks deleted, 3 rewritten-to-assert.
- Tier 1: 22 `vm-*` → **17** — drop 2 mocks (`vm-ssh-management`, `vm-sops-deployment`) + `vm-yazi` + merge
  the 2 stacks into 1 (`vm-compose-stack`), + 1 new `vm-wsl-dev-team-layers`. Majority migrated QEMU→nspawn
  (~5-7× faster); QEMU retained only for boot/graphics/real-ssh/image gates.

## Decisions resolved (Tim, 2026-08-21)
- **Q1 — sops on nspawn:** **MIGRATE** `vm-sops-secrets` to nspawn, verify the sops-nix activation-path
  fidelity in P5; fall back to QEMU only if that verification fails.
- **Q2 — compose-test consolidation:** **drop `vm-yazi`** (fold into isolation) AND **merge**
  `vm-full-cli-stack` + `vm-dev-team-stack` into one parameterized `vm-compose-stack`.
- **Q3 — weak-test disposition:** delete the no-ops + 2/3 files-family; **salvage one** real files-module
  test (`files-module-test` rewritten); rewrite `tmux-picker-syntax` (`bash -n`) and
  `module-base-integration` (`userGroups`).
- **Q4 — NixOS layer evals:** **CONSOLIDATE** the 6 `eval-nixos-module-*` into one `eval-nixos-modules`
  gate (mirrors the HM 20→1).
