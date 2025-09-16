# flake-modules/home-configurations.nix
# Standalone home-manager configurations
{ inputs, self, withSystem, ... }: {
  flake = {
    # Standalone home-manager configurations
    #
    # These configurations can be applied in two ways:
    #
    # 1. For NixOS systems:
    #    - Primary: These configurations are already integrated into NixOS through
    #      the home-manager.nixosModules.home-manager module in nixos-configurations.nix
    #    - Optional: Can be applied separately with:
    #      nix run home-manager -- switch --flake .#user@hostname
    #    - Benefit: Allows testing home-manager changes without rebuilding the system
    #
    # 2. For non-NixOS systems (Ubuntu, macOS):
    #    - Required: These are the only way to apply home-manager on non-NixOS systems
    #    - Applied with: nix run home-manager -- switch --flake .#user@hostname
    #    - Works on any system with Nix installed (Linux, macOS, WSL)
    #
    # Using standalone configurations for all hosts provides deployment flexibility 
    # and consistent user environments across different systems.
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
            ../home/modules/mcp-servers.nix
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
