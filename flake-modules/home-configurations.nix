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
            self.modules.homeManager.shell # Dendritic pattern shell module
            self.modules.homeManager.git # Dendritic pattern git module
            self.modules.homeManager.tmux # Dendritic pattern tmux module
            self.modules.homeManager.neovim # Dendritic pattern neovim/nixvim module
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
              };

              # Enable tmux auto-reload on home-manager generation change
              programs.tmux.autoReload.enable = true;

              # Secrets management
              secretsManagement = {
                enable = true;
                rbw.email = "timblaktu@gmail.com";
              };

              # GitHub authentication
              gitAuth.github = {
                enable = true;
                mode = "bitwarden";
                bitwarden = {
                  item = "github.com";
                  field = "PAT-timtam2026";
                };
                cli.tokenOverrides.pr = {
                  item = "github.com";
                  field = "PAT-pubclassic";
                };
              };
            }
            # ../home/migration/darwin-home-files.nix # macOS-specific unified files configuration - DISABLED after module-based migration
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "mbp";
          };
        }
      );

      "tim@thinky-ubuntu" = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.home-manager-wsl.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../home/modules/base.nix
            self.modules.homeManager.shell # Dendritic pattern shell module
            self.modules.homeManager.git # Dendritic pattern git module
            self.modules.homeManager.tmux # Dendritic pattern tmux module
            self.modules.homeManager.neovim # Dendritic pattern neovim/nixvim module
            self.modules.homeManager.wsl-home # Dendritic pattern WSL home module
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
              };

              # WSL home settings
              wsl-home-settings = {
                distroName = "ubuntu";
              };

              # Enable tmux auto-reload on home-manager generation change
              programs.tmux.autoReload.enable = true;

              # Secrets management
              secretsManagement = {
                enable = true;
                rbw.email = "timblaktu@gmail.com";
              };

              # GitHub authentication
              gitAuth.github = {
                enable = true;
                mode = "bitwarden";
                bitwarden = {
                  item = "github.com";
                  field = "PAT-timtam2026";
                };
                cli.tokenOverrides.pr = {
                  item = "github.com";
                  field = "PAT-pubclassic";
                };
              };
            }
            ../hosts/thinky-ubuntu
            # ../home/migration/wsl-home-files.nix # WSL-specific unified files configuration - DISABLED after module-based migration
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "thinky-ubuntu";
          };
        }
      );

      "tim@pa161878-nixos" = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.home-manager-wsl.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../home/modules/base.nix
            self.modules.homeManager.shell # Dendritic pattern shell module
            self.modules.homeManager.git # Dendritic pattern git module
            self.modules.homeManager.tmux # Dendritic pattern tmux module
            self.modules.homeManager.neovim # Dendritic pattern neovim/nixvim module
            self.modules.homeManager.wsl-home # Dendritic pattern WSL home module
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
              };

              # WSL home settings (defaults from wsl-home module)
              wsl-home-settings = {
                distroName = "nixos";
              };

              # Enable tmux auto-reload on home-manager generation change
              programs.tmux.autoReload.enable = true;

              # Secrets management (HOST-SPECIFIC)
              secretsManagement = {
                enable = true;
                rbw.email = "timblaktu@gmail.com";
              };

              # GitHub authentication (HOST-SPECIFIC)
              gitAuth.github = {
                enable = true;
                mode = "bitwarden";
                bitwarden = {
                  item = "github.com";
                  field = "PAT-timtam2026";
                };
                cli.tokenOverrides.pr = {
                  item = "github.com";
                  field = "PAT-pubclassic";
                };
              };

              # GitLab authentication (HOST-SPECIFIC)
              gitAuth.gitlab = {
                enable = true;
                mode = "bitwarden";
                host = "git.panasonic.aero";
                bitwarden = {
                  item = "GitLab git.panasonic.aero";
                  field = "lord (access token)";
                };
                cli.enable = true;
              };

              # Windows Terminal settings management (HOST-SPECIFIC)
              windowsTerminal = {
                enable = true;
                font = {
                  face = "CaskaydiaMono NFM, Noto Color Emoji";
                  size = 12;
                };
                keybindings = [
                  { id = "Terminal.CopyToClipboard"; keys = "ctrl+shift+c"; }
                  { id = "Terminal.PasteFromClipboard"; keys = "ctrl+shift+v"; }
                  { id = "Terminal.DuplicatePaneAuto"; keys = "alt+shift+d"; }
                  { id = "Terminal.NextTab"; keys = "alt+ctrl+l"; }
                  { id = "Terminal.PrevTab"; keys = "alt+ctrl+h"; }
                ];
              };
            }
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "pa161878-nixos";
          };
        }
      );

      "tim@thinky-nixos" = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.home-manager-wsl.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            ../home/modules/base.nix
            self.modules.homeManager.shell # Dendritic pattern shell module
            self.modules.homeManager.git # Dendritic pattern git module
            self.modules.homeManager.tmux # Dendritic pattern tmux module
            self.modules.homeManager.neovim # Dendritic pattern neovim/nixvim module
            self.modules.homeManager.wsl-home # Dendritic pattern WSL home module
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
              };

              # WSL home settings (defaults from wsl-home module)
              wsl-home-settings = {
                distroName = "nixos";
              };

              # Enable tmux auto-reload on home-manager generation change
              programs.tmux.autoReload.enable = true;

              # Secrets management
              secretsManagement = {
                enable = true;
                rbw.email = "timblaktu@gmail.com";
              };

              # GitHub authentication
              gitAuth.github = {
                enable = true;
                mode = "bitwarden";
                bitwarden = {
                  item = "github.com";
                  field = "PAT-timtam2026";
                };
                cli.tokenOverrides.pr = {
                  item = "github.com";
                  field = "PAT-pubclassic";
                };
              };
            }
            # ../home/migration/wsl-home-files.nix # WSL-specific unified files configuration - DISABLED after module-based migration
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
            self.modules.homeManager.shell # Dendritic pattern shell module
            self.modules.homeManager.git # Dendritic pattern git module
            self.modules.homeManager.tmux # Dendritic pattern tmux module
            {
              homeBase = {
                username = "tim";
                homeDirectory = "/home/tim";
                environmentVariables = {
                  EDITOR = "nvim";
                };
              };

              # Enable tmux auto-reload on home-manager generation change
              programs.tmux.autoReload.enable = true;

              # Secrets management
              secretsManagement = {
                enable = true;
                rbw.email = "timblaktu@gmail.com";
              };

              # GitHub authentication
              gitAuth.github = {
                enable = true;
                mode = "bitwarden";
                bitwarden = {
                  item = "github.com";
                  field = "PAT-timtam2026";
                };
                cli.tokenOverrides.pr = {
                  item = "github.com";
                  field = "PAT-pubclassic";
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
