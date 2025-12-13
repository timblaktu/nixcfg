# WSL Configuration Consolidation Plan

**Date**: 2025-12-12
**Branch**: `refactor/consolidate-wsl-config`
**Goal**: Implement ARCHITECTURE.md improvement opportunities (Phase 1: Consolidate)

## Executive Summary

This plan implements the high-priority consolidation improvements from ARCHITECTURE.md to:
- Reduce duplication from 1,230 LOC (5.6%) to <3%
- Prepare modules for colleague sharing
- Improve maintainability and clarity

**Expected Benefits**:
- ~280 LOC reduction (30 + 100 + 150)
- Cleaner host configurations
- Easier to share with colleagues
- Single source of truth for WSL defaults

## Platform Requirements

**CRITICAL**: This consolidation creates TWO distinct WSL module types with different platform requirements:

### 1. NixOS System Module: `hosts/common/wsl-base.nix`
**Platform**: NixOS-WSL distribution ONLY
**Module Type**: NixOS system configuration module
**Requirements**:
- Full NixOS-WSL distribution installed
- NixOS system configuration enabled
- Cannot be used on vanilla Ubuntu/Debian/Alpine WSL

**Provides**:
- System-level WSL integration (wsl.conf, systemd services)
- User and group management
- SSH daemon configuration with WSL-specific settings
- SOPS-nix secrets management
- NixOS-WSL module imports

**Use Cases**:
- thinky-nixos (NixOS-WSL host)
- pa161878-nixos (NixOS-WSL host)

### 2. Home Manager Module: `home/common/wsl-home-base.nix`
**Platform**: ANY WSL distribution + Nix + home-manager ✅
**Module Type**: Home Manager user configuration module
**Requirements**:
- ANY WSL distribution (NixOS-WSL, Ubuntu, Debian, Alpine, etc.)
- Nix package manager installed
- home-manager installed

**Provides**:
- User-level WSL tweaks (shell wrappers, environment variables)
- Windows Terminal settings management
- WSL utilities (wslu)
- Home Manager `targets.wsl` configuration

**Use Cases**:
- thinky-nixos (NixOS-WSL host) - home-manager config
- pa161878-nixos (NixOS-WSL host) - home-manager config
- **Colleague on vanilla Ubuntu WSL** - portable config! ✅
- Any other WSL distribution with Nix installed

### Package Duplication: wslu
The `wslu` package appears in BOTH modules intentionally:
- **System level** (`hosts/common/wsl-base.nix`): Provides system-wide access on NixOS-WSL
- **User level** (`home/common/wsl-home-base.nix`): Ensures availability on ANY WSL distro

This duplication is harmless on NixOS-WSL (Nix deduplicates automatically) and essential for portability to vanilla WSL distributions.

### Sharing Strategy
When sharing with colleagues:
- **If they use NixOS-WSL**: They can use both modules
- **If they use vanilla WSL** (Ubuntu, Debian, etc.): They can ONLY use `home/common/wsl-home-base.nix`
- Provide clear documentation about platform requirements

### Example: Colleague on Vanilla Ubuntu WSL
```nix
# ~/.config/home-manager/flake.nix (on Ubuntu WSL)
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcfg.url = "github:timblaktu/nixcfg";  # Your shared config repo
  };

  outputs = { nixpkgs, home-manager, nixcfg, ... }: {
    homeConfigurations."colleague@ubuntu-wsl" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      modules = [
        nixcfg.homeManagerModules.wsl-base  # ✅ Works on vanilla Ubuntu WSL!
        {
          homeBase = {
            username = "colleague";
            homeDirectory = "/home/colleague";
          };
        }
      ];
    };
  };
}
```

**Note**: The NixOS system module (`nixcfg.nixosModules.wsl-base`) would fail on vanilla Ubuntu WSL because it requires NixOS-WSL-specific features.

## Implementation Strategy

**Philosophy**: Small, testable, committable batches
- Each batch is independently valuable
- Each batch validates before committing
- Work can be paused/resumed at any batch boundary
- Reversible if issues discovered

## Batch Overview

| Batch | Task | LOC Saved | Risk | Validation |
|-------|------|-----------|------|------------|
| 1 | Centralize SSH keys | ~30 | Low | `nix flake check` |
| 2a | Create NixOS wsl-base | - | Low | `nix flake check` |
| 2b | Migrate thinky-nixos | ~50 | Medium | `nixos-rebuild build` |
| 2c | Migrate pa161878-nixos | ~50 | Medium | `nixos-rebuild build` |
| 3a | Create home wsl-base | - | Low | `nix flake check` |
| 3b | Migrate thinky home | ~75 | Medium | `home-manager build` |
| 3c | Migrate pa161878 home | ~75 | Medium | `home-manager build` |

---

## Batch 1: Centralize SSH Keys

**Goal**: Single source of truth for SSH authorized keys

### Current State (Duplication)
```nix
# hosts/thinky-nixos/default.nix:44-46
authorizedKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP58REN5jOx+Lxs6slx2aepF/fuO+0eSbBXrUhijhVZu timblaktu@gmail.com"
];

# hosts/pa161878-nixos/default.nix:45-47
authorizedKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP58REN5jOx+Lxs6slx2aepF/fuO+0eSbBXrUhijhVZu timblaktu@gmail.com"
];
```

### Target State
```nix
# NEW: hosts/common/ssh-keys.nix
{
  timblaktu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP58REN5jOx+Lxs6slx2aepF/fuO+0eSbBXrUhijhVZu timblaktu@gmail.com";
}

# hosts/thinky-nixos/default.nix
let
  sshKeys = import ../common/ssh-keys.nix;
in
{
  wslCommon.authorizedKeys = [ sshKeys.timblaktu ];
  # ...
}
```

### Steps
1. Create `hosts/common/ssh-keys.nix`
2. Update `hosts/thinky-nixos/default.nix` to use it
3. Update `hosts/pa161878-nixos/default.nix` to use it
4. Validate with `nix flake check`
5. Test SSH access to both hosts
6. Commit changes

### Validation
```bash
nix flake check
# Should pass

# Verify SSH keys in generated config
nix eval '.#nixosConfigurations.thinky-nixos.config.wslCommon.authorizedKeys' --json
nix eval '.#nixosConfigurations.pa161878-nixos.config.wslCommon.authorizedKeys' --json
# Both should show the same key
```

---

## Batch 2: Extract Common WSL Host Configuration

**Goal**: Create reusable NixOS base for WSL hosts

### Current State (Analysis)

**Common sections across thinky-nixos and pa161878-nixos:**
- Identical imports (except CUDA module on pa161878)
- Identical `nixpkgs.config.allowUnfree`
- Identical `base` module config (19-35)
- Identical `wslCommon` config (38-48, except hostname)
- Identical `wsl` config (51-57)
- Identical SSH config (64-67 / 89-92)
- Identical SOPS config (122-137 / 73-88)
- Identical `system.stateVersion` (140-141 / 90-92)

**Differences (host-specific):**
- thinky: ESP32 udev rules (94-116)
- thinky: Bare mount config (commented out, 58-86)
- pa161878: CUDA support (11, 59-61)

### Batch 2a: Create hosts/common/wsl-base.nix

**File**: `hosts/common/wsl-base.nix`

```nix
# Common WSL host configuration base
# Usage: Import this in WSL host configs to get standard WSL setup
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

  # Allow unfree packages by default
  nixpkgs.config.allowUnfree = lib.mkDefault true;

  # Standard base module configuration for WSL
  base = {
    userName = lib.mkDefault "tim";
    userGroups = lib.mkDefault [ "wheel" "dialout" ];
    enableClaudeCodeEnterprise = lib.mkDefault false;
    nixMaxJobs = lib.mkDefault 8;
    nixCores = lib.mkDefault 0;
    enableBinaryCache = lib.mkDefault true;
    cacheTimeout = lib.mkDefault 10;
    sshPasswordAuth = lib.mkDefault true;
    requireWheelPassword = lib.mkDefault false;
    additionalShellAliases = lib.mkDefault {
      esp32c5 = "esp-idf-shell";
      explorer = "explorer.exe .";
      code = "code.exe";
      code-insiders = "code-insiders.exe";
    };
  };

  # WSL-specific configuration
  wsl = {
    enable = true;
    interop.register = lib.mkDefault true;
    usbip.enable = lib.mkDefault true;
    usbip.autoAttach = lib.mkDefault [ "3-1" "3-2" ];
    usbip.snippetIpAddress = lib.mkDefault "localhost";
  };

  # SOPS-NiX configuration for secrets management
  sopsNix = {
    enable = lib.mkDefault true;
    hostKeyPath = lib.mkDefault "/etc/sops/age.key";
  };

  # System state version (override in host if needed)
  system.stateVersion = lib.mkDefault "24.11";
}
```

**Steps**:
1. Create the file
2. Validate with `nix flake check`
3. Commit

**Validation**:
```bash
nix flake check
# Should pass (new file doesn't break anything)
```

### Batch 2b: Migrate thinky-nixos to wsl-base

**Changes to** `hosts/thinky-nixos/default.nix`:

```nix
# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

let
  sshKeys = import ../common/ssh-keys.nix;
in
{
  imports = [
    ./hardware-config.nix
    ../common/wsl-base.nix  # NEW: Use common WSL base
  ];

  # Host-specific WSL common configuration
  wslCommon = {
    hostname = "thinky-nixos";
    defaultUser = "tim";
    sshPort = 2223;
    userGroups = [ "wheel" "dialout" ];
    authorizedKeys = [ sshKeys.timblaktu ];
  };

  # SSH service configuration
  services.openssh.ports = [ 2223 ];

  # USB device management for ESP32 development (HOST-SPECIFIC)
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "10-esp32-usb";
      destination = "/etc/udev/rules.d/10-esp32-usb.rules";
      text = ''
        # CP2102N USB to UART Bridge Controller - Device 1
        # Serial: a84d26d0ef5fef1186befc45d9b539e6
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="a84d26d0ef5fef1186befc45d9b539e6", SYMLINK+="ttyESP0", MODE="0666", GROUP="dialout"

        # CP2102N USB to UART Bridge Controller - Device 2
        # Serial: 4095a7a28d1af0119da88250ac170b28
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="4095a7a28d1af0119da88250ac170b28", SYMLINK+="ttyESP1", MODE="0666", GROUP="dialout"

        # Generic rule for all CP2102N devices (fallback)
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"

        # Also handle the usb-serial subsystem
        SUBSYSTEM=="usb-serial", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
      '';
    })
  ];

  # User environment managed by standalone Home Manager
  # Deploy with: home-manager switch --flake '.#tim@thinky-nixos'
}
```

**Steps**:
1. Edit `hosts/thinky-nixos/default.nix`
2. Format with `nixpkgs-fmt`
3. Validate with `nix flake check`
4. Build config with `nixos-rebuild build --flake '.#thinky-nixos'`
5. Compare generated config with original
6. Commit changes

**Validation**:
```bash
nix flake check
nixos-rebuild build --flake '.#thinky-nixos'
# Should succeed

# Verify configuration is equivalent
nix eval '.#nixosConfigurations.thinky-nixos.config.wslCommon' --json > /tmp/new.json
# Compare with old config manually
```

### Batch 2c: Migrate pa161878-nixos to wsl-base

**Changes to** `hosts/pa161878-nixos/default.nix`:

```nix
# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

let
  sshKeys = import ../common/ssh-keys.nix;
in
{
  imports = [
    ./hardware-config.nix
    ../common/wsl-base.nix  # NEW: Use common WSL base
    ../../modules/nixos/wsl-cuda.nix  # HOST-SPECIFIC: CUDA support
  ];

  # Host-specific WSL common configuration
  wslCommon = {
    hostname = "pa161878-nixos";
    defaultUser = "tim";
    sshPort = 2223;
    userGroups = [ "wheel" "dialout" ];
    authorizedKeys = [ sshKeys.timblaktu ];
  };

  # SSH service configuration
  services.openssh.ports = [ 2223 ];

  # WSL CUDA support - enables GPU passthrough for ML workloads (HOST-SPECIFIC)
  # GPU: NVIDIA RTX 2000 Ada (8GB VRAM) via WSL2 passthrough
  wslCuda.enable = true;

  # User environment managed by standalone Home Manager
  # Deploy with: home-manager switch --flake '.#tim@pa161878-nixos'
}
```

**Steps**:
1. Edit `hosts/pa161878-nixos/default.nix`
2. Format with `nixpkgs-fmt`
3. Validate with `nix flake check`
4. Build config with `nixos-rebuild build --flake '.#pa161878-nixos'`
5. Commit changes

**Validation**:
```bash
nix flake check
nixos-rebuild build --flake '.#pa161878-nixos'
# Should succeed
```

---

## Batch 3: Extract Common WSL Home Configuration

**Goal**: Create reusable home-manager base for WSL environments

### Current State (Analysis)

**Common sections in thinky-nixos and pa161878-nixos home configs:**
- Identical `allowUnfree` (82, 172)
- Identical `home/modules/base.nix` import (83, 173)
- Nearly identical `homeBase` config (85-102, 175-192)
  - username, homeDirectory
  - enable flags
  - environment variables
  - shell aliases
- Identical `home.packages` with `wslu` (104-106, 194-196)
- Identical `targets.wsl` config (133-141, 198-206)

**Differences:**
- pa161878 has explicit `secretsManagement.enable = true` (109)
- pa161878 has `githubAuth` config (115-131)
- pa161878 has `windowsTerminal` config (144-157)
- thinky only has `secretsManagement.rbw.email` (197)

### Batch 3a: Create home/common/wsl-base.nix

**File**: `home/common/wsl-base.nix`

```nix
# Common home-manager configuration for WSL environments
# Provides sensible defaults for WSL development setup
{ config, lib, pkgs, ... }:

{
  # Standard homeBase configuration for WSL
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
      esp32c5 = lib.mkDefault "esp-idf-shell";
    };
  };

  # WSL utilities
  home.packages = with pkgs; [
    wslu
  ];

  # WSL target configuration
  targets.wsl = {
    enable = true;
    windowsTools = {
      enablePowerShell = lib.mkDefault true;
      enableCmd = lib.mkDefault false;
      enableWslPath = lib.mkDefault true;
      wslPathPath = lib.mkDefault "/bin/wslpath";
    };
  };
}
```

**Steps**:
1. Create the file
2. Format with `nixpkgs-fmt`
3. Validate with `nix flake check`
4. Commit

**Validation**:
```bash
nix flake check
# Should pass
```

### Batch 3b: Migrate thinky-nixos home config to wsl-base

**Changes to** `flake-modules/home-configurations.nix` (lines 168-217):

```nix
"tim@thinky-nixos" = withSystem "x86_64-linux" ({ pkgs, ... }:
  inputs.home-manager-wsl.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      { nixpkgs.config.allowUnfree = true; }
      ../home/modules/base.nix
      ../home/common/wsl-base.nix  # NEW: Use common WSL base
      {
        homeBase = {
          username = "tim";
          homeDirectory = "/home/tim";
          # All other settings come from wsl-base.nix
        };
        secretsManagement.rbw.email = "timblaktu@gmail.com";
      }
    ];
    extraSpecialArgs = {
      inherit inputs;
      inherit (inputs) nixpkgs-stable;
      wslHostname = "thinky-nixos";
    };
  }
);
```

**Steps**:
1. Edit `flake-modules/home-configurations.nix`
2. Format with `nixpkgs-fmt`
3. Validate with `nix flake check`
4. Build with `nix build '.#homeConfigurations."tim@thinky-nixos".activationPackage'`
5. Test with `home-manager switch --flake '.#tim@thinky-nixos' --dry-run`
6. Commit changes

**Validation**:
```bash
nix flake check
nix build '.#homeConfigurations."tim@thinky-nixos".activationPackage'
home-manager switch --flake '.#tim@thinky-nixos' --dry-run
# All should succeed
```

### Batch 3c: Migrate pa161878-nixos home config to wsl-base

**Changes to** `flake-modules/home-configurations.nix` (lines 78-166):

```nix
"tim@pa161878-nixos" = withSystem "x86_64-linux" ({ pkgs, ... }:
  inputs.home-manager-wsl.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      { nixpkgs.config.allowUnfree = true; }
      ../home/modules/base.nix
      ../home/common/wsl-base.nix  # NEW: Use common WSL base
      {
        homeBase = {
          username = "tim";
          homeDirectory = "/home/tim";
          # All other settings come from wsl-base.nix
        };

        # Secrets management (HOST-SPECIFIC)
        secretsManagement = {
          enable = true;
          rbw.email = "timblaktu@gmail.com";
        };

        # GitHub and GitLab authentication (HOST-SPECIFIC)
        githubAuth = {
          enable = true;
          mode = "bitwarden";
          bitwarden = {
            item = "github.com";
            field = "PAT-timtam2026";
          };
          gitlab = {
            enable = true;
            host = "git.panasonic.aero";
            bitwarden = {
              item = "GitLab git.panasonic.aero";
              field = "lord (access token)";
            };
            glab.enable = true;
          };
        };

        # Windows Terminal settings management (HOST-SPECIFIC)
        windowsTerminal = {
          enable = true;
          font = {
            face = "CaskaydiaMono NFM, Noto Color Emoji";
            size = 12;
          };
          keybindings = [
            { id = "Terminal.CopyToClipboard"; keys = "ctrl+shift+c"; }
            { id = "Terminal.PasteFromClipboard"; keys = "ctrl+shift+v"; }
            { id = "Terminal.DuplicatePaneAuto"; keys = "alt+shift+d"; }
            { id = "Terminal.NextTab"; keys = "alt+ctrl+l"; }
            { id = "Terminal.PrevTab"; keys = "alt+ctrl+h"; }
          ];
        };
      }
    ];
    extraSpecialArgs = {
      inherit inputs;
      inherit (inputs) nixpkgs-stable;
      wslHostname = "pa161878-nixos";
    };
  }
);
```

**Steps**:
1. Edit `flake-modules/home-configurations.nix`
2. Format with `nixpkgs-fmt`
3. Validate with `nix flake check`
4. Build with `nix build '.#homeConfigurations."tim@pa161878-nixos".activationPackage'`
5. Test with `home-manager switch --flake '.#tim@pa161878-nixos' --dry-run`
6. Commit changes

**Validation**:
```bash
nix flake check
nix build '.#homeConfigurations."tim@pa161878-nixos".activationPackage'
home-manager switch --flake '.#tim@pa161878-nixos' --dry-run
# All should succeed
```

---

## Post-Consolidation Validation

After completing all batches, perform end-to-end validation:

### 1. Flake Check
```bash
nix flake check
# Should pass cleanly
```

### 2. Build All Configurations
```bash
# NixOS configs
nixos-rebuild build --flake '.#thinky-nixos'
nixos-rebuild build --flake '.#pa161878-nixos'

# Home configs
nix build '.#homeConfigurations."tim@thinky-nixos".activationPackage'
nix build '.#homeConfigurations."tim@pa161878-nixos".activationPackage'
```

### 3. Dry-Run Switches
```bash
# Test on actual machines (if accessible)
home-manager switch --flake '.#tim@thinky-nixos' --dry-run
home-manager switch --flake '.#tim@pa161878-nixos' --dry-run
```

### 4. Git Status
```bash
git status
# Should show:
# - hosts/common/ssh-keys.nix (new)
# - hosts/common/wsl-base.nix (new)
# - home/common/wsl-base.nix (new)
# - hosts/thinky-nixos/default.nix (modified)
# - hosts/pa161878-nixos/default.nix (modified)
# - flake-modules/home-configurations.nix (modified)
# - docs/CONSOLIDATION-PLAN.md (new)
# - CLAUDE.md (modified)
```

### 5. LOC Comparison
```bash
# Before (estimate from ARCHITECTURE.md):
# - WSL host duplication: ~100 LOC
# - WSL home duplication: ~150 LOC
# - SSH keys duplication: ~30 LOC
# Total waste: ~280 LOC

# After:
# - Created: 3 new files (~150 LOC total)
# - Removed: ~280 LOC of duplication
# Net reduction: ~130 LOC
# Maintenance win: Much cleaner, more maintainable code
```

---

## Success Criteria

- [ ] All batches completed and committed
- [ ] `nix flake check` passes
- [ ] All NixOS configurations build successfully
- [ ] All home configurations build successfully
- [ ] No functional changes (configurations behave identically)
- [ ] Code is cleaner and more maintainable
- [ ] Ready for Phase 2: Prepare for Sharing

---

## Next Steps (Future Work)

After consolidation is complete:

### Phase 2: Prepare for Sharing
1. Add flake outputs for modules (Option B from ARCHITECTURE.md)
2. Generalize `modules/base.nix` (remove hardcoded "tim")
3. Create module documentation
4. Create WSL and Darwin templates

### Deferred
- Unify Claude Code wrapper functions (~900 LOC saved)
  - More complex, lower priority
  - Can be done after colleague sharing is enabled
- Enable image matrix building
  - Add nixos-generators integration
  - Extract roles from existing hosts

---

**Document Version**: 1.0
**Last Updated**: 2025-12-12
**Status**: Ready for execution
