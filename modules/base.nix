# DEPRECATED: Parameterized base module for NixOS systems
#
# This module is DEPRECATED in favor of the dendritic system type layers:
#   - inputs.self.modules.nixos.system-minimal   (1-minimal: nix settings, store, GC)
#   - inputs.self.modules.nixos.system-default   (2-default: users, locale, SSH)
#   - inputs.self.modules.nixos.system-cli       (3-cli: dev tools, containers, SSH keys)
#   - inputs.self.modules.nixos.system-desktop   (4-desktop: DE, audio, printing)
#
# Migration guide:
#
# BEFORE (old pattern):
#   imports = [ ../../modules/base.nix ];
#   base = {
#     userName = "tim";
#     userGroups = [ "wheel" ];
#     sshPasswordAuth = true;
#     requireWheelPassword = false;
#     nixMaxJobs = 8;
#     nixCores = 0;
#     enableBinaryCache = true;
#     cacheTimeout = 10;
#     additionalShellAliases = { foo = "bar"; };
#   };
#
# AFTER (new pattern):
#   imports = [ inputs.self.modules.nixos.system-cli ];  # or system-default, system-desktop
#   systemMinimal = {
#     nixMaxJobs = 8;
#     nixCores = 0;
#     enableBinaryCache = true;
#     cacheTimeout = 10;
#   };
#   systemDefault = {
#     userName = "tim";
#     userGroups = [ "wheel" ];
#     sshPasswordAuth = true;
#     wheelNeedsPassword = false;
#     extraShellAliases = { foo = "bar"; };
#   };
#   systemCli = {
#     enablePodman = true;  # replaces containerSupport
#   };
#
# Option mapping:
#   base.userName             -> systemDefault.userName
#   base.userGroups           -> systemDefault.userGroups
#   base.userShell            -> systemDefault.userShell
#   base.userPackages         -> systemDefault.userPackages
#   base.sshPasswordAuth      -> systemDefault.sshPasswordAuth
#   base.sshRootLogin         -> systemDefault.sshRootLogin
#   base.sshKeys              -> systemCli.sshAuthorizedKeys
#   base.timeZone             -> systemDefault.timeZone
#   base.locale               -> systemDefault.locale
#   base.consoleFont          -> systemDefault.consoleFont
#   base.consoleKeyMap        -> systemDefault.consoleKeyMap
#   base.consolePackages      -> systemDefault.consolePackages
#   base.requireWheelPassword -> systemDefault.wheelNeedsPassword
#   base.gcDates              -> systemMinimal.gcDates
#   base.gcOptions            -> systemMinimal.gcOptions
#   base.nixMaxJobs           -> systemMinimal.nixMaxJobs
#   base.nixCores             -> systemMinimal.nixCores
#   base.enableBinaryCache    -> systemMinimal.enableBinaryCache
#   base.cacheTimeout         -> systemMinimal.cacheTimeout
#   base.additionalShellAliases -> systemDefault.extraShellAliases
#   base.systemEnvironmentVariables -> systemDefault.extraEnvironment
#   base.additionalPackages   -> systemDefault.additionalPackages
#   base.containerSupport     -> systemCli.enablePodman
#   base.enableClaudeCodeEnterprise -> systemCli.enableClaudeCodeEnterprise
#
# This file will be removed in a future release.
{ config, lib, pkgs, ... }:

# Import the lib for easier option definitions
with lib;

let
  cfg = config.base;
in
{
  # Define the module options
  options.base = {
    # SSH Configuration options
    sshPasswordAuth = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable SSH password authentication";
    };

    sshRootLogin = mkOption {
      type = types.str;
      default = "no";
      description = "SSH root login policy";
    };

    sshKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "SSH authorized keys";
    };

    # User configuration options
    userName = mkOption {
      type = types.str;
      description = "Primary user name (required - must be explicitly set)";
      example = "myuser";
    };

    userGroups = mkOption {
      type = types.listOf types.str;
      default = [ "wheel" "networkmanager" "audio" "video" ];
      description = "User groups";
    };

    userShell = mkOption {
      type = types.package;
      default = pkgs.zsh;
      description = "Default user shell";
    };

    userPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "User-specific packages";
    };

    # Time and locale options
    timeZone = mkOption {
      type = types.str;
      default = "America/Los_Angeles";
      description = "System time zone";
    };

    locale = mkOption {
      type = types.str;
      default = "en_US.UTF-8";
      description = "System locale";
    };

    # Console options
    consoleFont = mkOption {
      type = types.str;
      default = "Lat2-Terminus16";
      description = "Console font";
    };

    consoleKeyMap = mkOption {
      type = types.str;
      default = "us";
      description = "Console keymap";
    };

    consolePackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Console-related packages";
    };

    # System packages
    additionalPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional system packages";
    };

    # Security options
    requireWheelPassword = mkOption {
      type = types.bool;
      default = true;
      description = "Whether sudo requires password for wheel group";
    };

    # Nix options
    gcDates = mkOption {
      type = types.str;
      default = "weekly";
      description = "Garbage collection frequency";
    };

    gcOptions = mkOption {
      type = types.str;
      default = "--delete-older-than 30d";
      description = "Garbage collection options";
    };

    # System options
    stateVersion = mkOption {
      type = types.str;
      default = "24.11";
      description = "NixOS state version";
    };

    # Shell aliases
    additionalShellAliases = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional shell aliases";
    };

    # System environment variables
    systemEnvironmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "System-wide environment variables";
    };

    # Nix performance options
    nixMaxJobs = mkOption {
      type = types.int;
      default = 8;
      description = "Maximum number of build jobs";
    };

    nixCores = mkOption {
      type = types.int;
      default = 0;
      description = "Number of cores per job (0 = all available)";
    };

    enableBinaryCache = mkOption {
      type = types.bool;
      default = true;
      description = "Enable binary cache optimizations";
    };

    cacheTimeout = mkOption {
      type = types.int;
      default = 10;
      description = "Connection timeout for cache in seconds";
    };

    # Claude Code enterprise settings
    enableClaudeCodeEnterprise = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Claude Code enterprise managed settings";
    };

    # Container support options
    containerSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable container support (podman) for development and CI workflows";
    };
  };

  # Actual configuration based on the options
  config = lib.mkMerge [
    {
      # Emit deprecation warning
      warnings = [
        ''
          modules/base.nix is DEPRECATED and will be removed in a future release.
          Please migrate to the dendritic system type layers:
            - inputs.self.modules.nixos.system-minimal
            - inputs.self.modules.nixos.system-default
            - inputs.self.modules.nixos.system-cli
            - inputs.self.modules.nixos.system-desktop

          See the comment at the top of modules/base.nix for migration guide.
        ''
      ];

      # Runtime assertions for configuration validation
      assertions = [
        {
          assertion = cfg.userName != "";
          message = "base.userName must not be empty";
        }
        {
          assertion = cfg.nixCores >= 0;
          message = "base.nixCores must be non-negative (0 for auto-detect)";
        }
        {
          assertion = cfg.cacheTimeout > 0;
          message = "base.cacheTimeout must be positive";
        }
        {
          assertion = builtins.elem "wheel" cfg.userGroups || !cfg.requireWheelPassword;
          message = "User must be in wheel group when requireWheelPassword is false";
        }
        {
          assertion = cfg.sshRootLogin == "no" || cfg.sshRootLogin == "yes" || cfg.sshRootLogin == "prohibit-password" || cfg.sshRootLogin == "forced-commands-only";
          message = "base.sshRootLogin must be one of: no, yes, prohibit-password, forced-commands-only";
        }
      ];
      # Time zone and internationalization
      time.timeZone = lib.mkDefault cfg.timeZone;
      i18n.defaultLocale = lib.mkDefault cfg.locale;

      # Console configuration
      console = {
        font = lib.mkDefault cfg.consoleFont;
        keyMap = lib.mkDefault cfg.consoleKeyMap;
        packages = lib.mkDefault cfg.consolePackages;
      };

      # Enable OpenSSH daemon with configurable parameters
      services.openssh = {
        enable = lib.mkDefault true;
        settings = {
          PermitRootLogin = lib.mkDefault cfg.sshRootLogin;
          PasswordAuthentication = lib.mkDefault cfg.sshPasswordAuth;
        };
      };

      services.atd.enable = true;

      # Configure sudo access
      security.sudo.wheelNeedsPassword = lib.mkDefault cfg.requireWheelPassword;

      # Basic system packages
      environment.systemPackages = with pkgs; [
        at
        vim
        wget
        curl
        git
        home-manager
        htop
        tmux
        ripgrep
        fd
      ] ++ cfg.additionalPackages;


      # System-wide shell aliases
      environment.shellAliases = {
        ll = "ls -la";
        update = "sudo nixos-rebuild switch";
        upgrade = "sudo nixos-rebuild switch --upgrade";
      } // cfg.additionalShellAliases;

      # Default shell configuration
      programs.zsh.enable = true;
      users.defaultUserShell = cfg.userShell;

      # System environment variables
      environment.variables = lib.mkMerge [
        { EDITOR = "nvim"; }
        cfg.systemEnvironmentVariables
      ];

      # System-level nix settings
      nix = {
        package = pkgs.nixVersions.stable;
        settings = {
          auto-optimise-store = true;
          experimental-features = [ "nix-command" "flakes" ];
          trusted-users = [ "root" cfg.userName ];
          warn-dirty = false;
          # Increase download buffer size to prevent warnings during large downloads
          download-buffer-size = 134217728; # 128 MB (default is typically 64 MB)

          # Performance settings
          max-jobs = lib.mkDefault cfg.nixMaxJobs;
          cores = lib.mkDefault cfg.nixCores;
        } // (lib.optionalAttrs cfg.enableBinaryCache {
          # Network optimizations
          substituters = [
            "https://cache.nixos.org/"
            "https://nix-community.cachix.org"
          ];
          trusted-public-keys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          ];
          # Cache optimizations
          narinfo-cache-positive-ttl = 86400; # Cache binary info for 24h
          connect-timeout = cfg.cacheTimeout;
        });
        gc = {
          automatic = true;
          dates = cfg.gcDates;
          options = cfg.gcOptions;
        };
      };

      # Claude Code Enterprise Settings (conditional)
      environment.etc."claude-code/managed-settings.json" = lib.mkIf cfg.enableClaudeCodeEnterprise {
        text = builtins.toJSON {
          # Top-precedence settings that cannot be overridden by users
          model = "opus";

          # Security and permissions (organization-wide enforcement) - v2.0 schema
          permissions = {
            allow = [
              "Bash"
              "mcp__context7"
              "mcp__mcp-nixos"
              "mcp__sequential-thinking"
              "Read"
              "Write"
              "Edit"
              "WebFetch"
            ];
            deny = [
              "Search"
              "Find"
              "Bash(rm -rf /*)"
              "Read(.env)"
              "Write(/etc/passwd)"
            ];
            ask = [ ];
            defaultMode = "default";
            additionalDirectories = [ ];
          };

          # Environment variables
          env = {
            CLAUDE_CODE_ENABLE_TELEMETRY = "0";
          };

          # Statusline configuration (consistent across all accounts)
          statusLine = {
            type = "command";
            command = "claude-statusline-powerline";
            padding = 0;
          };

          # Project overrides
          projectOverrides = {
            enabled = true;
            searchPaths = [
              ".claude/settings.json"
              ".claude.json"
              "claude.config.json"
            ];
          };
        };
        mode = "0644";
      };

      # Default user configuration
      users.users.${cfg.userName} = {
        isNormalUser = lib.mkDefault true;
        extraGroups = lib.mkDefault cfg.userGroups;
        shell = lib.mkForce cfg.userShell;
        packages = lib.mkDefault cfg.userPackages;
        openssh.authorizedKeys.keys = lib.mkDefault cfg.sshKeys;
      };

      # Set NixOS compatibility version
      system.stateVersion = cfg.stateVersion;
    }

    # Container support configuration
    (lib.mkIf cfg.containerSupport {
      # Enable podman with Docker compatibility for act
      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
        dockerSocket.enable = true;
        defaultNetwork.settings.dns_enabled = true;
      };

      # Enable container support
      virtualisation.containers.enable = true;

      # Configure user for rootless podman
      users.users.${cfg.userName} = {
        subUidRanges = [{ startUid = 100000; count = 65536; }];
        subGidRanges = [{ startGid = 100000; count = 65536; }];
        extraGroups = [ "podman" ];
      };

      # Additional packages for container workflows
      environment.systemPackages = with pkgs; [
        podman-compose
        podman-tui
      ];
    })
  ];
}
