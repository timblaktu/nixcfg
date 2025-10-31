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
                windowsUsername = "timbl";
                windowsTools = {
                  enablePowerShell = true;
                  enableCmd = false;
                  enableWslPath = true;
                  wslPathPath = "/bin/wslpath";
                };
                bindMountRoot.enable = true;
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
              targets.wsl = {
                enable = true;
                windowsUsername = "timbl";
                windowsTools = {
                  enablePowerShell = true;
                  enableCmd = false;
                  enableWslPath = true;
                  wslPathPath = "/bin/wslpath";
                };
                # Disable bind mount - handled by NixOS-WSL module
                bindMountRoot.enable = false;
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
