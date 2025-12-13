{
  description = "macOS Configuration Template (nix-darwin + home-manager)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Optional: Import shared modules from nixcfg
    # nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { self, nixpkgs, darwin, home-manager, ... }: {
    darwinConfigurations.my-mac = darwin.lib.darwinSystem {
      system = "x86_64-darwin"; # or "aarch64-darwin" for Apple Silicon
      modules = [
        {
          # System configuration
          system.stateVersion = 4;

          # User configuration
          users.users.myuser = {
            name = "myuser"; # Change this to your username
            home = "/Users/myuser"; # Change this to match your username
          };

          # Allow unfree packages
          nixpkgs.config.allowUnfree = true;

          # Enable Nix daemon
          services.nix-daemon.enable = true;

          # Nix settings
          nix = {
            settings = {
              experimental-features = "nix-command flakes";
              max-jobs = 8;
            };
          };

          # System packages
          environment.systemPackages = with nixpkgs.legacyPackages.${system}; [
            vim
            git
            wget
            curl
          ];

          # macOS system defaults
          system.defaults = {
            dock = {
              autohide = true;
              orientation = "bottom";
              show-recents = false;
            };

            finder = {
              AppleShowAllExtensions = true;
              FXEnableExtensionChangeWarning = false;
              ShowPathbar = true;
            };

            NSGlobalDomain = {
              AppleShowAllExtensions = true;
              InitialKeyRepeat = 15;
              KeyRepeat = 2;
            };
          };
        }

        # Home Manager integration
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.myuser = { pkgs, ... }: {
            home.stateVersion = "24.11";

            # User packages
            home.packages = with pkgs; [
              ripgrep
              fd
              fzf
              htop
              jq
            ];

            # Git configuration
            programs.git = {
              enable = true;
              userName = "Your Name";
              userEmail = "your-email@example.com";
            };

            # Zsh configuration
            programs.zsh = {
              enable = true;
              enableCompletion = true;
              syntaxHighlighting.enable = true;
            };
          };
        }
      ];
    };
  };
}
