# Plan 019: Migrate nixcfg to Dendritic Pattern

> **WORK IN WRONG DIRECTORY?** This plan MUST be worked on in:
> ```
> cd ~/src/nixcfg-dendritic   # <-- THE CORRECT WORKTREE
> git branch                   # Should show: refactor/dendritic-pattern
> ```
> If you're in `~/src/nixcfg` (main repo), STOP and switch to the dendritic worktree!

**Created**: 2026-02-07
**Status**: COMPLETE
**Branch**: `refactor/dendritic-pattern`
**Worktree**: `~/src/nixcfg-dendritic` (NOT ~/src/nixcfg!)
**Replaces**: Plan 018 (modularization) - same goal, new approach

### Review History

| Date | Reviewer | Findings |
|------|----------|----------|
| 2026-02-08 | Claude (review task) | Reviewed against dendritic research (docs 01-10). Core pattern ✅, Phase 6 tasks correctly ordered. Added: Task 6.4.1 clarification (disabledModules placement), derivation diffing for 6.4.11, import-tree conventions (Decision 8), specialArgs bridge pattern (Decision 9), Future Work section (F1-F4), corrected Darwin module status. |
| 2026-02-08 | Claude (post-completion audit) | **CRITICAL FIXES**: (1) shared-modules.nix referenced deleted `modules/nixos/wsl-base.nix` - fixed to export `self.modules.nixos.wsl`; (2) wsl-nixos template used old options - updated to `wsl-settings`. **CLEANUP**: Deleted orphaned files: `wsl-common.nix`, `ssh-keys-data.nix`, `wsl-tarball-checks.nix` (inlined to nixos-wsl-minimal). Commit: 527c70f |

## Executive Summary

Migrate nixcfg from host-centric organization to feature-centric dendritic pattern using flake-parts + import-tree. This unifies all Nix files as flake-parts modules, eliminates manual imports, and enables cross-platform feature definitions.

## Current State Assessment

### What nixcfg Already Has (Keep)
- ✅ Flake-parts for output organization (12 modules in `flake-modules/`)
- ✅ Parameterized modules with custom options (`homeBase.*`, `config.base.*`)
- ✅ Standalone home-manager (fast iteration, clear separation)
- ✅ Module exports for sharing (`nixosModules.*`, `homeManagerModules.*`)
- ✅ Clean layering (NixOS system vs HM user)

### What Needs to Change
| Current | Dendritic |
|---------|-----------|
| Manual imports in flake-modules/*.nix | import-tree auto-loading |
| Host-centric: `hosts/thinky-nixos/` | Feature-centric: `modules/services/wsl/` |
| Separate files: `home/common/git.nix` + `hosts/common/ssh.nix` | Unified: `modules/services/git/git.nix` with all contexts |
| `specialArgs = { inherit inputs; }` | Top-level `config.*` access |
| No `flake.modules.*` namespace | Full `flake.modules.{nixos,darwin,homeManager}.*` |

### Repository Statistics
- ~22,000 lines of Nix across 99 files
- 5 NixOS hosts, 6 HM configs, 1 Darwin config
- 12 flake-module components
- Key complexity: nixvim (1871 LOC), tmux (733 LOC), claude-code (710 LOC)

## Architecture Design

### Target Directory Structure

```
nixcfg/
├── flake.nix                        # Minimal: 3-line outputs via import-tree
├── modules/
│   ├── flake-parts []/              # Infrastructure (no platform indicator)
│   │   ├── modules.nix              # Enable flake.modules.* infrastructure
│   │   ├── configurations.nix       # nixosConfigurations, homeConfigurations
│   │   ├── lib.nix                  # mkNixos, mkDarwin, mkHomeManager helpers
│   │   ├── factory.nix              # Factory pattern infrastructure
│   │   ├── systems.nix              # Supported architectures
│   │   ├── overlays.nix             # Overlay definitions
│   │   ├── packages.nix             # Custom packages
│   │   ├── dev-shells.nix           # Development shells
│   │   ├── templates.nix            # Flake templates
│   │   └── exports.nix              # Module exports for sharing
│   │
│   ├── system/                       # System-level configuration
│   │   ├── types/                   # Composition layers
│   │   │   ├── 1-minimal [NDnd]/    # Base: nix settings, state version
│   │   │   ├── 2-default [NDnd]/    # + user, locale, SSH client (HM)
│   │   │   ├── 3-cli [NDnd]/        # + SSH daemon, dev tools
│   │   │   └── 4-desktop [NDnd]/    # + printing, DE, GUI
│   │   └── settings/
│   │       ├── locale [NDnd]/       # Timezone, keyboard
│   │       ├── networking [N]/      # NetworkManager, firewall
│   │       └── wsl [N]/             # WSL-specific system config
│   │
│   ├── services/                     # System services
│   │   ├── ssh [NDnd]/              # SSH client + server config
│   │   ├── printing [N]/            # CUPS configuration
│   │   └── docker [N]/              # Container runtime
│   │
│   ├── programs/                     # User applications
│   │   ├── shell [NDnd]/            # zsh, fish, starship
│   │   ├── git [NDnd]/              # git, gh, gitlab-cli
│   │   ├── tmux [NDnd]/             # tmux configuration
│   │   ├── neovim [NDnd]/           # nixvim configuration
│   │   ├── claude-code [nd]/        # Claude Code multi-account
│   │   ├── opencode [nd]/           # OpenCode multi-account
│   │   └── browser [nd]/            # Firefox, Chrome profiles
│   │
│   ├── users/                        # User account definitions
│   │   └── tim [NDnd]/              # Factory: nixos.tim, darwin.tim, homeManager.tim
│   │
│   ├── hosts/                        # Host-specific compositions
│   │   ├── thinky-nixos [N]/        # WSL primary development
│   │   ├── pa161878-nixos [N]/      # WSL work environment
│   │   ├── thinky-ubuntu [nd]/      # Vanilla WSL (HM only)
│   │   ├── mbp [N]/                 # Intel MacBook Pro
│   │   ├── potato [N]/              # ARM SBC
│   │   ├── macbook-air [D]/         # Apple Silicon Mac
│   │   └── nixos-wsl-minimal [N]/   # Minimal WSL template
│   │
│   └── meta/                         # Shared constants and options
│       ├── options.nix              # ReadOnly options (username, etc.)
│       └── constants.nix            # Shared values
│
├── secrets/                          # SOPS secrets (unchanged)
├── overlays/                         # Package overlays (unchanged)
├── pkgs/                            # Custom packages (unchanged)
├── templates/                        # Flake templates (unchanged)
└── docs/                            # Documentation (unchanged)
```

### Bracket Notation Convention
- `[N]` = NixOS only
- `[D]` = Darwin only
- `[nd]` = home-manager only
- `[ND]` = NixOS + Darwin
- `[NDnd]` = All three contexts
- `[]` = Infrastructure/meta

### Module Namespace Usage

Each feature module defines its configurations in `flake.modules.*`:

```nix
# modules/programs/shell [NDnd]/shell.nix
{ config, lib, inputs, ... }:
{
  flake.modules = {
    nixos.shell = { pkgs, ... }: {
      programs.fish.enable = true;
      users.users.${config.username}.shell = pkgs.fish;
    };

    darwin.shell = { pkgs, ... }: {
      programs.fish.enable = true;
    };

    homeManager.shell = { ... }: {
      programs.fish.enable = true;
      programs.starship.enable = true;
      programs.zsh = { ... };
    };
  };
}
```

### Host Composition Pattern

```nix
# modules/hosts/thinky-nixos [N]/configuration.nix
{ inputs, config, ... }:
let
  inherit (inputs.self.modules) nixos homeManager;
in
{
  flake.modules.nixos.thinky-nixos = {
    imports = [
      nixos.system-cli           # Inherits minimal → default → cli
      nixos.wsl                  # WSL-specific
      nixos.docker               # Container support
    ];

    # Host-specific overrides
    networking.hostName = "thinky-nixos";
    wsl.defaultUser = config.username;
  };

  # Register as NixOS configuration
  flake.nixosConfigurations =
    inputs.self.lib.mkNixos "x86_64-linux" "thinky-nixos";

  # Register home-manager config
  flake.homeConfigurations =
    inputs.self.lib.mkHomeManager "x86_64-linux" "${config.username}@thinky-nixos";
}

# modules/hosts/thinky-nixos [N]/home.nix
{ inputs, config, ... }:
let
  inherit (inputs.self.modules) homeManager;
in
{
  flake.modules.homeManager."${config.username}@thinky-nixos" = {
    imports = [
      homeManager.shell
      homeManager.git
      homeManager.tmux
      homeManager.neovim
      homeManager.claude-code
      homeManager.wsl-home
    ];
  };
}
```

## Migration Phases

### Phase 0: Infrastructure Foundation
**Goal**: Add dendritic infrastructure without breaking existing config

| Task | Description | Status |
|------|-------------|--------|
| 0.1 | Add import-tree to flake inputs | TASK:COMPLETE |
| 0.2 | Create `modules/flake-parts/modules.nix` (enable flake.modules.*) | TASK:COMPLETE |
| 0.3 | Create `modules/flake-parts/lib.nix` (mkNixos, mkHomeManager helpers) | TASK:COMPLETE |
| 0.4 | Create `modules/meta/options.nix` (username as readOnly option) | TASK:COMPLETE |
| 0.5 | Create `modules/flake-parts/systems.nix` (supported architectures) | TASK:COMPLETE |
| 0.6 | Verify `nix flake check` passes with new structure | TASK:COMPLETE |

**Definition of Done**:
- import-tree loads all modules from `modules/`
- `flake.modules.{nixos,darwin,homeManager}` namespace available
- Existing flake-modules/ still work (parallel structure)
- No build breakage

### Phase 1: First Feature Migration (Shell)
**Goal**: Prove pattern works with representative feature

| Task | Description | Status |
|------|-------------|--------|
| 1.1 | Create `modules/programs/shell [NDnd]/shell.nix` | TASK:COMPLETE |
| 1.2 | Migrate zsh config from `home/common/zsh.nix` | TASK:COMPLETE (included in 1.1) |
| 1.3 | Migrate fish config (if any) | TASK:N/A (no fish config exists) |
| 1.4 | Migrate starship config | TASK:N/A (no starship config exists) |
| 1.5 | Test on thinky-nixos (NixOS + HM) | TASK:COMPLETE |
| 1.6 | Test on thinky-ubuntu (HM only) | TASK:COMPLETE (wired in, dry-run verified) |
| 1.7 | Remove old shell configs after verification | TASK:COMPLETE |

**Definition of Done**:
- Shell works identically on all hosts
- Single source of truth in `modules/programs/shell/`
- Old files removed

### Phase 2: System Types Layer
**Goal**: Establish composition hierarchy

| Task | Description | Status |
|------|-------------|--------|
| 2.1 | Create `modules/system/types/1-minimal/` | TASK:COMPLETE |
| 2.2 | Create `modules/system/types/2-default/` | TASK:COMPLETE |
| 2.3 | Create `modules/system/types/3-cli/` | TASK:COMPLETE |
| 2.4 | Create `modules/system/types/4-desktop/` | TASK:COMPLETE |
| 2.5 | Migrate `modules/base.nix` → system types | TASK:COMPLETE |
| 2.6 | Migrate `home/modules/base.nix` → system types | TASK:COMPLETE |

**Definition of Done**:
- Hosts import system-type, not individual modules
- Clear layering: minimal → default → cli → desktop
- Base modules deprecated

### Phase 3: Feature Migrations (Core)
**Goal**: Migrate high-value features

| Task | Description | Priority | Status |
|------|-------------|----------|--------|
| 3.1 | git [NDnd] | High | TASK:COMPLETE |
| 3.2 | ssh [NDnd] | High | TASK:PARTIAL (integrated into system types) |
| 3.3 | tmux [NDnd] | High | TASK:COMPLETE |
| 3.4 | neovim [NDnd] (1871 LOC) | High | TASK:COMPLETE |
| 3.5 | wsl [N] system settings | High | TASK:COMPLETE |
| 3.6 | wsl-home [nd] user settings | High | TASK:COMPLETE |

### Phase 4: Feature Migrations (Tools)
**Goal**: Migrate development tools

| Task | Description | Priority | Status |
|------|-------------|----------|--------|
| 4.1 | claude-code [nd] | High | TASK:COMPLETE |
| 4.2 | opencode [nd] | High | TASK:COMPLETE |
| 4.3 | secrets-management [NDnd] | Medium | TASK:COMPLETE |
| 4.4 | github-auth [nd] | Medium | TASK:COMPLETE |
| 4.5 | gitlab-auth [nd] | Medium | TASK:COMPLETE |
| 4.6 | development tools [nd] | Medium | TASK:COMPLETE |

### Phase 5: Host Compositions
**Goal**: Migrate all hosts to new structure

| Task | Description | Status |
|------|-------------|--------|
| 5.1 | thinky-nixos (WSL primary) | TASK:COMPLETE |
| 5.2 | pa161878-nixos (WSL work) | TASK:COMPLETE |
| 5.3 | thinky-ubuntu (HM only) | TASK:COMPLETE |
| 5.4 | mbp (Intel Mac running NixOS) | TASK:COMPLETE |
| 5.5 | potato (ARM SBC) | TASK:COMPLETE |
| 5.6 | macbook-air (Apple Silicon) | TASK:COMPLETE |
| 5.7 | nixos-wsl-minimal (template) | TASK:COMPLETE |

### Phase 6: Cleanup
**Goal**: Remove deprecated structure

| Task | Description | Status |
|------|-------------|--------|
| 6.1 | Remove `flake-modules/` (replaced by import-tree) | TASK:COMPLETE |
| 6.2 | Remove `hosts/common/` | TASK:COMPLETE |
| 6.3 | Remove `home/common/` (moved to `home/modules/legacy-common/`) | TASK:COMPLETE |
| 6.4 | Remove `home/modules/` | TASK:COMPLETE (2026-02-08) |
| 6.5 | Remove `modules/` (old NixOS modules) | TASK:COMPLETE (2026-02-08) |
| 6.6 | Update ARCHITECTURE.md | TASK:COMPLETE (2026-02-08) |
| 6.7 | Update CLAUDE.md with new patterns | TASK:COMPLETE (2026-02-08) |

#### Task 6.4 Sub-tasks: Remove `home/modules/`

**Context**: `home/modules/base.nix` is still imported by all 6 hosts. It provides:
- `disabledModules` for upstream claude-code/opencode
- `homeBase` options (username, homeDirectory, stateVersion)
- Program configs: claude-code (~150 LOC), opencode (~120 LOC), yazi (~100 LOC)
- Imports: legacy-common/* (~4300 LOC), files/, terminal modules

**Strategy**: Migrate content to dendritic modules, then update hosts to remove base.nix import.

| Sub-task | Description | Status |
|----------|-------------|--------|
| 6.4.1 | Move `disabledModules` to dendritic modules | TASK:COMPLETE (2026-02-08) |
| 6.4.2 | Replace `homeBase` options with dendritic system types | TASK:COMPLETE (2026-02-08) |
| 6.4.3 | Move claude-code CONFIG (accounts, mcp) to host files | TASK:COMPLETE (2026-02-08) |
| 6.4.4 | Move opencode CONFIG to host files | TASK:COMPLETE (2026-02-08) |
| 6.4.5 | Create dendritic yazi module | TASK:COMPLETE (2026-02-08) |
| 6.4.6 | Migrate legacy-common/environment.nix | TASK:COMPLETE (2026-02-08) |
| 6.4.7 | Migrate legacy-common/aliases.nix | TASK:COMPLETE (2026-02-08) |
| 6.4.8 | Migrate legacy-common/shell-utils.nix | TASK:COMPLETE (2026-02-08) |
| 6.4.9 | Migrate remaining legacy-common/* | TASK:COMPLETE (2026-02-08) |
| 6.4.10 | Migrate standalone modules | TASK:COMPLETE (2026-02-08) |
| 6.4.11 | Update all hosts to remove base.nix import | TASK:COMPLETE (2026-02-08) |
| 6.4.12 | Move shared libs to dendritic structure | TASK:COMPLETE (2026-02-08) |
| 6.4.13 | Migrate home/modules/files to dendritic | TASK:COMPLETE (2026-02-08) |
| 6.4.14 | Delete remaining home/modules/ files | TASK:COMPLETE (2026-02-08) |
| 6.4.15 | Delete home/modules/ directory | TASK:COMPLETE (2026-02-08) |

**Execution Order**: 6.4.1-6.4.2 (infrastructure) → 6.4.3-6.4.5 (high-value) → 6.4.6-6.4.10 (legacy) → 6.4.11 (hosts) → 6.4.12-6.4.15 (final cleanup)

**Per-task validation**: After each sub-task, run `nix flake check --no-build` and verify at least one host builds.

---

### Sub-task Implementation Details

#### 6.4.1: Move `disabledModules` to dendritic modules

**Goal**: Each dendritic module disables its upstream counterpart automatically.

**Current state** (`home/modules/base.nix:36-39`):
```nix
disabledModules = [
  "programs/claude-code.nix"
  "programs/opencode.nix"
];
```

**⚠️ CRITICAL - Correct Placement**:
Per dendritic pattern research (doc 04/09), `disabledModules` MUST be placed **INSIDE** the
deferredModule content block, not at the flake-parts module level. The reason: deferredModule
content is evaluated by home-manager's evalModules, so `disabledModules` only works inside it.

```nix
# WRONG - at flake-parts level (won't work!)
{ ... }:
{
  disabledModules = [ "programs/claude-code.nix" ];  # ❌
  flake.modules.homeManager.claude-code = { ... };
}

# CORRECT - inside deferredModule content
{ ... }:
{
  flake.modules.homeManager.claude-code = {
    disabledModules = [ "programs/claude-code.nix" ];  # ✅
    # ... rest of module options and config
  };
}
```

**Files to modify**:
1. `modules/programs/claude-code/claude-code.nix` - Add inside `homeManager.claude-code` block (after imports):
   ```nix
   disabledModules = [ "programs/claude-code.nix" ];
   ```
2. `modules/programs/opencode/opencode.nix` - Add inside `homeManager.opencode` block (after imports):
   ```nix
   disabledModules = [ "programs/opencode.nix" ];
   ```

**Validation**: `nix flake check --no-build` passes

**Note**: The `disabledModules` in base.nix stays until task 6.4.12 (backward compatibility).

---

#### 6.4.2: Replace `homeBase` options with dendritic system types

**Goal**: Remove dependency on `homeBase.*` options; use `homeMinimal.*` from system types.

**Current state** (`home/modules/base.nix:71-84`):
- `homeBase.username` - required, used by all hosts
- `homeBase.homeDirectory` - required, used by all hosts
- Also provides `basePackages` list

**Files to modify**:
1. `modules/system/types/1-minimal/home.nix` - Ensure `homeMinimal.username` and `homeMinimal.homeDirectory` are defined
2. Each host's home.nix - Change from `homeBase.username` to `homeMinimal.username`

**Validation**: `nix flake check --no-build` + dry-run on thinky-nixos

---

#### 6.4.3: Move claude-code CONFIG to host files

**Goal**: Each host defines its own claude-code accounts/MCP config inline.

**Implementation** (2026-02-08): Used DRY approach with lib presets.

**What was done**:
1. Added `flake.lib.claudeCode` presets to `modules/flake-parts/lib.nix`:
   - `baseConfig` - enable, defaults, taskAutomation, skills
   - `personalAccounts` - max + pro accounts
   - `workAccount` - work (Code-Companion proxy) for work machines only
   - `defaultStatusline`, `defaultMcpServers`, `defaultSubAgents`

2. Updated all 6 host files to use presets (~8 lines each instead of ~150):
   - Personal hosts: `accounts = inputs.self.lib.claudeCode.personalAccounts`
   - Work host (pa161878-nixos): `accounts = personalAccounts // workAccount`

3. Removed ~150 LOC from `home/modules/base.nix`

**Files modified**:
- `modules/flake-parts/lib.nix` - Added claudeCode presets
- `modules/hosts/*/` - All 6 host files updated
- `home/modules/base.nix` - Removed claude-code config block

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.4: Move opencode CONFIG to host files

**Goal**: Each host defines its own opencode accounts inline.

**Implementation** (2026-02-08): Used DRY approach with lib presets (parallel to claude-code).

**What was done**:
1. Added `flake.lib.openCode` presets to `modules/flake-parts/lib.nix`:
   - `baseConfig` - enable, defaultModel, provider (anthropic), permissions
   - `personalAccounts` - max + pro accounts
   - `workAccount` - work (Code-Companion proxy) for work machines only
   - `workProvider` - codecompanion provider config with qwen-a3b model
   - `defaultMcpServers`, `defaultCommands`

2. Updated all 6 host files to use presets (~6 lines each instead of ~120):
   - Personal hosts: `accounts = inputs.self.lib.openCode.personalAccounts`
   - Work host (pa161878-nixos): `accounts = personalAccounts // workAccount`, `provider = baseConfig.provider // workProvider`

3. Removed ~120 LOC from `home/modules/base.nix` (config block + import)

**Files modified**:
- `modules/flake-parts/lib.nix` - Added openCode presets
- `modules/hosts/*/` - All 6 host files updated
- `home/modules/base.nix` - Removed opencode config block and import

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.5: Create dendritic yazi module

**Goal**: Move yazi config to `modules/programs/yazi/`.

**Implementation** (2026-02-08): Created full dendritic yazi module.

**What was done**:
1. Created `modules/programs/yazi/yazi.nix` - Full yazi config with:
   - Custom compact_meta linemode (size, mtime, permissions in 20 chars)
   - Patched glow plugin for dynamic preview width
   - WSL2 clipboard integration (clip.exe keybindings)
   - Plugin ecosystem (toggle-pane, mediainfo, miller, ouch, chmod, git, smart-enter)

2. Copied Lua files to `modules/programs/yazi/files/`:
   - `yazi-init.lua` - Custom linemode function
   - `yazi-glow-main.lua` - Patched glow plugin

3. Removed yazi config block (~115 LOC) from `home/modules/base.nix`

4. Updated all 6 host files to import `inputs.self.modules.homeManager.yazi`

**Files created**:
- `modules/programs/yazi/yazi.nix`
- `modules/programs/yazi/files/yazi-init.lua`
- `modules/programs/yazi/files/yazi-glow-main.lua`

**Files modified**:
- `home/modules/base.nix` - Removed yazi config block
- `modules/hosts/*/` - All 6 host files updated

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.6: Migrate legacy-common/environment.nix

**Goal**: Absorb environment variables and session config into appropriate dendritic module.

**Implementation** (2026-02-08): Migrated useful parts to development-tools, removed legacy.

**Analysis**:
- File had 294 lines of environment configuration
- Most content was already handled by shell module (GPG_TTY, HM session vars sourcing)
- Development paths (Go, Cargo, Pyenv) belonged in development-tools
- Some variables were unused legacy (BUILD_DIR, TRIP, ANDROID_SDK)

**What was done**:
1. Added to `modules/programs/development-tools/development-tools.nix`:
   - `enableGo` option (default: true) with GOPATH, go/bin paths, activation script
   - `enablePyenv` option (default: false) with PYENV_ROOT, shell init hooks
   - Rust PATH addition ($HOME/.cargo/bin) when enableRust is true
   - Common $HOME/.local/bin path

2. Removed environment.nix import from base.nix with migration comment

3. Deleted `home/modules/legacy-common/environment.nix` (294 lines)

**Removed (unused legacy)**:
- BUILD_DIR, TRIP (Yocto-specific, only referenced in environment.nix)
- ANDROID_SDK_ROOT, ADB_PORT, ADB_SERVER_SOCKET (unused)
- VIMRUNTIME hardcoded path (unnecessary with Nix)
- Complex idempotent sourcing scripts (redundant with shell module)

**Preserved (migrated to development-tools)**:
- Go environment setup (GOPATH, paths, directory creation)
- Pyenv setup (PYENV_ROOT, shell init)
- Cargo bin path
- Common local bin path

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.7: Migrate legacy-common/aliases.nix

**Goal**: Move shell aliases to shell module or host configs.

**Implementation** (2026-02-08): Migrated useful aliases and functions to shell module.

**What was done**:
1. Added to `modules/programs/shell/shell.nix` shellAliases:
   - `lsblk` - enhanced lsblk with vendor, model, label, etc.
   - `lh` - ls -lath | head
   - `gitit`, `dgit` - git workflow shortcuts
   - `rbwl/rbwu/rbws/rbwg/rbwgn/rbwls/rbwlock/rbwstop` - Bitwarden (rbw) aliases
   - `sopse/sopsd` - SOPS aliases
   - `poetryshell` - Poetry virtual environment activation

2. Added shell functions to initContent:
   - `better_less()` - pipe files through cat for better ANSI rendering
   - `verbosecd()` - cd + ls -lath | head
   - `SSHOPTS_LENIENT` - SSH options array for dev/testing

3. Removed from base.nix imports with migration comment

4. Deleted `home/modules/legacy-common/aliases.nix` (143 lines)

**Removed (too personal/specific)**:
- Project navigation aliases (cdtr, cdmx, nvtr, nvmx, cdddd)
- Drive mount aliases (cdint, cdext1, cdext2, cdc, cdg, cdx, cdy, cdz)
- These were user-specific project paths, not universally useful

**Files modified**:
- `modules/programs/shell/shell.nix` - Added aliases and functions
- `home/modules/base.nix` - Removed import, added migration comment

**Files deleted**:
- `home/modules/legacy-common/aliases.nix` (143 lines)

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.8: Migrate legacy-common/shell-utils.nix

**Goal**: Move shell utilities to `modules/programs/shell-utils/`.

**Implementation** (2026-02-08): Created dedicated dendritic module.

**What was done**:
1. Created `modules/programs/shell-utils/shell-utils.nix` - Full dendritic module with:
   - 9 shell utility scripts (mytree, vwatch, mergejson, colorfuncs, help-format-template,
     soundcloud-dl, stress-wrapper, wifi-test-comparison, remote-wifi-analyzer)
   - 9 bash library files (~/.local/lib/*.bash) for sourcing

2. Copied source files to `modules/programs/shell-utils/files/`:
   - `files/bin/` - Shell script source files
   - `files/lib/` - Bash library files

3. Updated all 6 host files to import `inputs.self.modules.homeManager.shell-utils`

4. Removed shell-utils.nix import from base.nix with migration comment

5. Deleted `home/modules/legacy-common/shell-utils.nix` (209 lines)

**Architecture note**: Unlike legacy module which used `homeBase.enableShellUtils` option,
dendritic module is unconditionally enabled when imported (standard dendritic pattern).

**Files created**:
- `modules/programs/shell-utils/shell-utils.nix`
- `modules/programs/shell-utils/files/bin/*` (8 script files)
- `modules/programs/shell-utils/files/lib/*` (9 library files)

**Files modified**:
- `home/modules/base.nix` - Removed import, added migration comment
- `modules/hosts/*/` - All 6 host files updated

**Files deleted**:
- `home/modules/legacy-common/shell-utils.nix` (209 lines)

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.9: Migrate remaining legacy-common/*

**Goal**: Clear out `home/modules/legacy-common/` directory.

**Implementation** (2026-02-08): Migrated all remaining files and deleted the directory.

**What was done**:

1. **Deleted orphaned files** (already migrated to dendritic modules):
   - `nixvim.nix` (1600 LOC) - migrated to modules/programs/neovim/
   - `tmux.nix` (350 LOC) - migrated to modules/programs/tmux/
   - `wsl-home-base.nix` (75 LOC) - superseded by wsl-home module
   - `nixvim-keybindings-fix.patch` - no longer needed

2. **Created new dendritic modules**:
   - `modules/programs/terminal/terminal.nix` - 4 terminal font setup scripts
   - `modules/programs/system-tools/system-tools.nix` - 5 system admin scripts + PowerShell docs
   - `modules/programs/esp-idf/esp-idf.nix` - Full FHS environment, 5 wrapper scripts
   - `modules/programs/onedrive/onedrive.nix` - 2 OneDrive utilities with shell aliases

3. **Updated development-tools module**:
   - Added `enableEnhancedCli` option (bat, eza, delta, bottom, miller)
   - Added `enableClaudeUtils` option (pdf2md, claudevloop, restart_claude, etc.)
   - Added pymupdf4llm to default Python packages

4. **Updated all 6 host files**:
   - WSL hosts: Added terminal, system-tools, esp-idf (enabled), onedrive (enabled)
   - Non-WSL hosts: Added terminal, system-tools only

5. **Removed from base.nix**:
   - Imports for development.nix, terminal.nix, system.nix, esp-idf.nix, onedrive.nix
   - Options: enableDevelopment, enableTerminal, enableSystem, enableShellUtils, enableEspIdf, enableOneDriveUtils
   - OneDrive shell aliases (now in onedrive module)

6. **Fixed wsl-home.nix**:
   - Removed references to deleted homeBase.enable* options
   - Changed to use home.sessionVariables and programs.*.shellAliases directly

7. **Deleted directory**: `home/modules/legacy-common/` (now empty)

**Net change**: -3044 lines (deleted 3862, added 818)

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.10: Migrate standalone modules

**Goal**: Move remaining `home/modules/*.nix` files.

**Status**: COMPLETE (2026-02-08)

**Files migrated**:
- `terminal-verification.nix` → Extended `modules/programs/terminal/terminal.nix` (merged)
- `windows-terminal.nix` → `modules/programs/windows-terminal [nd]/windows-terminal.nix`
- `podman-tools.nix` → `modules/programs/podman [nd]/podman.nix`
- `git-auth-helpers.nix` → `modules/programs/git-auth-helpers [nd]/git-auth-helpers.nix`
- `gitlab-auth.nix` → Already exists at `modules/programs/gitlab-auth [nd]/` (deleted legacy)

**Host updates**:
- All 6 HM hosts updated to import new modules
- WSL hosts: podman, windows-terminal, git-auth-helpers
- Non-WSL hosts: podman (enabled), git-auth-helpers
- ARM SBC (potato): podman disabled for lightweight footprint

**base.nix changes**:
- Removed imports of migrated modules
- Removed `enableContainerSupport` option (now handled by podman module)
- Removed `terminalVerification` passthrough (now in terminal module directly)

**Validation**: `nix flake check --no-build` ✓

---

#### 6.4.11: Update all hosts to remove base.nix import

**Goal**: No host imports `home/modules/base.nix`.

**Implementation** (2026-02-08): Successfully removed base.nix from all 6 hosts.

**What was done**:
1. Extended `home-default.basePackages` in `modules/system/types/2-default/default.nix`:
   - Added ~17 missing packages from base.nix (act, dua, ffmpeg, glow, imagemagick, etc.)
   - Added tomd custom package

2. Migrated functionality to home-default:
   - `programs.parallel` with `will-cite = true`
   - `home.file.".config/glow/glow.yml"` for glow config

3. Updated all 6 host files:
   - Changed from `home-minimal` to `home-default` import (home-default includes home-minimal)
   - Replaced base.nix import with direct files module imports (`../../../home/modules/files`, `../../../home/files`)
   - Added `homeFiles.enable = true` to each host
   - Migrated `homeBase.environmentVariables` → `homeDefault.environmentVariables` (potato, macbook-air)

4. Cleaned up dead code in `home/modules/files/default.nix`:
   - Removed unused `cfg = config.homeBase` line

**Files modified**:
- `modules/system/types/2-default/default.nix` - Added packages, parallel, glow config
- `modules/hosts/thinky-nixos/thinky-nixos.nix` - Removed base.nix, added files imports
- `modules/hosts/pa161878-nixos [N]/pa161878-nixos.nix` - Removed base.nix, added files imports
- `modules/hosts/thinky-ubuntu [nd]/thinky-ubuntu.nix` - Removed base.nix, added files imports
- `modules/hosts/mbp [N]/mbp.nix` - Removed base.nix, added files imports
- `modules/hosts/potato [N]/potato.nix` - Removed base.nix, migrated homeBase→homeDefault
- `modules/hosts/macbook-air [D]/macbook-air.nix` - Removed base.nix, migrated homeBase→homeDefault
- `home/modules/files/default.nix` - Removed dead code

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

**Note**: base.nix still exists but is no longer imported by any host. Task 6.4.12 will delete it.

---

#### 6.4.12: Move shared libs to dendritic structure

**Goal**: Move `home/modules/lib/` and `home/modules/shared/` into dendritic module structure.

**Implementation** (2026-02-08): Completed successfully.

**What was done**:
1. Created `modules/lib/` directory for shared utilities
2. Copied `home/modules/lib/rbw.nix` → `modules/lib/rbw.nix`
3. Copied `home/modules/lib/git-forge-auth.nix` → `modules/lib/git-forge-auth.nix`
4. Copied `home/modules/shared/` → `modules/lib/shared/`
5. Updated import paths in 5 files:
   - `modules/programs/opencode/opencode.nix`
   - `modules/programs/opencode/_hm/mcp-servers.nix`
   - `modules/programs/claude-code/_hm/lib.nix`
   - `modules/programs/claude-code/_hm/mcp-servers.nix`
   - `modules/flake-parts/termux-outputs.nix`

**Files created**:
- `modules/lib/rbw.nix`
- `modules/lib/git-forge-auth.nix`
- `modules/lib/shared/ai-instructions.nix`
- `modules/lib/shared/mcp-server-defs.nix`

**Note**: Old files in `home/modules/lib/` and `home/modules/shared/` kept for now (will delete in 6.4.14)

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.13: Migrate home/modules/files to dendritic

**Goal**: Move `home/modules/files/` and `home/files/` to dendritic structure.

**Implementation** (2026-02-08): Moved as-is to dendritic location, deferred refactoring to F5.

**What was done**:
1. Created `modules/programs/files [nd]/` dendritic structure:
   - `files.nix` - Main dendritic wrapper exporting `homeManager.files`
   - `_completion-generator.nix` - Auto-completion generation (from home/modules/files)
   - `_homefiles-module.nix` - homeFiles module with autoWriter (from home/files/default.nix)
   - `files/` - All source files (bin/, lib/, claude/, etc.)

2. Renamed `.nix` files in `files/` with `_` prefix to exclude from import-tree:
   - `_default.nix`, `_example-config.nix`
   - `lib/_domain-generators.nix`, `lib/_script-libraries.nix`

3. Updated all 6 host files:
   - Changed from relative paths to `inputs.self.modules.homeManager.files`

4. Updated tests in `modules/flake-parts/tests.nix`:
   - Used path concatenation technique for special characters in directory names
   - `../programs + "/files [nd]/_homefiles-module.nix"` pattern

5. Deleted old directories: `home/modules/files/`, `home/files/`

**Files created**:
- `modules/programs/files [nd]/files.nix`
- `modules/programs/files [nd]/_completion-generator.nix`
- `modules/programs/files [nd]/_homefiles-module.nix`
- `modules/programs/files [nd]/files/*` (all source files)

**Note**: Anti-patterns documented in F5 remain - refactoring deferred.

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.14: Delete remaining home/modules/ files

**Goal**: Clean up any remaining files in `home/modules/`.

**Implementation** (2026-02-08): Deleted entire directory and fixed broken path references.

**What was done**:
1. Deleted `home/modules/` directory (66 files):
   - Nix modules: base.nix, claude-code.nix, opencode.nix, github-auth.nix, etc.
   - Directories: claude-code/, opencode/, lib/, shared/
   - Documentation: README-*.md files

2. Deleted `home/migration/` directory (leftover from dendritic migration):
   - darwin-home-files.nix, linux-home-files.nix, wsl-home-files.nix

3. Fixed `home/nixvim-minimal.nix` to use dendritic neovim module:
   - Changed from broken `./common/nixvim.nix` to `inputs.self.modules.homeManager.neovim`

4. Fixed path references in 5 modules (changed `home/files/` → `modules/programs/files [nd]/files/`):
   - `modules/programs/system-tools/system-tools.nix` - 9 paths
   - `modules/programs/terminal/terminal.nix` - 4 paths
   - `modules/programs/development-tools/development-tools.nix` - 4 paths
   - `modules/system/types/2-default/default.nix` - 1 path (glow.yml)
   - `modules/programs/tmux/tmux.nix` - 1 path (libPath)

**Files deleted**:
- `home/modules/` (66 files)
- `home/migration/` (3 files)

**Remaining in `home/`**:
- `home/nixvim-minimal.nix` - Still used by tim@nixvim-minimal config

**Validation**: `nix flake check --no-build` ✓, `home-manager switch --dry-run` ✓

---

#### 6.4.15: Delete home/modules/ directory

**Goal**: Remove the deprecated directory entirely.

**Status**: COMPLETE (2026-02-08) - Done as part of 6.4.14

**Note**: Directory deleted in 6.4.14. The `home/` directory now only contains
`nixvim-minimal.nix` which is still used by the tim@nixvim-minimal configuration.

## Technical Decisions

### 1. import-tree vs flake-file
**Decision**: Use import-tree only (not flake-file)
**Rationale**:
- import-tree handles module loading, which is the core benefit
- flake-file adds complexity for input declaration
- Keep inputs in flake.nix for now (familiar pattern)
- Can add flake-file later if needed

### 2. Standalone Home Manager
**Decision**: Keep standalone HM (not integrated)
**Rationale**:
- Current architecture works well
- Fast iteration without root
- Dendritic pattern supports both approaches
- Preserve tim@thinky-ubuntu (vanilla WSL)

### 3. User Factory Pattern
**Decision**: Use factory for user creation
**Rationale**:
- User "tim" needs nixos + darwin + homeManager configs
- Factory generates all three from single definition
- Allows host-specific overrides via mkMerge

### 4. Incremental Migration
**Decision**: Migrate one feature at a time
**Rationale**:
- Reduces risk of breaking working configs
- Each phase has clear validation criteria
- Old and new can coexist during transition

### 5. Module Naming
**Decision**: Use platform indicators in directory names
**Rationale**:
- Self-documenting structure
- Clear at-a-glance platform applicability
- Matches dendritic community convention

### 6. Layer Boundary Definitions (2026-02-07)
**Decision**: Clear separation of concerns per layer

| Layer | NixOS Content | Home Manager Content |
|-------|---------------|---------------------|
| **1-minimal** | Nix settings, GC, state version | HM basics, targets.genericLinux |
| **2-default** | User creation, locale, console | SSH client, fonts, secrets tools |
| **3-cli** | SSH daemon, dev tools, containers | Yazi, CLI packages, parallel |
| **4-desktop** | DE, audio, bluetooth, printing | GUI packages only |

**Key Decisions**:
- SSH daemon in cli (not default): containers/CI/WSL don't need it
- SSH client in home-default: symmetry with system layers
- Power tools (tmux, ripgrep, fd) in cli, not default
- Yazi in cli (TUI, not GUI)
- Container tools in cli (CLI, not desktop)

**Principle**: "Does this require a display server?" determines cli vs desktop

### 7. Darwin Architecture Support (2026-02-08)
**Decision**: Home Manager modules are architecture-agnostic; Darwin system modules implemented per-layer

**Architecture Matrix**:
| System | Architecture | Home Manager | System Modules |
|--------|--------------|--------------|----------------|
| mbp | x86_64-linux (NixOS) | ✅ Uses HM modules | NixOS system-cli |
| potato | aarch64-linux | ✅ Uses HM modules | NixOS system-cli |
| macbook-air | aarch64-darwin | ✅ Uses HM modules | ✅ darwin.system-default |
| Future M4 Mac | aarch64-darwin | ✅ Uses HM modules | ✅ darwin.system-default |
| Future Intel Mac (darwin) | x86_64-darwin | ✅ Uses HM modules | ✅ darwin.system-default |

**Key Insights**:
- Home Manager modules (shell, git, tmux, neovim, claude-code, etc.) work on all architectures
- `homeDirectory` difference handled by `homeBase` option: `/home/tim` (Linux) vs `/Users/tim` (Darwin)
- Darwin system modules implemented: `system-minimal`, `system-default` (see `2-default/default.nix:211-322`)
- Darwin-specific features (Touch ID, Homebrew, system.defaults) configured in host file
- No blockers for adding Apple Silicon hosts; existing modules work unchanged

**Note**: mbp runs NixOS on Intel Mac hardware (not nix-darwin), so it follows NixOS patterns.

### 8. import-tree Conventions (2026-02-08)
**Convention**: Use `/_` prefix to exclude files/directories from auto-import

**Exclusion Rules** (from import-tree):
- `/_hidden.nix` → excluded (underscore after slash)
- `/dir/_local.nix` → excluded
- `/a_b.nix` → INCLUDED (no slash before underscore)

**Usage in this repo**:
- `modules/programs/claude-code/_hm/` - helper modules not auto-imported, explicitly imported by parent
- Use `_` prefix for work-in-progress during migration (remove when ready)

### 9. specialArgs Bridge Pattern (2026-02-08)
**Decision**: `specialArgs`/`extraSpecialArgs` acceptable in configuration creation helpers

The dendritic pattern eliminates `specialArgs` chains in **module files**. However, the bridge
code that creates configurations (in `lib.nix`, `home-configurations.nix`) still uses them
to inject `inputs` into the module evaluation context. This is acceptable and follows the
pattern used by mightyiam/infra and other dendritic implementations.

**Key distinction**:
- ❌ `specialArgs` in **host/feature modules** → anti-pattern, use top-level config access
- ✅ `specialArgs` in **configuration creation helpers** → necessary bridge code

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Breaking existing configs | Parallel structures during migration; keep old until new verified |
| Complex nixvim migration | Migrate as single unit; extensive testing before removal |
| import-tree learning curve | Start with simple modules; document patterns |
| Home-manager standalone breaks | Verify each HM config after changes |
| WSL-specific edge cases | Test on both NixOS-WSL and vanilla Ubuntu |

## Success Criteria

1. **Functional**: All hosts build and deploy correctly
2. **Structure**: Feature-centric organization (no host-centric remnants)
3. **DRY**: No duplicated feature configs across platforms
4. **Maintainable**: Adding new feature = one file in one location
5. **Documented**: Updated ARCHITECTURE.md reflects new patterns

## Resource Requirements

- **Time**: ~2-3 weeks elapsed (at 1 task/session pace)
- **Testing**: Each phase requires validation on at least 2 hosts
- **Rollback**: Git branches allow reverting any phase

## Open Questions

1. Should we add flake-file for distributed inputs? (Decided: No, keep inputs in flake.nix)
2. How to handle 70KB nixvim config? (Decided: Migrated as unit, extraConfigLua split to separate file)
3. Keep existing flake-modules/ during transition? (Yes, remove in Phase 6)
4. Factory pattern for WSL hosts? (TBD: evaluate after user factory works)

## Future Work (Post-Phase 6)

Tasks identified during plan review (2026-02-08) that are **out of scope** for Phase 6 cleanup
but should be addressed in future sessions:

### F1: Username Centralization
**Status**: Low priority - pattern works, just not DRY
**Issue**: `meta.username` option exists in `modules/meta/options.nix` but hosts still hardcode
`username = "tim"` locally (found in 20+ files).
**Action**: Update hosts to use `config.meta.username` instead of local variable.
**Blocked by**: None, can be done anytime after Phase 6.

### F2: Legacy NixOS Modules Cleanup
**Status**: ✅ COMPLETE (Task 6.5, 2026-02-08)
**Resolution**: All 12 legacy modules in `modules/nixos/` deleted - all were superseded by dendritic modules.
`hosts/` directory also deleted; `hardware-config.nix` files moved to `modules/hosts/*/_hardware-config.nix`.

### F3: darwin.system-cli and darwin.system-desktop
**Status**: Low priority - macbook-air only uses system-default currently
**Issue**: Only `darwin.system-minimal` and `darwin.system-default` are implemented.
The higher layers (`system-cli`, `system-desktop`) exist for NixOS but not Darwin.
**Action**: Implement Darwin equivalents when needed for additional Darwin hosts.

### F4: User Factory Pattern
**Status**: Future enhancement - per Open Question #4
**Issue**: Currently each host defines user inline; factory would generate from single definition.
**Action**: Evaluate after basic dendritic migration is complete.

### F5: Files Module Refactoring
**Status**: Low priority - works but anti-pattern
**Issue**: `home/modules/files/default.nix` and `home/files/default.nix` use several anti-patterns:
  - **Exclusion list anti-pattern**: `validatedScriptNames` list (316-339) manually tracks scripts "installed elsewhere". Fragile and easy to forget updating.
  - **Path coupling**: Hardcoded `filesDir = ./../../files` creates tight coupling between module and file location.
  - **Eval-time generation**: Generates bash/zsh completions dynamically by parsing help text at evaluation time. Clever but expensive.
**Recommended approach**:
  - Distribute file ownership to feature modules (each module owns its scripts)
  - Use `inputs.self + "/path"` instead of relative paths
  - Generate completions at build time (derivation) not eval time
  - Central files module becomes a thin coordinator or disappears entirely
**Deferred from**: Task 6.4.10 (2026-02-08)

## Notes

- Plan 018 (modularization) is paused - this plan supersedes its goals
- Reference implementation: `~/src/nix-flake-parts-dendritic-pattern/`
- Community examples: mightyiam/infra, vic/vix, drupol/nixos-x260
