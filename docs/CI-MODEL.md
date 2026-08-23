# CI Model: Flake-Owned Classification as Single Source of Truth

> Status: plan 054 P11 deliverable. This document is the specification that plan
> 052 / nixcfg-work-004 T1 builds the nixcfg-work GitLab pipeline against. It
> defines the ONE flake-owned classification map from which BOTH the GitHub
> Actions workflow and the GitLab child pipeline are derived, so that CI is a
> pure function of the flake rather than a pair of hand-maintained matrices that
> silently drift.
>
> The flake side (the `ci.classification` map, `.#ci.matrix`, `.#ci.tarballs`, and
> the `ci-matrix-sync` drift guard) is IMPLEMENTED and verified in
> [ci-classification.nix](../modules/flake-parts/ci-classification.nix). The
> GitHub `ci.yml` rewire to consume `.#ci.matrix` is the second half of P11 and
> lands after Tim signs off on the classification map.

## 1. Motivation: CI as a pure function of the flake

Before this model, `.github/workflows/ci.yml` carried the check-to-job partition
as hand-maintained YAML matrices. Every time a check was added, renamed, or
retiered, a human had to remember to edit those matrices - in two places once a
second platform (GitLab) came online. That is exactly the class of drift that
plan 054 is closing: the check set is generated from the flake, but the
*partition* of that set into jobs (which tier, which backend, which arch, which
builder features) was still prose living in YAML.

The fix is to make the partition itself a flake output. One attrset,
`ci.classification`, records for every check its tier, backend, systems, and
required builder features. From that attrset the flake computes `.#ci.matrix`, a
platform-neutral JSON manifest. Each CI platform reads the SAME JSON and realizes
it in its own native matrix syntax. A drift guard (`ci-matrix-sync`) fails the
build if any check in `.#checks.<system>` is missing a classification, so a new
check cannot reach `main` unclassified.

Design goal, restated: `ci.classification` must reproduce the current `ci.yml`
partition EXACTLY (behavior-preserving rewire), AND be consumable by both a
GitHub `fromJSON` matrix and a GitLab child pipeline generated from the same JSON.

## 2. The portability boundary

This is the heart of the document. Everything CI does splits into two disjoint
lists. If a fact is in list A it lives in the flake and is identical on every
platform. If it is in list B it is realized differently per platform and lives in
that platform's CI config, never in the flake.

### (A) SHARED / flake-owned (identical on GitHub and GitLab)

These are computed once, in Nix, and are byte-for-byte identical no matter which
CI consumes them:

1. **The check set** - `.#checks.<system>` (the 58-check suite: 57 domain checks
   plus the `ci-matrix-sync` guard itself, mirrored on `x86_64-linux` and
   `aarch64-linux`). Generated from the flake; never hand-listed in any CI file.
2. **The `ci.classification` map** - the per-check `{ tier, backend, systems,
   requires, enabled }` attrset (schema in section 3). The single source of truth
   for the partition.
3. **tier / backend / arch / requires facts** - the classification values
   themselves. "vm-boot-minimal is a `qemu` backend check that needs `kvm` and is
   meaningful only on `x86_64-linux`" is a flake fact, not a GitHub fact.
4. **The dispatch command** - every check runs via exactly
   `nix build '.#checks.<system>.<name>' --print-build-logs`. Identical shell on
   both platforms. There is no per-platform test invocation logic.
5. **The `.#ci.matrix` manifest** (and its sibling `.#ci.tarballs`) - the
   platform-neutral JSON derived from `ci.classification`, the artifact both CIs
   consume.
6. **The `ci-matrix-sync` drift guard** - a check that fails if
   `attrNames .#checks.<system>` and `attrNames ci.classification` disagree.
   Identical on both platforms; it is itself just another `.#checks` entry.

The invariant: if you can compute it from the flake without knowing which CI is
asking, it belongs in list A.

### (B) PLATFORM-SPECIFIC (realized differently per platform)

These cannot be flake facts because they name platform-proprietary machinery.
They live in `.github/workflows/ci.yml` and in the nixcfg-work `.gitlab-ci.yml`
respectively, and each is a thin adapter over the same list-A JSON:

1. **Cache backend** -
   - GitHub: `DeterminateSystems/magic-nix-cache-action@v14` (magic-nix-cache).
   - GitLab: hsw-infra S3 cache (the self-hosted store the nixcfg-work runners
     already point at). Configured via `nix.conf` `substituters` /
     `extra-substituters` on the runner, not in the flake.
2. **Runner selection** -
   - GitHub: `runs-on:` values - `ubuntu-latest` (x86_64),
     `ubuntu-24.04-arm` (aarch64).
   - GitLab: `tags:` values matching the hsw-infra runner registration
     (e.g. an x86_64 tag and an aarch64 tag). Same intent, different key.
3. **Matrix realization** -
   - GitHub: `strategy.matrix` populated by `fromJSON(...)` reading `.#ci.matrix`.
   - GitLab: a parent-child (dynamic child) pipeline - a generator job emits a
     child `.yml` from the same `.#ci.matrix` JSON, and `trigger:` runs it.
4. **KVM / arch reach for the qemu backend** - THE one place where the same
   classification produces a DIFFERENT realized set per platform:
   - GitHub: the `qemu` backend runs on `x86_64-linux` ONLY. GitHub's arm64
     runners (`ubuntu-24.04-arm`) have no `/dev/kvm`, so aarch64 qemu checks
     cannot run there.
   - GitLab (nixcfg-work): the hsw-infra runners were redeployed with
     KVM-on-all-arches, so the `qemu` backend CAN also run on `aarch64-linux`.
     GitLab may therefore expand a qemu check to both arches where GitHub is
     forced to x86_64 only.

   Note that this divergence is NOT a fork of the classification. The
   classification records the *capability requirement* (`requires = ["kvm"]`) and
   the *meaningful arches* (`systems`). Each platform's adapter then INTERSECTS
   those flake facts with what its runners can actually provide. GitHub's adapter
   drops aarch64 qemu because its runners lack kvm; GitLab's adapter keeps it
   because its runners have kvm. The flake stays single-source; the reach
   difference is a pure consequence of runner capability, expressed entirely in
   list B.

The invariant: if realizing it requires naming a proprietary runner, cache, or
matrix syntax, it belongs in list B.

## 3. Classification schema reference

Every entry in `ci.classification` is keyed by check name and has this shape:

```nix
ci.classification.<checkName> = {
  tier    = "pr" | "nightly" | "local";
  backend = "eval" | "lint" | "build" | "nspawn" | "qemu" | "tarball";
  systems = [ "x86_64-linux" ... ];   # arches on which the check is meaningful
  requires = [ ... ];                 # builder features: "kvm", "uid-range", or []
  enabled  = true;                    # optional; false => omit from the CI matrix
};
```

### tier - WHEN it runs

| tier | Meaning | GitHub realization | GitLab realization |
|---|---|---|---|
| `pr` | every push / PR / MR | default jobs (no `if:`) | default child jobs |
| `nightly` | scheduled + manual dispatch only | `if: schedule || workflow_dispatch` | scheduled pipeline + `when: manual` |
| `local` | never in CI - local validation only | excluded from all matrices | excluded from all matrices |

### backend - HOW it runs / what it needs

| backend | What it is | Builder feature | Typical cost |
|---|---|---|---|
| `lint` | `runCommand` source-level lint (formatting, statix, deadnix, ps1, version) | none | seconds |
| `eval` | pure eval or light `runCommand` deep-eval forcer (no VM, no build) | none | seconds |
| `build` | forces a real derivation to BUILD (HM activationPackage, package closures) | none | minutes |
| `nspawn` | behavioral test on the systemd-nspawn container backend | `uid-range` | ~5s boot |
| `qemu` | behavioral test on a real QEMU VM (needs a kernel + `/dev/kvm`) | `kvm` | tens of s to min |
| `tarball` | nixosConfiguration `tarballBuilder` build + run (shipped-image path) | `kvm` | minutes |

`nspawn` needs `uid-range` (the builder must advertise it via `auto-allocate-uids`;
see [TESTING-NSPAWN.md](TESTING-NSPAWN.md)). `qemu`/`tarball` need `kvm`. `lint`,
`eval`, and `build` need no special builder feature.

### systems - WHICH arches the check is meaningful on

The arches where the check has semantic meaning (mirrored suite is
`x86_64-linux` + `aarch64-linux`). This is a flake fact independent of any runner.
The per-platform adapter intersects it with runner capability (section 2, item B4).

### requires - builder features

The concrete builder features the backend needs: `["kvm"]`, `["uid-range"]`, or
`[]`. This is what each platform's adapter reads to decide `extra-system-features`
/ `extra-nix-config` and, for qemu, whether a given arch's runners can host it.

### enabled - matrix emission toggle

Optional, defaults `true`. `enabled = false` keeps a check classified (so the
drift guard still requires it to exist as a real derivation) but instructs the
matrix derivation to OMIT it from the CI views. Used for `build-docling` (section
6). It does NOT remove the check from `.#checks`.

## 4. The classification map (behavior-preserving mirror of ci.yml)

The full map is the source of truth
([ci-classification.nix](../modules/flake-parts/ci-classification.nix)); the
salient groupings, which reproduce the pre-P11 `ci.yml` jobs exactly, are:

- **lint / pr / x86_64 / no requires** (job `lint`): `lint-formatting`,
  `lint-statix`, `lint-deadnix`, `lint-ps1-encoding`, `lint-version`.
- **eval / pr / x86_64 / no requires** (job `checks`, eval subset):
  `regression-test`, `eval-hm-modules`, `eval-nixos-modules`,
  `eval-wsl-settings-ssh-port`, `eval-nixos-dev-team-toplevel`,
  `eval-nixos-wsl-minimal-toplevel`, `eval-thinky-nixos-toplevel`,
  `eval-nixos-wsl-dev-team-tarball`, `eval-thinky-nixos-tarball`,
  `eval-images-dev-team`, `eval-images-ec2`, `eval-images-graviton`,
  `files-module-test`, `module-base-integration`, `module-binfmt-integration`,
  `tmux-picker-syntax`, `user-configured`, `wsl-dev-team-setup-username-user`,
  `opencode-json-syntax`, `opencode-mcp-structure`, `skill-injection-awscli`,
  `skill-injection-glab`, `skill-injection-negative`, `skill-injection-pulumi`,
  plus `ci-matrix-sync` itself (the self-classified guard).
- **build / pr / x86_64 / no requires** (job `checks`, build subset):
  `activate-hm-nixvim-minimal`, `activate-hm-thinky-nixos`.
- **nspawn / pr / BOTH arches / requires uid-range** (job `vmtest-nspawn`):
  `vm-nspawn-smoke`, `vm-system-type-default`, `vm-sops-secrets`,
  `vm-hm-activation`, `vm-shell-env`, `vm-neovim`, `vm-tmux`, `vm-git-advanced`,
  `vm-hm-composition-pairs`, `vm-hm-module-isolation`, `vm-development-tools`.
- **qemu / pr / x86_64 (GitHub) / requires kvm** (job `vmtest-qemu`):
  `vm-boot-minimal`, `vm-system-type-cli`, `vm-system-type-desktop`,
  `vm-ssh-service`, `vm-user-config`, `vm-wsl-dev-team-layers`,
  `vm-dev-team-vm-smoketest`.
- **qemu / nightly / x86_64 / requires kvm** (job `vmtest-compose-stack`):
  `vm-compose-stack` (heavy two-VM ~6min ~80 asserts).
- **build / nightly / x86_64 / no requires** (job `pkgs`): `build-marker-pdf`,
  `build-markitdown`, `build-nixvim-anywhere`, `build-termux-claude-scripts`,
  `build-tomd`, and `build-docling` (`enabled = false`, see section 6).

### 4.1 Two special-case checks the guard classifies explicitly

The check set contains two entries that are in `.#checks` but NOT in any CI job.
The guard cannot treat them as unclassified drift; the classification names them
explicitly:

- **`github-actions`** - `tier=local`, `backend=eval`. It is an `act`-based local
  validation `runCommand` (runs GitHub Actions locally via act + podman;
  disabled by default in
  [github-actions.nix](../modules/flake-parts/github-actions.nix)). Running it in
  CI would be recursive and needs podman. `tier=local` means the generated matrix
  MUST exclude it from every CI job; it is validated locally only.
- **`build-docling`** - `tier=nightly`, `backend=build`, but currently DISABLED
  (`enabled = false`). See section 6.

### 4.2 The tarball builds are not `.#checks` entries (`.#ci.tarballs`)

The nightly `tarball-build` job builds
`nixosConfigurations.{nixos-wsl-dev-team,thinky-nixos}.config.system.build.tarballBuilder`
and then runs the builder. These are nixosConfiguration builds, NOT entries in
`.#checks`. They are exposed in a sibling `.#ci.tarballs` manifest keyed by CONFIG
name (`{ config, artifact, systems, requires = ["kvm"] }`), which the
`ci-matrix-sync` guard (reconciling `.#checks` against `ci.classification`) never
touches - so they are not flagged as missing checks. A dedicated CI job on each
platform consumes `.#ci.tarballs`. Do NOT try to make them look like `.#checks`
entries. Note the DISTINCT eval-tier forcers `eval-nixos-wsl-dev-team-tarball` /
`eval-thinky-nixos-tarball` ARE real `.#checks` entries (they force the builder
derivation to eval, never build) and are unrelated to the nightly tarball builds
that actually run the builder.

## 5. The `.#ci.matrix` shape and consuming it on each platform

`.#ci.matrix` is a JSON object pre-grouped by `{ tier -> backend }` so each list
is a ready-to-realize matrix payload. The actual shape (verify with
`nix eval '.#ci.matrix' --json | jq`):

```json
{
  "schemaVersion": 1,
  "all":     [ { "name": "...", "tier": "...", "backend": "...", "systems": [...], "requires": [...], "enabled": true }, ... ],
  "ci":      [ ...every enabled, non-local row (flat)... ],
  "pr": {
    "lint":   [ { "name": "lint-formatting", "systems": ["x86_64-linux"], "requires": [] }, ... ],
    "eval":   [ ... ],
    "build":  [ ... ],
    "nspawn": [ { "name": "vm-nspawn-smoke", "systems": ["x86_64-linux","aarch64-linux"], "requires": ["uid-range"] }, ... ],
    "qemu":   [ { "name": "vm-boot-minimal", "systems": ["x86_64-linux"], "requires": ["kvm"] }, ... ]
  },
  "nightly": {
    "build": [ ...5 package builds... ],
    "qemu":  [ { "name": "vm-compose-stack", ... } ]
  }
}
```

- `all` is the audit view: every classified row INCLUDING `tier=local` and
  `enabled=false`.
- `ci` and the `pr`/`nightly` groups are the CI views: they OMIT `tier=local`
  (`github-actions`) and `enabled=false` (`build-docling`) rows, so a consumer
  that iterates them never schedules a skip-ci or disabled check.
- The nightly tarball builds are NOT here; they are in `.#ci.tarballs` (section
  4.2).

### 5.1 GitHub Actions (strategy.matrix + fromJSON)

A one-time `matrix` prep job emits the JSON groups as step outputs; downstream
jobs read them via `fromJSON`:

```yaml
jobs:
  matrix:
    runs-on: ubuntu-latest
    outputs:
      pr_lint:      ${{ steps.gen.outputs.pr_lint }}
      pr_eval:      ${{ steps.gen.outputs.pr_eval }}
      pr_build:     ${{ steps.gen.outputs.pr_build }}
      pr_nspawn:    ${{ steps.gen.outputs.pr_nspawn }}
      pr_qemu:      ${{ steps.gen.outputs.pr_qemu }}
      nightly_build: ${{ steps.gen.outputs.nightly_build }}
      nightly_qemu:  ${{ steps.gen.outputs.nightly_qemu }}
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v31
      - uses: DeterminateSystems/magic-nix-cache-action@v14
      - id: gen
        run: |
          echo "pr_nspawn=$(nix eval --json '.#ci.matrix.pr.nspawn')" >> "$GITHUB_OUTPUT"
          echo "pr_qemu=$(nix eval --json '.#ci.matrix.pr.qemu')"     >> "$GITHUB_OUTPUT"
          # ...one line per group...

  vmtest-nspawn:
    needs: matrix
    strategy:
      fail-fast: false
      matrix:
        check: ${{ fromJSON(needs.matrix.outputs.pr_nspawn) }}
        target:
          - { runner: ubuntu-latest,    system: x86_64-linux }
          - { runner: ubuntu-24.04-arm, system: aarch64-linux }
    runs-on: ${{ matrix.target.runner }}
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v31
        with:
          extra_nix_config: |
            extra-experimental-features = nix-command flakes auto-allocate-uids cgroups
            auto-allocate-uids = true
            extra-system-features = uid-range
      - uses: DeterminateSystems/magic-nix-cache-action@v14
      - run: nix build '.#checks.${{ matrix.target.system }}.${{ matrix.check.name }}' --print-build-logs
```

For the `qemu` group GitHub keeps `runs-on: ubuntu-latest` (x86_64 only) - its
adapter drops aarch64 because arm64 runners lack `/dev/kvm` (section 2, B4).

### 5.2 GitLab CI (parent-child / dynamic child pipeline)

A generator job turns the SAME `.#ci.matrix` JSON into a child `.gitlab-ci.yml`
and triggers it. This generator is the one piece of GitLab-specific code
nixcfg-work-004 T1 must write; it is a pure function of `.#ci.matrix` and contains
no check names, tiers, or arches of its own:

```yaml
generate-matrix:
  stage: prepare
  tags: [nix-x86_64]         # hsw-infra runner tag (list B: runner selection)
  script:
    # a small script that reads `nix eval --json '.#ci.matrix'` and emits YAML
    - ./ci/gen-gitlab-child.sh > child-pipeline.yml
  artifacts:
    paths: [child-pipeline.yml]

run-checks:
  stage: test
  needs: [generate-matrix]
  trigger:
    include:
      - artifact: child-pipeline.yml
        job: generate-matrix
    strategy: depend
```

The emitted child jobs each run the identical dispatch
`nix build '.#checks.<system>.<check>' --print-build-logs`, select an hsw-infra
runner by `tags:`, and use the hsw-infra S3 substituter from the runner's
`nix.conf` (list B: cache backend). Because the hsw-infra runners have
KVM-on-all-arches, the GitLab generator MAY expand a `qemu` check across both
arches in `systems` where GitHub could not (section 2, B4). Same JSON, wider
realized reach.

## 6. build-docling: the disabled-but-classified row

`build-docling` is classified `tier=nightly`, `backend=build`,
`systems=["x86_64-linux"]`, `requires=[]`, PLUS `enabled = false`. It is DISABLED
pending plan 054 P10: `docling-parse-4.5.0` will not compile against nlohmann
under GCC14 (3.10.5 gives an ambiguous `input_adapter`; 3.11.3 gives a
`basic_json` bool SFINAE failure) - a distinct upstream compat blocker, not a CI
problem.

Because `enabled = false`, the matrix derivation omits `build-docling` from the
`ci` / `nightly.build` views, so BOTH consumers skip it. It stays in
`ci.classification` (so `ci-matrix-sync` does not flag it as missing) and stays
buildable on demand via `nix build '.#checks.x86_64-linux.build-docling'` or
`workflow_dispatch`. Re-enabling after P10 is a single flag flip
(`enabled = true`) in the classification, with no edit to either CI file - the
payoff of the whole model.

## 7. How a new check flows (and how forgetting to classify fails closed)

The lifecycle of any new check under this model:

1. **Add the check.** Author writes the new `.#checks.<system>.<name>`
   derivation in the appropriate flake-parts module
   ([tests.nix](../modules/flake-parts/tests.nix) or
   [vm-tests.nix](../modules/flake-parts/vm-tests.nix)).
2. **Classify it.** Author adds one `ci.classification.<name> = { tier; backend;
   systems; requires; }` entry in
   [ci-classification.nix](../modules/flake-parts/ci-classification.nix).
3. **Both CIs pick it up automatically.** `.#ci.matrix` recomputes; the GitHub
   `fromJSON` matrix and the GitLab child pipeline both gain the check on their
   next run. No YAML matrix edit on either platform.

If step 2 is skipped:

4. **`ci-matrix-sync` fails.** The drift guard reconciles
   `attrNames .#checks.<system>` against `attrNames ci.classification`. A check
   present in `.#checks` but absent from `ci.classification` (or vice versa) makes
   the guard exit non-zero and NAME the offender. Because `ci-matrix-sync` is
   itself a `pr`-tier check run on both platforms, an unclassified check CANNOT
   reach `main` - the model fails closed. This is the mechanism that keeps CI a
   pure function of the flake: you literally cannot add a check without
   classifying it.

The only escape hatches are the two explicit special cases in section 4.1
(`github-actions` as `tier=local`, `build-docling` as `enabled=false`), both of
which are recorded IN the classification, so the guard sees them as classified,
not as drift.

## 8. Verifying the model locally

```bash
# The manifest evaluates and is well-formed:
nix eval '.#ci.matrix' --json | jq '{schema: .schemaVersion, all: (.all|length), ci: (.ci|length)}'
nix eval '.#ci.tarballs' --json | jq

# The drift guard passes on a synced tree, and fails (naming the offender) if a
# check is added without a classification row:
nix build '.#checks.x86_64-linux.ci-matrix-sync' -L
```

## 9. Related documents

- [ci-cd-integration.md](ci-cd-integration.md) - general CI/CD integration
  strategies and the platform compatibility matrix.
- [TESTING-NSPAWN.md](TESTING-NSPAWN.md) - the systemd-nspawn container backend
  (the `uid-range` requirement, host prerequisites, writing a container test).
- [nix-store-model-and-vmtest-backends.md](nix-store-model-and-vmtest-backends.md)
  - the store model behind the qemu vs nspawn backend split.
- [github-actions.nix](../modules/flake-parts/github-actions.nix) - the
  `act`-based local validation check classified `tier=local`.
