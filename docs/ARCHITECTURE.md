# NixOS Configuration Architecture Analysis

**Date**: 2025-12-12
**Purpose**: Architectural overview and base layer extraction strategy for sharing with colleagues

## Executive Summary

This is a **mature, well-organized Nix configuration** with excellent modularity foundations:

- **~22,000 lines of Nix code** across 99 files
- **Flake-parts modular architecture** (recently migrated from 19KB monolithic flake)
- **5 NixOS hosts** (4 WSL2, 1 ARM SBC) + 1 Darwin host
- **6 home-manager configurations** (standalone approach for fast iteration)
- **38% of codebase (~8,300 LOC) is shareable** with minimal modification
- **Only 5.6% duplication** - minimal waste

### Key Finding

The repository already has excellent modularity. Main opportunities:
1. **Extracting platform-agnostic components** for sharing
2. **Consolidating WSL-specific patterns** to reduce duplication
3. **Creating reusable base layer** for WSL2 and Darwin colleagues
4. **Enabling image matrix building** to deploy same config across multiple formats (WSL, AMI, ISO, VM, Docker)

---

## Table of Contents

1. [Repository Structure](#repository-structure)
2. [Architecture Patterns](#architecture-patterns)
3. [Platform Support Matrix](#platform-support-matrix)
4. [Modularity Assessment](#modularity-assessment)
5. [Base Layer Strategy](#base-layer-strategy)
6. [Image Matrix Building Pattern](#image-matrix-building-pattern)
7. [Improvement Opportunities](#improvement-opportunities)
8. [Action Plan](#action-plan)

---

## Repository Structure

### Top-Level Organization

```
nixcfg/
├── flake.nix                    # 90-line entry point using flake-parts
├── flake-modules/               # 9 modular components (post-migration)
│   ├── nixos-configurations.nix # NixOS system definitions
│   ├── home-configurations.nix  # Home Manager standalone configs
│   ├── darwin-configurations.nix# macOS system definitions
│   └── [5 more modules]
├── hosts/                       # Host-specific configurations
│   ├── common/                  # Shared NixOS config
│   ├── thinky-nixos/           # Primary WSL dev machine
│   ├── pa161878-nixos/         # Work WSL instance with CUDA
│   ├── mbp/                    # Intel MacBook Pro (NixOS)
│   ├── potato/                 # ARM SBC for Private CA
│   └── macbook-air/            # macOS Darwin config
├── home/                        # Home Manager configurations
│   ├── modules/                 # Structured modules (5,246 LOC)
│   │   ├── base.nix            # Core home-manager module (500 LOC)
│   │   ├── claude-code.nix     # AI assistant integration (710 LOC)
│   │   └── files/              # Drop-in file management (427 LOC)
│   └── common/                  # Shared home configs (12 modules)
│       ├── git.nix             # Git + GitHub CLI (216 LOC)
│       ├── zsh.nix, tmux.nix, nixvim.nix
│       ├── development.nix     # Dev tools (488 LOC)
│       └── [8 more modules]
├── modules/                     # Custom NixOS modules (16 files)
│   ├── base.nix                # Parameterized NixOS base (388 LOC)
│   ├── wsl-common.nix          # WSL module with options (143 LOC)
│   └── nixos/                  # NixOS-specific modules
│       ├── sops-nix.nix, wsl-cuda.nix
│       └── github-auth.nix, ssh-key-automation.nix
├── overlays/                    # Package overlays
├── pkgs/                        # Custom packages
├── secrets/                     # SOPS-encrypted secrets
└── claude-runtime/             # Claude Code multi-account state
```

### Quantitative Metrics

| Metric | Count | Details |
|--------|-------|---------|
| **Total Nix files** | 99 | Across entire repo |
| **Total lines of Nix code** | ~22,000 | Production code |
| **NixOS hosts** | 5 active | 4 WSL2, 1 ARM64 |
| **Darwin hosts** | 1 | macOS Apple Silicon |
| **Home Manager configs** | 6 | All standalone mode |
| **Shell scripts** | 114 | In home/files/bin/ |
| **Custom NixOS modules** | 16 | In modules/ |
| **Custom Home modules** | 13 | In home/modules/ |
| **Shareable code** | ~8,300 LOC | 38% of codebase |
| **Duplication** | ~1,230 LOC | 5.6% waste |

---

## Architecture Patterns

### 1. Standalone Home Manager Approach

**Strategy**: All home-manager configurations are deployed independently from NixOS system configuration.

**Benefits** (documented in `flake-modules/home-configurations.nix`):
- ✅ Fast iteration on user environment changes
- ✅ Clear separation of system vs user concerns
- ✅ Error isolation between system and user environments
- ✅ User autonomy (no root required)

### 2. Parameterized Module Pattern

All major modules use options-based configuration with runtime validation.

**Example**: `modules/wsl-common.nix` (143 LOC)
```nix
options.wslCommon = {
  enable = mkEnableOption "WSL common configuration";
  hostname = mkOption { type = types.str; };
  defaultUser = mkOption { type = types.str; };
  # ... 9 more options
};

config = mkIf cfg.enable {
  # Configuration based on options

  assertions = [
    {
      assertion = cfg.hostname != "";
      message = "wslCommon.hostname must not be empty";
    }
    # ... 5 more assertions
  ];
};
```

**Quality Indicators**:
- Type safety with `lib.types`
- Default values with `mkDefault`
- Runtime validation with `assertions`
- Clear option descriptions

### 3. Flake-Parts Modular Structure

Recent migration from 19KB monolithic `flake.nix` to 90-line entry point + 9 focused modules:

```nix
# flake.nix
{
  inputs = { flake-parts.url = "github:hercules-ci/flake-parts"; };
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      ./flake-modules/systems.nix
      ./flake-modules/overlays.nix
      ./flake-modules/packages.nix
      ./flake-modules/nixos-configurations.nix
      ./flake-modules/darwin-configurations.nix
      ./flake-modules/home-configurations.nix
      ./flake-modules/dev-shells.nix
      ./flake-modules/tests.nix
      ./flake-modules/github-actions.nix
    ];
  };
}
```

**Benefits**:
- Clear separation of concerns
- Easy to find and modify
- Better git diff readability
- Reduced risk of breaking changes

### 4. Conditional Module Loading

**Pattern**: Feature flags control which modules are loaded.

**Example**: `home/modules/base.nix`
```nix
options.homeBase = {
  enableGit = mkEnableOption "Git configuration" // { default = true; };
  enableTmux = mkEnableOption "Tmux configuration" // { default = true; };
  enableNeovim = mkEnableOption "Neovim configuration" // { default = true; };
  enableDevelopment = mkEnableOption "Development tools" // { default = false; };
  enableClaudeCode = mkEnableOption "Claude Code integration" // { default = false; };
  # ... more flags
};

config = {
  imports = []
    ++ (lib.optional cfg.enableGit ../common/git.nix)
    ++ (lib.optional cfg.enableTmux ../common/tmux.nix)
    ++ (lib.optional cfg.enableClaudeCode ./claude-code.nix);
    # ... more conditional imports
};
```

**Benefits**:
- Minimal surface area for minimal configs
- Easy to enable/disable features
- Clear dependencies

---

## Platform Support Matrix

This section documents cross-platform support for nixcfg, enabling sharing configurations with colleagues across different operating systems and deployment modes.

**Related**: See `CROSS-PLATFORM-STRATEGY.md` for detailed platform strategy and implementation plan.

### Supported Platforms

| Host Platform | CPU Arch | Native nix develop | NixOS VM | Primary Use Case | Current Status |
|--------------|----------|-------------------|-----------|------------------|----------------|
| **Bare-metal Linux** | x86_64 | ✅ Excellent | ✅ KVM/QEMU native | Server, workstation | ✅ Fully working |
| **Bare-metal Linux** | aarch64 | ✅ Excellent | ✅ KVM/QEMU native | ARM servers, SBCs | ✅ Fully working |
| **Windows 11 + WSL2** | x86_64 | ✅ Via WSL | ✅ QEMU in WSL | Developer workstations | ✅ Consolidated (2025-12-13) |
| **macOS Darwin** | aarch64 (M3-4) | ⚠️ Lagging | ✅ QEMU + Hypervisor.framework | Apple Silicon Macs | 🟡 Template exists |
| **macOS Darwin** | x86_64 (Intel) | ⚠️ Lagging | ✅ QEMU + Hypervisor.framework | Intel Macs | 🔜 Planned |

### Deployment Modes

**nix develop shells** - Best for:
- Fast iteration on projects
- CI/CD pipelines (GitHub Actions, GitLab CI)
- Lightweight tooling needs
- Developer workstations with working Nix

**NixOS VMs** - Best for:
- Full system isolation and testing
- Darwin workarounds (when nix-darwin broken)
- Consistent test environments across platforms
- Reproducible builds at OS level

### WSL-Specific Modules

**Two distinct scenarios** with different module requirements:

1. **NixOS-WSL** (`nixosModules.wsl-base`)
   - Requires: Full NixOS-WSL distribution
   - Cannot work on vanilla Ubuntu/Debian/Alpine WSL
   - Provides: System-level WSL integration

2. **Home Manager on ANY WSL** (`homeManagerModules.wsl-home-base`)
   - Requires: ANY WSL distro + Nix + home-manager
   - Works on NixOS-WSL AND vanilla Ubuntu/Debian/Alpine WSL
   - Provides: User-level WSL configuration
   - **Critical for colleague sharing** - vanilla WSL is most common scenario

### Templates

Available templates for bootstrapping new configurations:

| Template | Target Platform | Module Type | Use Case |
|----------|----------------|-------------|----------|
| `wsl-nixos` | NixOS-WSL | nixosConfiguration | Full NixOS-WSL installation |
| `wsl-home` | Any WSL distro | homeConfiguration | home-manager on vanilla WSL |
| `darwin` | macOS | darwinConfiguration | nix-darwin + home-manager |

Usage:
```bash
nix flake init -t github:timblaktu/nixcfg#wsl-home
```

### Image Building Strategy (Planned)

**Hybrid approach** combining pre-built images for bootstrapping with live building for iteration:

**Pre-built Images** (for colleague onboarding):
- WSL tarball (`.tar.gz`) - CRITICAL priority for Windows onboarding
- QEMU image (`.qcow2`) - For VM testing/development
- ISO installer - For bare-metal installation

**Live Building** (for development):
- Build VMs directly from flake: `nix build .#nixosConfigurations.vm.config.system.build.vm`
- Use nixos-generators for custom formats: `nix run github:nix-community/nixos-generators`

See `CROSS-PLATFORM-STRATEGY.md` for detailed implementation plan.

---

## Modularity Assessment

### Strengths (Grade: A)

1. ✅ **Proper Module System Usage**
   - All modules use `options` and `config` pattern
   - Type-safe with `lib.types`
   - Runtime validation with assertions
   - Default values with `mkDefault`

2. ✅ **Shallow Dependency Tree**
   - Max depth: 3 levels
   - Average depth: 2 levels
   - No circular dependencies

3. ✅ **Clear Separation of Concerns**
   - System modules in `modules/`
   - Home modules in `home/modules/`
   - No cross-imports between system and home
   - Platform-specific clearly marked

4. ✅ **Loose Coupling**
   - Modules communicate via options
   - Not via direct imports
   - Optional dependencies via feature flags

### Dependency Graph

```
NixOS Host (e.g., thinky-nixos)
├── modules/base.nix (pure options, no imports)
├── modules/wsl-common.nix (pure options, no imports)
├── modules/wsl-tarball-checks.nix
└── modules/nixos/sops-nix.nix

Home Manager Config (e.g., tim@thinky-nixos)
└── home/modules/base.nix
    ├── home/common/git.nix
    ├── home/common/tmux.nix
    ├── home/common/nixvim.nix
    ├── home/modules/claude-code.nix
    │   └── claude-code/* (7 submodules)
    └── home/modules/files/default.nix
```

### Current Duplication Analysis

| Type | Instances | Estimated Waste | Priority |
|------|-----------|-----------------|----------|
| WSL host configs | 2 | ~100 LOC | **High** |
| WSL home configs | 2 | ~150 LOC | **High** |
| Claude wrappers | 3 | ~900 LOC | Medium |
| SSH keys | 3+ | ~30 LOC | Low |

**Total**: 1,230 LOC (5.6% of codebase)

---

## Base Layer Strategy

### Shareability Tiers

#### Tier 1: Universal (All Platforms)

**Home Manager Modules** (~3,000 LOC):
- `home/common/git.nix` (216 LOC) - Git + GitHub CLI
- `home/common/zsh.nix` - Zsh configuration
- `home/common/tmux.nix` - Terminal multiplexer
- `home/common/nixvim.nix` - Neovim configuration
- `home/modules/claude-code.nix` (710 LOC) - AI assistant integration
- `home/modules/files/default.nix` (427 LOC) - File management
- `home/modules/secrets-management.nix` - SOPS + Bitwarden
- `home/modules/github-auth.nix` - GitHub/GitLab authentication
- `home/common/aliases.nix` - Shell aliases
- `home/common/environment.nix` - Environment variables
- `home/common/shell-utils.nix` - Bash/zsh libraries

**Platform Coverage**: Linux, macOS, WSL2, standalone

#### Tier 2: WSL-Specific

**NixOS Modules** (~300 LOC):
- `modules/wsl-common.nix` (143 LOC) - ⭐ **High value**
  - 12 parameterized options
  - 6 runtime assertions
  - Ready for sharing as-is
- `modules/wsl-tarball-checks.nix` - WSL validation
- `modules/nixos/wsl-cuda.nix` - CUDA support
- `modules/nixos/wsl-storage-mount.nix` - Bare mount support

**Home Manager Modules** (~200 LOC):
- `home/modules/windows-terminal.nix` - Terminal settings management
- `home/modules/terminal-verification.nix` - Font/rendering verification
- `home/common/esp-idf.nix` - ESP32 development (FHS wrapper)
- `home/common/onedrive.nix` - OneDrive utilities

**Platform Coverage**: WSL2 only

#### Tier 3: NixOS-General

**NixOS Modules** (~1,500 LOC):
- `modules/base.nix` (388 LOC) - Parameterized system base
  - 28 configurable options
  - Container support
  - Binary cache optimization
  - Needs minor cleanup (remove "tim" hardcoding)
- `modules/nixos/sops-nix.nix` - Secrets management
- `modules/nixos/github-auth.nix` - GitHub authentication
- `modules/nixos/ssh-key-automation.nix` - SSH key management
- `modules/nixos/bitwarden-ssh-keys.nix` - Bitwarden integration

**Platform Coverage**: NixOS (all platforms)

#### Tier 4: Darwin

**Current State**: Minimal (56 LOC in `macbook-air/default.nix`)

**Opportunity**: Share Tier 1 home-manager modules + create darwin-base module

### Extraction Strategies

#### Option A: Multi-Repository (Recommended)

```
timblaktu/
├── nix-base-config/                    # NEW: Shareable base
│   ├── flake.nix                      # Export modules
│   ├── modules/
│   │   ├── nixos/
│   │   │   ├── base.nix
│   │   │   └── wsl-common.nix
│   │   └── home-manager/
│   │       ├── base.nix
│   │       ├── git.nix
│   │       ├── claude-code/
│   │       └── wsl-base.nix (NEW)
│   ├── templates/
│   │   ├── wsl-nixos/
│   │   └── darwin/
│   └── docs/
│       ├── README.md
│       ├── MODULES.md
│       └── EXAMPLES.md
│
└── nixcfg/                            # Current: Personal config
    ├── flake.nix                      # Uses nix-base-config as input
    ├── hosts/                         # Host-specific customizations
    └── home/                          # Personal home config
```

**Benefits**:
- Clear separation between shareable and personal
- Easy for colleagues to consume
- Independent versioning
- Community-friendly

#### Option B: Monorepo with Exports

Add exports to current `flake.nix`:

```nix
outputs = { ... }: {
  # Existing
  nixosConfigurations = { ... };
  homeConfigurations = { ... };

  # NEW: Exportable modules
  nixosModules = {
    base = import ./modules/base.nix;
    wsl-common = import ./modules/wsl-common.nix;
  };

  homeManagerModules = {
    base = import ./home/modules/base.nix;
    git = import ./home/common/git.nix;
    claude-code = import ./home/modules/claude-code.nix;
    # ...
  };

  templates = {
    wsl-nixos = {
      path = ./templates/wsl-host;
      description = "WSL NixOS host template";
    };
  };
};
```

**Colleague Usage**:
```nix
{
  inputs.timblaktu-nix.url = "github:timblaktu/nixcfg";

  outputs = { nixpkgs, timblaktu-nix, ... }: {
    nixosConfigurations.my-wsl = nixpkgs.lib.nixosSystem {
      modules = [
        timblaktu-nix.nixosModules.wsl-common
        {
          wslCommon = {
            hostname = "my-wsl";
            defaultUser = "myuser";
          };
        }
      ];
    };
  };
}
```

**Benefits**:
- Simpler to maintain (single repo)
- Immediate availability
- Less overhead

**Drawbacks**:
- Personal and shareable mixed
- Harder to manage separate lifecycles

### Recommendation

**Start with Option B** (monorepo exports) for rapid colleague onboarding, then **migrate to Option A** (multi-repo) when ready for broader community sharing.

---

## Image Matrix Building Pattern

### Overview: Multi-Format Deployment Architecture

**Core Principle**: Separate machine configuration from image format to enable building the same system for multiple deployment targets (AMI, ISO, QCOW2, raw disk images, etc.).

This pattern enables "matrix building" where a single machine configuration can be deployed across:
- AWS EC2 (AMI format)
- Local VMs (QCOW2, VirtualBox, VMware)
- Bare metal installation (ISO)
- Cloud-init images (various cloud providers)
- Container images
- WSL tarballs

### Layered Module Composition

The key is structuring configurations in composable layers:

```
┌─────────────────────────────────────┐
│     Image Format Layer              │  ← AMI, ISO, QCOW2, raw, WSL tarball, etc.
├─────────────────────────────────────┤
│     Hardware/Platform Layer         │  ← bare-metal drivers, VM guest tools, WSL shims
├─────────────────────────────────────┤
│     Machine Role Layer              │  ← your actual config (services, users, packages)
└─────────────────────────────────────┘
```

**Example of the pattern**:
```nix
# roles/workstation.nix - Machine role (reusable)
{ config, pkgs, ... }: {
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [ git vim tmux ];
  users.users.tim = { ... };
}

# formats/ami-tweaks.nix - AWS-specific adjustments
{ config, lib, ... }: {
  # Only included when building AMI
  services.amazon-ssm-agent.enable = lib.mkDefault true;
  ec2.hvm = true;
}

# Final composition in flake.nix
nixosConfigurations.workstation-bare-metal = {
  modules = [ ./roles/workstation.nix ./hardware/thinkpad.nix ];
};

packages.x86_64-linux.workstation-ami = nixos-generators.nixosGenerate {
  modules = [ ./roles/workstation.nix ./formats/ami-tweaks.nix ];
  format = "amazon";
};
```

### Method 1: Using nixos-generators (Recommended)

**nixos-generators** is the canonical community tool for this exact use case.

**Integration Example**:
```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }: {
    # Reusable machine module (the core configuration)
    nixosModules.workstation = ./roles/workstation.nix;

    # Bare metal configuration
    nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.workstation
        ./hardware/my-laptop.nix  # Hardware-specific only
      ];
    };

    # Generate various image formats from the SAME base config
    packages.x86_64-linux = {
      workstation-ami = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "amazon";
        modules = [ self.nixosModules.workstation ];
      };

      workstation-vm = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ self.nixosModules.workstation ];
      };

      workstation-iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "iso";
        modules = [ self.nixosModules.workstation ];
      };

      workstation-raw = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "raw-efi";
        modules = [ self.nixosModules.workstation ];
      };

      workstation-wsl = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "wsl";
        modules = [ self.nixosModules.workstation ];
      };
    };
  };
}
```

**Supported Formats** (nixos-generators):
- `amazon` - AWS AMI
- `qcow` - QEMU/KVM
- `virtualbox` - VirtualBox OVA
- `vmware` - VMware VMDK
- `iso` - Installation ISO
- `raw-efi` - Raw disk image with EFI
- `wsl` - WSL tarball
- `docker` - Docker image
- `lxc` - LXC container
- `install-iso` - Installer ISO
- And many more...

### Method 2: Using config.system.build Directly

For more control or custom formats, use NixOS's built-in module system:

```nix
{
  nixosConfigurations.base-machine = nixpkgs.lib.nixosSystem {
    modules = [
      ./roles/workstation.nix
      ({ config, pkgs, modulesPath, ... }: {
        imports = [
          # Import format-specific modules as needed
          "${modulesPath}/virtualisation/amazon-image.nix"
          # OR "${modulesPath}/virtualisation/qemu-vm.nix"
          # OR "${modulesPath}/installer/cd-dvd/iso-image.nix"
        ];
      })
    ];
  };
}

# Access format-specific outputs:
# - config.system.build.toplevel      → root filesystem closure
# - config.system.build.amazonImage   → AMI-specific output
# - config.system.build.qcow          → QCOW2 image
# - config.system.build.isoImage      → ISO image
```

### Recommended Module Structure for Matrix Building

Reorganize modules to maximize reusability across formats:

```
modules/
├── roles/                    # What the machine DOES (100% reusable)
│   ├── workstation.nix      # Desktop/dev workstation role
│   ├── server.nix           # Server role
│   ├── build-machine.nix    # CI/CD builder
│   └── dev-machine.nix      # Development environment
├── profiles/                 # Common feature sets (90% reusable)
│   ├── desktop.nix          # GUI applications
│   ├── headless.nix         # No GUI
│   ├── hardened.nix         # Security-focused
│   └── minimal.nix          # Minimal footprint
├── hardware/                 # Physical hardware (NOT reusable across formats)
│   ├── thinkpad-x1.nix
│   ├── dell-precision.nix
│   └── raspberry-pi.nix
└── formats/                  # Image format customizations (format-specific)
    ├── ami-tweaks.nix       # AWS-specific (EC2 metadata, SSM agent)
    ├── vm-test.nix          # Test VM settings (memory, disk size)
    ├── bare-metal.nix       # Real hardware settings
    ├── wsl-tweaks.nix       # WSL-specific (interop, systemd shims)
    └── iso-installer.nix    # ISO-specific (installer UI, partitioning)
```

### Best Practices for Matrix-Compatible Modules

#### 1. Keep Hardware-Specific Config Isolated

**DO**:
```nix
# roles/workstation.nix (reusable)
{ config, lib, pkgs, ... }: {
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [ git vim ];
}

# hardware/my-laptop.nix (hardware-specific only)
{ config, lib, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true;
}
```

**DON'T**:
```nix
# roles/workstation.nix (BAD - mixed concerns)
{ config, lib, pkgs, ... }: {
  services.openssh.enable = true;
  boot.loader.systemd-boot.enable = true;  # ← Hardware-specific!
  fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };  # ← Hardware-specific!
}
```

#### 2. Use lib.mkDefault for Overridable Defaults

Allows image formats to override filesystem layout, boot config, etc.:

```nix
{ config, lib, ... }: {
  # Can be overridden by format-specific modules
  fileSystems."/" = lib.mkDefault {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  boot.loader.grub.enable = lib.mkDefault true;
  services.openssh.passwordAuthentication = lib.mkDefault false;
}
```

#### 3. Conditionally Include Platform-Specific Features

Use feature flags or capability detection:

```nix
{ config, lib, pkgs, ... }: {
  # Only enable on AWS
  services.amazon-ssm-agent.enable = lib.mkDefault (config.ec2.hvm or false);

  # Only enable on WSL
  wsl.enable = lib.mkDefault (config.wsl.enable or false);

  # Conditional packages based on desktop profile
  environment.systemPackages = with pkgs;
    (lib.optionals config.services.xserver.enable [ firefox chromium ]);
}
```

#### 4. Use specialArgs or _module.args for Context

Pass deployment context when needed:

```nix
nixos-generators.nixosGenerate {
  format = "amazon";
  modules = [ ./roles/workstation.nix ];
  specialArgs = {
    deploymentType = "cloud";
    provider = "aws";
  };
}

# In module:
{ deploymentType, provider, ... }: {
  services.cloud-init.enable = lib.mkDefault (deploymentType == "cloud");
}
```

### Testing with NixOS VM Tests

VM tests can import the same modules to ensure consistency:

```nix
checks.x86_64-linux.workstation-test = nixpkgs.lib.nixos.runTest {
  name = "workstation-integration";
  nodes.machine = { config, pkgs, ... }: {
    imports = [ self.nixosModules.workstation ];

    # Test-specific overrides
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
  };

  testScript = ''
    machine.wait_for_unit("default.target")
    machine.succeed("git --version")
    machine.succeed("ssh -V")
  '';
};
```

### Current Repository Application

**Applicable to this repository**:

1. **WSL configurations** could be generated as tarballs:
   ```nix
   packages.x86_64-linux.thinky-wsl-tarball = nixos-generators.nixosGenerate {
     format = "wsl";
     modules = [ ./hosts/thinky-nixos ];
   };
   ```

2. **Extract common workstation role** from existing hosts:
   ```nix
   # New: modules/roles/dev-workstation.nix
   # Extracted from thinky-nixos and pa161878-nixos

   # Then reuse across formats:
   - Bare metal laptop
   - WSL instances
   - Cloud dev environments (EC2, GCP)
   - Local VMs for testing
   ```

3. **Create test ISOs** for bare metal validation:
   ```nix
   packages.x86_64-linux.thinky-iso = nixos-generators.nixosGenerate {
     format = "install-iso";
     modules = [
       ./hosts/thinky-nixos
       ./formats/iso-installer.nix
     ];
   };
   ```

### Advantages for This Repository

1. **Colleague Sharing**: Share workstation role, colleagues choose their deployment format
2. **Testing**: Build ISOs or VMs to test config changes before deploying to WSL
3. **Portability**: Move from WSL → bare metal → cloud without rewriting config
4. **CI/CD**: Build and test multiple formats in parallel
5. **Disaster Recovery**: Generate recovery ISOs from current configuration

### Example: Multi-Format Matrix Build

```nix
# Single role definition
nixosModules.devWorkstation = ./modules/roles/dev-workstation.nix;

# Matrix of outputs (all from same base config)
packages.x86_64-linux = {
  # For colleagues on WSL
  dev-wsl = nixosGenerate { format = "wsl"; modules = [ self.nixosModules.devWorkstation ]; };

  # For cloud development
  dev-ami = nixosGenerate { format = "amazon"; modules = [ self.nixosModules.devWorkstation ]; };

  # For local testing
  dev-vm = nixosGenerate { format = "qcow"; modules = [ self.nixosModules.devWorkstation ]; };

  # For bare metal installation
  dev-iso = nixosGenerate { format = "iso"; modules = [ self.nixosModules.devWorkstation ]; };

  # For containers
  dev-docker = nixosGenerate { format = "docker"; modules = [ self.nixosModules.devWorkstation ]; };
};
```

**Build command**:
```bash
# Build all formats in parallel
nix build \
  .#dev-wsl \
  .#dev-ami \
  .#dev-vm \
  .#dev-iso \
  .#dev-docker \
  --print-build-logs
```

### References

- **nixos-generators**: https://github.com/nix-community/nixos-generators
- **NixOS manual - Building Images**: https://nixos.org/manual/nixos/stable/index.html#sec-building-image
- **Modules guide**: https://nixos.org/manual/nixos/stable/index.html#sec-writing-modules

---

## Improvement Opportunities

### High-Priority (Quick Wins)

#### 1. Extract Common WSL Host Configuration

**Impact**: High | **Effort**: Low | **LOC Saved**: ~100

Create `hosts/common/wsl-base.nix`:

```nix
{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    ../../modules/base.nix
    ../../modules/wsl-common.nix
    ../../modules/wsl-tarball-checks.nix
    ../../modules/nixos/sops-nix.nix
    inputs.sops-nix.nixosModules.sops
    inputs.nixos-wsl.nixosModules.default
  ];

  base = {
    userName = lib.mkDefault "tim";
    userGroups = lib.mkDefault [ "wheel" "dialout" ];
    nixMaxJobs = lib.mkDefault 8;
    nixCores = lib.mkDefault 0;
    enableBinaryCache = lib.mkDefault true;
    sshPasswordAuth = lib.mkDefault true;
    requireWheelPassword = lib.mkDefault false;
  };

  wslCommon = {
    enable = lib.mkDefault true;
    enableWindowsTools = lib.mkDefault true;
  };

  wsl = {
    enable = true;
    interop.register = true;
    usbip.enable = lib.mkDefault true;
  };
}
```

**Then simplify hosts**:
```nix
# hosts/thinky-nixos/default.nix
{ ... }: {
  imports = [ ../common/wsl-base.nix ];

  wslCommon.hostname = "thinky-nixos";
  wslCommon.sshPort = 2223;
  # Only unique config here
}
```

**Files to modify**:
- Create: `hosts/common/wsl-base.nix`
- Simplify: `hosts/thinky-nixos/default.nix:1-50`
- Simplify: `hosts/pa161878-nixos/default.nix:1-50`

#### 2. Extract Common WSL Home Configuration

**Impact**: High | **Effort**: Low | **LOC Saved**: ~150

Create `home/common/wsl-base.nix`:

```nix
{ config, lib, pkgs, ... }:
{
  homeBase = {
    enableDevelopment = lib.mkDefault true;
    enableEspIdf = lib.mkDefault true;
    enableOneDriveUtils = lib.mkDefault true;
    enableShellUtils = lib.mkDefault true;
    enableTerminal = lib.mkDefault true;

    environmentVariables = {
      WSL_DISTRO = lib.mkDefault "nixos";
      EDITOR = lib.mkDefault "nvim";
    };

    shellAliases = {
      explorer = lib.mkDefault "explorer.exe .";
      code = lib.mkDefault "code.exe";
      code-insiders = lib.mkDefault "code-insiders.exe";
    };
  };

  targets.wsl = {
    enable = true;
    windowsTools = {
      enablePowerShell = lib.mkDefault true;
      enableCmd = lib.mkDefault false;
      enableWslPath = lib.mkDefault true;
    };
  };

  home.packages = with pkgs; [ wslu ];
}
```

**Files to modify**:
- Create: `home/common/wsl-base.nix`
- Simplify: `flake-modules/home-configurations.nix:50-80` (tim@thinky-nixos)
- Simplify: `flake-modules/home-configurations.nix:100-130` (tim@pa161878-nixos)

#### 3. Unify Claude Code Wrapper Function

**Impact**: Medium | **Effort**: Low | **LOC Saved**: ~900

Extract shared wrapper function in `home/common/development.nix`:

```nix
mkClaudeWrapper = { account, displayName }:
  pkgs.writeShellApplication {
    name = if account == "default" then "claude" else "claude${account}";
    text = ''
      ACCOUNT="${account}"
      CONFIG_DIR="${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-''${ACCOUNT}"
      # ... shared logic here
    '';
    runtimeInputs = with pkgs; [ procps coreutils claude-code ];
  };

# Use for all three:
home.packages = [
  (mkClaudeWrapper { account = "default"; displayName = "Claude Default"; })
  (mkClaudeWrapper { account = "max"; displayName = "Claude Max"; })
  (mkClaudeWrapper { account = "pro"; displayName = "Claude Pro"; })
];
```

**Files to modify**:
- `home/common/development.nix:200-400` (consolidate wrappers)

#### 4. Centralize SSH Keys

**Impact**: Low | **Effort**: Minimal | **LOC Saved**: ~30

```nix
# hosts/common/ssh-keys.nix
{
  timblaktu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP58REN5jOx+Lxs6slx2aepF/fuO+0eSbBXrUhijhVZu timblaktu@gmail.com";
}

# Use in hosts:
wslCommon.authorizedKeys = [ (import ../common/ssh-keys.nix).timblaktu ];
```

**Files to modify**:
- Create: `hosts/common/ssh-keys.nix` (rename from ssh-keys-example.nix)
- Update: `hosts/thinky-nixos/default.nix:30`
- Update: `hosts/pa161878-nixos/default.nix:30`

### Medium-Priority (Worthwhile)

#### 5. Create Shareable Base Flake

**Impact**: High (enables colleague sharing) | **Effort**: Medium

Add to current `flake.nix` or create `nix-base-config`:

```nix
outputs = { ... }: {
  nixosModules = {
    base = import ./modules/base.nix;
    wsl-common = import ./modules/wsl-common.nix;
    wsl-base = import ./hosts/common/wsl-base.nix; # After creating in step 1
  };

  homeManagerModules = {
    base = import ./home/modules/base.nix;
    wsl-home-base = import ./home/common/wsl-home-base.nix; # After creating in step 2
    git = import ./home/common/git.nix;
    zsh = import ./home/common/zsh.nix;
    tmux = import ./home/common/tmux.nix;
    nixvim = import ./home/common/nixvim.nix;
    claude-code = import ./home/modules/claude-code.nix;
    files = import ./home/modules/files/default.nix;
  };

  templates = {
    wsl-nixos = {
      path = ./templates/wsl-host;
      description = "Minimal WSL NixOS host";
    };
    darwin = {
      path = ./templates/darwin-host;
      description = "Minimal Darwin host";
    };
  };
};
```

#### 6. Add Module Documentation

**Impact**: Medium (improves usability) | **Effort**: Medium

Generate option documentation:

```bash
# For each module
nix-build '<nixpkgs/nixos>' -A config.system.build.manual.optionsJSON \
  -I nixos-config=./modules/base.nix

# Create docs/MODULES.md with:
# - Module purpose
# - Available options with types and defaults
# - Usage examples
# - Platform compatibility
```

#### 7. Create Templates

**Impact**: High (colleague onboarding) | **Effort**: Medium

**Template 1**: Minimal WSL NixOS host
```
templates/wsl-host/
├── flake.nix
├── configuration.nix
├── hardware-configuration.nix (empty)
└── README.md
```

**Template 2**: Minimal Darwin host
```
templates/darwin-host/
├── flake.nix
├── configuration.nix
└── README.md
```

#### 8. Enable Image Matrix Building

**Impact**: High (multi-platform deployment) | **Effort**: Medium

Add nixos-generators integration and refactor for multi-format support:

**Steps**:
1. Add nixos-generators to flake inputs
2. Extract common roles from existing hosts (e.g., dev-workstation.nix from thinky-nixos)
3. Reorganize modules/ to separate roles/, profiles/, hardware/, and formats/
4. Add matrix build outputs to flake.nix

**Example outputs**:
```nix
packages.x86_64-linux = {
  thinky-wsl = nixosGenerate { format = "wsl"; modules = [ ./roles/dev-workstation.nix ]; };
  thinky-iso = nixosGenerate { format = "iso"; modules = [ ./roles/dev-workstation.nix ]; };
  thinky-vm = nixosGenerate { format = "qcow"; modules = [ ./roles/dev-workstation.nix ]; };
  thinky-ami = nixosGenerate { format = "amazon"; modules = [ ./roles/dev-workstation.nix ]; };
};
```

**Benefits**:
- Test configs in VMs before deploying to WSL
- Generate recovery ISOs from current configuration
- Deploy to cloud environments (AWS, GCP, Azure)
- Share config with colleagues who use different platforms

**Files to modify**:
- Add to `flake.nix`: nixos-generators input
- Create: `modules/roles/dev-workstation.nix` (extract from hosts/thinky-nixos)
- Create: `modules/formats/` directory with format-specific tweaks
- Update: `flake-modules/packages.nix` to add matrix build outputs

---

## Action Plan

### Phase 1: Consolidate (Week 1)

**Goal**: Eliminate duplication in personal config

- [ ] Create `hosts/common/wsl-base.nix` (Step 1)
- [ ] Create `home/common/wsl-home-base.nix` (Step 2)
- [ ] Simplify `thinky-nixos` and `pa161878-nixos` hosts
- [ ] Simplify home configurations
- [ ] Test with `nix flake check` and manual switch
- [ ] Commit changes

**Expected Result**: ~250 LOC reduction, cleaner host configs

### Phase 2: Prepare for Sharing (Week 2-3)

**Goal**: Make modules shareable

- [ ] Add flake outputs for modules (Step 5)
- [ ] Generalize `modules/base.nix` (remove hardcoded "tim")
- [ ] Create module documentation (Step 6)
- [ ] Create WSL and Darwin templates (Step 7)
- [ ] Test templates on clean system
- [ ] Commit changes

**Expected Result**: Colleagues can use `inputs.timblaktu-nix.nixosModules.*`

### Phase 3: Colleague Onboarding (Week 4)

**Goal**: Enable colleagues to use base config

- [ ] Share flake URL with colleagues
- [ ] Provide example flake.nix using modules
- [ ] Document customization points
- [ ] Create troubleshooting guide
- [ ] Gather feedback

**Expected Result**: 2-3 colleagues successfully using base config

### Phase 4: Extract to Separate Repo (Month 2-3)

**Goal**: Community-ready base layer

- [ ] Create `timblaktu/nix-base-config` repository
- [ ] Copy universal modules (Tier 1 + Tier 2)
- [ ] Comprehensive README and docs
- [ ] CI/CD for validation
- [ ] Update personal nixcfg to consume nix-base-config
- [ ] Announce to community

**Expected Result**: Shareable, reusable Nix configuration library

---

## Special Modules of Interest

### Claude Code Integration (710 LOC)

**Location**: `home/modules/claude-code.nix` + 7 submodules

**Features**:
- Multi-account support (max, pro, default)
- MCP server integration (Context7, Sequential Thinking, mcp-nixos)
- Configuration coalescence (V2.0)
- Custom statusline with powerline styles
- Hook system, sub-agents, slash commands
- Memory management

**Shareability**: ⭐⭐⭐⭐⭐ (100% platform-agnostic, high community value)

**Recommendation**: Extract as standalone flake for community

### Git Configuration (216 LOC)

**Location**: `home/common/git.nix`

**Features**:
- Delta syntax-aware diff viewer
- Smart mergetool for Neovim
- Pre-commit hooks (nixpkgs-fmt, cargo fmt, flake check)
- GitHub CLI integration
- Credential helpers

**Shareability**: ⭐⭐⭐⭐⭐ (95% platform-agnostic)

### WSL Common Module (143 LOC)

**Location**: `modules/wsl-common.nix`

**Features**:
- 12 parameterized options
- 6 runtime assertions
- SSH configuration
- User/group management
- Windows tool aliases

**Shareability**: ⭐⭐⭐⭐⭐ (100% for WSL users, ready as-is)

### File Management System (427 LOC)

**Location**: `home/modules/files/default.nix`

**Features**:
- Auto-deploy scripts from `home/files/bin/`
- Auto-generate shell completions (bash + zsh)
- Library file management
- Exclusion system

**Shareability**: ⭐⭐⭐⭐⭐ (100% platform-agnostic)

---

## Best Practices Observed

### Module System

✅ **Proper options definition** with `lib.types`
✅ **Runtime assertions** for validation
✅ **Default values** with `mkDefault`
✅ **Conditional configuration** with `mkIf`, `lib.optional`

### Flake Architecture

✅ **Flake-parts modular structure** (9 focused modules)
✅ **Input follows** for dependency consistency
✅ **Standalone home-manager** for fast iteration
✅ **Clear separation** between system and user

### Documentation

✅ **Inline comments** explaining complex logic
✅ **Separate README files** for major components
✅ **Migration guides** preserved
✅ **Upstream contribution plans** documented

### Testing

✅ **Flake checks** for validation
✅ **Test infrastructure** in `tests/`
✅ **Pre-commit hooks** for formatting
✅ **Validation scripts** for configurations

### Security

✅ **SOPS** for secrets management
✅ **SSH key automation** with Bitwarden
✅ **No secrets in git**
✅ **Proper permissions** on sensitive files

---

## Appendix: File Reference

### Critical Configuration Files

| Purpose | File | LOC | Shareability |
|---------|------|-----|--------------|
| Flake entry | `flake.nix` | 90 | N/A |
| NixOS base | `modules/base.nix` | 388 | 85% |
| WSL common | `modules/wsl-common.nix` | 143 | 100% (WSL) |
| Home base | `home/modules/base.nix` | 500 | 90% |
| Claude Code | `home/modules/claude-code.nix` | 710 | 100% |
| Git config | `home/common/git.nix` | 216 | 95% |
| File mgmt | `home/modules/files/default.nix` | 427 | 100% |
| Development | `home/common/development.nix` | 488 | 90% |

### Example Hosts

| Host | Platform | File | LOC | Purpose |
|------|----------|------|-----|---------|
| thinky-nixos | WSL2 | `hosts/thinky-nixos/default.nix` | 141 | Primary dev |
| pa161878-nixos | WSL2 | `hosts/pa161878-nixos/default.nix` | 92 | Work + CUDA |
| macbook-air | Darwin | `hosts/macbook-air/default.nix` | 56 | macOS |
| potato | ARM64 | `hosts/potato/default.nix` | ~80 | Private CA |

### Key Documentation

- `README.md` - Main documentation
- `home/modules/claude-code/README.md` - Claude Code guide
- `home/modules/README-MCP.md` - MCP server troubleshooting
- `home/modules/claude-code/UPSTREAM-CONTRIBUTION-PLAN.md` - Contribution roadmap

---

## Success Metrics

### For Personal Config

- [ ] **Code reuse**: Target 50% reduction in LOC after base layer extraction
- [ ] **Maintainability**: Reduce duplication to <3%
- [ ] **Documentation**: 100% of shared modules documented with examples

### For Colleague Sharing

- [ ] **Adoption**: 3+ colleagues using base config within 1 month
- [ ] **Ease of use**: New WSL config from template in <1 hour
- [ ] **Feedback**: Positive feedback on module clarity and docs

### For Community

- [ ] **Open source**: Base layer published with comprehensive docs
- [ ] **Engagement**: 10+ stars on base config repository
- [ ] **Contributions**: At least 1 external contribution or issue report

---

**Document Version**: 1.1
**Last Updated**: 2025-12-12
**Changes in 1.1**: Added comprehensive "Image Matrix Building Pattern" section covering multi-format deployment architecture
**Maintenance**: Update this document when making significant architectural changes
