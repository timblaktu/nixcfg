# Shared NixOS, Home Manager, and Darwin Modules

This repository exports reusable modules for team consumption via flake input.

**Repository**: <https://github.com/timblaktu/nixcfg>

## Quick Start

```nix
{
  inputs.nixcfg.url = "github:timblaktu/nixcfg";

  outputs = { nixpkgs, nixcfg, ... }: {
    # Use a bundle (includes many feature modules):
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      modules = [ nixcfg.nixosModules.wsl-dev-team ];
    };

    # Or cherry-pick individual modules:
    homeConfigurations."me@host" = home-manager.lib.homeManagerConfiguration {
      modules = [
        nixcfg.homeManagerModules.shell
        nixcfg.homeManagerModules.git
        nixcfg.homeManagerModules.tmux
      ];
    };
  };
}
```

All options use `lib.mkDefault` — override freely in your config.

---

## NixOS Modules (16)

### System Type Layers

Hierarchical layers — each imports the one above it.

| Export Name | Description |
|-------------|-------------|
| `system-minimal` | Nix settings, locale, timezone, core packages |
| `system-default` | Users, networking, fonts, SSH client (imports system-minimal) |
| `system-cli` | Dev tools, shell, tmux, neovim system-level (imports system-default) |
| `system-desktop` | GUI, display manager, desktop environment (imports system-cli) |

### WSL System Settings

| Export Name | Description |
|-------------|-------------|
| `wsl-base` | Common WSL config: wsl.conf, users, SSH daemon, SOPS, USBIP, CUDA |
| `wsl-enterprise` | Enterprise WSL base: system-cli + WSL + CrowdStrike + enterprise defaults |
| `wsl-dev-team` | Dev team WSL: enterprise + binfmt + Podman + Claude Code + USBIP |

### Platform-Agnostic

| Export Name | Description |
|-------------|-------------|
| `dev-team` | Dev team base for non-WSL hosts (VM, Proxmox, bare metal): system-cli + binfmt + Podman |

### Image Configuration

| Export Name | Description |
|-------------|-------------|
| `proxmox-image-config` | Proxmox VE image defaults (UEFI, cloud-init, guest agent) |
| `amazon-image-config` | Amazon EC2 AMI defaults (raw format, 6 GiB disk) |

### Feature Modules (NixOS)

| Export Name | Description |
|-------------|-------------|
| `crowdstrike-falcon` | CrowdStrike Falcon sensor (systemd service + FHS-wrapped .deb). WSL2: [RFM only](CROWDSTRIKE-WSL2-SECURITY-BRIEF.md) |
| `secrets-management` | SOPS-nix integration, Bitwarden helpers |
| `shell` | System-level zsh/bash setup |
| `git` | System-level gitconfig |
| `tmux` | System-level tmux config |
| `neovim` | Nixvim system-level setup |

---

## Home Manager Modules (29)

### System Type Layers

| Export Name | Description |
|-------------|-------------|
| `home-minimal` | Username, homeDirectory, stateVersion |
| `home-default` | XDG, fonts, basic programs (imports home-minimal) |
| `home-cli` | Full CLI tooling bundle (imports home-default) |
| `home-desktop` | GUI applications (imports home-cli) |

### WSL / Enterprise / Team Bundles

| Export Name | Description |
|-------------|-------------|
| `wsl-home-base` | WSL user-level tweaks. Works on **any** WSL distro (Ubuntu, Debian, Alpine, NixOS) |
| `home-enterprise` | Enterprise bundle: shell, git, tmux, neovim, yazi, files, onedrive |
| `home-dev-team` | Dev team bundle: enterprise + claude-code, opencode, gitlab-auth, podman |

### Feature Modules (Home Manager)

| Export Name | Description |
|-------------|-------------|
| `shell` | zsh/bash config, starship prompt, direnv, fzf |
| `git` | User-level gitconfig, aliases, delta pager |
| `tmux` | Config, plugins, auto-reload |
| `neovim` | Nixvim plugins, LSP, keybindings |
| `terminal` | Font detection, TERM config |
| `shell-utils` | Custom shell functions and libraries |
| `system-tools` | Bootstrap, admin utilities |
| `yazi` | Terminal file manager |
| `onedrive` | OneDrive utilities for WSL |
| `files` | Scripts, completions, autoWriter integration |
| `git-auth-helpers` | Credential refresh utilities |
| `claude-code` | Multi-account AI coding assistant |
| `opencode` | Multi-account AI coding assistant |
| `gitlab-auth` | CLI + credential helpers + Bitwarden/SOPS |
| `github-auth` | CLI + credential helpers + Bitwarden/SOPS |
| `podman` | Podman container tools (compose, docker aliases) |
| `development-tools` | Python, Rust, Node, Go toolchains |
| `windows-terminal` | Windows Terminal settings management for WSL |
| `awscli` | AWS CLI v2 with Azure AD SSO support |
| `pulumi` | Pulumi infrastructure-as-code CLI |
| `esp-idf` | ESP-IDF embedded development environment |
| `secrets-management` | Bitwarden CLI, rbw helpers |

---

## Darwin Modules (9)

For macOS hosts via nix-darwin.

### System Type Layers

| Export Name | Description |
|-------------|-------------|
| `system-minimal` | Nix settings, locale, core packages |
| `system-default` | Users, networking, fonts |
| `system-cli` | Dev tools, shell, tmux, neovim |
| `system-desktop` | GUI, desktop environment |

### Feature Modules (Darwin)

| Export Name | Description |
|-------------|-------------|
| `shell` | zsh/bash setup |
| `git` | gitconfig |
| `tmux` | tmux config |
| `neovim` | Nixvim setup |
| `secrets-management` | SOPS/Bitwarden integration |

---

## Platform Compatibility

| Module Type | NixOS | NixOS-WSL | Ubuntu/Debian WSL | macOS |
|-------------|-------|-----------|-------------------|-------|
| `nixosModules.*` | Yes | Yes | No | No |
| `homeManagerModules.*` | Yes | Yes | Yes (with Nix + HM) | Yes |
| `darwinModules.*` | No | No | No | Yes |

**Key insight**: Home Manager modules work on any platform with Nix + home-manager
installed. NixOS modules require a NixOS system. Darwin modules require nix-darwin.

---

## Usage Examples

### Dev Team WSL Image (Turnkey)

Use the pre-built NixOS-WSL bundles for a complete setup:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    home-manager.url = "github:nix-community/home-manager";
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { nixpkgs, nixos-wsl, home-manager, nixcfg, ... }: {
    nixosConfigurations.my-wsl = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        nixcfg.nixosModules.wsl-dev-team
        {
          systemDefault.userName = "myuser";
          wsl-settings.hostname = "my-wsl";
        }
      ];
    };

    homeConfigurations."myuser@my-wsl" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      modules = [
        nixcfg.homeManagerModules.home-dev-team
        {
          home = {
            username = "myuser";
            homeDirectory = "/home/myuser";
          };
        }
      ];
    };
  };
}
```

### Vanilla WSL (Ubuntu/Debian) with Home Manager Only

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { nixpkgs, home-manager, nixcfg, ... }: {
    homeConfigurations."me@ubuntu-wsl" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      modules = [
        nixcfg.homeManagerModules.wsl-home-base
        nixcfg.homeManagerModules.shell
        nixcfg.homeManagerModules.git
        nixcfg.homeManagerModules.tmux
        nixcfg.homeManagerModules.neovim
        {
          home = {
            username = "me";
            homeDirectory = "/home/me";
          };
        }
      ];
    };
  };
}
```

### Cherry-Pick for Non-WSL NixOS

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { nixpkgs, nixcfg, ... }: {
    nixosConfigurations.my-server = nixpkgs.lib.nixosSystem {
      modules = [
        nixcfg.nixosModules.system-cli
        nixcfg.nixosModules.secrets-management
      ];
    };
  };
}
```

### Proxmox VM Image

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { nixpkgs, nixcfg, ... }: {
    nixosConfigurations.my-vm = nixpkgs.lib.nixosSystem {
      modules = [
        nixcfg.nixosModules.dev-team
        nixcfg.nixosModules.proxmox-image-config
      ];
    };
  };
}
```

---

## Bundle Composition

Bundles compose feature modules for convenience. You can use a bundle and override
any option, or skip bundles and cherry-pick features directly.

```
NixOS bundles:
  wsl-dev-team  ->  wsl-enterprise  ->  system-cli  ->  system-default  ->  system-minimal
                                    +   wsl-base
                +   binfmt, podman, claude-code, usbip

  dev-team      ->  system-cli + binfmt + podman + claude-code + usbutils/kmod

HM bundles:
  home-dev-team ->  home-enterprise  ->  home-cli  ->  home-default  ->  home-minimal
                +   claude-code, opencode, gitlab-auth, podman
```

---

## Distribution

**Pre-built WSL image**: Download from [GitHub Releases](https://github.com/timblaktu/nixcfg/releases/latest).
See [WSL-TEAM-QUICKSTART.md](WSL-TEAM-QUICKSTART.md) for import instructions.

**Flake input**: `inputs.nixcfg.url = "github:timblaktu/nixcfg";`

---

**Last Updated**: 2026-03-18
