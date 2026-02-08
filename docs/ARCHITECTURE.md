# NixOS Configuration Architecture

**Date**: 2026-02-08
**Pattern**: Dendritic (flake-parts + import-tree)
**Migration**: Completed from host-centric to feature-centric organization

## Executive Summary

This is a **feature-centric Nix configuration** using the dendritic pattern:

- **~22,000 lines of Nix code** across 99 files
- **Dendritic architecture** with import-tree auto-discovery
- **5 NixOS hosts** (4 WSL2, 1 ARM SBC) + 1 Darwin host + 1 vanilla WSL
- **6 home-manager configurations** (standalone approach)
- **22 feature modules** in `modules/programs/`
- **4-layer system type hierarchy** for composition

### Key Design Principles

1. **Feature-centric**: One location per feature (git, tmux, neovim), not scattered across hosts
2. **Auto-discovery**: import-tree loads all modules from `modules/` automatically
3. **Composable layers**: Hosts compose from system types (minimal → default → cli → desktop)
4. **Platform indicators**: Bracket notation (`[N]`, `[D]`, `[nd]`) shows platform support
5. **Standalone HM**: Home Manager deployed independently for fast iteration

---

## Repository Structure

```
nixcfg/
├── flake.nix                    # ~50 lines, uses import-tree
├── modules/
│   ├── flake-parts/             # Infrastructure (14 modules)
│   │   ├── lib.nix              # mkNixos, mkDarwin, mkHomeManager helpers
│   │   ├── modules.nix          # Enable flake.modules.* infrastructure
│   │   ├── systems.nix          # Supported architectures
│   │   ├── overlays.nix         # Overlay definitions
│   │   ├── packages.nix         # Custom packages
│   │   ├── dev-shells.nix       # Development shells
│   │   ├── templates.nix        # Flake templates
│   │   ├── tests.nix            # NixOS VM tests
│   │   ├── nixos-configurations.nix
│   │   ├── darwin-configurations.nix
│   │   ├── home-configurations.nix
│   │   ├── shared-modules.nix   # Module exports
│   │   ├── github-actions.nix   # CI workflow generation
│   │   └── termux-outputs.nix   # Android package outputs
│   │
│   ├── meta/
│   │   └── options.nix          # ReadOnly options (username, etc.)
│   │
│   ├── lib/                     # Shared utility libraries
│   │   ├── rbw.nix              # Bitwarden CLI helpers
│   │   ├── git-forge-auth.nix   # GitHub/GitLab auth helpers
│   │   └── shared/              # AI instructions, MCP definitions
│   │
│   ├── system/                  # NixOS system configuration
│   │   ├── types/
│   │   │   ├── 1-minimal/       # Nix settings, GC, store
│   │   │   ├── 2-default/       # + users, locale, SSH client
│   │   │   ├── 3-cli/           # + SSH daemon, dev tools, containers
│   │   │   └── 4-desktop/       # + DE, audio, printing
│   │   └── settings/
│   │       ├── wsl/             # NixOS WSL-specific settings
│   │       └── wsl-home/        # HM on WSL settings
│   │
│   ├── programs/                # Home Manager feature modules (22)
│   │   ├── shell/               # zsh, fish, starship
│   │   ├── git/                 # git, gh, delta
│   │   ├── tmux/                # tmux + plugins
│   │   ├── neovim/              # nixvim configuration
│   │   ├── claude-code/         # Multi-account Claude Code
│   │   ├── opencode/            # OpenCode SDK
│   │   ├── development-tools/   # Languages, formatters
│   │   ├── yazi/                # File manager
│   │   ├── terminal/            # Terminal font setup
│   │   ├── system-tools/        # System admin scripts
│   │   ├── shell-utils/         # Bash libraries
│   │   ├── esp-idf/             # ESP32 development
│   │   ├── onedrive/            # OneDrive utilities
│   │   ├── podman [nd]/         # Container tools
│   │   ├── windows-terminal [nd]/ # Windows Terminal config
│   │   ├── secrets-management/  # SOPS + Bitwarden
│   │   ├── github-auth/         # GitHub authentication
│   │   ├── gitlab-auth [nd]/    # GitLab authentication
│   │   ├── git-auth-helpers [nd]/ # Git credential helpers
│   │   └── files [nd]/          # Shared scripts and libs
│   │
│   └── hosts/                   # Host-specific configurations
│       ├── thinky-nixos/        # Primary WSL NixOS dev machine
│       ├── pa161878-nixos [N]/  # Work WSL with CUDA
│       ├── thinky-ubuntu [nd]/  # Vanilla Ubuntu WSL (HM only)
│       ├── mbp [N]/             # Intel MacBook Pro (NixOS)
│       ├── potato [N]/          # ARM SBC (Private CA)
│       ├── macbook-air [D]/     # Apple Silicon Darwin
│       └── nixos-wsl-minimal [N]/ # Minimal WSL template
│
├── home/
│   └── nixvim-minimal.nix       # Fallback for minimal VMs
│
├── secrets/                     # SOPS-encrypted secrets
├── overlays/                    # Package overlays
├── pkgs/                        # Custom packages
├── templates/                   # Flake templates
└── docs/                        # Documentation
```

### Quantitative Metrics

| Metric | Count |
|--------|-------|
| Total Nix files | 99 |
| Lines of Nix code | ~22,000 |
| NixOS hosts | 5 active |
| Darwin hosts | 1 |
| Home Manager configs | 6 |
| Feature modules | 22 |
| System type layers | 4 |

---

## Architecture Patterns

### 1. Dendritic Module Pattern

Each feature module defines its Home Manager configuration in the `flake.modules.homeManager.*` namespace:

```nix
# modules/programs/git/git.nix
{ config, lib, inputs, ... }:
{
  flake.modules.homeManager.git = { config, lib, pkgs, ... }:
  let
    cfg = config.programs.git;
  in {
    # Override upstream if needed
    disabledModules = [ ];  # Not needed for git

    options.programs.git = {
      # Additional options beyond upstream
    };

    config = lib.mkIf cfg.enable {
      programs.git = {
        enable = true;
        delta.enable = true;
        # ... configuration
      };
    };
  };
}
```

Hosts import these modules:
```nix
# modules/hosts/thinky-nixos/thinky-nixos.nix
flake.modules.homeManager."tim@thinky-nixos" = { inputs, ... }: {
  imports = [
    inputs.self.modules.homeManager.git
    inputs.self.modules.homeManager.tmux
    inputs.self.modules.homeManager.neovim
  ];
};
```

### 2. System Type Layers

NixOS configurations compose from layered system types:

```
4-desktop  ─┬─ DE, audio, bluetooth, printing
3-cli      ─┤─ SSH daemon, dev tools, containers
2-default  ─┤─ Users, locale, SSH client
1-minimal  ─┴─ Nix settings, GC, store
```

Each layer imports its parent:
```nix
# modules/system/types/3-cli/cli.nix
{
  flake.modules.nixos.system-cli = { ... }: {
    imports = [
      inputs.self.modules.nixos.system-default  # Inherits 2-default + 1-minimal
    ];
    # CLI-specific config
  };
}
```

Hosts select their layer:
```nix
# WSL host (no GUI)
imports = [ inputs.self.modules.nixos.system-cli ];

# Desktop host
imports = [ inputs.self.modules.nixos.system-desktop ];
```

### 3. Platform Indicator Brackets

Directory names indicate platform support:

| Notation | Meaning | Example |
|----------|---------|---------|
| `[N]` | NixOS only | `pa161878-nixos [N]/` |
| `[D]` | Darwin only | `macbook-air [D]/` |
| `[nd]` | Home Manager only (NixOS + Darwin) | `thinky-ubuntu [nd]/` |
| `[ND]` | NixOS + Darwin system | (not currently used) |
| `[NDnd]` | All three contexts | (not currently used) |
| No brackets | Universal | `git/`, `shell/` |

### 4. import-tree Auto-Discovery

The flake uses import-tree to auto-load all modules:

```nix
# flake.nix
{
  inputs.import-tree.url = "github:vic/import-tree";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      (inputs.import-tree.lib.importTree [
        ./modules/flake-parts
        ./modules/meta
        ./modules/programs
        ./modules/system
        ./modules/hosts
      ])
    ];
  };
}
```

**Exclusion convention**: Files/directories prefixed with `_` are excluded from auto-import:
- `_hm/` - Sub-modules explicitly imported by parent
- `_hardware-config.nix` - Hardware config explicitly imported

### 5. Standalone Home Manager

All home-manager configurations are deployed independently from NixOS:

```bash
# Deploy user environment (no root needed)
home-manager switch --flake '.#tim@thinky-nixos'

# Deploy system (requires root)
sudo nixos-rebuild switch --flake '.#thinky-nixos'
```

**Benefits**:
- Fast iteration on user environment
- Clear system vs user separation
- Error isolation
- Works on vanilla WSL (thinky-ubuntu)

### 6. Host Composition

Hosts combine system modules + home manager modules:

```nix
# modules/hosts/thinky-nixos/thinky-nixos.nix
{ inputs, ... }:
{
  # NixOS system configuration
  flake.modules.nixos.thinky-nixos = { config, lib, pkgs, ... }: {
    imports = [
      ./_hardware-config.nix
      inputs.self.modules.nixos.system-cli
      inputs.self.modules.nixos.wsl
    ];

    networking.hostName = "thinky-nixos";
    systemDefault.userName = "tim";
  };

  # Home Manager configuration
  flake.modules.homeManager."tim@thinky-nixos" = { inputs, ... }: {
    imports = [
      inputs.self.modules.homeManager.shell
      inputs.self.modules.homeManager.git
      inputs.self.modules.homeManager.tmux
      inputs.self.modules.homeManager.neovim
      inputs.self.modules.homeManager.claude-code
      inputs.self.modules.homeManager.wsl-home
    ];

    programs.claude-code.enable = true;
    programs.opencode.enable = true;
  };
}
```

---

## Module Namespaces

### Flake Module Outputs

```nix
flake.modules = {
  nixos = {
    system-minimal, system-default, system-cli, system-desktop,
    wsl, thinky-nixos, pa161878-nixos, mbp, potato, nixos-wsl-minimal
  };
  darwin = {
    system-minimal, system-default, macbook-air
  };
  homeManager = {
    shell, git, tmux, neovim, claude-code, opencode,
    development-tools, yazi, terminal, system-tools, shell-utils,
    esp-idf, onedrive, podman, windows-terminal, secrets-management,
    github-auth, gitlab-auth, git-auth-helpers, files, wsl-home,
    home-minimal, home-default,
    "tim@thinky-nixos", "tim@pa161878-nixos", "tim@thinky-ubuntu",
    "tim@mbp", "tim@potato", "tim@macbook-air"
  };
};
```

### Flake Outputs

```nix
{
  nixosConfigurations = { thinky-nixos, pa161878-nixos, mbp, potato, nixos-wsl-minimal };
  darwinConfigurations = { macbook-air };
  homeConfigurations = { tim@thinky-nixos, tim@pa161878-nixos, tim@thinky-ubuntu, ... };

  nixosModules = { wsl-base };           # Shared WSL NixOS module
  homeManagerModules = { wsl-home-base }; # Shared WSL HM module

  packages.x86_64-linux = { ... };        # Custom packages
  devShells.x86_64-linux = { default };   # Development shell
  templates = { wsl-nixos, wsl-home, darwin };
  checks.x86_64-linux = { ... };          # NixOS VM tests
}
```

---

## Key Feature Modules

### Claude Code (modules/programs/claude-code/)

Multi-account Claude Code with:
- Account profiles (max, pro, work)
- MCP server integration (Context7, mcp-nixos, sequential-thinking)
- Categorized hooks
- Custom statusline styles
- Sub-agents and slash commands

```nix
programs.claude-code = {
  enable = true;
  accounts = inputs.self.lib.claudeCode.personalAccounts;
  mcp.servers = inputs.self.lib.claudeCode.defaultMcpServers;
  statusline = inputs.self.lib.claudeCode.defaultStatusline;
};
```

### Neovim (modules/programs/neovim/)

Full nixvim configuration (~1,800 LOC):
- LSP for Nix, Python, Rust, Go, TypeScript
- Treesitter syntax highlighting
- Telescope fuzzy finder
- Custom keybindings

### Development Tools (modules/programs/development-tools/)

Languages and tools:
- Go, Rust, Python, Node.js environments
- Enhanced CLI (bat, eza, delta, bottom)
- Claude utilities (pdf2md, claudevloop)

---

## WSL Architecture

### Two WSL Scenarios

1. **NixOS-WSL** (`nixos.wsl` module)
   - Full NixOS distribution in WSL
   - System-level WSL integration
   - Used by: thinky-nixos, pa161878-nixos

2. **Home Manager on vanilla WSL** (`homeManager.wsl-home` module)
   - Any WSL distro (Ubuntu, Debian, etc.) + Nix + home-manager
   - User-level configuration only
   - Used by: thinky-ubuntu
   - **Best for colleague sharing** - works without NixOS

### WSL Module Stack

```
NixOS-WSL Host
├── modules/nixos/system-cli
├── modules/nixos/wsl               # NixOS system WSL config
└── modules/homeManager/wsl-home    # HM WSL config

Vanilla WSL Host (e.g., Ubuntu)
└── modules/homeManager/wsl-home    # HM WSL config only
```

---

## Layer Definitions

### System Layers (NixOS)

| Layer | Includes | Use Case |
|-------|----------|----------|
| 1-minimal | Nix settings, GC, state version | Containers, minimal VMs |
| 2-default | + users, locale, SSH client | Basic interactive systems |
| 3-cli | + SSH daemon, dev tools, containers | Development machines |
| 4-desktop | + DE, audio, bluetooth, printing | Workstations |

### Home Layers

| Layer | Includes | Use Case |
|-------|----------|----------|
| home-minimal | HM basics, genericLinux target | Minimal user environment |
| home-default | + fonts, parallel, base packages | Standard user environment |

---

## Platform Support Matrix

| Host | Platform | Arch | System Layer | HM Config |
|------|----------|------|--------------|-----------|
| thinky-nixos | NixOS-WSL | x86_64 | system-cli + wsl | tim@thinky-nixos |
| pa161878-nixos | NixOS-WSL | x86_64 | system-cli + wsl + cuda | tim@pa161878-nixos |
| thinky-ubuntu | Ubuntu WSL | x86_64 | N/A (HM only) | tim@thinky-ubuntu |
| mbp | NixOS bare metal | x86_64 | system-cli | tim@mbp |
| potato | NixOS ARM SBC | aarch64 | system-cli | tim@potato |
| macbook-air | nix-darwin | aarch64 | darwin-default | tim@macbook-air |

---

## Development Workflow

### Common Commands

```bash
# Validate flake
nix flake check --no-build

# Deploy home environment
home-manager switch --flake '.#tim@thinky-nixos'

# Deploy system (NixOS)
sudo nixos-rebuild switch --flake '.#thinky-nixos'

# Deploy system (Darwin)
darwin-rebuild switch --flake '.#macbook-air'

# Format Nix files
nixpkgs-fmt modules/

# Enter dev shell
nix develop
```

### Adding a New Feature Module

1. Create `modules/programs/my-feature/my-feature.nix`:
```nix
{ config, lib, inputs, ... }:
{
  flake.modules.homeManager.my-feature = { config, lib, pkgs, ... }: {
    options.programs.my-feature = {
      enable = lib.mkEnableOption "My feature";
    };

    config = lib.mkIf config.programs.my-feature.enable {
      home.packages = [ pkgs.my-package ];
    };
  };
}
```

2. import-tree auto-discovers it

3. Add to hosts:
```nix
imports = [ inputs.self.modules.homeManager.my-feature ];
programs.my-feature.enable = true;
```

### Adding a New Host

1. Create `modules/hosts/my-host/my-host.nix`:
```nix
{ inputs, ... }:
{
  flake.modules.nixos.my-host = { ... }: {
    imports = [
      ./_hardware-config.nix
      inputs.self.modules.nixos.system-cli
    ];
    networking.hostName = "my-host";
  };

  flake.modules.homeManager."tim@my-host" = { inputs, ... }: {
    imports = [
      inputs.self.modules.homeManager.shell
      inputs.self.modules.homeManager.git
    ];
  };
}
```

2. Add to `modules/flake-parts/nixos-configurations.nix`:
```nix
flake.nixosConfigurations.my-host = mkNixos "x86_64-linux" "my-host";
```

---

## Best Practices

### Module Organization

✅ One feature per directory (`git/`, `tmux/`, not `development.nix`)
✅ Use bracket notation for platform support
✅ Use `_` prefix for sub-modules not auto-imported
✅ Keep hardware config in `_hardware-config.nix`

### Composition

✅ Hosts import system type layers, not individual settings
✅ Features enable via `programs.<name>.enable = true`
✅ Use lib presets for DRY configuration (e.g., `lib.claudeCode.personalAccounts`)

### Testing

✅ `nix flake check --no-build` before commits
✅ `home-manager switch --dry-run` to preview changes
✅ VM tests in `modules/flake-parts/tests.nix`

---

## Migration History

- **2025-12**: Initial flake-parts migration from monolithic flake.nix
- **2026-02-07**: Started Plan 019 dendritic migration
- **2026-02-08**: Completed migration to feature-centric organization
  - Removed `hosts/`, `flake-modules/`, `home/modules/`, `home/common/`
  - All content moved to `modules/` hierarchy
  - 22 feature modules in `modules/programs/`
  - 4 system type layers in `modules/system/types/`
  - 7 host configurations in `modules/hosts/`

---

## References

- **Dendritic Pattern**: [vic/import-tree](https://github.com/vic/import-tree)
- **flake-parts**: [hercules-ci/flake-parts](https://github.com/hercules-ci/flake-parts)
- **NixOS-WSL**: [nix-community/NixOS-WSL](https://github.com/nix-community/NixOS-WSL)
- **Plan 019**: `.claude/user-plans/019-dendritic-migration.md`

---

**Document Version**: 2.0
**Last Updated**: 2026-02-08
**Changes in 2.0**: Complete rewrite for dendritic pattern migration (Plan 019)
