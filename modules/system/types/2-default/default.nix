# modules/system/types/2-default/default.nix
# Default system configuration layer [NDnd]
#
# Provides:
#   flake.modules.nixos.system-default - NixOS with user management + integrations
#   flake.modules.darwin.system-default - Darwin with user management + integrations
#   flake.modules.homeManager.home-default - Home Manager with SSH client, packages, fonts
#
# This layer IMPORTS system-minimal and adds:
#   - User creation with configurable options
#   - Locale and timezone settings
#   - Home Manager integration (optional)
#   - SOPS-nix secrets management (optional)
#   - Console configuration
#
# Does NOT include:
#   - SSH daemon (3-cli)
#   - SSH keys or authorized_keys (3-cli or per-host)
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

          consolePackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Console-related packages (fonts, etc.)";
          };

          # Security
          wheelNeedsPassword = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Require password for sudo (null = use system default)";
          };

          # NOTE: enableHomeManager and enableSops options removed.
          # These integrations should be done at the host level by importing
          # the appropriate modules directly. See the comment in the config section.

          # System packages beyond minimal
          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional system packages";
          };

          # Shell aliases
          extraShellAliases = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional shell aliases";
          };

          # Environment variables
          extraEnvironment = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional system-wide environment variables";
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
              packages = lib.mkDefault cfg.consolePackages;
            };

            # User creation
            users.users.${cfg.userName} = {
              isNormalUser = lib.mkDefault true;
              extraGroups = lib.mkDefault cfg.userGroups;
              shell = lib.mkForce cfg.userShell; # mkForce to override NixOS default
              packages = lib.mkDefault cfg.userPackages;
            };

            # Add user to trusted-users
            nix.settings.trusted-users = [ cfg.userName ];

            # Default shell program
            programs.zsh.enable = lib.mkDefault (cfg.userShell == pkgs.zsh);

            # Security - only set if explicitly configured
            security.sudo.wheelNeedsPassword = lib.mkIf (cfg.wheelNeedsPassword != null) cfg.wheelNeedsPassword;

            # System packages - basic troubleshooting utilities
            # Power tools (tmux, ripgrep, fd) are in system-cli
            environment.systemPackages = with pkgs; [
              wget
              curl
              htop
              less
              home-manager
            ] ++ cfg.additionalPackages;

            # Shell aliases
            environment.shellAliases = {
              ll = "ls -la";
            } // cfg.extraShellAliases;

            # Environment variables
            environment.variables = lib.mkMerge [
              { EDITOR = "nvim"; }
              cfg.extraEnvironment
            ];
          }

          # NOTE: Home Manager and SOPS integration should be handled at the host level
          # by importing the appropriate modules directly. Conditional imports don't
          # work properly in Nix modules.
          #
          # Example in host config:
          #   imports = [
          #     inputs.home-manager.nixosModules.home-manager
          #     inputs.sops-nix.nixosModules.sops
          #   ];
          #   home-manager.useGlobalPkgs = true;
          #   home-manager.useUserPackages = true;
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

          # NOTE: enableHomeManager and enableSops options removed.
          # These integrations should be done at the host level.

          # System packages beyond minimal
          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional system packages";
          };

          # Shell aliases
          extraShellAliases = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional shell aliases";
          };

          # Environment variables
          extraEnvironment = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional system-wide environment variables";
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
            } // cfg.extraShellAliases;

            # Environment variables
            environment.variables = lib.mkMerge [
              { EDITOR = "nvim"; }
              cfg.extraEnvironment
            ];
          }

          # NOTE: Home Manager and SOPS integration should be handled at the host level
        ];
      };

    # === Home Manager Default Module ===
    homeManager.home-default = { config, lib, pkgs, ... }:
      let
        cfg = config.homeDefault;
      in
      {
        imports = [
          # Import minimal layer
          inputs.self.modules.homeManager.home-minimal
        ];

        options.homeDefault = {
          # Default editor
          defaultEditor = lib.mkOption {
            type = lib.types.str;
            default = "nvim";
            description = "Default editor";
          };

          # SSH client configuration
          enableSshClient = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable SSH client configuration";
          };

          sshAddKeysToAgent = lib.mkOption {
            type = lib.types.enum [ "yes" "no" "confirm" "ask" ];
            default = "yes";
            description = "Add keys to ssh-agent automatically";
          };

          sshIdentityFiles = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "~/.ssh/id_ed25519" "~/.ssh/id_rsa" ];
            description = "Default SSH identity files";
          };

          # Base packages
          basePackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = with pkgs; [
              # Core utilities
              act
              coreutils-full
              curl
              dua
              fd
              ffmpeg
              ffmpegthumbnailer
              file
              fzf
              glow
              htop
              imagemagick
              jq
              lbzip2
              markitdown
              nix-diff
              nixfmt
              pkg-config
              poppler
              resvg
              ripgrep
              stress-ng
              tree
              unzip
              yt-dlp
              zoxide
              p7zip

              # Secrets and security
              age
              rbw
              pinentry-curses
              sops
              openssl
              openssl.dev

              # Fonts
              nerd-fonts.caskaydia-mono
              cascadia-code
              noto-fonts-color-emoji
              twemoji-color-font
            ] ++ lib.optionals pkgs.stdenv.isLinux ([
              inotify-tools
              (pkgs.callPackage ../../../../pkgs/tomd { })
              speedtest
              ueberzugpp
            ] ++ lib.optionals cfg.enableLocalAI [
              marker-pdf
            ]);
            description = "Base packages for all home environments";
          };

          # Local AI / GPU-accelerated packages (e.g. marker-pdf)
          enableLocalAI = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Include GPU-accelerated AI packages (marker-pdf) in base packages";
          };

          # Additional packages
          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional packages for this configuration";
          };

          # Environment variables
          environmentVariables = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional environment variables";
          };
        };

        config = lib.mkMerge [
          {
            # Packages
            home.packages = cfg.basePackages ++ cfg.additionalPackages;

            # Environment variables
            home.sessionVariables = {
              EDITOR = cfg.defaultEditor;
            } // cfg.environmentVariables;

            # Font configuration
            fonts.fontconfig.enable = lib.mkForce true;

            # Disable input method to avoid fcitx5 package issues
            i18n.inputMethod.enable = false;
            i18n.inputMethod.type = null;

            # GNU Parallel with citation notice silenced
            programs.parallel = {
              enable = true;
              will-cite = true; # Accept citation policy to avoid first-run prompt
            };

            # Glow markdown renderer configuration
            home.file.".config/glow/glow.yml".source = ../../../.. + "/modules/programs/files [nd]/files/glow.yml";
          }

          # SSH client configuration
          (lib.mkIf cfg.enableSshClient {
            programs.ssh = {
              enable = true;
              # Disable deprecated defaults - we set our own in matchBlocks."*"
              enableDefaultConfig = false;

              # Sensible defaults for SSH client
              extraConfig = ''
                # Use modern key exchange and ciphers
                KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org

                # Connection multiplexing for faster subsequent connections
                ControlMaster auto
                ControlPath ~/.ssh/sockets/%r@%h-%p
                ControlPersist 600

                # Keep connections alive
                ServerAliveInterval 60
                ServerAliveCountMax 3
              '';

              # Default match blocks
              matchBlocks = {
                # Global defaults (applies to all hosts)
                "*" = {
                  addKeysToAgent = cfg.sshAddKeysToAgent;
                };

                # GitHub
                "github.com" = {
                  hostname = "github.com";
                  user = "git";
                  identityFile = cfg.sshIdentityFiles;
                };

                # GitLab
                "gitlab.com" = {
                  hostname = "gitlab.com";
                  user = "git";
                  identityFile = cfg.sshIdentityFiles;
                };

                # Work hosts (migrated from manual ~/.ssh/config)
                "pdx-gw2" = {
                  user = "blackt1";
                };

                "he*" = {
                  proxyJump = "pdx-gw2";
                  user = "blackt1";
                };
              };
            };

            # Ensure socket directory exists
            home.file.".ssh/sockets/.keep".text = "";
          })
        ];
      };
  };
}
