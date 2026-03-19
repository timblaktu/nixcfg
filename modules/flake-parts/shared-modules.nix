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

      # --- Image Configuration Modules (for image.modules framework) ---

      # Proxmox VE image defaults (UEFI, cloud-init, guest agent)
      # Use as: image.modules.proxmox = { imports = [ inputs.nixcfg.nixosModules.proxmox-image-config ]; };
      inherit (self.modules.nixos) proxmox-image-config;

      # Amazon EC2 AMI defaults (raw format for coldsnap, 6 GiB disk)
      # Use as: image.modules.amazon = { imports = [ inputs.nixcfg.nixosModules.amazon-image-config ]; };
      inherit (self.modules.nixos) amazon-image-config;

      # --- Feature Modules (NixOS) ---
      # crowdstrike-falcon: CrowdStrike Falcon sensor (WSL2: RFM mode)
      # secrets-management: sops-nix integration, Bitwarden helpers
      # shell/git/tmux/neovim: System-level configuration
      inherit (self.modules.nixos)
        crowdstrike-falcon
        secrets-management
        shell
        git
        tmux
        neovim
        ;
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
      inherit (self.modules.homeManager)
        shell# zsh/bash config, starship prompt, direnv, fzf
        git# user-level gitconfig, aliases, delta pager
        tmux# config, plugins, auto-reload
        neovim# Nixvim plugins, LSP, keybindings
        terminal# font detection, TERM config
        shell-utils# custom shell functions and libraries
        system-tools# bootstrap, admin utilities
        yazi# terminal file manager
        onedrive# OneDrive utilities for WSL
        files# scripts, completions, autoWriter integration
        git-auth-helpers# credential refresh utilities
        claude-code# multi-account AI coding assistant
        opencode# multi-account AI coding assistant
        gitlab-auth# GitLab CLI + credential helpers + Bitwarden/SOPS
        github-auth# GitHub CLI + credential helpers + Bitwarden/SOPS
        podman# container tools (podman-tui, compose, docker aliases)
        development-tools# Python, Rust, Node, Go toolchains
        windows-terminal# Windows Terminal settings management for WSL
        awscli# AWS CLI v2 with Azure AD SSO support
        pulumi# Pulumi infrastructure-as-code CLI
        esp-idf# ESP-IDF embedded development environment
        secrets-management# Bitwarden CLI, rbw helpers
        ;
    };

    # =========================================================================
    # Darwin Modules (macOS system-level configuration)
    # =========================================================================
    darwinModules = {

      # System type layers + feature modules with Darwin support
      inherit (self.modules.darwin)
        system-minimal
        system-default
        system-cli
        system-desktop
        shell
        git
        tmux
        neovim
        secrets-management
        ;
    };
  };
}
