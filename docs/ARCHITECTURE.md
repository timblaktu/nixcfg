# NixOS Configuration Architecture

**Date**: 2026-03-19
**Pattern**: Dendritic (flake-parts + import-tree)
**Migration**: Completed from host-centric to feature-centric organization

## Executive Summary

This is a **feature-centric Nix configuration** using the dendritic pattern:

- **~26,000 lines of Nix code** across 98 files
- **Dendritic architecture** with import-tree auto-discovery
- **9 NixOS hosts** (3 WSL, 3 non-WSL dev-team variants, 1 template, 1 ARM SBC, 1 Intel laptop) + 1 Darwin host + 1 vanilla WSL
- **7 home-manager configurations** (standalone approach)
- **23 feature modules** in `modules/programs/`
- **54 exported modules** (16 NixOS + 29 HM + 9 Darwin)
- **4-layer system type hierarchy** for composition
- **Pre-built WSL tarballs** via CI/CD for team distribution

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
├── VERSION                      # Semver source of truth for releases
├── modules/
│   ├── flake-parts/             # Infrastructure (16 modules)
│   │   ├── lib.nix              # mkNixos, mkDarwin, mkHomeManager helpers
│   │   ├── modules.nix          # Enable flake.modules.* infrastructure
│   │   ├── systems.nix          # Supported architectures
│   │   ├── overlays.nix         # Overlay definitions
│   │   ├── packages.nix         # Custom packages
│   │   ├── dev-shells.nix       # Development shells
│   │   ├── templates.nix        # Flake templates
│   │   ├── tests.nix            # Integration and eval tests
│   │   ├── vm-tests.nix         # NixOS VM tests
│   │   ├── version.nix          # VERSION file reader + lint check
│   │   ├── nixos-configurations.nix
│   │   ├── darwin-configurations.nix
│   │   ├── home-configurations.nix
│   │   ├── shared-modules.nix   # Module exports (54 modules)
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
│   │       ├── wsl/             # NixOS WSL base settings
│   │       ├── wsl-enterprise/  # Enterprise WSL base (CrowdStrike, etc.)
│   │       ├── wsl-dev-team/    # Dev team WSL (binfmt, Podman, Claude Code)
│   │       ├── wsl-home/        # HM on vanilla WSL settings
│   │       ├── dev-team/        # Non-WSL dev team (VM, bare metal)
│   │       ├── proxmox/         # Proxmox VE image settings
│   │       └── amazon/          # Amazon EC2 AMI settings
│   │
│   ├── programs/                # Home Manager feature modules (23)
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
│   │   ├── podman/              # Container tools
│   │   ├── windows-terminal/    # Windows Terminal config
│   │   ├── secrets-management/  # SOPS + Bitwarden
│   │   ├── github-auth/         # GitHub authentication
│   │   ├── gitlab-auth/         # GitLab authentication
│   │   ├── git-auth-helpers/    # Git credential helpers
│   │   ├── crowdstrike-falcon/  # CrowdStrike Falcon sensor
│   │   ├── awscli/              # AWS CLI v2
│   │   ├── pulumi/              # Pulumi IaC CLI
│   │   └── files/               # Shared scripts and libs
│   │
│   └── hosts/                   # Host-specific configurations
│       ├── thinky-nixos/        # Primary WSL NixOS dev machine
│       ├── pa161878-nixos [N]/  # Work WSL with CUDA + USB/IP
│       ├── nixos-wsl-dev-team [N]/ # Distributable team WSL image
│       ├── nixos-dev-team [N]/  # Non-WSL dev team (VM, bare metal)
│       ├── nixos-dev-team-ec2 [N]/   # EC2 AMI variant
│       ├── nixos-dev-team-graviton [N]/ # EC2 Graviton (aarch64)
│       ├── nixos-wsl-minimal [N]/ # Minimal WSL template
│       ├── thinky-ubuntu/       # Vanilla Ubuntu WSL (HM only)
│       ├── mbp [N]/             # Intel MacBook Pro (NixOS)
│       ├── potato [N]/          # ARM SBC (Private CA)
│       └── macbook-air [D]/     # Apple Silicon Darwin
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
| Total Nix files | 98 |
| Lines of Nix code | ~26,000 |
| NixOS hosts | 9 active |
| Darwin hosts | 1 |
| Home Manager configs | 7 |
| Feature modules (programs/) | 23 |
| Exported modules total | 54 (16 NixOS + 29 HM + 9 Darwin) |
| System type layers | 4 |
| Flake-parts modules | 16 |

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
| No brackets | Universal | `git/`, `shell/` |

> **Note**: `[nd]` and `[NDnd]` directory suffixes were removed in Plan 026 Task 4.
> Platform scope is now documented in module header comments only.

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

### Exported Modules (54 total)

These are the modules available to external consumers via flake input.
See [SHARED-MODULES.md](SHARED-MODULES.md) for the full catalog with
descriptions and usage examples.

```nix
# NixOS modules (16)
nixosModules = {
  # System type layers
  system-minimal, system-default, system-cli, system-desktop,
  # WSL and enterprise layers
  wsl-base, wsl-enterprise, wsl-dev-team,
  # Non-WSL dev team
  dev-team,
  # Image configs
  proxmox-image-config, amazon-image-config,
  # Feature modules
  crowdstrike-falcon, monitoring, secrets-management, shell, git, tmux, neovim,
};

# Home Manager modules (29)
homeManagerModules = {
  # System type layers
  home-minimal, home-default, home-cli, home-desktop,
  # WSL and enterprise layers
  wsl-home-base, home-enterprise, home-dev-team,
  # Feature modules
  shell, git, tmux, neovim, claude-code, opencode,
  monitoring, development-tools, yazi, terminal, system-tools, shell-utils,
  esp-idf, onedrive, podman, windows-terminal, secrets-management,
  github-auth, gitlab-auth, git-auth-helpers, files, awscli, pulumi,
};

# Darwin modules (9)
darwinModules = {
  system-minimal, system-default, system-cli, system-desktop,
  shell, git, tmux, neovim, secrets-management,
};
```

### Flake Outputs

```nix
{
  nixosConfigurations = {
    thinky-nixos, pa161878-nixos, mbp, potato,
    nixos-wsl-minimal, nixos-wsl-dev-team,
    nixos-dev-team, nixos-dev-team-ec2, nixos-dev-team-graviton,
  };
  darwinConfigurations = { macbook-air };
  homeConfigurations = {
    "tim@thinky-nixos", "tim@pa161878-nixos", "tim@thinky-ubuntu",
    "tim@mbp", "tim@potato", "tim@macbook-air", "tim@nixvim-minimal",
  };

  nixosModules = { ... };           # 16 shared NixOS modules
  homeManagerModules = { ... };     # 29 shared HM modules
  darwinModules = { ... };          # 9 shared Darwin modules

  packages.x86_64-linux = { ... };  # Custom packages
  devShells.x86_64-linux = { default }; # Development shell
  templates = { wsl-nixos, wsl-home, darwin };
  checks.x86_64-linux = { ... };    # Eval, lint, integration, VM tests
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

### Monitoring (modules/programs/monitoring/)

Dual-registered module (HM + NixOS) for system monitoring with a tmux dashboard.

**Home Manager module** (`monitoring.enable`):
- Tier 1 packages: btop, bandwhich, sysstat (iostat/sar), iotop-c, nvtop, below, trippy
- Tier 2 packages (`monitoring.enableTier2`): gping, nload, dool, iftop
- btop configured for build monitoring (gruvbox theme, iowait graphs, 2s interval)
- tmuxp YAML session with 3-4 windows (overview, io, network, +extra if Tier 2)
- `monitor` launcher script: creates or attaches to dashboard tmux session

**NixOS module** (`monitoring.enable`):
- `security.wrappers` for bandwhich (cap_net_admin), iotop-c (cap_sys_ptrace), trippy (cap_net_raw)
- Optional `below` recording daemon (`monitoring.below.enable`, opt-in for WSL2)
- Optional `sysstat` collection timer (`monitoring.sysstat.enable`, opt-in)

```nix
# HM config
monitoring.enable = true;
monitoring.enableTier2 = true;

# NixOS config
monitoring.enable = true;
# monitoring.below.enable = true;   # opt-in: needs cgroupv2 + eBPF
# monitoring.sysstat.enable = true; # opt-in: sadc collection
```

Quick start: run `monitor` to launch the dashboard, or use individual tools directly.

---

## WSL Architecture

### Two WSL Scenarios

1. **NixOS-WSL** (`nixos.wsl-base` + layer modules)
   - Full NixOS distribution in WSL
   - System-level WSL integration (wsl.conf, SSH, SOPS, CUDA, USB/IP)
   - Used by: thinky-nixos, pa161878-nixos, nixos-wsl-dev-team

2. **Home Manager on vanilla WSL** (`homeManager.wsl-home-base` module)
   - Any WSL distro (Ubuntu, Debian, etc.) + Nix + home-manager
   - User-level configuration only
   - Used by: thinky-ubuntu
   - **Best for colleague sharing** - works without NixOS

### WSL Layer Stack

The distributable team image composes layers 0-3:

```
nixos-wsl-dev-team (distributable image host)
├── wsl-dev-team        # L3: binfmt, Podman, Claude Code, USB/IP
│   └── wsl-enterprise  # L2: CrowdStrike (opt-in), enterprise defaults
│       └── system-cli  # L1: dev tools, SSH daemon, containers
│           └── system-default → system-minimal  # L0: Nix, locale, users
│       └── wsl-base    # WSL integration: wsl.conf, SSH, SOPS, CUDA
├── home-dev-team       # HM L3: claude-code, opencode, gitlab-auth, podman
│   └── home-enterprise # HM L2: shell, git, tmux, neovim, yazi, files
│       └── home-cli → home-default → home-minimal  # HM L0-1
│   └── wsl-home-base   # WSL user-level tweaks
└── Generic "dev" user + setup-username script

Personal host (pa161878-nixos) adds:
└── wsl-dev-team (all of the above) + CUDA + ESP-IDF + personal modules
```

### Non-WSL Variant

The `dev-team` NixOS module provides the same dev stack for non-WSL
targets. Host configs exist for bare-metal/VM (`nixos-dev-team`),
Amazon EC2 x86_64 (`nixos-dev-team-ec2`), and EC2 Graviton aarch64
(`nixos-dev-team-graviton`).

### Vanilla WSL Host (e.g., Ubuntu)

```
thinky-ubuntu (HM only, no NixOS)
└── homeManager/wsl-home-base  # WSL user-level tweaks
└── homeManager/shell, git, tmux, neovim, ...  # cherry-picked features
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

| Host | Platform | Arch | System Layer | HM Config | Purpose |
|------|----------|------|--------------|-----------|---------|
| thinky-nixos | NixOS-WSL | x86_64 | system-cli + wsl | tim@thinky-nixos | Primary dev machine |
| pa161878-nixos | NixOS-WSL | x86_64 | wsl-dev-team + CUDA | tim@pa161878-nixos | Work machine |
| nixos-wsl-dev-team | NixOS-WSL | x86_64 | wsl-dev-team | (generic dev) | Distributable image |
| nixos-dev-team | NixOS | x86_64 | dev-team | (generic dev) | VM / bare metal |
| nixos-dev-team-ec2 | NixOS | x86_64 | dev-team + AMI | (generic dev) | Amazon EC2 |
| nixos-dev-team-graviton | NixOS | aarch64 | dev-team + AMI | (generic dev) | EC2 Graviton |
| nixos-wsl-minimal | NixOS-WSL | x86_64 | system-cli + wsl | N/A | Minimal template |
| thinky-ubuntu | Ubuntu WSL | x86_64 | N/A (HM only) | tim@thinky-ubuntu | Vanilla WSL |
| mbp | NixOS bare metal | x86_64 | system-cli | tim@mbp | Intel MacBook Pro |
| potato | NixOS ARM SBC | aarch64 | system-cli | tim@potato | Private CA (Yubikey) |
| macbook-air | nix-darwin | aarch64 | darwin-default | tim@macbook-air | Apple Silicon |

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

## CI/CD and Distribution

The repository includes a full CI/CD pipeline and automated release process.
See [DISTRIBUTION.md](DISTRIBUTION.md) for the layer architecture, release
lifecycle, and consumption options. See [../RELEASE.md](../RELEASE.md) for
the VERSION file design rationale and release mechanics.

The CI pipeline (`ci.yml`) runs on every push to `main` and every PR:
flake evaluation, linting, 26 module isolation evaluations, 14 configuration
evaluations, 23 integration tests, and 3 full tarball builds.

The release pipeline (`release.yml`) triggers when the `VERSION` file changes
on `main`, building and publishing the `nixos-wsl-dev-team` tarball as a
GitHub Release asset alongside `Import-NixOSWSL.ps1`.

## References

- **Dendritic Pattern**: [vic/import-tree](https://github.com/vic/import-tree)
- **flake-parts**: [hercules-ci/flake-parts](https://github.com/hercules-ci/flake-parts)
- **NixOS-WSL**: [nix-community/NixOS-WSL](https://github.com/nix-community/NixOS-WSL)
- **Distribution**: [DISTRIBUTION.md](DISTRIBUTION.md) — layer architecture, release, consumption
- **Module Catalog**: [SHARED-MODULES.md](SHARED-MODULES.md) — 54 exported modules with usage examples
- **Team Quickstart**: [WSL-TEAM-QUICKSTART.md](WSL-TEAM-QUICKSTART.md) — end-user import guide
- **Release Process**: [../RELEASE.md](../RELEASE.md) — versioning and pipeline details
- **CrowdStrike**: [CROWDSTRIKE-WSL2-SECURITY-BRIEF.md](CROWDSTRIKE-WSL2-SECURITY-BRIEF.md) — IT security analysis

---

**Document Version**: 3.0
**Last Updated**: 2026-03-19
**Changes in 3.0**: Updated for distributable images (Plan 023), CI/CD pipeline,
enterprise/dev-team layers, new hosts, expanded module catalog (54 modules),
CrowdStrike integration, and cross-references to distribution documentation.
