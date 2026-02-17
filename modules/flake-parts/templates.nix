# modules/flake-parts/templates.nix
# Flake templates for easy colleague onboarding
_: {
  flake = {
    templates = {
      # WSL NixOS template - Full NixOS-WSL distribution
      wsl-nixos = {
        path = ../../templates/wsl-nixos;
        description = "NixOS-WSL configuration using shared wsl-base module";
        welcomeText = ''
          # WSL NixOS Template

          This template provides a NixOS-WSL configuration with shared modules.

          ## Next steps:
          1. Edit flake.nix and customize wslCommon settings
          2. Change 'myuser' to your actual username
          3. Run: sudo nixos-rebuild switch --flake .#my-wsl

          See README.md for detailed instructions.
        '';
      };

      # WSL Home Manager template - Works on ANY WSL distro
      wsl-home = {
        path = ../../templates/wsl-home;
        description = "Portable home-manager configuration for any WSL distribution";
        welcomeText = ''
          # WSL Home Manager Template

          This template works on ANY WSL distribution (Ubuntu, Debian, Alpine, etc.)

          ## Next steps:
          1. Edit flake.nix and change 'myuser' to your username
          2. Update homeDirectory to match your home directory
          3. Run: home-manager switch --flake .#myuser@my-wsl

          See README.md for detailed instructions.
        '';
      };

      # macOS template - nix-darwin + home-manager
      darwin = {
        path = ../../templates/darwin;
        description = "macOS configuration using nix-darwin and home-manager";
        welcomeText = ''
          # macOS (nix-darwin) Template

          This template provides a macOS configuration with nix-darwin.

          ## Next steps:
          1. Edit flake.nix and customize system settings
          2. Change 'myuser' to your actual username
          3. Update 'system' to match your hardware (x86_64-darwin or aarch64-darwin)
          4. First time: nix run nix-darwin -- switch --flake .#my-mac
          5. After that: darwin-rebuild switch --flake .#my-mac

          See README.md for detailed instructions.
        '';
      };
    };
  };
}
