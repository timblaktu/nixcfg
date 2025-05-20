# Unified Nix Configuration

This repository contains my unified Nix configurations for multiple systems:

- NixOS (x86_64, ARM)
- macOS with nix-darwin
- Linux with Home Manager

## Repository Structure

```
nixcfg/
├── flake.nix          # Main entry point
├── flake.lock         # Lock file
├── shell.nix          # For nix-shell fallback
├── .gitignore         # Typical files to ignore
├── README.md          # Documentation
├── hosts/             # Host-specific configurations
│   ├── common/        # Common configuration shared across NixOS hosts
│   ├── mbp/           # MacBook Pro configuration
│   ├── potato/        # ARM device configuration
│   └── thinky-nixos/  # WSL configuration
├── home/              # Home-manager configurations
│   ├── common/        # Common home-manager configurations
│   └── profiles/      # Specific profiles for different usage scenarios
├── modules/           # Custom NixOS and Home-manager modules
├── pkgs/              # Custom packages
├── overlays/          # Nixpkgs overlays
└── secrets/           # For sensitive configuration (with age/sops-nix)
```

## Usage

### NixOS Systems

```bash
sudo nixos-rebuild switch --flake .#hostname
```

### Home Manager (Standalone)

```bash
home-manager switch --flake .#username@hostname
```

### MacOS (Darwin)

```bash
darwin-rebuild switch --flake .#hostname
```

## Development

To enter a development environment with required tools:

```bash
nix develop
```
