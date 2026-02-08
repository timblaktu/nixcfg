# modules/flake-parts/shared-modules.nix
# Exports reusable NixOS and Home Manager modules for sharing with colleagues
{ inputs, self, ... }: {
  flake = {
    # NixOS modules for system-level configuration
    nixosModules = {
      # Common WSL system configuration base
      # Platform: NixOS-WSL distribution ONLY
      # Provides: System-level WSL integration (wsl.conf, users, SSH daemon, SOPS)
      # Usage: Import in WSL NixOS host configs
      wsl-base = import ../nixos/wsl-base.nix;

      # NOTE: SSH keys are available as data in modules/ssh-keys-data.nix
      # (not a module, just an attribute set for use in host configurations)
    };

    # Home Manager modules for user-level configuration
    homeManagerModules = {
      # Common WSL home-manager configuration (dendritic pattern)
      # Platform: ANY WSL distro + Nix + home-manager
      # Provides: User-level WSL tweaks (shell, Windows Terminal, wslu)
      # Works on: NixOS-WSL AND vanilla Ubuntu/Debian/Alpine WSL
      # Usage: Import in WSL home-manager configs
      # Options: wsl-home-settings.{distroName, enableWindowsAliases, ...}
      wsl-home-base = self.modules.homeManager.wsl-home;
    };
  };
}
