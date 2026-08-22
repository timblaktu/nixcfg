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

# Run the Tier-0 eval-regression gate
nix build '.#checks.x86_64-linux.regression-test'

# Run a QEMU VM test (requires KVM)
nix build '.#checks.x86_64-linux.vm-boot-minimal' -L

# Run lint checks only
nix build '.#checks.x86_64-linux.lint-formatting'
nix build '.#checks.x86_64-linux.lint-statix'
nix build '.#checks.x86_64-linux.lint-deadnix'

# Run the consolidated module isolation eval gates
nix build '.#checks.x86_64-linux.eval-hm-modules'
nix build '.#checks.x86_64-linux.eval-nixos-modules'

# Run module isolation VM test (all 8 HM modules in parallel, nspawn)
nix build '.#checks.x86_64-linux.vm-hm-module-isolation' -L

# Run composition pair tests (nspawn)
nix build '.#checks.x86_64-linux.vm-hm-composition-pairs' -L

# Run the full compose-stack integration test (QEMU)
nix build '.#checks.x86_64-linux.vm-compose-stack' -L

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
    └── test-secrets/                      # SOPS fixtures (VM tests: modules/flake-parts/vm-tests.nix)

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

### mkHmContainerTest helper

`vm-tests.nix` provides `mkHmContainerTest` for testing Home Manager modules on
the fast **systemd-nspawn** backend (the nspawn analog of the former QEMU
`mkHmModuleTest`, removed in plan 054 P5c). It provides `system-default` +
`home-manager` + `home-minimal` automatically via the `hmNspawnNode` recipe -
which bakes in the R2 HM-on-nspawn config (`build-users-group = ""` + a
daemon-free `nix-store --load-db` of the HM closure) so full HM activation runs
on a read-only store with no KVM. The caller only specifies which HM modules to
test and what to assert:

```nix
mkHmContainerTest {
  name = "example";                                  # check name: vm-example
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
- `description` -- Human-readable description (default: derived from `name`)
- `hmModules` -- List of HM modules (from `self.modules.homeManager.*`)
- `testScript` -- Python test script (nixos-test-driver syntax)
- `extraNixosModules` -- Additional NixOS modules (default: [])
- `hmConfig` -- Additional attrs merged into the HM user config (default: {})

See [TESTING-NSPAWN.md](../docs/TESTING-NSPAWN.md) for the nspawn host
prerequisites (the `uid-range` system feature via `auto-allocate-uids`).

### Consolidated eval gates (tests.nix)

Plan 054 P5a replaced the former per-module/per-host eval helpers
(`mkHmModuleEvalTest`, `mkNixosModuleEvalTest`, `mkEvalTest`, `mkHmEvalTest`,
`mkModuleTest`) with a few **batched** gates:

- `regression-test` -- consolidated host + HM stateVersion/username regression gate
  (folds the former 12 standalone `eval-*` host/config evals).
- `eval-hm-modules` -- forces ALL HM modules to evaluate standalone (folds the
  former 20 `eval-hm-module-*`); via an inlined `forceHmModuleEval` over the
  module attrset.
- `eval-nixos-modules` -- forces ALL NixOS layer modules to evaluate standalone
  (folds the former 6 `eval-nixos-module-*`); via an inlined `forceNixosModuleEval`.

VM tests compose from **dendritic modules** (`self.modules.nixos.*`,
`self.modules.homeManager.*`) rather than importing full host configs.
This avoids WSL/hardware dependencies that cannot run in a test backend.

## Check Inventory (57 total, x86_64/aarch64 mirrored)

The authoritative live list is
`nix eval '.#checks.x86_64-linux' --apply builtins.attrNames`.

### Tier 0 - Eval-regression gates (12)

**Batched gates** (4): `regression-test`, `eval-hm-modules`, `eval-nixos-modules`,
`eval-wsl-settings-ssh-port`.

**Toplevel / tarball / image eval forcers** (8, renamed from `build-*-dryrun`):
`eval-thinky-nixos-toplevel`, `eval-nixos-wsl-minimal-toplevel`,
`eval-nixos-dev-team-toplevel`, `eval-thinky-nixos-tarball`,
`eval-nixos-wsl-dev-team-tarball`, `eval-images-dev-team`, `eval-images-ec2`,
`eval-images-graviton`.

### Lint (5)

`lint-formatting` (`nixpkgs-fmt --check`), `lint-statix`, `lint-deadnix`,
`lint-ps1-encoding`, `lint-version`.

### Module / integration / config checks (12)

`module-base-integration`, `module-binfmt-integration`, `files-module-test`,
`tmux-picker-syntax`, `user-configured`, `wsl-dev-team-setup-username-user`,
`opencode-json-syntax`, `opencode-mcp-structure`, and the `skill-injection-*`
prompt-injection guards (`awscli`, `glab`, `negative`, `pulumi`).

### Package / activation builds (8) + CI meta (1)

**Activation builds** (2): `activate-hm-nixvim-minimal`, `activate-hm-thinky-nixos`.
**Package builds** (6): `build-docling`, `build-marker-pdf`, `build-markitdown`,
`build-nixvim-anywhere`, `build-termux-claude-scripts`, `build-tomd`.
**CI meta** (1): `github-actions` (local `act` runner; not run in CI).

### Tier 1 - Behavioral VMTests (19)

Boot-independent tests run on the **systemd-nspawn** backend (fast, no KVM, run on
BOTH x86_64 and aarch64); boot/kernel/graphics/real-network/image tests stay on
**QEMU** (x86_64 KVM). See [../docs/TESTING-NSPAWN.md](../docs/TESTING-NSPAWN.md).

**nspawn** (11):
- `vm-nspawn-smoke` -- nspawn reference; system-cli userspace smoke
- `vm-system-type-default` -- user creation, locale, timezone, zsh
- `vm-sops-secrets` -- sops-nix decryption, permissions, service access
- `vm-hm-activation` -- Home Manager activates, generates configs
- `vm-shell-env` -- zsh config, aliases, plugins, session variables
- `vm-neovim` -- config loading, treesitter, plugins, LSP, checkhealth
- `vm-tmux` -- server lifecycle, plugins, sessions, helper scripts
- `vm-git-advanced` -- delta, aliases, merge tools, hooks
- `vm-development-tools` -- Rust, Node, Python, Go, Claude utils
- `vm-hm-module-isolation` -- each HM module activated alone (parallel nodes; folds the former `vm-yazi`)
- `vm-hm-composition-pairs` -- module pairs testing integration points

**QEMU** (8):
- `vm-boot-minimal` -- minimal NixOS boots, `nix --version` works
- `vm-system-type-cli` -- SSH daemon, dev tools, neovim, tmux
- `vm-system-type-desktop` -- GNOME, PipeWire, Bluetooth, CUPS, fonts
- `vm-ssh-service` -- multi-node SSH: key auth, password rejection
- `vm-user-config` -- user setup, groups, passwordless sudo escalation
- `vm-wsl-dev-team-layers` -- monitoring (`security.wrappers`) + `mss-clamp`
- `vm-dev-team-vm-smoketest` -- shipped dev-team image smoketest
- `vm-compose-stack` -- full HM stack over system-cli + real nixos-dev-team host module (nightly in CI)

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

### New host / config eval

Extend the batched `regression-test` gate in `modules/flake-parts/tests.nix` -
add the new config's `system.stateVersion` (or HM `home.username`) to its
inherited attrs. There is no per-host `mkEvalTest` anymore.

### New module isolation eval

Module isolation is batched: adding a module to `self.modules.homeManager.*` or
`self.modules.nixos.*` makes it automatically covered by `eval-hm-modules` /
`eval-nixos-modules` (they map over the whole module attrset). If a NixOS layer
needs extra options to evaluate standalone, add them to that gate's per-module
`extraConfig` in `tests.nix`. No new per-module check is needed.

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

The `vm-compose-stack` test combines all 9 VM-safe HM modules with both
`system-cli` and the real `nixos-dev-team` host module to prove the full
composition is conflict-free (QEMU; runs nightly in CI).

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
