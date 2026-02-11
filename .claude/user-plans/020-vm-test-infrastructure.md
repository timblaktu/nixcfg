# Plan 020: VM Test Infrastructure & Comprehensive Test Coverage

**Branch**: `refactor/dendritic-pattern`
**Worktree**: `/home/tim/src/nixcfg-dendritic`
**Status**: COMPLETE
**Created**: 2026-02-10

---

## Context

After the Plan 019 dendritic migration, the repository has 22 feature modules, 5 NixOS hosts, 7 HM configs, 1 Darwin config, and 6 custom packages. The existing test suite (`modules/flake-parts/tests.nix`) has 30+ checks, but they are almost entirely **eval-time attribute checks** — they verify that Nix expressions evaluate without error but never boot a system, start a service, or activate Home Manager.

Additionally:
- `pa161878-nixos` NixOS config has **no eval test** at all
- **Zero** Home Manager config eval tests exist
- The `test-integration` check is a **stub** (prints "AVAILABLE", runs no VMs)
- The `regression-test` check is a **stub** (prints a message, tests nothing)
- Existing VM tests in `tests/integration/` are **not wired** into `nix flake check`
- The 22 feature modules have **no runtime validation**
- Custom packages have **no build tests**
- KVM **is available** on the current system (`/dev/kvm` writable)

**Goal**: Build a layered test infrastructure using the nixpkgs VM test driver (`pkgs.nixosTest`) that can validate NixOS configurations, service startup, Home Manager activation, and feature module behavior in lightweight QEMU VMs — without needing access to physical target hosts.

---

## Testing Taxonomy

| Tier | Type | Speed | What it proves | Current |
|------|------|-------|----------------|---------|
| T0 | Eval | ~1s | Nix expressions evaluate | 30+ checks (gaps) |
| T1 | Build | ~minutes | Derivations build | 0 checks |
| T2 | VM boot | ~2-3min | System boots to multi-user.target | 0 checks |
| T3 | VM feature | ~3-5min | Services start, programs work | 0 checks (2 unwired) |

**Convention**: All checks live in `checks.x86_64-linux.*`. Prefix indicates tier:
- `eval-*` → T0 (run with `--no-build`)
- `build-*` → T1
- `vm-*` → T2/T3 (require KVM)

---

## Constraints

- **WSL features** cannot be VM-tested (no Windows host in QEMU)
- **Darwin configs** cannot be VM-tested (need macOS)
- **aarch64-linux** (potato) VM tests need cross-compilation or native runner
- VM tests should compose from **dendritic modules**, not import full host configs (avoids WSL/hardware deps)
- `nix flake check --no-build` must remain fast (eval-only path unchanged)

---

## Session Workflow (MANDATORY per task)

Every task follows this protocol — no exceptions:

1. **Update plan**: Set task status to `TASK:IN_PROGRESS`
2. **Execute**: Make changes, validate as specified in task DoD
3. **Commit**: `git add` + `git commit` with descriptive message
4. **Validate**: Run `nix flake check --no-build` (always) + task-specific checks
5. **Update plan**: Set task status to `TASK:COMPLETE`
6. **Commit plan**: `git add` + `git commit` the plan status update
7. **STOP**: Provide `/next-task`-compatible continuation prompt and end session

User will issue `/next-task` in a fresh session to continue.
If validation fails at step 4, fix in-place and re-commit — do NOT leave broken state.

---

## Task Progress

| Task | Phase | Status | Validation | Description |
|------|-------|--------|------------|-------------|
| 1.1 | Gap Analysis | `TASK:COMPLETE` | N/A (analysis) | Gap matrix — done inline below |
| 1.2 | Eval Coverage | `TASK:COMPLETE` | `nix flake check --no-build` | Add eval tests: pa161878 + 5 HM configs |
| 1.3 | Fix Stubs | `TASK:COMPLETE` | `nix flake check --no-build` | Fix 4 stub checks to test real things |
| 2.1 | Wire Existing | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.vm-ssh-management' -L` | Wire ssh-management.nix into checks |
| 2.2 | Wire Existing | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.vm-sops-deployment' -L` | Wire sops-deployment.nix into checks (2026-02-10) |
| 3.1 | VM Scaffold | `TASK:COMPLETE` | `nix flake check --no-build` | Create vm-tests.nix + mkVmTest helper (2026-02-10) |
| 3.2 | VM Boot | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.vm-boot-minimal' -L` | Boot smoke test (minimal config) (2026-02-10) |
| 3.3 | VM Sys Types | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.vm-system-type-default' -L` | System type layer tests (2026-02-10) |
| 4.1 | VM Features | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.vm-ssh-service' -L` | SSH service test (2026-02-10) |
| 4.2 | VM Features | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.vm-user-config' -L` | User configuration test (2026-02-10) |
| 4.3 | VM Features | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.vm-hm-activation' -L` | Home Manager activation test (2026-02-10) |
| 4.4 | VM Features | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.vm-shell-env' -L` | Shell environment test (2026-02-11) |
| 4.5 | VM Features | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.vm-sops-secrets' -L` | SOPS secrets test (2026-02-11) |
| 5.1 | Pkg Builds | `TASK:COMPLETE` | `nix build '.#checks.x86_64-linux.build-marker-pdf'` | Package build tests (2026-02-11) |
| 6.1 | Documentation | `TASK:COMPLETE` | N/A (docs) | Update tests/README.md (2026-02-11) |

---

## Phase 1: Eval Coverage Gaps (T0)

### Task 1.1 — Gap Analysis

**Deliverable**: Coverage matrix showing what's tested vs. not.

Current eval test coverage:

**NixOS Configs** (5 hosts):
| Host | Eval Test | Notes |
|------|-----------|-------|
| thinky-nixos | eval-thinky-nixos | Has test |
| pa161878-nixos | **MISSING** | No test at all |
| potato | eval-potato | Has test |
| mbp | eval-mbp | Has test |
| nixos-wsl-minimal | eval-nixos-wsl-minimal | Has test |

**Home Manager Configs** (7 configs):
| Config | Eval Test | Notes |
|--------|-----------|-------|
| tim@thinky-nixos | **MISSING** | Referenced in some tests but no eval |
| tim@pa161878-nixos | **MISSING** | No test |
| tim@thinky-ubuntu | **MISSING** | No test |
| tim@mbp | **MISSING** | No test |
| tim@potato | **MISSING** | No test (aarch64) |
| tim@macbook-air | **MISSING** | No test (darwin) |
| tim@nixvim-minimal | **MISSING** | No test |

**Feature Modules** (22 modules — tested via host configs, not individually):
| Module | Any Test? | Notes |
|--------|-----------|-------|
| shell | No | |
| git | No | |
| tmux | tmux-picker-syntax | Syntax only |
| neovim | No | |
| claude-code | No | |
| opencode | opencode-* (3 tests) | Config validation |
| development-tools | No | |
| files | files-module, hybrid-files | Eval tests |
| Others (14) | No | |

**Stub Checks** (claim to test, but don't):
- `regression-test`: Prints text, evaluates nothing
- `build-thinky-nixos-dryrun`: Doesn't reference the config
- `build-nixos-wsl-minimal-dryrun`: Doesn't reference the config
- `test-integration`: Prints "AVAILABLE", runs no VMs

### Task 1.2 — Add Missing Eval Tests

**File**: `modules/flake-parts/tests.nix`

Add:
```nix
# Missing NixOS eval
eval-pa161878-nixos = mkEvalTest "pa161878-nixos" "pa161878-nixos";

# Home Manager eval tests (new helper)
mkHmEvalTest = name: configName:
  pkgs.runCommand "eval-hm-${name}" {
    meta.description = "Evaluation test for ${configName} HM configuration";
    meta.timeout = 30;
    inherit (self.homeConfigurations.${configName}.config.home) homeDirectory;
  } ''
    echo "Testing ${configName} HM evaluation..."
    echo "Home directory: $homeDirectory"
    echo "OK" && touch $out
  '';

eval-hm-thinky-nixos = mkHmEvalTest "thinky-nixos" "tim@thinky-nixos";
eval-hm-pa161878-nixos = mkHmEvalTest "pa161878-nixos" "tim@pa161878-nixos";
eval-hm-thinky-ubuntu = mkHmEvalTest "thinky-ubuntu" "tim@thinky-ubuntu";
eval-hm-mbp = mkHmEvalTest "mbp" "tim@mbp";
eval-hm-nixvim-minimal = mkHmEvalTest "nixvim-minimal" "tim@nixvim-minimal";
# Note: tim@potato (aarch64) and tim@macbook-air (darwin) skip — wrong system
```

**Definition of Done**: `nix flake check --no-build` passes with new eval tests.

### Task 1.3 — Fix Stub Tests

Replace stub implementations:
- `regression-test`: Actually evaluate ALL nixos + HM configs
- `build-thinky-nixos-dryrun`: Reference `self.nixosConfigurations.thinky-nixos.config.system.build.toplevel`
- `build-nixos-wsl-minimal-dryrun`: Reference `self.nixosConfigurations.nixos-wsl-minimal.config.system.build.toplevel`
- `test-integration`: Either remove or actually call the VM tests

**Definition of Done**: No check is a no-op stub.

---

## Phase 2: Wire Existing VM Tests

### Task 2.1 — Wire ssh-management.nix

**File**: `modules/flake-parts/tests.nix` (or new `vm-tests.nix`)

The test at `tests/integration/ssh-management.nix` already uses `pkgs.nixosTest`. Wire it:
```nix
vm-ssh-management = import ../../tests/integration/ssh-management.nix { inherit pkgs lib; };
```

**Definition of Done**: `nix build '.#checks.x86_64-linux.vm-ssh-management'` runs the VM test.

### Task 2.2 — Wire sops-deployment.nix

Same approach:
```nix
vm-sops-deployment = import ../../tests/integration/sops-deployment.nix { inherit pkgs lib; };
```

**Definition of Done**: `nix build '.#checks.x86_64-linux.vm-sops-deployment'` runs the VM test.

---

## Phase 3: VM Test Infrastructure (T2)

### Task 3.1 — Create VM Test Scaffold

**New file**: `modules/flake-parts/vm-tests.nix`

Create:
- `mkVmTest` helper: wraps `pkgs.nixosTest` with common defaults (memory, timeout, networking)
- `baseVmConfig`: minimal NixOS config suitable for VM testing (no WSL, no hardware deps)
- `vmModuleSet`: curated set of dendritic modules safe for VM testing (excludes WSL-specific, hardware-specific)
- Naming convention: all checks prefixed `vm-`

**Key design**: VM tests compose from dendritic modules (`self.modules.nixos.*` / `self.modules.homeManager.*`) rather than importing full host configs. This avoids WSL/hardware dependencies.

```nix
# Sketch
mkVmTest = { name, description, modules ? [], hmModules ? [], testScript, memory ? 1024 }:
  pkgs.nixosTest {
    name = "vm-${name}";
    nodes.machine = { config, pkgs, ... }: {
      imports = modules;
      virtualisation.memorySize = memory;
      # common: no firewall, test user
    };
    testScript = testScript;
  };
```

### Task 3.2 — Boot Smoke Test

First VM test: does a minimal NixOS config (system type `1-minimal`) boot?

**Module names** (verified): `self.modules.nixos.system-minimal`, `.system-default`, `.system-cli`, `.system-desktop`

```nix
vm-boot-minimal = mkVmTest {
  name = "boot-minimal";
  description = "Minimal NixOS boots to multi-user.target";
  modules = [ self.modules.nixos.system-minimal ];
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("nix --version")
  '';
};
```

**Definition of Done**: VM boots, reaches multi-user.target, `nix --version` works.

### Task 3.3 — System Type Layer Tests

Test each system type adds expected functionality. Module hierarchy:
- `system-minimal` → Nix, store optimization, GC
- `system-default` → + users, locale, HM integration (imports minimal)
- `system-cli` → + SSH, networking, CLI tools (imports default)
- `system-desktop` → + desktop env (imports cli)

```nix
vm-system-type-default = mkVmTest {
  name = "system-type-default";
  modules = [ self.modules.nixos.system-default ];
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("id tim")              # user exists
    machine.succeed("locale | grep en_US") # locale set
  '';
};

vm-system-type-cli = mkVmTest {
  name = "system-type-cli";
  modules = [ self.modules.nixos.system-cli ];
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sshd.service")  # SSH daemon running
    machine.succeed("git --version")       # dev tools present
  '';
};
```

**Definition of Done**: Each system type layer test passes, verifying cumulative composition.

---

## Phase 4: Feature VM Tests (T3)

### Task 4.1 — SSH Service Test

Test SSH daemon configuration matches expectations:
- Correct port (2223 for WSL, 22 for standard)
- Password auth disabled
- Key-based auth works
- Multi-node: test SSH from one node to another

### Task 4.2 — User Configuration Test

Test user setup:
- User `tim` exists with correct groups (wheel, etc.)
- Home directory created
- Shell is zsh (or configured shell)

### Task 4.3 — Home Manager Activation Test

**Critical test**: Verify Home Manager actually activates in a VM:
- NixOS + HM integration module
- HM activation script runs
- Programs from HM are in PATH
- Config files generated (e.g., `.gitconfig`, `.zshrc`)

This requires composing a minimal NixOS config + HM modules:
```nix
vm-home-manager-activation = pkgs.nixosTest {
  name = "vm-hm-activation";
  nodes.machine = { config, pkgs, ... }: {
    imports = [
      self.modules.nixos.system-default       # provides user tim, locale
      inputs.home-manager.nixosModules.home-manager
    ];
    home-manager.users.tim = { ... }: {
      imports = [
        self.modules.homeManager.git           # git config
        self.modules.homeManager.shell         # zsh config
      ];
      home.stateVersion = "24.11";
    };
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("su - tim -c 'git --version'")
    machine.succeed("test -f /home/tim/.gitconfig")
  '';
};
```

**HM module names available** (all under `self.modules.homeManager.*`):
`claude-code`, `development-tools`, `esp-idf`, `files`, `git`, `git-auth-helpers`,
`github-auth`, `gitlab-auth`, `neovim`, `onedrive`, `opencode`, `podman`,
`secrets-management`, `shell`, `shell-utils`, `system-tools`, `terminal`,
`tmux`, `windows-terminal`, `yazi`

**HM system type modules**: `home-minimal`, `home-default`, `home-cli`, `home-desktop`

### Task 4.4 — Shell Environment Test

Test shell configuration works:
- zsh starts without errors
- starship prompt loads
- Aliases defined
- PATH includes expected directories

### Task 4.5 — SOPS Secrets Test

Test SOPS-nix integration:
- Age keys available
- Secrets decrypted at boot
- Correct file permissions
- Services can read secrets

---

## Phase 5: Package Build Tests (T1)

### Task 5.1 — Build Tests for Custom Packages

Test that all custom packages build:
```nix
build-marker-pdf = self'.packages.marker-pdf;
build-markitdown = self'.packages.markitdown;
build-tomd = self'.packages.tomd;
build-nixvim-anywhere = self'.packages.nixvim-anywhere;
# docling has deprecation warning but should still build
```

**Note**: These are just references — putting them in `checks` means `nix flake check` will build them.

---

## Phase 6: Documentation

### Task 6.1 — Update Documentation

- Update `tests/README.md` to reflect new test architecture
- Document VM test conventions (naming, helpers, how to add new tests)
- Document how to run specific test tiers
- Add runbook for common test failures

---

## Verification

After each phase:
1. `nix flake check --no-build` — all eval tests pass
2. `nix build '.#checks.x86_64-linux.vm-boot-minimal'` — first VM test passes
3. `nix build '.#checks.x86_64-linux.vm-SPECIFIC' -L` — specific VM test with output
4. Full suite: `nix flake check` (runs everything including VM tests)

---

## Key Files

| File | Role |
|------|------|
| `modules/flake-parts/tests.nix` | Existing eval tests (modify) |
| `modules/flake-parts/vm-tests.nix` | **NEW**: VM test infrastructure |
| `tests/integration/ssh-management.nix` | Existing VM test (wire up) |
| `tests/integration/sops-deployment.nix` | Existing VM test (wire up) |
| `tests/vm/` | **NEW**: VM test definitions (if separate files needed) |
| `tests/README.md` | Test documentation (update) |
| `modules/system/types/` | System type modules (tested by 3.3) |
| `modules/programs/` | Feature modules (tested by Phase 4) |

---

## Estimated Test Execution Times

| Check Category | Count | Time per | Total |
|----------------|-------|----------|-------|
| Eval (T0) | ~15 | <1s | <15s |
| Build (T1) | ~5 | 1-5min | 5-25min |
| VM boot (T2) | ~4 | 2-3min | 8-12min |
| VM feature (T3) | ~5 | 3-5min | 15-25min |
| **Total** | ~29 | | ~30-60min |

`nix flake check --no-build` remains fast (~30-60s for eval-only).
