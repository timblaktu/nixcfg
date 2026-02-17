# nixcfg Test Suite

## Overview

This repository uses a layered test strategy with five tiers, all integrated
into `nix flake check`. Tests validate everything from Nix expression
evaluation through static analysis, module isolation, and full NixOS VM boots
with service verification. There are **86 checks** total.

## Test Tiers

| Tier | Prefix | Speed | What it proves | KVM? |
|------|--------|-------|----------------|------|
| T0 | `eval-*` | <1s | Nix expressions evaluate | No |
| T0.5 | `lint-*` | 5-30s | Code quality (format, lint, dead code) | No |
| T1 | `build-*` | min | Derivations build | No |
| T2 | `vm-*` (boot) | 2-3min | System boots to multi-user.target | Yes |
| T3 | `vm-*` (feature) | 3-5min | Services start, programs work | Yes |

**T0.5 note**: `lint-*` checks run source-level analysis tools. They require
a build to execute the tool, so they are skipped by `nix flake check --no-build`
but execute during full `nix flake check`.

## Quick Start

```bash
# Eval-only (fast, no builds, no KVM required)
nix flake check --no-build

# Run a specific check
nix build '.#checks.x86_64-linux.eval-thinky-nixos'

# Run a specific VM test (requires KVM)
nix build '.#checks.x86_64-linux.vm-boot-minimal' -L

# Run lint checks only
nix build '.#checks.x86_64-linux.lint-formatting'
nix build '.#checks.x86_64-linux.lint-statix'
nix build '.#checks.x86_64-linux.lint-deadnix'

# Run module isolation eval tests
nix build '.#checks.x86_64-linux.eval-hm-module-shell'
nix build '.#checks.x86_64-linux.eval-nixos-module-system-cli'

# Run module isolation VM test (all 8 HM modules in parallel)
nix build '.#checks.x86_64-linux.vm-hm-module-isolation' -L

# Run composition pair tests
nix build '.#checks.x86_64-linux.vm-hm-composition-pairs' -L

# Run full CLI stack integration test
nix build '.#checks.x86_64-linux.vm-full-cli-stack' -L

# Run everything (eval + lint + build + VM tests)
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
├── tests.nix                              # T0/T0.5/T1: eval, lint, build checks
└── vm-tests.nix                           # T2/T3: VM boot and feature tests
```

## Test Infrastructure

### Where checks are defined

All checks are registered in `checks.x86_64-linux.*` via two flake-parts modules:

- **`modules/flake-parts/tests.nix`** -- Eval tests (T0), lint checks (T0.5),
  build tests (T1), module isolation eval tests, and module integration tests.
  These run without KVM.
- **`modules/flake-parts/vm-tests.nix`** -- VM tests (T2/T3). Uses `mkVmTest`
  and `mkHmModuleTest` helpers plus `pkgs.testers.nixosTest`. Requires KVM.

### mkVmTest helper

`vm-tests.nix` provides a `mkVmTest` function that wraps `pkgs.testers.nixosTest`
with common defaults for NixOS-only tests:

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

### mkHmModuleTest helper

`vm-tests.nix` provides `mkHmModuleTest` for testing Home Manager modules
in VMs. It provides `system-default` + `home-manager` + `home-minimal`
automatically; the caller only specifies which HM modules to test and what
to assert:

```nix
mkHmModuleTest {
  name = "yazi";                                     # check name: vm-yazi
  hmModules = [ self.modules.homeManager.yazi ];     # HM modules to test
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("home-manager-tim.service")
    machine.succeed("su - tim -c 'yazi --version'")
  '';
}
```

Parameters:

- `name` -- Becomes `vm-${name}` in the checks attrset
- `hmModules` -- List of HM modules (from `self.modules.homeManager.*`)
- `testScript` -- Python test script
- `memory` -- VM memory in MB (default: 2048)
- `extraNixosModules` -- Additional NixOS modules (default: [])
- `hmConfig` -- Additional attrs merged into the HM user config (default: {})

### Module isolation eval helpers (tests.nix)

- `mkHmModuleEvalTest name module { extraImports?, extraConfig? }` --
  Proves a Home Manager module evaluates standalone with only `home-minimal`.
  Uses `home-manager.lib.homeManagerConfiguration` with test user settings.
- `mkNixosModuleEvalTest name module { extraConfig? }` --
  Proves a NixOS module evaluates standalone via `lib.nixosSystem`.

### Other helpers in tests.nix

- `mkEvalTest name hostName` -- Eval test for a NixOS configuration
- `mkHmEvalTest name configName` -- Eval test for a Home Manager configuration
- `mkModuleTest { name, description, hostName, attributes, checks }` --
  Module integration test with custom attribute checks

VM tests compose from **dendritic modules** (`self.modules.nixos.*`,
`self.modules.homeManager.*`) rather than importing full host configs.
This avoids WSL/hardware dependencies that cannot run in QEMU.

## Check Inventory (86 total)

### T0: Eval Tests

**NixOS configurations** (5):
`eval-thinky-nixos`, `eval-pa161878-nixos`, `eval-potato`,
`eval-nixos-wsl-minimal`, `eval-mbp`

**Home Manager configurations** (5, x86_64-linux only):
`eval-hm-thinky-nixos`, `eval-hm-pa161878-nixos`, `eval-hm-thinky-ubuntu`,
`eval-hm-mbp`, `eval-hm-nixvim-minimal`

Skipped: `tim@potato` (aarch64-linux), `tim@macbook-air` (aarch64-darwin)

**HM module isolation eval tests** (20):
Each proves a single HM module evaluates standalone with only `home-minimal`.
`eval-hm-module-shell`, `eval-hm-module-git`, `eval-hm-module-tmux`,
`eval-hm-module-neovim`, `eval-hm-module-development-tools`,
`eval-hm-module-yazi`, `eval-hm-module-shell-utils`,
`eval-hm-module-files`, `eval-hm-module-podman`,
`eval-hm-module-terminal`, `eval-hm-module-secrets-management`,
`eval-hm-module-claude-code`, `eval-hm-module-opencode`,
`eval-hm-module-github-auth`, `eval-hm-module-gitlab-auth`,
`eval-hm-module-git-auth-helpers`, `eval-hm-module-esp-idf`,
`eval-hm-module-windows-terminal`, `eval-hm-module-onedrive`,
`eval-hm-module-system-tools`

**NixOS module isolation eval tests** (6):
Each proves a NixOS module evaluates standalone.
`eval-nixos-module-system-minimal`, `eval-nixos-module-system-default`,
`eval-nixos-module-system-cli`, `eval-nixos-module-system-desktop`,
`eval-nixos-module-secrets-management`, `eval-nixos-module-wsl`

**Module integration** (9):
`module-base-integration`, `module-wsl-settings-integration`,
`ssh-service-configured`, `user-tim-configured`,
`config-snapshot-validation`, `cross-module-wsl-base`,
`cross-module-sops-base`, `cross-module-home-manager`,
`ssh-public-keys-registry`

**Build evaluation** (2, force toplevel derivation eval without building):
`build-thinky-nixos-dryrun`, `build-nixos-wsl-minimal-dryrun`

**Other eval tests** (10):
`flake-validation`, `validated-scripts-module`,
`unified-files-diagnostic-test`, `files-module-test`,
`hybrid-files-module-test`, `tmux-picker-syntax`,
`opencode-config-validation`, `opencode-json-syntax`,
`opencode-mcp-structure`, `regression-test`

### T0.5: Lint Checks (3)

- `lint-formatting` -- `nixpkgs-fmt --check` on all `.nix` files
- `lint-statix` -- `statix check` for Nix anti-patterns
- `lint-deadnix` -- `deadnix --no-lambda-pattern-names --no-underscore --fail`
  for dead code detection

### T1: Build Tests (7)

**Package builds** (6):
`build-marker-pdf`, `build-markitdown`, `build-tomd`,
`build-nixvim-anywhere`, `build-docling`, `build-termux-claude-scripts`

**CI** (1):
`github-actions`

### T2: VM Boot Tests (4)

- `vm-boot-minimal` -- Minimal NixOS boots, `nix --version` works
- `vm-system-type-default` -- User creation, locale, timezone, zsh
- `vm-system-type-cli` -- SSH daemon, dev tools, neovim, tmux
- `vm-system-type-desktop` -- GNOME, PipeWire, Bluetooth, CUPS, fonts

### T3: VM Feature Tests (15)

**Service and security tests**:
- `vm-ssh-management` -- Multi-node SSH key management pipeline
- `vm-sops-deployment` -- SOPS CLI encryption/decryption operations
- `vm-ssh-service` -- Multi-node SSH: key auth, password rejection
- `vm-user-config` -- User setup, groups, sudo, nix trusted-users
- `vm-sops-secrets` -- sops-nix decryption, permissions, service access

**Home Manager activation and shell**:
- `vm-hm-activation` -- Home Manager activates, generates configs
- `vm-shell-env` -- Zsh config, aliases, plugins, session variables

**Module-specific feature tests**:
- `vm-neovim` -- Config loading, treesitter, plugins, LSP, checkhealth
- `vm-tmux` -- Server lifecycle, plugins, sessions, helper scripts
- `vm-git-advanced` -- Delta, aliases, LFS, merge tools, hooks
- `vm-development-tools` -- Rust, Node, Python, Go, C/C++, Claude utils
- `vm-yazi` -- Config generation, custom init.lua

**Module isolation and composition** (dendritic pattern validation):
- `vm-hm-module-isolation` -- 8 HM modules each activated alone (parallel nodes)
- `vm-hm-composition-pairs` -- 4 module pairs testing integration points
- `vm-full-cli-stack` -- All 9 VM-safe HM modules + system-cli together

## Module Coverage Matrix

Each row is a module; columns show which test tiers cover it.

**NixOS system modules**:

| Module | T0 Eval | T0.5 Lint | T2 Boot | T3 Feature |
|--------|---------|-----------|---------|------------|
| system-minimal | isolation | src | boot | -- |
| system-default | isolation | src | boot | user-config |
| system-cli | isolation | src | boot | ssh-service |
| system-desktop | isolation | src | boot | desktop |
| secrets-mgmt | isolation | src | -- | sops-secrets |
| wsl | isolation | src | -- | (WSL only) |

**Home Manager modules**:

| Module | T0 Eval | T0 Isolation | T3 Feature | T3 Isolation | T3 Pairs | T3 Stack |
|--------|---------|-------------|------------|--------------|----------|----------|
| shell | config | standalone | shell-env | alone | +git,+tmux | full |
| git | config | standalone | git-adv | alone | +nvim,+shell | full |
| tmux | config | standalone | tmux | alone | +nvim,+shell | full |
| neovim | config | standalone | neovim | alone | +tmux,+git | full |
| dev-tools | config | standalone | dev-tools | alone | -- | full |
| yazi | config | standalone | yazi | alone | -- | full |
| shell-utils | config | standalone | -- | alone | -- | full |
| podman | config | standalone | -- | alone | -- | full |
| files | config | standalone | -- | -- | -- | -- |
| terminal | config | standalone | -- | -- | -- | -- |
| secrets-mgmt | config | standalone | -- | -- | -- | -- |
| claude-code | config | standalone | (API keys) | -- | -- | -- |
| opencode | config | standalone | (API keys) | -- | -- | -- |
| github-auth | config | standalone | (Bitwarden) | -- | -- | -- |
| gitlab-auth | config | standalone | (Bitwarden) | -- | -- | -- |
| git-auth-hlp | config | standalone | (Bitwarden) | -- | -- | -- |
| esp-idf | config | standalone | (hardware) | -- | -- | -- |
| windows-term | config | standalone | (WSL only) | -- | -- | -- |
| onedrive | config | standalone | (WSL only) | -- | -- | -- |
| system-tools | config | standalone | (bootstrap) | -- | -- | -- |

**Key**: `config` = host config eval, `standalone` = module isolation eval,
`alone` = single-module VM, `full` = full CLI stack test.
Parenthesized entries explain why VM testing is not applicable.

## Adding a New Test

### New eval test

Add to `modules/flake-parts/tests.nix`:

```nix
my-new-eval-test = mkEvalTest "my-host" "my-host";
```

### New module isolation eval test

Add to `modules/flake-parts/tests.nix`:

```nix
# HM module — proves it evaluates with only home-minimal
eval-hm-module-my-module = mkHmModuleEvalTest "my-module"
  self.modules.homeManager.my-module
  { };

# NixOS module — proves it evaluates standalone
eval-nixos-module-my-module = mkNixosModuleEvalTest "my-module"
  self.modules.nixos.my-module
  {
    extraConfig = {
      # Add any required options here
    };
  };
```

### New HM module VM test (using mkHmModuleTest)

Add to `modules/flake-parts/vm-tests.nix`:

```nix
vm-my-module = mkHmModuleTest {
  name = "my-module";
  hmModules = [ self.modules.homeManager.my-module ];
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("home-manager-tim.service")
    machine.succeed("su - tim -c 'my-command --version'")
    machine.succeed("test -f /home/tim/.config/my-module/config")
  '';
};
```

### New NixOS-only VM test

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

### New HM VM test (manual, for complex setups)

For tests needing custom NixOS modules or non-standard HM configuration,
bypass `mkHmModuleTest` and use `pkgs.testers.nixosTest` directly:

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

## Test Design Patterns

### Module isolation (dendritic validation)

The dendritic pattern promises that modules compose freely and work
independently. Two complementary approaches validate this:

1. **Eval isolation** (`eval-hm-module-*`, `eval-nixos-module-*`):
   Proves each module evaluates without depending on other modules.
   Fast (<1s each), runs during `--no-build`.

2. **VM isolation** (`vm-hm-module-isolation`):
   Proves each VM-safe module activates alone in a real NixOS VM.
   Uses parallel nodes (8 VMs boot simultaneously via `start_all()`).

### Composition testing

Module pairs with known integration points are tested together:

| Pair | Integration point |
|------|-------------------|
| neovim + tmux | vim-tmux-navigator keybindings |
| git + neovim | smart-nvimdiff merge/diff tool |
| git + shell | Git aliases in zsh |
| shell + tmux | $TMUX env var, zsh inside tmux |

The `vm-full-cli-stack` test combines all 9 VM-safe HM modules with
`system-cli` to prove the full composition is conflict-free.

### Multi-node tests

Use the `nodes` parameter of `mkVmTest` for tests requiring multiple
machines (e.g., SSH client/server):

```nix
mkVmTest {
  name = "my-multi-node";
  nodes = {
    server = { ... }: { imports = [ ... ]; };
    client = { ... }: { imports = [ ... ]; };
  };
  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")
  '';
};
```

## Prerequisites

**Eval tests (T0)**: Nix with flakes enabled. Any platform.

**Lint checks (T0.5)**: Nix with flakes enabled. Requires build of lint tools.

**Build tests (T1)**: Same as T0. Builds may take minutes.

**VM tests (T2/T3)**:
- KVM support: `ls /dev/kvm`
- User in `kvm` group: `id -nG | grep kvm`
- 2GB+ RAM available per VM test (3GB for full-cli-stack)

## Constraints

- **WSL features** cannot be VM-tested (no Windows host in QEMU)
- **Darwin configs** cannot be VM-tested (need macOS)
- **aarch64-linux** VM tests need cross-compilation or native runner
- `nix flake check --no-build` stays fast (eval-only, no KVM needed)
- Modules requiring external services (API keys, Bitwarden) cannot
  be VM-tested at runtime

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
