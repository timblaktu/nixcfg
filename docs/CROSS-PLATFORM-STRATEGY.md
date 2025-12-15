# Cross-Platform Support Strategy

**Created**: 2025-12-15
**Status**: Planning phase
**Related**: ARCHITECTURE.md, CONSOLIDATION-PLAN.md

## Overview

This document outlines the comprehensive cross-platform support strategy for nixcfg, ensuring it serves as a robust foundation for:
1. Personal system configurations (Tim's machines)
2. Shareable components for work colleagues
3. Multiple deployment modes (native dev shells vs NixOS VMs)
4. CI/CD integration across platforms

## Platform Support Matrix

### Target Platforms

| Host Platform | CPU Arch | Native nix develop | NixOS VM | Primary Use Case | Current Status |
|--------------|----------|-------------------|-----------|------------------|----------------|
| **Bare-metal Linux** | x86_64 | ✅ Excellent | ✅ KVM/QEMU native | Server, workstation | ✅ Fully working |
| **Bare-metal Linux** | aarch64 | ✅ Excellent | ✅ KVM/QEMU native | ARM servers, SBCs | ✅ Fully working |
| **Windows 11 + WSL2** | x86_64 | ✅ Via WSL | ✅ QEMU in WSL | Developer workstations | ✅ Recently consolidated |
| **macOS Darwin** | aarch64 (M3-4) | ⚠️ Lagging | ✅ QEMU + Hypervisor.framework | Apple Silicon Macs | 🟡 Template exists, VMs needed |
| **macOS Darwin** | x86_64 (Intel) | ⚠️ Lagging | ✅ QEMU + Hypervisor.framework | Intel Macs | 🔜 Planned |

### Platform-Specific Notes

#### Bare-metal Linux
- **Strengths**: Best performance, native Nix support, excellent VM acceleration
- **Dev Shell Support**: Optimal - no special handling needed
- **VM Support**: Native KVM/QEMU with hardware acceleration
- **CI/CD**: GitHub Actions Linux runners (x86_64)

#### Windows 11 + WSL2
- **Strengths**: Windows integration, WSLg for GUI apps, Hyper-V option
- **Dev Shell Support**: Excellent via WSL (any distro with Nix installed)
- **VM Support**: QEMU within WSL2 (nested virtualization)
- **Modules**:
  - `nixosModules.wsl-base` - For NixOS-WSL distro
  - `homeManagerModules.wsl-home-base` - For ANY WSL distro with home-manager
- **Templates**: `wsl-nixos`, `wsl-home`
- **Status**: ✅ Consolidated (Dec 2025-12-13)

#### macOS Darwin (M3-4 Apple Silicon)
- **Strengths**: Native aarch64, good performance
- **Dev Shell Support**: ⚠️ nix-darwin support lagging/broken in some cases
- **VM Support**: ✅ QEMU with Hypervisor.framework, UTM wrapper available
  - Can run aarch64 NixOS VMs natively (fast)
  - Can run x86_64 NixOS VMs with emulation (slow but compatible)
- **Modules**: Template exists, needs expansion
- **Templates**: `darwin`
- **Status**: 🟡 Template exists, VM configurations needed
- **VM Fallback**: Critical for workaround when nix-darwin breaks

## Deployment Mode Decision Tree

### When to use `nix develop` shells

✅ **Best for**:
- Fast iteration on projects
- CI/CD pipelines (GitHub Actions, GitLab CI)
- Lightweight tooling needs
- Host system integration desired (access to host files, network, etc.)
- Quick prototyping
- Developer workstations with working Nix

❌ **Not suitable for**:
- Full system testing
- OS-level configuration testing
- When nix-darwin is broken (use VM fallback)
- Reproducible builds requiring OS isolation

### When to use NixOS VMs

✅ **Best for**:
- Full system isolation
- Testing NixOS configurations
- Darwin workarounds (when nix-darwin broken)
- Consistent test environments
- Reproducible builds at OS level
- Desktop environments (GUI apps via X11/Wayland)

❌ **Not suitable for**:
- CI/CD (too heavy, slow startup)
- Quick development iteration
- Resource-constrained environments

## Architecture Layers

### Layer 1: Platform-Agnostic Components (Shareable)
**Location**: Future shared flake repository

**Contents**:
- Generic dev shells for common workflows:
  - Python development
  - Rust development
  - Node.js development
  - General CLI tools
- Tool configurations (git, editors, etc.)
- Generic NixOS VM base configurations
- Common home-manager modules

**Export Pattern**:
```nix
{
  devShells = {
    python = ...;
    rust = ...;
    node = ...;
  };

  nixosConfigurations = {
    generic-vm-headless-x86_64 = ...;
    generic-vm-headless-aarch64 = ...;
    generic-vm-gui-x86_64 = ...;
    generic-vm-gui-aarch64 = ...;
  };

  nixosModules = {
    base = ...;  # Platform-agnostic base
  };

  homeManagerModules = {
    base = ...;  # Platform-agnostic home config
  };
}
```

### Layer 2: Platform-Specific Adapters (Shareable)
**Location**: Future shared flake repository

**Contents**:
- WSL-specific tweaks (`wsl-home-base`, `wsl-base`)
- Darwin-specific tweaks (nix-darwin modules)
- Bare-metal Linux tweaks (if needed)

**Export Pattern**:
```nix
{
  nixosModules = {
    wsl-base = ...;        # NixOS-WSL specific
    darwin-base = ...;     # macOS specific
  };

  homeManagerModules = {
    wsl-home-base = ...;   # Any WSL distro
    darwin-home-base = ...; # macOS specific
  };
}
```

### Layer 3: Personal Configurations (Private - nixcfg)
**Location**: Current nixcfg repository

**Contents**:
- Tim's specific machines (thinky-nixos, pa161878-nixos, etc.)
- Personal secrets (SOPS encrypted)
- Personal preferences, aliases, custom scripts
- **Imports/composes from shared flake**

**Pattern**:
```nix
{
  inputs.shared-config.url = "github:timblaktu/shared-config";

  nixosConfigurations.thinky-nixos = {
    imports = [
      inputs.shared-config.nixosModules.base
      inputs.shared-config.nixosModules.wsl-base
      ./hosts/thinky-nixos  # Personal config
    ];
  };
}
```

### Layer 4: Colleague Configurations (Private - colleague repos)
**Location**: Colleagues' private repositories

**Contents**:
- Colleague-specific machines
- Their secrets and preferences
- **Imports/composes from shared flake**

**Onboarding Pattern**:
```bash
# Option 1: Bootstrap with pre-built image (RECOMMENDED for WSL)
wsl --import CompanyNixOS C:\WSL\CompanyNixOS company-nixos-wsl-2024.12.tar.gz
wsl -d CompanyNixOS

# Option 2: Initialize from template (for existing Nix installations)
nix flake init -t github:timblaktu/shared-config#wsl-home
# or
nix flake init -t github:timblaktu/shared-config#darwin
```

## Image Strategy (Hybrid Approach)

### Overview: Pre-built Images + Live Building

**Strategy**: Provide BOTH pre-built images for bootstrapping AND flake definitions for iteration

**Rationale**: Two distinct use cases require different approaches:
1. **Bootstrapping** (new colleague onboarding) → Pre-built images
2. **Iteration** (ongoing development) → Live building from flake

### Use Case A: Bootstrapping (Pre-built Images)

**When**: New colleague joining team, fresh machine setup

**Critical for WSL**: The `wsl --import` command REQUIRES a pre-built rootfs tarball - there's no way to bootstrap NixOS-WSL without an image.

**Image Formats to Provide**:
- **WSL tarball** (`.tar.gz`) - HIGHEST PRIORITY for Windows colleague onboarding
- QEMU image (`.qcow2`) - For VM testing/development
- ISO installer (`.iso`) - For bare-metal installation
- VirtualBox image (`.vdi`) - If team uses VirtualBox
- Docker image - For containerized workflows

**Distribution Strategy**:
- GitHub Releases (public) or company artifact storage (private)
- Monthly/quarterly release cycle
- Semantic versioning: `company-nixos-wsl-2024.12.tar.gz`
- Automated CI/CD builds on release tags

**Colleague Onboarding Flow (WSL Example)**:
```bash
# Day 1: New colleague with fresh Windows 11 laptop
# 1. Enable WSL2
wsl --install --no-distribution

# 2. Download pre-built company image
# From GitHub Releases or company storage

# 3. Import as WSL distribution
wsl --import CompanyNixOS C:\WSL\CompanyNixOS company-nixos-wsl-2024.12.tar.gz

# 4. Enter WSL
wsl -d CompanyNixOS

# 5. Clone company config
git clone github:company/nixcfg ~/.config/nixcfg

# 6. Apply latest configuration (updates beyond base image)
sudo nixos-rebuild switch --flake ~/.config/nixcfg#work-laptop

# Done! Running latest config from pre-built base
```

**Benefits**:
- ✅ Fast onboarding (download vs full system build)
- ✅ No chicken-and-egg problem (don't need Nix to get Nix)
- ✅ Works on locked-down corporate networks (if cached internally)
- ✅ Consistent base for all team members
- ✅ Can include company binary cache certificates pre-configured

**Trade-offs**:
- ⚠️ Images become stale (but colleagues update via `nixos-rebuild`)
- ⚠️ Large artifacts to distribute (500MB-2GB compressed)
- ⚠️ Need CI/CD infrastructure to build images

### Use Case B: Iteration (Live Building)

**When**: Already have Nix installed, testing/developing configurations

**Approach**: Build VMs/images directly from flake definitions

**Commands**:
```bash
# Build a VM for testing
nix build .#nixosConfigurations.test-vm.config.system.build.vm
./result/bin/run-*-vm

# Build specific image format on-demand
nix run github:nix-community/nixos-generators -- \
  --format qcow \
  --flake .#work-base
```

**Benefits**:
- ✅ Always up-to-date (built from latest flake)
- ✅ Nix-native reproducibility
- ✅ Easy to customize (override settings in flake)
- ✅ Binary cache speeds up builds
- ✅ No pre-built artifact distribution needed

**Trade-offs**:
- ⚠️ Slower first build (10-30 minutes depending on config)
- ⚠️ Requires Nix already installed (not suitable for bootstrapping)

### Image Matrix Building Pattern

**Goal**: Build the SAME configuration in MULTIPLE image formats from ONE definition

**Implementation**: Use `nixos-generators` or custom builders integrated into flake

**Flake Structure**:
```nix
{
  inputs.nixos-generators.url = "github:nix-community/nixos-generators";

  outputs = { self, nixpkgs, nixos-generators, ... }: {
    # The base configuration (single source of truth)
    nixosConfigurations.work-base = nixpkgs.lib.nixosSystem {
      # ... configuration ...
    };

    # Pre-built image outputs (for bootstrapping)
    packages.x86_64-linux = {
      # WSL tarball (CRITICAL for colleague onboarding)
      work-base-wsl = nixos-generators.nixosGenerate {
        format = "wsl-tarball";
        system = "x86_64-linux";
        modules = [ self.nixosConfigurations.work-base ];
      };

      # QEMU image for VM testing
      work-base-qcow2 = nixos-generators.nixosGenerate {
        format = "qcow";
        system = "x86_64-linux";
        modules = [ self.nixosConfigurations.work-base ];
      };

      # ISO for bare-metal installation
      work-base-iso = nixos-generators.nixosGenerate {
        format = "iso";
        system = "x86_64-linux";
        modules = [ self.nixosConfigurations.work-base ];
      };

      # Docker image for containers
      work-base-docker = nixos-generators.nixosGenerate {
        format = "docker";
        system = "x86_64-linux";
        modules = [ self.nixosConfigurations.work-base ];
      };
    };

    # Helper app to build all formats
    apps.x86_64-linux.build-all-images = {
      type = "app";
      program = toString (pkgs.writeShellScript "build-all" ''
        echo "Building all image formats..."
        nix build .#work-base-wsl
        nix build .#work-base-qcow2
        nix build .#work-base-iso
        nix build .#work-base-docker
        echo "All images built successfully!"
      '');
    };
  };
}
```

**CI/CD Integration**:
```yaml
# .github/workflows/release-images.yml
name: Build Release Images

on:
  release:
    types: [published]

jobs:
  build-images:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24

      - name: Build all image formats
        run: nix run .#build-all-images

      - name: Upload to release
        uses: actions/upload-release-asset@v1
        with:
          upload_url: ${{ github.event.release.upload_url }}
          asset_path: ./result/*.tar.gz
          asset_name: company-nixos-wsl-${{ github.event.release.tag_name }}.tar.gz
```

### Image/VM Variants to Provide

| Configuration | Architecture | Format | Primary Use Case | Priority |
|--------------|--------------|--------|------------------|----------|
| `work-base-wsl` | x86_64 | `.tar.gz` | **WSL colleague onboarding** | 🔴 CRITICAL |
| `work-base-qcow2` | x86_64 | `.qcow2` | VM testing on Linux/WSL | 🟡 High |
| `work-base-qcow2-aarch64` | aarch64 | `.qcow2` | VM testing on M-series Macs | 🟡 High |
| `work-base-iso` | x86_64 | `.iso` | Bare-metal installation | 🟢 Medium |
| `work-base-docker` | x86_64 | Docker | Container workflows | 🟢 Medium |

**Priority Explanation**:
- 🔴 **CRITICAL**: WSL tarball is required for Windows colleague onboarding - no alternative bootstrapping method
- 🟡 **High**: VM images enable testing/development workflows across platforms
- 🟢 **Medium**: ISO/Docker useful but not essential for initial colleague onboarding

### Platform-Specific Runtime Environments

**Linux (bare-metal)**:
- **Native execution**: Best for production deployments
- **VMs**: QEMU with KVM acceleration (excellent performance)
- **Containers**: Docker, Podman native

**Windows 11 + WSL2**:
- **Native execution**: Via imported WSL tarball (preferred method)
- **VMs**: QEMU within WSL2 (nested virtualization)
  - Requires Hyper-V enabled
  - WSLg provides display for GUI VMs
- **Containers**: Docker Desktop with WSL2 backend

**macOS Darwin**:
- **Native execution**: nix-darwin (when working) or home-manager only
- **VMs**: QEMU with Hypervisor.framework
  - Native aarch64 VMs on M-series (fast)
  - Emulated x86_64 VMs on M-series (slow but compatible)
  - UTM provides nice GUI wrapper
- **Containers**: Docker Desktop for Mac

## CI/CD Integration

### Requirements
- Dev shells must work **headless** (no GUI dependencies)
- Support GitHub Actions runners:
  - `ubuntu-latest` (x86_64-linux)
  - `macos-latest` (x86_64-darwin)
  - `macos-13` or newer (aarch64-darwin for Apple Silicon)
- Deterministic builds
- Cacheable via Nix binary caches

### Constraints
- ❌ **No VMs in CI** - Too heavy, slow startup, resource-intensive
- ✅ **Only dev shells in CI** - Fast, lightweight, cacheable

### Example CI Workflow
```yaml
name: Multi-platform CI
on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - run: nix flake check
      - run: nix develop --command pytest
```

## Testing Strategy

### For nixcfg (Personal Config)
1. **Local Testing**: Build and switch to configs on actual machines
2. **VM Testing**: Build VMs locally and smoke test
3. **Template Testing**: `nix flake init` tests in clean directories
4. **CI Testing**: `nix flake check` on GitHub Actions

### For Shared Flake (Future)
1. **Unit Tests**: Individual module tests via `nix flake check`
2. **Integration Tests**: Build all VM variants
3. **Template Tests**: Automated template initialization tests
4. **Cross-Platform CI**: Test dev shells on Linux, macOS (both arches)
5. **Colleague Testing**: Real-world usage by colleagues with feedback loop

### Multi-Architecture Testing Challenges
- Tim has x86_64 machines and WSL
- Testing aarch64 darwin requires:
  - GitHub Actions macOS runners (M-series), OR
  - Cross-compilation + QEMU emulation (slow), OR
  - Colleague with M3/M4 Mac for real testing

## Extraction Planning

### Phase 1: Identify Shareable Components (NEXT)

**Candidates for extraction**:
- ✅ `flake-modules/dev-shells.nix` - Generic dev shells
- ✅ `home/common/*.nix` - Platform-agnostic home modules (git, zsh, tmux, nixvim)
- ✅ `home/common/wsl-home-base.nix` - WSL home-manager adapter
- ✅ `hosts/common/wsl-base.nix` - WSL NixOS adapter
- ✅ Templates (`templates/wsl-nixos`, `templates/wsl-home`, `templates/darwin`)
- 🤔 `modules/base.nix` - Generic NixOS base (needs review for secrets/personal bits)
- 🤔 `home/modules/base.nix` - Generic home-manager base (needs review)

**Must stay in nixcfg**:
- ❌ Host-specific configs (`hosts/thinky-nixos`, etc.)
- ❌ Secrets (`secrets/`)
- ❌ Personal scripts with hardcoded paths
- ❌ Tim-specific preferences

### Phase 2: Design Shared Flake Structure (TODO)

```
shared-config/
├── flake.nix                 # Main entry point
├── modules/
│   ├── nixos/
│   │   ├── base.nix          # Platform-agnostic NixOS base
│   │   ├── wsl.nix           # WSL-specific module
│   │   └── darwin.nix        # Darwin-specific module
│   └── home-manager/
│       ├── base.nix          # Platform-agnostic home base
│       ├── wsl.nix           # WSL home tweaks
│       └── darwin.nix        # Darwin home tweaks
├── dev-shells/
│   ├── python.nix
│   ├── rust.nix
│   └── default.nix
├── vms/
│   ├── headless-x86_64.nix
│   ├── headless-aarch64.nix
│   ├── gui-x86_64.nix
│   └── gui-aarch64.nix
├── templates/
│   ├── wsl-nixos/
│   ├── wsl-home/
│   ├── darwin/
│   └── bare-metal/
└── docs/
    ├── README.md
    ├── PLATFORMS.md
    └── USAGE.md
```

### Phase 3: Migration Strategy (TODO)

1. **Create shared-config repo** (empty, public)
2. **Extract one component at a time** (start with dev-shells)
3. **Update nixcfg to consume shared flake** as input
4. **Test that nixcfg still works** after each extraction
5. **Iterate until all shareable components extracted**
6. **Document usage for colleagues**

## Next Steps

### Immediate (Phase 2: Documentation)
1. ✅ Create this document (CROSS-PLATFORM-STRATEGY.md)
2. 🔜 Update ARCHITECTURE.md with platform matrix section
3. 🔜 Fix naming inconsistencies in existing docs (`wsl-base` → `wsl-home-base`)
4. 🔜 Fix darwin template architecture hardcoding bug
5. 🔜 Merge `refactor/consolidate-wsl-config` to main

### Short-term (Phase 3: VM Configurations)
1. Design generic NixOS VM configurations (headless variants first)
2. Test VM building on Linux (x86_64)
3. Test VM building on WSL2
4. Document VM usage patterns
5. Add VM configurations to flake outputs

### Medium-term (Phase 4: Extraction Planning)
1. Audit modules for personal vs shareable separation
2. Design shared flake structure
3. Plan migration path (keep nixcfg working)
4. Set up shared-config repository

### Long-term (Phase 5: Colleague Onboarding)
1. Extract shareable components to shared-config
2. Update templates to reference shared-config
3. Write colleague onboarding documentation
4. Real-world testing with colleagues
5. Iteration based on feedback

## Related Documents

- `ARCHITECTURE.md` - Overall architecture analysis
- `CONSOLIDATION-PLAN.md` - WSL consolidation (completed)
- `CONSOLIDATION-VALIDATION-REPORT.md` - WSL consolidation review
- `SHARED-MODULES.md` - Shared module patterns
- `TESTING.md` - Testing strategies
