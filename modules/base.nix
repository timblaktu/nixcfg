# Parameterized base module for NixOS systems
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
      default = [];
      description = "SSH authorized keys";
    };
    
    # User configuration options
    userName = mkOption {
      type = types.str;
      default = "tim";
      description = "Primary user name";
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
      default = [];
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
      default = [];
      description = "Console-related packages";
    };
    
    # System packages
    additionalPackages = mkOption {
      type = types.listOf types.package;
      default = [];
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
      default = {};
      description = "Additional shell aliases";
    };

    # System environment variables
    systemEnvironmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = {};
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
  };

  # Actual configuration based on the options
  config = {
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

    # Configure sudo access
    security.sudo.wheelNeedsPassword = lib.mkDefault cfg.requireWheelPassword;

    # Basic system packages
    environment.systemPackages = with pkgs; [
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

    # common home-manager properties
    home-manager.backupFileExtension = "backup";
    
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
        narinfo-cache-positive-ttl = 86400;  # Cache binary info for 24h
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
        
        # Security and permissions (organization-wide enforcement)
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
  };
}
