# Distribution Overview

This document explains how nixcfg produces, releases, and distributes NixOS-WSL
images and reusable Nix modules for team consumption.

## What This Project Produces

nixcfg is a Nix flake that defines NixOS system configurations, Home Manager user
environments, and Darwin (macOS) setups. For team distribution, it produces three
primary output kinds:

1. **Pre-built WSL tarballs** — Ready-to-import `.wsl` images for Windows users
   who want a turnkey NixOS development environment.
2. **Reusable Nix modules** — 57 exported modules (16 NixOS, 32 Home Manager, 9 Darwin)
   that teams can compose into their own configurations via flake input.
3. **Platform image artifacts** — Proxmox VMA, EC2 AMIs (x86_64 + aarch64 Graviton), and an
   Apple-Silicon Mac-VM `qcow2`, all built from the same `dev-team` NixOS config. See
   [Prebuilt Image Outputs](#prebuilt-image-outputs) for build commands and consumption paths.

## Layer Architecture

Configurations are organized in composable layers. Each layer imports the one
below it and adds domain-specific concerns:

```
Layer 4: my-machine (personal, in private repo)
         ├── Personal modules (esp-idf, awscli, etc.)
         └── imports ↓

Layer 3: wsl-dev-team (team)
         ├── binfmt cross-compilation (aarch64)
         ├── Podman containers
         ├── Claude Code / OpenCode
         ├── USB/IP device sharing
         └── imports ↓

Layer 2: wsl-enterprise (organization)
         ├── CrowdStrike Falcon sensor (opt-in)
         ├── Enterprise defaults
         └── imports ↓

Layer 1: system-cli + wsl-base (foundation)
         ├── Core dev tools (git, neovim, tmux, direnv, etc.)
         ├── WSL integration (wsl.conf, SSH, SOPS, CUDA)
         └── imports ↓

Layer 0: system-default → system-minimal
         ├── Nix settings, locale, timezone
         ├── Users, networking, fonts
         └── Core packages
```

Layers are convenience bundles, not gatekeepers. Any module can be imported
independently — the layers just provide curated combinations for common use cases.

The distributable image is built from the `nixos-wsl-dev-team` host configuration,
which composes layers 0–3 (everything except personal config). It ships with a
generic `dev` user and a `setup-username` script for personalization after import.

### Non-WSL Variant

The `dev-team` NixOS module provides the same dev stack (layers 0–3) for
non-WSL targets: VMs, Proxmox, bare metal, EC2. Image configurations for
Proxmox VMA and Amazon AMI formats are included.

### Home Manager Modules

Each layer has a parallel Home Manager bundle (`home-enterprise`, `home-dev-team`)
that works on **any** platform with Nix + home-manager installed — including
vanilla Ubuntu/Debian WSL distros, NixOS, and macOS. This means teammates who
can't or won't run NixOS can still get the shell, git, tmux, neovim, and tooling
configuration by importing Home Manager modules only.

## Release Process

### For Maintainers

Releasing a new version is a three-step process:

1. **Merge changes to `main`** — via PR from a feature branch.

2. **Update the `VERSION` file** — bump the semver string (e.g., `0.1.0` → `0.2.0`).
   Commit directly to `main` or via a "bump version" PR.

3. **Everything else is automated**:
   - `auto-tag.yml` detects the VERSION change, validates semver, and creates an
     annotated git tag.
   - `release.yml` is triggered by the new tag and:
     - Validates the tag matches the VERSION file
     - Builds the `nixos-wsl-dev-team` tarball builder derivation
     - Executes the builder to produce a `.wsl` tarball
     - Generates release notes from conventional commit messages
     - Creates a GitHub Release with two attached assets:
       - `nixcfg-wsl-dev-team-<version>.wsl` — the distribution image
       - `Import-NixOSWSL.ps1` — the PowerShell import/setup script

**Technical note**: `auto-tag.yml` uses a `RELEASE_PAT` (personal access token)
instead of `GITHUB_TOKEN` because GitHub Actions events created by `GITHUB_TOKEN`
don't trigger downstream workflows. The PAT ensures `release.yml` fires when the
tag is pushed.

### Manual Release

For ad-hoc releases without changing the VERSION file:

```bash
# Create and push a tag manually
git tag -a 0.3.0 -m "Release 0.3.0"
git push origin 0.3.0
# release.yml will trigger, but will fail if VERSION doesn't match the tag
```

Or trigger `release.yml` via workflow dispatch in the GitHub Actions UI.

## CI/CD Pipeline

Every push to `main` and every pull request runs the full validation pipeline
(`ci.yml`):

| Stage | What It Checks | Timeout |
|-------|----------------|---------|
| Flake evaluation | `nix flake metadata` + check name enumeration | 15 min |
| Linting (5 parallel) | nixpkgs-fmt, statix, deadnix, PS1 encoding, version | 15 min each |
| Module evaluations (26) | Each HM (20) and NixOS (6) module in isolation | 30 min each |
| Config evaluations (14) | All nixos-\*, hm-\*, vm-test configs | 30 min each |
| Integration tests (23) | Tarball dry-runs, image outputs, service tests | 30 min each |
| Tarball builds (3) | Full `.wsl` builds, uploaded as artifacts | 120 min |

The tarball build artifacts from CI are retained for 5 days, allowing testing
before an official release.

## How Teammates Consume This

### Option A: Pre-Built Image (Simplest)

Download and import the `.wsl` tarball. No Nix knowledge required.

1. Go to [GitHub Releases](https://github.com/timblaktu/nixcfg/releases/latest)
2. Download `nixcfg-wsl-dev-team-<version>.wsl` and `Import-NixOSWSL.ps1`
3. Run the import script

See [WSL-TEAM-QUICKSTART.md](WSL-TEAM-QUICKSTART.md) for the full walkthrough.

### Option B: Flake Input (Customizable)

Use this repo as a flake input and compose modules into your own configuration.
You get the same building blocks but can override anything, add your own modules,
or cherry-pick individual features.

```nix
{
  inputs.nixcfg.url = "github:timblaktu/nixcfg";

  # Full bundle:
  modules = [ nixcfg.nixosModules.wsl-dev-team ];

  # Or cherry-pick:
  modules = [
    nixcfg.homeManagerModules.shell
    nixcfg.homeManagerModules.git
    nixcfg.homeManagerModules.claude-code
  ];
}
```

See [SHARED-MODULES.md](SHARED-MODULES.md) for the complete module catalog with
usage examples and platform compatibility matrix.

### Option C: Build from Source

Clone the repo and build the tarball locally:

```bash
git clone https://github.com/timblaktu/nixcfg.git && cd nixcfg
nix build '.#nixosConfigurations.nixos-wsl-dev-team.config.system.build.tarballBuilder'
sudo ./result/bin/nixos-wsl-tarball-builder nixos.wsl
```

### A Note on `system.nix` (No-Flakes NixOS)

NixOS 26.05 added [`system.nix`](https://nixos.org/manual/nixos/stable/release-notes),
an entry point that lets you configure NixOS **without channels and without flakes** —
you pin nixpkgs with `builtins.fetchTarball` and `import "${nixpkgs}/nixos" { configuration = ./configuration.nix; }`,
then build with `nixos-rebuild --file`/`--attr`. This is an **upstream option for your own
machines**, not a nixcfg consumption path: nixcfg's modules are exported through flake-parts
(the `flake.modules.*` namespace), so there is no channel-style `${nixcfg}/nixos` import target.
Teammates who prefer to avoid flakes should use **Option A** (the pre-built `.wsl` image, zero Nix
knowledge required); `system.nix` is only relevant if you are hand-rolling a non-flake NixOS
config of your own and want to reference upstream nixpkgs without `nix-channel`.

## Prebuilt Image Outputs

Beyond the `.wsl` tarball, the flake exports **five** distributable image artifacts as short
convenience aliases (`packages.<system>.image-*`), so you don't have to type the long
`nixosConfigurations.<host>.config.system.build.*` paths. Each builds from a dedicated host
config and targets a specific platform:

| Artifact | Build attr | Arch (build host) | `result/` contents | Consumed by |
|----------|-----------|-------------------|--------------------|-------------|
| Proxmox VMA | `image-proxmox-dev-team` | x86_64-linux | `vzdump-qemu-*.vma.zst` | Proxmox VE restore |
| EC2 AMI (x86_64) | `image-ec2-dev-team` | x86_64-linux | `*.img` (raw) | AWS AMI import (coldsnap) |
| WSL tarball builder | `image-wsl-dev-team` | x86_64-linux | `bin/nixos-wsl-tarball-builder` | run it -> `.wsl` (see below) |
| EC2 AMI (aarch64 Graviton) | `image-ec2-dev-team-graviton` | aarch64-linux | `*.img` (raw) | AWS Graviton AMI import |
| **Mac-VM qcow2** | `image-vm-dev-team` | aarch64-linux | `nixos.qcow2` (UEFI, ext4, auto-resize) | Apple-Silicon UTM/QEMU |

Source of truth: `modules/flake-parts/packages.nix` (aliases) building the
`nixos-dev-team{,-ec2,-graviton,-vm}` and `nixos-wsl-dev-team` host configs in
`modules/flake-parts/nixos-configurations.nix`.

```bash
# x86_64-linux artifacts (build on an x86_64 Linux host):
nix build '.#image-proxmox-dev-team'      # -> result/vzdump-qemu-*.vma.zst
nix build '.#image-ec2-dev-team'          # -> result/*.img
nix build '.#image-wsl-dev-team'          # -> result/bin/nixos-wsl-tarball-builder
sudo ./result/bin/nixos-wsl-tarball-builder nixos.wsl   # then: wsl --import

# aarch64-linux artifacts (build on aarch64: a Graviton runner or Apple-Silicon Linux VM;
# nixcfg-work CI already builds+publishes the qcow2 on its aarch64 Graviton runner):
nix build '.#image-ec2-dev-team-graviton' # -> result/*.img
nix build '.#image-vm-dev-team'           # -> result/nixos.qcow2
```

Note the single quotes around `.#...` — zsh would otherwise glob-expand the `#`.

### Mac-VM (Apple Silicon / UTM) walkthrough

The `image-vm-dev-team` output is an aarch64 NixOS `qcow2` for running the dev-team NixOS
environment as a guest on an Apple-Silicon Mac (native aarch64 virtualisation, no emulation):

1. **Build the qcow2 on an aarch64-linux builder** (a Graviton runner, an Apple-Silicon Linux
   VM, or pull the CI-published artifact from nixcfg-work's pipeline):
   `nix build '.#image-vm-dev-team'` -> `result/nixos.qcow2`.
2. **Copy `nixos.qcow2` to the Mac** (`result/` is a read-only store symlink -- copy the
   dereferenced file, e.g. `cp -L result/nixos.qcow2 ~/nixos.qcow2`).
3. **Create a UTM VM:** New -> Virtualize -> Linux; under "Boot Image / existing disk" import
   `nixos.qcow2`; keep the default UEFI (the image is a UEFI/ext4 disk that auto-resizes to the
   virtual disk on first boot).
4. **Boot and personalise:** log in as the generic `dev` user and run the same
   `setup-username` / Home Manager steps used for the WSL image.

This is the Apple-Silicon counterpart to the WSL `.wsl` image and the EC2/Graviton AMIs -- one
shared NixOS `dev-team` config, delivered per platform.

## Import Script

`Import-NixOSWSL.ps1` automates WSL tarball import and Windows Terminal profile
setup. It exists because `wsl --import` has several bugs
([microsoft/WSL#13064](https://github.com/microsoft/WSL/issues/13064),
[#13129](https://github.com/microsoft/WSL/issues/13129),
[#13339](https://github.com/microsoft/WSL/issues/13339)) that prevent it from
creating Terminal profile fragments correctly.

The script handles:

- **WSL storage detection** — finds where existing distros are stored and places
  the new one alongside them
- **Distro replacement** — detects existing distro with same name, offers to
  replace (unregister + reimport)
- **Terminal profile creation** — computes the correct two-tier GUID and writes
  a Terminal fragment file with custom icon/font/colors
- **Orphan cleanup** — removes stale profiles and state.json entries left by
  previous imports
- **Terminal restart prompt** — reminds the user to restart Terminal to see the
  new profile

Source: `docs/tools/Import-NixOSWSL.ps1`
Architecture details: `docs/tools/TERMINAL-PROFILE-ARCHITECTURE.md`

## Validation

`Test-WslImport.ps1` is an integration test harness that automates the full
**Build -> Import -> Validate -> Cleanup** pipeline. It calls `Import-NixOSWSL.ps1`
directly (testing the real import path) and verifies the result.

### Quick Start

```powershell
# Full pipeline (build + import + validate + cleanup)
.\Test-WslImport.ps1

# Test a pre-built tarball from a release download
.\Test-WslImport.ps1 -TarballPath .\nixcfg-wsl-dev-team-0.1.0.wsl -SkipBuild

# Test all WSL-capable configs
.\Test-WslImport.ps1 -All

# Keep test distro for manual inspection
.\Test-WslImport.ps1 -SkipCleanup
```

### What It Validates

- Distro responds and boots to systemd
- Default user and hostname match Nix config expectations
- Nix and NixOS are functional (`nix --version`, `nixos-version`)
- Nix store integrity (`nix-store --verify`)
- WSL conf default user
- Available tools (git, tmux, podman, setup-username -- conditional)
- Windows Terminal fragment file exists with correct GUID computation
- Two-tier GUID system (Tier 2 profile GUID and Tier 1 hide GUID)

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | One or more checks failed |
| 2 | Fatal error (WSL missing, build failed, import failed) |

### When to Run

- **Pre-release**: Full pipeline to validate a new tarball before tagging
- **Post-download**: With `-SkipBuild -TarballPath` to verify a release artifact
- **CI artifact testing**: Download CI artifact and validate on a real Windows machine

Source: `docs/tools/Test-WslImport.ps1`

## Tarball Contents

The `.wsl` tarball is a compressed NixOS root filesystem. It includes:

- **Full NixOS system** at the `system-cli` level (no GUI packages)
- **WSL integration** — wsl.conf, automount, interop, SSH daemon
- **Dev tooling** — git, neovim, tmux, direnv, fzf, ripgrep, fd, and ~50 other
  CLI tools
- **AI assistants** — Claude Code and OpenCode with multi-account wrapper scripts
- **Containers** — Podman with `docker` alias
- **Cross-compilation** — aarch64 binfmt via QEMU
- **CrowdStrike Falcon** — module included but disabled by default (opt-in).
  On WSL2, the sensor enters Reduced Functionality Mode (compliance inventory only).
  See [CrowdStrike WSL2 Security Brief](CROWDSTRIKE-WSL2-SECURITY-BRIEF.md)
- **Generic `dev` user** — with `setup-username` for personalization
- **wsl-distribution.conf** — custom Terminal profile metadata (icon, name)

The tarball does **not** include Home Manager user configuration. Users apply HM
config after import, either manually or by using this flake's `home-dev-team`
module.

Approximate tarball size: ~1.8 GiB (optimized by disabling Mesa/LLVM for
CLI-only operation; CUDA auto-enables graphics when needed).

## Related Documentation

- [WSL-TEAM-QUICKSTART.md](WSL-TEAM-QUICKSTART.md) — End-user import guide
- [SHARED-MODULES.md](SHARED-MODULES.md) — Module catalog for flake consumers
- [ARCHITECTURE.md](ARCHITECTURE.md) — Repository structure and design patterns
- [WSL-CONFIGURATION-GUIDE.md](WSL-CONFIGURATION-GUIDE.md) — WSL-specific config details
- [CrowdStrike WSL2 Security Brief](CROWDSTRIKE-WSL2-SECURITY-BRIEF.md) — IT-facing analysis and recommendations
- [CrowdStrike WSL Limitations](../modules/programs/crowdstrike-falcon/docs/WSL-LIMITATIONS.md) — Technical reference for module developers

---

**Last Updated**: 2026-03-18
