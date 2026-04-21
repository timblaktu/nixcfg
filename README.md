# nixcfg

Modular Nix configurations for NixOS, macOS, and WSL, built with
[flake-parts](https://flake.parts) and
[import-tree](https://github.com/vic/import-tree) for automatic module
discovery. The repository produces **pre-built NixOS-WSL images** for team
onboarding and exports **54 reusable modules** (NixOS, Home Manager, Darwin)
that can be composed into any Nix configuration via flake input.

## Who This Is For

| Audience | Start Here |
|----------|------------|
| **Team member** wanting a ready-to-use WSL dev environment | [WSL-TEAM-QUICKSTART.md](docs/WSL-TEAM-QUICKSTART.md) |
| **IT / Security** reviewing what ships in the image | [DISTRIBUTION.md](docs/DISTRIBUTION.md), [CrowdStrike WSL2 Security Brief](docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md) |
| **Nix user** wanting to consume modules in their own flake | [SHARED-MODULES.md](docs/SHARED-MODULES.md) |
| **Contributor** wanting to understand the codebase | [ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| **Maintainer** making a release | [RELEASE.md](RELEASE.md) |

## Repository Structure

```
nixcfg/
├── flake.nix                    # Entry point (~50 lines, uses import-tree)
├── VERSION                      # Semver source of truth for releases
├── modules/
│   ├── flake-parts/             # Flake infrastructure (16 modules)
│   ├── meta/                    # ReadOnly options (username, etc.)
│   ├── lib/                     # Shared utility libraries
│   ├── system/
│   │   ├── types/               # 4-layer hierarchy (minimal → default → cli → desktop)
│   │   └── settings/            # Platform settings (wsl, wsl-enterprise, wsl-dev-team, ...)
│   ├── programs/                # 23 Home Manager feature modules
│   └── hosts/                   # 11 host configurations
├── pkgs/                        # Custom packages
├── overlays/                    # Nixpkgs overlays
├── templates/                   # Flake templates (wsl-nixos, wsl-home, darwin)
├── secrets/                     # SOPS-encrypted secrets (age)
└── docs/                        # Documentation
```

## Configurations

### NixOS Systems

| Host | Purpose | Arch |
|------|---------|------|
| `thinky-nixos` | Primary WSL dev machine | x86_64 |
| `nixos-wsl-dev-team` | Distributable team WSL image | x86_64 |
| `nixos-dev-team` | Non-WSL dev team (VM, bare metal) | x86_64 |
| `nixos-dev-team-ec2` | EC2 AMI variant | x86_64 |
| `nixos-dev-team-graviton` | EC2 Graviton variant | aarch64 |
| `nixos-wsl-minimal` | Minimal WSL template | x86_64 |
| `potato` | ARM SBC (Private CA) | aarch64 |
| `mbp` | Intel MacBook Pro | x86_64 |

### Home Manager

| Config | Platform |
|--------|----------|
| `tim@thinky-nixos` | NixOS-WSL |
| `tim@thinky-ubuntu` | Ubuntu WSL (HM only) |
| `tim@mbp` | NixOS bare metal |
| `tim@potato` | NixOS ARM |
| `tim@macbook-air` | macOS (Darwin) |
| `tim@nixvim-minimal` | Portable neovim |

### Darwin

| Host | Purpose |
|------|---------|
| `macbook-air` | Apple Silicon macOS |

## Common Commands

```bash
# Validate flake (quick, no builds)
nix flake check --no-build

# Deploy system
sudo nixos-rebuild switch --flake ".#$(hostname)"

# Deploy user environment
home-manager switch --flake ".#${USER}@$(hostname)"

# Deploy macOS
darwin-rebuild switch --flake '.#macbook-air'

# Enter dev shell
nix develop

# Format Nix files
nixpkgs-fmt modules/
```

## Distribution

The `nixos-wsl-dev-team` host produces a `.wsl` tarball containing a
complete NixOS development environment. The release pipeline builds the
tarball automatically and publishes it as a GitHub Release asset alongside
an `Import-NixOSWSL.ps1` script that handles import and Windows Terminal
setup.

See [DISTRIBUTION.md](docs/DISTRIBUTION.md) for the full lifecycle:
layer architecture, CI/CD pipeline, consumption options, and tarball
contents.

## CI/CD

Every push to `main` and every PR runs the full validation pipeline:

- Flake evaluation and metadata checks
- Linting (nixpkgs-fmt, statix, deadnix, PS1 encoding, version format)
- 20 Home Manager module isolation evaluations
- 6 NixOS module isolation evaluations
- 14 full configuration evaluations
- 23 integration tests (tarball dry-runs, image outputs, service checks)
- 3 full tarball builds (retained as artifacts for 5 days)

Releases are triggered by updating the `VERSION` file on `main`. See
[RELEASE.md](RELEASE.md) for the process.

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Codebase structure, design patterns, module system |
| [DISTRIBUTION.md](docs/DISTRIBUTION.md) | How images are built, released, and consumed |
| [WSL-TEAM-QUICKSTART.md](docs/WSL-TEAM-QUICKSTART.md) | End-user import guide (no Nix knowledge needed) |
| [SHARED-MODULES.md](docs/SHARED-MODULES.md) | Exported module catalog with usage examples |
| [RELEASE.md](RELEASE.md) | Versioning policy and release pipeline |
| [TESTS.md](TESTS.md) | Test infrastructure and execution |
| [CrowdStrike WSL2 Brief](docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md) | Security posture analysis for IT review |

## Secrets Management

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix)
using age encryption. See `secrets/` for encrypted files and
`secrets/README.md` for setup instructions.

## Platform Support

- **x86_64-linux**: NixOS, NixOS-WSL, Ubuntu WSL (HM only)
- **aarch64-linux**: NixOS ARM (potato), EC2 Graviton
- **x86_64-darwin**: Intel macOS
- **aarch64-darwin**: Apple Silicon macOS
