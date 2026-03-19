# Distribution Overview

This document explains how nixcfg produces, releases, and distributes NixOS-WSL
images and reusable Nix modules for team consumption.

## What This Project Produces

nixcfg is a Nix flake that defines NixOS system configurations, Home Manager user
environments, and Darwin (macOS) setups. For team distribution, it produces two
primary outputs:

1. **Pre-built WSL tarballs** — Ready-to-import `.wsl` images for Windows users
   who want a turnkey NixOS development environment.
2. **Reusable Nix modules** — 47 exported modules (NixOS, Home Manager, Darwin)
   that teams can compose into their own configurations via flake input.

## Layer Architecture

Configurations are organized in composable layers. Each layer imports the one
below it and adds domain-specific concerns:

```
Layer 4: pa161878-nixos (personal)
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
