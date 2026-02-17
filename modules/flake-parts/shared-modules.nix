# modules/flake-parts/shared-modules.nix
# Exports reusable NixOS and Home Manager modules for sharing with colleagues
{ inputs, self, ... }: {
  flake = {
    # NixOS modules for system-level configuration
    nixosModules = {
      # Common WSL system configuration base (dendritic pattern)
      # Platform: NixOS-WSL distribution ONLY
      # Provides: System-level WSL integration (wsl.conf, users, SSH daemon, SOPS, USBIP)
      # Usage: Import in WSL NixOS host configs
      # Options: wsl-settings.{hostname, defaultUser, sshPort, usbip, cuda, ...}
      #
      # Example:
      #   imports = [ nixcfg.nixosModules.wsl-base ];
      #   wsl-settings = {
      #     hostname = "my-wsl";
      #     defaultUser = "myuser";
      #     sshPort = 2222;
      #   };
      wsl-base = self.modules.nixos.wsl;

      # Enterprise WSL base (dendritic pattern)
      # Platform: NixOS-WSL distribution ONLY
      # Provides: system-cli + WSL integration + enterprise defaults (CrowdStrike stub, welcome message)
      # Usage: Import in team modules or directly in WSL NixOS host configs
      # Options: enterprise.{crowdStrike, welcomeMessage} + wsl-settings.*
      wsl-enterprise = self.modules.nixos.wsl-enterprise;

      # Tiger team WSL layer (dendritic pattern)
      # Platform: NixOS-WSL distribution ONLY
      # Provides: wsl-enterprise + binfmt + Podman + Claude Code enterprise + setup-username
      # Usage: Import in tiger team host configs
      wsl-tiger-team = self.modules.nixos.wsl-tiger-team;
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
