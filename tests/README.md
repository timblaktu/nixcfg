# nixcfg Test Suite

## Overview

This repository uses a layered test strategy with four tiers, all integrated
into `nix flake check`. Tests validate everything from Nix expression
evaluation through full NixOS VM boots with service verification.

## Test Tiers

| Tier | Prefix | Speed | What it proves | KVM? |
|------|--------|-------|----------------|------|
| T0 | `eval-*` | <1s | Nix expressions evaluate | No |
| T1 | `build-*` | min | Derivations build | No |
| T2 | `vm-*` (boot) | 2-3min | System boots to multi-user.target | Yes |
| T3 | `vm-*` (feature) | 3-5min | Services start, programs work | Yes |

## Quick Start

```bash
# Eval-only (fast, no builds, no KVM required)
nix flake check --no-build

# Run a specific check
nix build '.#checks.x86_64-linux.eval-thinky-nixos'

# Run a specific VM test (requires KVM)
nix build '.#checks.x86_64-linux.vm-boot-minimal' -L

# Run everything (eval + build + VM tests)
nix flake check
```

## File Layout

```
tests/
├── README.md                              # This file
├── sops-simple.nix                        # SOPS encryption/decryption tests
├── ssh-auth.nix                           # SSH key format validation
├── sops-nix.nix                           # SOPS-NiX integration tests
├── fixtures/
│   └── sops/                              # Pre-generated SOPS test fixtures
│       ├── README.md                      # How to regenerate fixtures
│       ├── test-age-key.txt               # Static age keypair (test only)
│       └── test-secrets.yaml              # SOPS-encrypted test secrets
└── integration/
    ├── ssh-management.nix                 # Multi-node SSH key management VM test
    ├── sops-deployment.nix                # SOPS secret deployment VM test
    └── bitwarden-mock.nix                 # Mock Bitwarden service for testing

modules/flake-parts/
├── tests.nix                              # T0/T1 checks: eval, build, module integration
└── vm-tests.nix                           # T2/T3 checks: VM boot and feature tests
```

## Test Infrastructure

### Where checks are defined

All checks are registered in `checks.x86_64-linux.*` via two flake-parts modules:

- **`modules/flake-parts/tests.nix`** -- Eval tests (T0), build tests (T1), and
  module integration tests. These run without KVM.
- **`modules/flake-parts/vm-tests.nix`** -- VM tests (T2/T3). Uses `mkVmTest`
  helper and `pkgs.testers.nixosTest`. Requires KVM.

### mkVmTest helper

`vm-tests.nix` provides a `mkVmTest` function that wraps `pkgs.testers.nixosTest`
with common defaults:

```nix
mkVmTest {
  name = "boot-minimal";                          # check name: vm-boot-minimal
  description = "Minimal NixOS boots";
  modules = [ self.modules.nixos.system-minimal ]; # dendritic modules
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
  '';
}
```

Parameters:

- `name` -- Becomes `vm-${name}` in the checks attrset
- `modules` -- NixOS modules (from `self.modules.nixos.*`)
- `nodes` -- Full nodes attrset (overrides single-node shorthand)
- `testScript` -- Python test script (nixos-test-driver syntax)
- `memory` -- VM memory in MB (default: 1024)
- `extraConfig` -- Additional NixOS config merged into the machine node

VM tests compose from **dendritic modules** (`self.modules.nixos.*`,
`self.modules.homeManager.*`) rather than importing full host configs.
This avoids WSL/hardware dependencies that cannot run in QEMU.

### Helper functions in tests.nix

- `mkEvalTest name hostName` -- Eval test for a NixOS configuration
- `mkHmEvalTest name configName` -- Eval test for a Home Manager configuration
- `mkModuleTest { name, description, hostName, attributes, checks }` --
  Module integration test with custom attribute checks

## Check Inventory

### T0: Eval Tests

**NixOS configurations** (5):
`eval-thinky-nixos`, `eval-pa161878-nixos`, `eval-potato`,
`eval-nixos-wsl-minimal`, `eval-mbp`

**Home Manager configurations** (5, x86_64-linux only):
`eval-hm-thinky-nixos`, `eval-hm-pa161878-nixos`, `eval-hm-thinky-ubuntu`,
`eval-hm-mbp`, `eval-hm-nixvim-minimal`

Skipped: `tim@potato` (aarch64-linux), `tim@macbook-air` (aarch64-darwin)

**Module integration**:
`module-base-integration`, `module-wsl-settings-integration`,
`ssh-service-configured`, `user-tim-configured`,
`config-snapshot-validation`, `cross-module-wsl-base`,
`cross-module-sops-base`, `cross-module-home-manager`,
`ssh-public-keys-registry`

**Build evaluation** (force toplevel derivation eval without building):
`build-thinky-nixos-dryrun`, `build-nixos-wsl-minimal-dryrun`

**Other eval tests**:
`flake-validation`, `validated-scripts-module`,
`unified-files-diagnostic-test`, `files-module-test`,
`hybrid-files-module-test`, `tmux-picker-syntax`,
`opencode-config-validation`, `opencode-json-syntax`,
`opencode-mcp-structure`, `regression-test`

### T1: Build Tests

**Package builds** (6):
`build-marker-pdf`, `build-markitdown`, `build-tomd`,
`build-nixvim-anywhere`, `build-docling`, `build-termux-claude-scripts`

### T2: VM Boot Tests

- `vm-boot-minimal` -- Minimal NixOS boots, `nix --version` works
- `vm-system-type-default` -- User creation, locale, timezone, zsh
- `vm-system-type-cli` -- SSH daemon, dev tools, neovim, tmux

### T3: VM Feature Tests

- `vm-ssh-management` -- Multi-node SSH key management pipeline
- `vm-sops-deployment` -- SOPS CLI encryption/decryption operations
- `vm-ssh-service` -- Multi-node SSH: key auth, password rejection
- `vm-user-config` -- User setup, groups, sudo, nix trusted-users
- `vm-hm-activation` -- Home Manager activates, generates configs
- `vm-shell-env` -- Zsh config, aliases, plugins, session variables
- `vm-sops-secrets` -- sops-nix decryption, permissions, service access

## Adding a New Test

### New eval test

Add to `modules/flake-parts/tests.nix`:

```nix
my-new-eval-test = mkEvalTest "my-host" "my-host";
```

### New VM test

Add to `modules/flake-parts/vm-tests.nix`:

```nix
vm-my-feature = mkVmTest {
  name = "my-feature";
  description = "Test that my-feature works in a VM";
  modules = [ self.modules.nixos.system-default ];
  extraConfig = {
    systemDefault.userName = "tim";
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("some-command")
  '';
};
```

For tests that need Home Manager:

```nix
vm-my-hm-feature = pkgs.testers.nixosTest {
  name = "vm-my-hm-feature";
  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      self.modules.nixos.system-default
      inputs.home-manager.nixosModules.home-manager
    ];
    systemDefault.userName = "tim";
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs; };
      users.tim = { ... }: {
        imports = [
          self.modules.homeManager.home-minimal
          self.modules.homeManager.my-feature
        ];
        homeMinimal = {
          username = "tim";
          homeDirectory = "/home/tim";
        };
        targets.genericLinux.enable = lib.mkForce false;
      };
    };
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("home-manager-tim.service")
    machine.succeed("su - tim -c 'my-command'")
  '';
};
```

### New package build test

Add to `modules/flake-parts/tests.nix`:

```nix
build-my-package = self'.packages.my-package;
```

Putting a package in `checks` makes `nix flake check` build it.

## Prerequisites

**Eval tests (T0)**: Nix with flakes enabled. Any platform.

**Build tests (T1)**: Same as T0. Builds may take minutes.

**VM tests (T2/T3)**:
- KVM support: `ls /dev/kvm`
- User in `kvm` group: `id -nG | grep kvm`
- 2GB+ RAM available per VM test

## Constraints

- **WSL features** cannot be VM-tested (no Windows host in QEMU)
- **Darwin configs** cannot be VM-tested (need macOS)
- **aarch64-linux** VM tests need cross-compilation or native runner
- `nix flake check --no-build` stays fast (eval-only, no KVM needed)

## Debugging

### Verbose output

```bash
nix build '.#checks.x86_64-linux.vm-boot-minimal' -L --show-trace
```

### Keep failed build artifacts

```bash
nix build '.#checks.x86_64-linux.vm-my-test' --keep-failed
ls /tmp/nix-build-*/
```

### View VM test build logs

```bash
nix log /nix/store/...-vm-test-vm-boot-minimal
```

### Interactive VM debugging

In your test script:

```python
machine.shell_interact()  # Drop to interactive shell
```

### Common failures

**"KVM not available"** -- Check `/dev/kvm` permissions:
```bash
sudo modprobe kvm-intel  # or kvm-amd
sudo usermod -a -G kvm $USER
# Re-login for group change to take effect
```

**VM test timeout** -- Increase memory or check for boot loops:
```nix
mkVmTest {
  memory = 2048;  # increase from default 1024
  # ...
};
```

**"Existing file would be clobbered"** (HM tests) -- Use `lib.mkForce` to
override conflicting options, or set `targets.genericLinux.enable = false`
for NixOS-integrated HM tests.
