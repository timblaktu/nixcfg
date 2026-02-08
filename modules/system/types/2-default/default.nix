# modules/system/types/2-default/default.nix
# Default system configuration layer [ND]
#
# Provides:
#   flake.modules.nixos.system-default - NixOS with user management + integrations
#   flake.modules.darwin.system-default - Darwin with user management + integrations
#
# This layer IMPORTS system-minimal and adds:
#   - User creation with configurable options
#   - Locale and timezone settings
#   - Home Manager integration (optional)
#   - SOPS-nix secrets management (optional)
#   - SSH daemon configuration
#   - Console configuration
#
# Does NOT include:
#   - SSH keys or authorized_keys (managed per-host or via SOPS)
#   - Desktop environments (4-desktop)
#   - Advanced CLI tools (3-cli)
#
# Usage in host config:
#   imports = [ inputs.self.modules.nixos.system-default ];
#   systemDefault = {
#     userName = "myuser";
#     timeZone = "America/New_York";
#   };
#
# Or compose with higher layers:
#   imports = [ inputs.self.modules.nixos.system-cli ];  # inherits default
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === NixOS Default Module ===
    nixos.system-default = { config, lib, pkgs, ... }:
      let
        cfg = config.systemDefault;
      in
      {
        imports = [
          # Import minimal layer
          inputs.self.modules.nixos.system-minimal
        ];

        options.systemDefault = {
          # User configuration
          userName = lib.mkOption {
            type = lib.types.str;
            description = "Primary user name (required)";
            example = "tim";
          };

          userGroups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "wheel" "networkmanager" "audio" "video" ];
            description = "Groups for the primary user";
          };

          userShell = lib.mkOption {
            type = lib.types.package;
            default = pkgs.zsh;
            description = "Default shell for the primary user";
          };

          userPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Packages installed for the primary user";
          };

          # Locale and timezone
          timeZone = lib.mkOption {
            type = lib.types.str;
            default = "America/Los_Angeles";
            description = "System time zone";
          };

          locale = lib.mkOption {
            type = lib.types.str;
            default = "en_US.UTF-8";
            description = "System locale";
          };

          # Console configuration
          consoleFont = lib.mkOption {
            type = lib.types.str;
            default = "Lat2-Terminus16";
            description = "Console font";
          };

          consoleKeyMap = lib.mkOption {
            type = lib.types.str;
            default = "us";
            description = "Console keymap";
          };

          # SSH configuration
          sshEnable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable SSH daemon";
          };

          sshPasswordAuth = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Allow SSH password authentication";
          };

          sshRootLogin = lib.mkOption {
            type = lib.types.enum [ "no" "yes" "prohibit-password" "forced-commands-only" ];
            default = "no";
            description = "SSH root login policy";
          };

          # Security
          wheelNeedsPassword = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Require password for sudo";
          };

          # Integration options
          enableHomeManager = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Enable Home Manager NixOS module integration.
              When true, imports home-manager.nixosModules.home-manager.
              You must still configure home-manager.users.<name> separately.
            '';
          };

          enableSops = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Enable SOPS-nix for secrets management.
              When true, imports sops-nix.nixosModules.sops.
              You must configure sops.defaultSopsFile and secrets separately.
            '';
          };

          # System packages beyond minimal
          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional system packages";
          };
        };

        config = lib.mkMerge [
          # Core configuration
          {
            # Assertions
            assertions = [
              {
                assertion = cfg.userName != "";
                message = "systemDefault.userName must be set";
              }
            ];

            # Locale and timezone
            time.timeZone = lib.mkDefault cfg.timeZone;
            i18n.defaultLocale = lib.mkDefault cfg.locale;

            # Console
            console = {
              font = lib.mkDefault cfg.consoleFont;
              keyMap = lib.mkDefault cfg.consoleKeyMap;
            };

            # User creation
            users.users.${cfg.userName} = {
              isNormalUser = lib.mkDefault true;
              extraGroups = lib.mkDefault cfg.userGroups;
              shell = lib.mkDefault cfg.userShell;
              packages = lib.mkDefault cfg.userPackages;
            };

            # Add user to trusted-users
            nix.settings.trusted-users = [ cfg.userName ];

            # Default shell program
            programs.zsh.enable = lib.mkDefault (cfg.userShell == pkgs.zsh);

            # Security
            security.sudo.wheelNeedsPassword = lib.mkDefault cfg.wheelNeedsPassword;

            # System packages - common utilities
            environment.systemPackages = with pkgs; [
              wget
              curl
              htop
              tmux
              ripgrep
              fd
              home-manager
            ] ++ cfg.additionalPackages;

            # Shell aliases
            environment.shellAliases = {
              ll = "ls -la";
              update = "sudo nixos-rebuild switch";
              upgrade = "sudo nixos-rebuild switch --upgrade";
            };
          }

          # SSH configuration
          (lib.mkIf cfg.sshEnable {
            services.openssh = {
              enable = true;
              settings = {
                PermitRootLogin = lib.mkDefault cfg.sshRootLogin;
                PasswordAuthentication = lib.mkDefault cfg.sshPasswordAuth;
              };
            };
          })

          # Home Manager integration
          (lib.mkIf cfg.enableHomeManager {
            imports = [ inputs.home-manager.nixosModules.home-manager ];

            home-manager = {
              useGlobalPkgs = lib.mkDefault true;
              useUserPackages = lib.mkDefault true;
            };
          })

          # SOPS integration
          (lib.mkIf cfg.enableSops {
            imports = [ inputs.sops-nix.nixosModules.sops ];
          })
        ];
      };

    # === Darwin Default Module ===
    darwin.system-default = { config, lib, pkgs, ... }:
      let
        cfg = config.systemDefault;
      in
      {
        imports = [
          # Import minimal layer
          inputs.self.modules.darwin.system-minimal
        ];

        options.systemDefault = {
          # User configuration
          userName = lib.mkOption {
            type = lib.types.str;
            description = "Primary user name (required)";
            example = "tim";
          };

          userShell = lib.mkOption {
            type = lib.types.package;
            default = pkgs.zsh;
            description = "Default shell for the primary user";
          };

          userPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Packages installed for the primary user";
          };

          # Locale and timezone
          timeZone = lib.mkOption {
            type = lib.types.str;
            default = "America/Los_Angeles";
            description = "System time zone";
          };

          # Integration options
          enableHomeManager = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Enable Home Manager Darwin module integration.
              When true, imports home-manager.darwinModules.home-manager.
              You must still configure home-manager.users.<name> separately.
            '';
          };

          enableSops = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Enable SOPS-nix for secrets management.
              When true, imports sops-nix.darwinModules.sops.
              You must configure sops.defaultSopsFile and secrets separately.
            '';
          };

          # System packages beyond minimal
          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional system packages";
          };
        };

        config = lib.mkMerge [
          # Core configuration
          {
            # Assertions
            assertions = [
              {
                assertion = cfg.userName != "";
                message = "systemDefault.userName must be set";
              }
            ];

            # Timezone
            time.timeZone = lib.mkDefault cfg.timeZone;

            # User creation - Darwin uses users.users differently
            users.users.${cfg.userName} = {
              home = "/Users/${cfg.userName}";
              shell = lib.mkDefault cfg.userShell;
              packages = lib.mkDefault cfg.userPackages;
            };

            # Add user to trusted-users
            nix.settings.trusted-users = [ cfg.userName ];

            # System packages - common utilities
            environment.systemPackages = with pkgs; [
              wget
              curl
              htop
              tmux
              ripgrep
              fd
            ] ++ cfg.additionalPackages;

            # Shell aliases
            environment.shellAliases = {
              ll = "ls -la";
            };
          }

          # Home Manager integration
          (lib.mkIf cfg.enableHomeManager {
            imports = [ inputs.home-manager.darwinModules.home-manager ];

            home-manager = {
              useGlobalPkgs = lib.mkDefault true;
              useUserPackages = lib.mkDefault true;
            };
          })

          # SOPS integration
          (lib.mkIf cfg.enableSops {
            imports = [ inputs.sops-nix.darwinModules.sops ];
          })
        ];
      };
  };
}
