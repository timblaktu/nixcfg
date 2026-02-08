# Plan 019: Migrate nixcfg to Dendritic Pattern

**Created**: 2026-02-07
**Status**: IN_PROGRESS
**Branch**: `refactor/modularization` (existing, Plan 018 paused)
**Replaces**: Plan 018 (modularization) - same goal, new approach

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
| 0.1 | Add import-tree to flake inputs | COMPLETE |
| 0.2 | Create `modules/flake-parts/modules.nix` (enable flake.modules.*) | COMPLETE |
| 0.3 | Create `modules/flake-parts/lib.nix` (mkNixos, mkHomeManager helpers) | COMPLETE |
| 0.4 | Create `modules/meta/options.nix` (username as readOnly option) | COMPLETE |
| 0.5 | Create `modules/flake-parts/systems.nix` (supported architectures) | COMPLETE |
| 0.6 | Verify `nix flake check` passes with new structure | COMPLETE |

**Definition of Done**:
- import-tree loads all modules from `modules/`
- `flake.modules.{nixos,darwin,homeManager}` namespace available
- Existing flake-modules/ still work (parallel structure)
- No build breakage

### Phase 1: First Feature Migration (Shell)
**Goal**: Prove pattern works with representative feature

| Task | Description | Status |
|------|-------------|--------|
| 1.1 | Create `modules/programs/shell [NDnd]/shell.nix` | COMPLETE |
| 1.2 | Migrate zsh config from `home/common/zsh.nix` | COMPLETE (included in 1.1) |
| 1.3 | Migrate fish config (if any) | N/A (no fish config exists) |
| 1.4 | Migrate starship config | N/A (no starship config exists) |
| 1.5 | Test on thinky-nixos (NixOS + HM) | COMPLETE |
| 1.6 | Test on thinky-ubuntu (HM only) | COMPLETE (wired in, dry-run verified) |
| 1.7 | Remove old shell configs after verification | COMPLETE |

**Definition of Done**:
- Shell works identically on all hosts
- Single source of truth in `modules/programs/shell/`
- Old files removed

### Phase 2: System Types Layer
**Goal**: Establish composition hierarchy

| Task | Description | Status |
|------|-------------|--------|
| 2.1 | Create `modules/system/types/1-minimal/` | COMPLETE |
| 2.2 | Create `modules/system/types/2-default/` | COMPLETE |
| 2.3 | Create `modules/system/types/3-cli/` | COMPLETE |
| 2.4 | Create `modules/system/types/4-desktop/` | COMPLETE |
| 2.5 | Migrate `modules/base.nix` → system types | COMPLETE |
| 2.6 | Migrate `home/modules/base.nix` → system types | COMPLETE |

**Definition of Done**:
- Hosts import system-type, not individual modules
- Clear layering: minimal → default → cli → desktop
- Base modules deprecated

### Phase 3: Feature Migrations (Core)
**Goal**: Migrate high-value features

| Task | Description | Priority | Status |
|------|-------------|----------|--------|
| 3.1 | git [NDnd] | High | COMPLETE |
| 3.2 | ssh [NDnd] | High | PARTIAL (integrated into system types) |
| 3.3 | tmux [NDnd] | High | COMPLETE |
| 3.4 | neovim [NDnd] (1871 LOC) | High | COMPLETE |
| 3.5 | wsl [N] system settings | High | COMPLETE |
| 3.6 | wsl-home [nd] user settings | High | COMPLETE |

### Phase 4: Feature Migrations (Tools)
**Goal**: Migrate development tools

| Task | Description | Priority | Status |
|------|-------------|----------|--------|
| 4.1 | claude-code [nd] | High | COMPLETE |
| 4.2 | opencode [nd] | High | COMPLETE |
| 4.3 | secrets-management [NDnd] | Medium | COMPLETE |
| 4.4 | github-auth [nd] | Medium | COMPLETE |
| 4.5 | gitlab-auth [nd] | Medium | COMPLETE |
| 4.6 | development tools [nd] | Medium | COMPLETE |

### Phase 5: Host Compositions
**Goal**: Migrate all hosts to new structure

| Task | Description | Status |
|------|-------------|--------|
| 5.1 | thinky-nixos (WSL primary) | COMPLETE |
| 5.2 | pa161878-nixos (WSL work) | COMPLETE |
| 5.3 | thinky-ubuntu (HM only) | COMPLETE |
| 5.4 | mbp (Intel Mac running NixOS) | COMPLETE |
| 5.5 | potato (ARM SBC) | PENDING |
| 5.6 | macbook-air (Apple Silicon) | PENDING |
| 5.7 | nixos-wsl-minimal (template) | PENDING |

### Phase 6: Cleanup
**Goal**: Remove deprecated structure

| Task | Description | Status |
|------|-------------|--------|
| 6.1 | Remove `flake-modules/` (replaced by import-tree) | PENDING |
| 6.2 | Remove `hosts/common/` | PENDING |
| 6.3 | Remove `home/common/` | PENDING |
| 6.4 | Remove `home/modules/` | PENDING |
| 6.5 | Remove `modules/` (old NixOS modules) | PENDING |
| 6.6 | Update ARCHITECTURE.md | PENDING |
| 6.7 | Update CLAUDE.md with new patterns | PENDING |

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
**Decision**: Home Manager modules are architecture-agnostic; Darwin system modules need separate implementation

**Architecture Matrix**:
| System | Architecture | Home Manager | System Modules |
|--------|--------------|--------------|----------------|
| mbp | x86_64-linux (NixOS) | ✅ Uses HM modules | NixOS system-cli |
| potato | aarch64-linux | ✅ Uses HM modules | NixOS system-cli |
| macbook-air | aarch64-darwin | ✅ Uses HM modules | Needs darwin modules |
| Future M4 Mac | aarch64-darwin | ✅ Uses HM modules | Needs darwin modules |
| Future Intel Mac (darwin) | x86_64-darwin | ✅ Uses HM modules | Needs darwin modules |

**Key Insights**:
- Home Manager modules (shell, git, tmux, neovim, claude-code, etc.) work on all architectures
- `homeDirectory` difference handled by `homeBase` option: `/home/tim` (Linux) vs `/Users/tim` (Darwin)
- Darwin system modules (`flake.modules.darwin.*`) are empty - need implementation for Task 5.6
- No blockers for adding Apple Silicon hosts; existing HM modules work unchanged
- Darwin-specific features (Touch ID, Homebrew, system.defaults) go in darwin system modules

**Note**: mbp runs NixOS on Intel Mac hardware (not nix-darwin), so it follows NixOS patterns.

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

## Notes

- Plan 018 (modularization) is paused - this plan supersedes its goals
- Reference implementation: `~/src/nix-flake-parts-dendritic-pattern/`
- Community examples: mightyiam/infra, vic/vix, drupol/nixos-x260
