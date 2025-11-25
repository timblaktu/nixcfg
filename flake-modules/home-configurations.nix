# flake-modules/home-configurations.nix
# Standalone-only home-manager configurations
{ inputs, self, withSystem, ... }: {
  flake = {
    # Standalone-only home-manager configurations
    #
    # These configurations provide user environments independent of system configuration.
    # Applied with: home-manager switch --flake .#user@hostname
    # Works on any system with Nix installed (NixOS, Ubuntu, macOS, WSL)
    #
    # Benefits of standalone-only approach:
    # - Fast iteration on user environment changes
    # - Clear separation of system vs user concerns
    # - Error isolation between system and user environments
    # - User autonomy (no root required for user changes)
    homeConfigurations = {
      "tim@mbp" = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../home/modules/base.nix
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
              };
            }
            # ../home/migration/darwin-home-files.nix # macOS-specific unified files configuration - DISABLED after module-based migration
            ../home/modules/mcp-servers.nix
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "mbp";
          };
        }
      );

      "tim@thinky-ubuntu" = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../home/modules/base.nix
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
                environmentVariables = {
                  WSL_DISTRO = "ubuntu";
                  EDITOR = "nvim";
                };
                shellAliases = {
                  explorer = "explorer.exe .";
                };
              };
              targets.wsl = {
                enable = true;
                windowsTools = {
                  enablePowerShell = true;
                  enableCmd = false;
                  enableWslPath = true;
                  wslPathPath = "/bin/wslpath";
                };
              };
            }
            ../hosts/thinky-ubuntu
            # ../home/migration/wsl-home-files.nix # WSL-specific unified files configuration - DISABLED after module-based migration
            ../home/modules/mcp-servers.nix
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "thinky-ubuntu";
          };
        }
      );

      "tim@pa161878-nixos" = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../home/modules/base.nix
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
                enableDevelopment = true;
                enableEspIdf = true;
                enableOneDriveUtils = true;
                enableShellUtils = true;
                enableTerminal = true;
                environmentVariables = {
                  WSL_DISTRO = "nixos";
                  EDITOR = "nvim";
                };
                shellAliases = {
                  explorer = "explorer.exe .";
                  code = "code.exe";
                  code-insiders = "code-insiders.exe";
                  esp32c5 = "esp-idf-shell";
                };
              };
              home.packages = with pkgs; [
                wslu
              ];
              secretsManagement.rbw.email = "timblaktu@gmail.com";
              targets.wsl = {
                enable = true;
                windowsTools = {
                  enablePowerShell = true;
                  enableCmd = false;
                  enableWslPath = true;
                  wslPathPath = "/bin/wslpath";
                };

                # Windows Terminal settings management
                windowsTerminal = {
                  enable = true;
                  colorSchemes = [{
                    name = "Solarized Dark (Correct)";
                    background = "#002b36";
                    foreground = "#839496";
                    black = "#073642";
                    red = "#dc322f";
                    green = "#859900";
                    yellow = "#b58900";
                    blue = "#268bd2";
                    purple = "#d33682";
                    cyan = "#2aa198";
                    white = "#eee8d5";
                    brightBlack = "#002b36";
                    brightRed = "#cb4b16";
                    brightGreen = "#586e75";
                    brightYellow = "#657b83";
                    brightBlue = "#839496";
                    brightPurple = "#6c71c4";
                    brightCyan = "#93a1a1";
                    brightWhite = "#fdf6e3";
                  }];
                  defaultColorScheme = "Solarized Dark (Correct)";
                  font = {
                    face = "CaskaydiaMono Nerd Font Mono, Noto Color Emoji";
                    size = 11;
                  };
                };
              };
            }
            ../home/modules/mcp-servers.nix
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "pa161878-nixos";
          };
        }
      );

      "tim@thinky-nixos" = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../home/modules/base.nix
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
                enableDevelopment = true;
                enableEspIdf = true;
                enableOneDriveUtils = true;
                enableShellUtils = true;
                enableTerminal = true;
                environmentVariables = {
                  WSL_DISTRO = "nixos";
                  EDITOR = "nvim";
                };
                shellAliases = {
                  explorer = "explorer.exe .";
                  code = "code.exe";
                  code-insiders = "code-insiders.exe";
                  esp32c5 = "esp-idf-shell";
                };
              };
              home.packages = with pkgs; [
                wslu
              ];
              secretsManagement.rbw.email = "timblaktu@gmail.com";
              targets.wsl = {
                enable = true;
                windowsTools = {
                  enablePowerShell = true;
                  enableCmd = false;
                  enableWslPath = true;
                  wslPathPath = "/bin/wslpath";
                };
              };
            }
            # ../home/migration/wsl-home-files.nix # WSL-specific unified files configuration - DISABLED after module-based migration
            ../home/modules/mcp-servers.nix
            # ../home/modules/autovalidate-demo.nix  # Disabled - requires home-manager autoValidate integration
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "thinky-nixos";
          };
        }
      );

      # tim@tblack-t14-nixos configuration archived (work laptop no longer in use)
      # See hosts/archived/tblack-t14-nixos/ for reference

      "tim@nixvim-minimal" = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            {
              nixpkgs.config.allowUnfree = true;
              home = {
                username = "tim";
                homeDirectory = "/home/tim";
                stateVersion = "24.11";
              };
              nix = {
                package = pkgs.nix;
                settings = {
                  experimental-features = [ "nix-command" "flakes" ];
                };
              };
              programs.home-manager.enable = true;
              targets.genericLinux.enable = true;
            }
            ../home/nixvim-minimal.nix
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "nixvim-minimal";
          };
        }
      );

      # tim@tblack-t14-ubuntu configuration archived (work laptop no longer in use)
      # See hosts/archived/ for reference

      "tim@potato" = withSystem "aarch64-linux" ({ pkgs, ... }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../home/modules/base.nix
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
                environmentVariables = {
                  EDITOR = "nvim";
                };
              };
            }
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "potato";
          };
        }
      );
    };
  };
}
