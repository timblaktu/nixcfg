# flake-modules/shared-modules.nix
# Exports reusable NixOS and Home Manager modules for sharing with colleagues
{ inputs, self, ... }: {
  flake = {
    # NixOS modules for system-level configuration
    nixosModules = {
      # Common WSL system configuration base
      # Platform: NixOS-WSL distribution ONLY
      # Provides: System-level WSL integration (wsl.conf, users, SSH daemon, SOPS)
      # Usage: Import in WSL NixOS host configs
      wsl-base = import ../hosts/common/wsl-base.nix;

      # Centralized SSH authorized keys
      # Provides: Shared SSH public keys for user access
      # Usage: Import and reference in user configuration
      ssh-keys = import ../hosts/common/ssh-keys.nix;
    };

    # Home Manager modules for user-level configuration
    homeManagerModules = {
      # Common WSL home-manager configuration
      # Platform: ANY WSL distro + Nix + home-manager ✅
      # Provides: User-level WSL tweaks (shell, Windows Terminal, wslu)
      # Works on: NixOS-WSL AND vanilla Ubuntu/Debian/Alpine WSL
      # Usage: Import in WSL home-manager configs
      wsl-home-base = import ../home/common/wsl-home-base.nix;
    };
  };
}
