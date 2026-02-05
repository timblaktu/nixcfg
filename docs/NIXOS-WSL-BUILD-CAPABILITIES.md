# NixOS WSL Build Capabilities Research

**Date**: 2026-02-04
**Branch**: `research/nixos-wsl-build`
**Status**: Research Complete

## Executive Summary

This document summarizes the current capabilities for building NixOS WSL tarballs/images from this nixcfg repository and the broader Nix ecosystem.

### Key Findings

1. **NixOS-WSL provides the tarball builder** - The `system.build.tarballBuilder` attribute is the primary mechanism
2. **nixos-generators does NOT support WSL format** - No built-in WSL format exists
3. **This repo already has working infrastructure** - `nixos-wsl-minimal` config can build tarballs today
4. **Security checks exist** - `wsl-tarball-checks.nix` validates tarballs before distribution

---

## Current Capabilities in This Repository

### Existing NixOS Configurations for WSL

```
nixosConfigurations:
├── nixos-wsl-minimal  # Generic distribution config (allowUnfree=false)
├── thinky-nixos       # Personal WSL dev machine
└── pa161878-nixos     # Work WSL instance with CUDA
```

### Building a WSL Tarball

**From this flake (recommended)**:
```bash
# Dry-run to verify build
nix build '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballBuilder' --dry-run

# Actual build (requires sudo for tarball creation)
sudo nix run '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballBuilder'

# Output: nixos.wsl in current directory
```

**From upstream NixOS-WSL**:
```bash
sudo nix run github:nix-community/NixOS-WSL#nixosConfigurations.default.config.system.build.tarballBuilder
```

### Tarball Builder Options

The `tarballBuilder` script supports:

| Option | Description |
|--------|-------------|
| `--extra-files <path>` | Copy additional files into the tarball root |
| `--chown <path> <uid:gid>` | Adjust ownership of files post-copy |

**Example with customization**:
```bash
sudo nix run '.#...' -- --extra-files ./extra --chown /home/myuser 1000:100
```

### Security Validation

`modules/wsl-tarball-checks.nix` provides:
- Personal identifier detection (tim, tblack, etc.)
- Sensitive environment variable checking
- SSH key inclusion warnings
- Bypass option: `WSL_TARBALL_SKIP_CHECKS=1`

Access the security check script:
```bash
nix build '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballSecurityCheck'
./result/bin/wsl-tarball-security-check
```

---

## Module Architecture

### WSL-Related Modules

```
modules/
├── wsl-common.nix           # Parameterized WSL config (143 LOC)
│   - hostname, defaultUser, interop settings
│   - SSH configuration
│   - Windows PATH integration
├── wsl-tarball-checks.nix   # Security/privacy validation
├── nixos/
│   ├── wsl-cuda.nix         # CUDA support for WSL
│   └── wsl-storage-mount.nix # Bare disk mounting

home/
├── common/wsl-home-base.nix # Home Manager WSL module (portable)
└── modules/
    ├── windows-terminal.nix # Windows Terminal management
    └── terminal-verification.nix # Font verification
```

### Two Distinct WSL Scenarios

| Scenario | Module Type | Requirement | Portability |
|----------|-------------|-------------|-------------|
| **NixOS-WSL** | `nixosModules.wsl-base` | Full NixOS-WSL distro | NixOS-WSL only |
| **Home Manager on WSL** | `homeManagerModules.wsl-home-base` | Any distro + nix + HM | Universal |

---

## External Tools Comparison

### NixOS-WSL (Primary Tool)

**URL**: `github:nix-community/NixOS-WSL`

**Flake Outputs**:
- `nixosModules.default` / `nixosModules.wsl` - NixOS module for WSL integration
- `nixosConfigurations.default` - Reference configuration
- `packages.x86_64-linux.{docs,utils,staticUtils}` - Utilities

**Tarball Building**: Via `config.system.build.tarballBuilder`

**Strengths**:
- Purpose-built for WSL
- Active development (nix-community)
- Includes utilities package

**Limitations**:
- x86_64-linux only (no aarch64 WSL support - Windows ARM WSL uses x86 emulation)
- Requires sudo for tarball creation

### nixos-generators (Does NOT Support WSL)

**URL**: `github:nix-community/nixos-generators`

**Supported Formats** (32 total):
```
amazon, azure, cloudstack, do, docker, gce, hyperv,
install-iso, iso, kexec, kubevirt, linode, lxc,
openstack, proxmox, qcow, raw, sd-aarch64,
vagrant-virtualbox, virtualbox, vm, vmware
```

**WSL Status**: NO WSL FORMAT EXISTS

**Why**: WSL tarballs require specific boot configuration and WSL-specific userspace that NixOS-WSL handles internally.

---

## Import Workflow (Windows Side)

After building `nixos.wsl`:

```powershell
# Import into WSL
wsl --import NixOS C:\wsl\NixOS .\nixos.wsl

# Set as default (optional)
wsl --set-default NixOS

# Launch
wsl -d NixOS
```

---

## Flake Input Configuration

Current `flake.nix` input:
```nix
# Custom fork for plugin-shim-integration (WIP)
nixos-wsl.url = "github:timblaktu/NixOS-WSL/plugin-shim-integration";
nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";
```

Alternative (upstream):
```nix
nixos-wsl.url = "github:nix-community/NixOS-WSL";
nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";
```

---

## Recommendations

### For Distribution to Colleagues

1. Use `nixos-wsl-minimal` as base (generic, unfree disabled)
2. Run security checks before building tarball
3. Document import instructions

### For Personal Development

1. Use personal configs (`thinky-nixos`, `pa161878-nixos`)
2. Skip security checks with caution

### Future Improvements

1. **CI/CD tarball building** - GitHub Actions workflow for automated builds
2. **nixos-generators WSL format** - Potential upstream contribution
3. **aarch64 support** - Monitor Windows ARM WSL developments
4. **Incremental tarballs** - Delta updates for faster distribution

---

## Related Documentation

- `docs/ARCHITECTURE.md` - Overall repository architecture
- `docs/WSL-CONFIGURATION-GUIDE.md` - Windows Terminal and WSL config
- `docs/NIXOS-WSL-BARE-MOUNT-*.md` - Bare mount feature documentation
- [NixOS-WSL Official Docs](https://nix-community.github.io/NixOS-WSL/)

---

## Quick Reference

### Build Commands

```bash
# List available NixOS configs
nix eval '.#nixosConfigurations' --apply 'x: builtins.attrNames x'

# Dry-run tarball build
nix build '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballBuilder' --dry-run

# Build tarball (produces nixos.wsl)
sudo nix run '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballBuilder'

# Run security check
nix build '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballSecurityCheck'
./result/bin/wsl-tarball-security-check nixos-wsl-minimal
```

### Key Paths

| Item | Location |
|------|----------|
| Minimal WSL config | `hosts/nixos-wsl-minimal/default.nix` |
| WSL common module | `modules/wsl-common.nix` |
| Security checks | `modules/wsl-tarball-checks.nix` |
| Home Manager WSL base | `home/common/wsl-home-base.nix` |
