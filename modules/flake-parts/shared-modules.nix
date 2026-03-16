# modules/flake-parts/shared-modules.nix
# Exports reusable NixOS, Home Manager, and Darwin modules for team consumption.
#
# Teammates consume these via flake input:
#   inputs.nixcfg.url = "github:timblaktu/nixcfg";
#
# Then import specific modules:
#   imports = [ inputs.nixcfg.nixosModules.wsl-dev-team ];
#   imports = [ inputs.nixcfg.homeManagerModules.home-dev-team ];
#
# Or cherry-pick individual feature modules:
#   imports = [ inputs.nixcfg.homeManagerModules.shell ];
#
# Module naming convention:
#   Export names match internal flake.modules.* registration names.
#   Bundles: wsl-enterprise, home-dev-team, system-cli, etc.
#   Features: shell, git, tmux, claude-code, etc.
{ inputs, self, ... }: {
  flake = {

    # =========================================================================
    # NixOS Modules (system-level configuration)
    # =========================================================================
    nixosModules = {

      # --- System Type Layers (hierarchical: minimal -> default -> cli -> desktop) ---

      # Base system layer: Nix settings, locale, timezone, core packages
      inherit (self.modules.nixos) system-minimal;

      # Default system layer: Users, networking, fonts, SSH client
      # Imports: system-minimal
      inherit (self.modules.nixos) system-default;

      # CLI system layer: Dev tools, shell config, tmux, neovim system-level
      # Imports: system-default
      inherit (self.modules.nixos) system-cli;

      # Desktop system layer: GUI, display manager, desktop environment
      # Imports: system-cli
      inherit (self.modules.nixos) system-desktop;

      # --- WSL System Settings ---

      # Common WSL system configuration base
      # Provides: wsl.conf, users, SSH daemon, SOPS, USBIP, CUDA
      # Options: wsl-settings.{hostname, defaultUser, sshPort, usbip, cuda, ...}
      wsl-base = self.modules.nixos.wsl;

      # Enterprise WSL base (system-cli + WSL + CrowdStrike + enterprise defaults)
      # Options: enterprise.{welcomeMessage, terminal.*} + wsl-settings.*
      inherit (self.modules.nixos) wsl-enterprise;

      # Dev team WSL layer (enterprise + binfmt + Podman + Claude Code + USBIP)
      inherit (self.modules.nixos) wsl-dev-team;

      # --- Platform-Agnostic Dev Team Base ---

      # Dev team base (system-cli + binfmt + Podman + Claude Code + usbutils/kmod)
      # Use this for non-WSL dev team hosts (VM, Proxmox, bare metal)
      inherit (self.modules.nixos) dev-team;

      # --- Feature Modules (NixOS) ---

      # CrowdStrike Falcon sensor (systemd service + FHS-wrapped .deb package)
      # Note: On WSL2 kernel, sensor enters Reduced Functionality Mode (RFM)
      inherit (self.modules.nixos) crowdstrike-falcon;

      # Secrets management (sops-nix integration, Bitwarden helpers)
      inherit (self.modules.nixos) secrets-management;

      # Shell configuration (system-level zsh/bash setup)
      inherit (self.modules.nixos) shell;

      # Git configuration (system-level gitconfig)
      inherit (self.modules.nixos) git;

      # Tmux configuration (system-level)
      inherit (self.modules.nixos) tmux;

      # Neovim/Nixvim configuration (system-level)
      inherit (self.modules.nixos) neovim;
    };

    # =========================================================================
    # Home Manager Modules (user-level configuration)
    # =========================================================================
    homeManagerModules = {

      # --- System Type Layers (HM counterparts) ---

      # Minimal HM layer: username, homeDirectory, stateVersion
      inherit (self.modules.homeManager) home-minimal;

      # Default HM layer: XDG, fonts, basic programs
      # Imports: home-minimal
      inherit (self.modules.homeManager) home-default;

      # CLI HM layer: Full CLI tooling bundle
      # Imports: home-default
      inherit (self.modules.homeManager) home-cli;

      # Desktop HM layer: GUI applications
      # Imports: home-cli
      inherit (self.modules.homeManager) home-desktop;

      # --- WSL / Enterprise / Team Bundles ---

      # WSL user-level tweaks (works on ANY WSL distro + Nix + home-manager)
      # Options: wsl-home-settings.{distroName, enableWindowsAliases, ...}
      wsl-home-base = self.modules.homeManager.wsl-home;

      # Enterprise HM bundle (shell, git, tmux, neovim, yazi, files, onedrive, ...)
      inherit (self.modules.homeManager) home-enterprise;

      # Dev team HM bundle (enterprise + claude-code, opencode, gitlab-auth, podman, ...)
      inherit (self.modules.homeManager) home-dev-team;

      # --- Feature Modules (Home Manager) ---

      # Shell (zsh/bash config, starship prompt, direnv, fzf)
      inherit (self.modules.homeManager) shell;

      # Git (user-level gitconfig, aliases, delta pager)
      inherit (self.modules.homeManager) git;

      # Tmux (config, plugins, auto-reload)
      inherit (self.modules.homeManager) tmux;

      # Neovim/Nixvim (plugins, LSP, keybindings)
      inherit (self.modules.homeManager) neovim;

      # Terminal (font detection, TERM config)
      inherit (self.modules.homeManager) terminal;

      # Shell utilities (custom shell functions and libraries)
      inherit (self.modules.homeManager) shell-utils;

      # System tools (bootstrap, admin utilities)
      inherit (self.modules.homeManager) system-tools;

      # Yazi (terminal file manager)
      inherit (self.modules.homeManager) yazi;

      # OneDrive utilities for WSL
      inherit (self.modules.homeManager) onedrive;

      # Files management (scripts, completions, autoWriter integration)
      inherit (self.modules.homeManager) files;

      # Git auth helpers (credential refresh utilities)
      inherit (self.modules.homeManager) git-auth-helpers;

      # Claude Code (multi-account AI coding assistant)
      inherit (self.modules.homeManager) claude-code;

      # OpenCode (multi-account AI coding assistant)
      inherit (self.modules.homeManager) opencode;

      # GitLab authentication (CLI + credential helpers + Bitwarden/SOPS)
      inherit (self.modules.homeManager) gitlab-auth;

      # GitHub authentication (CLI + credential helpers + Bitwarden/SOPS)
      inherit (self.modules.homeManager) github-auth;

      # Podman container tools (podman-tui, compose, docker aliases)
      inherit (self.modules.homeManager) podman;

      # Development tools (Python, Rust, Node, Go toolchains)
      inherit (self.modules.homeManager) development-tools;

      # Windows Terminal settings management for WSL
      inherit (self.modules.homeManager) windows-terminal;

      # AWS CLI v2 with Azure AD SSO support
      inherit (self.modules.homeManager) awscli;

      # Pulumi infrastructure-as-code CLI
      inherit (self.modules.homeManager) pulumi;

      # ESP-IDF embedded development environment
      inherit (self.modules.homeManager) esp-idf;

      # Secrets management (Bitwarden CLI, rbw helpers)
      inherit (self.modules.homeManager) secrets-management;
    };

    # =========================================================================
    # Darwin Modules (macOS system-level configuration)
    # =========================================================================
    darwinModules = {

      # System type layers
      inherit (self.modules.darwin) system-minimal;
      inherit (self.modules.darwin) system-default;
      inherit (self.modules.darwin) system-cli;
      inherit (self.modules.darwin) system-desktop;

      # Feature modules with Darwin support
      inherit (self.modules.darwin) shell;
      inherit (self.modules.darwin) git;
      inherit (self.modules.darwin) tmux;
      inherit (self.modules.darwin) neovim;
      inherit (self.modules.darwin) secrets-management;
    };
  };
}
