{
  description = "WSL Home Manager Configuration Template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Import shared WSL home-manager modules from nixcfg
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { self, nixpkgs, home-manager, nixcfg, ... }: {
    homeConfigurations."myuser@my-wsl" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };

      modules = [
        nixcfg.homeManagerModules.wsl-home-base # Common WSL user configuration
        {
          # User information (REQUIRED)
          homeBase = {
            username = "myuser"; # Change this to your username
            homeDirectory = "/home/myuser"; # Change this to match your username
          };

          # WSL integration
          targets.wsl = {
            enable = true;
            windowsTools = {
              enablePowerShell = true;
              enableCmd = false;
              enableWslPath = true;
            };
          };

          # Optional: Windows Terminal settings management
          windowsTerminal = {
            enable = true;
            font = {
              face = "CaskaydiaMono NFM, Noto Color Emoji";
              size = 12;
            };
            keybindings = [
              { id = "Terminal.CopyToClipboard"; keys = "ctrl+shift+c"; }
              { id = "Terminal.PasteFromClipboard"; keys = "ctrl+shift+v"; }
            ];
          };
        }
      ];
    };
  };
}
