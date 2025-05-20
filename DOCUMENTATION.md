# NixCfg - Unified Nix Configuration

This repository contains a unified Nix configuration for multiple systems, including NixOS, macOS with nix-darwin, and standalone home-manager setups.

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
# First time setup
sudo nixos-rebuild switch --flake .#hostname

# Subsequent updates
sudo nixos-rebuild switch
```

### Home Manager (Standalone)

```bash
# First time setup
home-manager switch --flake .#username@hostname

# Subsequent updates
home-manager switch
```

### MacOS (Darwin)

```bash
# First time setup
darwin-rebuild switch --flake .#hostname

# Subsequent updates
darwin-rebuild switch
```

## Adding a New Host

1. Create a new directory under `hosts/` with your hostname
2. Add hardware-configuration.nix (generate with `nixos-generate-config`)
3. Create a default.nix with host-specific configuration
4. Add the host to flake.nix nixosConfigurations or darwinConfigurations
5. For secrets, generate an age key and add to .sops.yaml

## Adding a New User Profile

1. Create a new file under `home/profiles/`
2. Import common modules as needed
3. Configure user-specific packages and settings
4. Add profile to `homeConfigurations` in flake.nix

## Secret Management

This repo uses [sops-nix](https://github.com/Mic92/sops-nix) for secret management.

1. Generate a key with `age-keygen -o ~/.config/sops/age/keys.txt`
2. Add the public key to `.sops.yaml`
3. Create encrypted secrets with `sops secrets/common/mysecret.yaml`
4. Reference secrets in your configuration with `sops.secrets.<name>`

## Development

Enter a development shell with required tools:

```bash
nix develop
```

## License

MIT
