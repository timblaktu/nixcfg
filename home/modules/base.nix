# Parameterized Home Manager base module
{ config, lib, pkgs, inputs ? null, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
  imports = [
    ../common/git.nix
    ../common/tmux.nix
    ../common/nixvim.nix
    ../common/zsh.nix
    ../common/environment.nix
    ../common/aliases.nix
    # Import both files modules - they will be conditionally enabled
    ./files
    ../files
    ../common/development.nix
    ./terminal-verification.nix # WSL Windows Terminal verification
    ./claude-code.nix # Claude Code MCP servers configuration
    ./secrets-management.nix # RBW and SOPS configuration
    ./podman-tools.nix # Container tools configuration
    # Enhanced nix-writers based script management  
    # TEMPORARY: Force local validated-scripts module for tmux-session-picker fix
    ./validated-scripts
    # Import ESP-IDF development module
    # ../common/esp-idf.nix
  ];

  options.homeBase = {
    # User information
    username = mkOption {
      type = types.str;
      default = "tim";
      description = "Username for Home Manager";
    };

    homeDirectory = mkOption {
      type = types.str;
      default = "/home/tim";
      description = "Home directory path";
    };

    # Basic utilities common to all environments
    # More specific packages are provided in separate modules
    basePackages = mkOption {
      type = types.listOf types.package;
      default = with pkgs; [

        age
        act
        coreutils-full
        curl
        dua
        fd
        ffmpeg
        file
        fzf
        glow
        jq
        htop
        imagemagick
        inotify-tools
        lbzip2
        nix-diff
        nixfmt-rfc-style
        parallel
        poppler
        resvg
        ripgrep
        speedtest
        stress-ng
        tree
        unzip
        zoxide
        p7zip

        rbw
        pinentry-curses
        sops
        nerd-fonts.caskaydia-mono
        cascadia-code
        noto-fonts-emoji
        twemoji-color-font
      ];
      description = "Base packages for all home environments";
    };

    # Additional packages specific to this configuration
    additionalPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional packages for this specific configuration";
    };

    # Shell configuration
    shellAliases = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Shell aliases";
    };

    # Editor preferences
    defaultEditor = mkOption {
      type = types.str;
      default = "nvim";
      description = "Default editor";
    };

    # Enable standard modules
    enableGit = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Git configuration";
    };

    enableTmux = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Tmux configuration";
    };

    enableNeovim = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Neovim configuration";
    };

    enableDevelopment = mkOption {
      type = types.bool;
      default = false;
      description = "Enable development packages and tools";
    };

    enableEspIdf = mkOption {
      type = types.bool;
      default = false;
      description = "Enable ESP-IDF development environment with FHS compatibility";
    };

    enableValidatedScripts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable nix-writers based validated script management";
    };


    enableClaudeCode = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Claude Code configuration with MCP servers";
    };

    enableContainerSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable user container tools (podman-compose, podman-tui, etc.)";
    };

    # Environment variables
    environmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional environment variables";
    };

    # State version
    stateVersion = mkOption {
      type = types.str;
      default = "24.11";
      description = "Home Manager state version";
    };


    # Terminal verification options (WSL-specific)
    terminalVerification = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable automatic Windows Terminal verification on WSL systems";
          };
          verbose = mkOption {
            type = types.bool;
            default = false;
            description = "Show verification messages on startup";
          };
          warnOnMisconfiguration = mkOption {
            type = types.bool;
            default = true;
            description = "Show warning if Windows Terminal bold rendering is not configured optimally";
          };
        };
      };
      default = { };
      description = "Windows Terminal verification settings for WSL systems";
    };
  };

  # Conditionally import common modules based on configuration
  config = mkMerge [
    # Always apply these configs
    {
      # Home Manager needs information about you and the paths it should manage
      home = {
        username = cfg.username;
        homeDirectory = cfg.homeDirectory;

        # Packages combined from base and additional sets
        packages = cfg.basePackages ++ cfg.additionalPackages;

        # State version for Home Manager
        stateVersion = cfg.stateVersion;

        # Add $HOME/bin to PATH for our drop-in scripts
        sessionPath = [ "$HOME/bin" ];

        # Set environment variables
        sessionVariables = {
          EDITOR = cfg.defaultEditor;
          YAZI_LOG = "debug"; # Enable yazi plugin debug logging (works for both standalone and NixOS-integrated HM)
        } // cfg.environmentVariables;

        # Files and scripts
        file = { };

        # THis isn't working. For now just run exec $SHELL manually
        # auto-exec $SHELL after a home-manager switch
        #         activation.reloadShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
        # if [[ "$SHELL" == *zsh && -n "''${ZSH_VERSION:-}" ]]; then
        #   exec zsh
        # elif [[ "$SHELL" == *bash && -n "''${BASH_VERSION:-}" ]]; then
        #   exec bash
        # fi
        # '';
      };

      nix = {
        package = lib.mkDefault pkgs.nix;
        settings = {
          max-jobs = 2;
          warn-dirty = false;
          experimental-features = [ "nix-command" "flakes" ];
        };
      };

      # Configure shell aliases
      programs.bash.shellAliases = lib.mkDefault (cfg.shellAliases //
        lib.optionalAttrs (config.targets.wsl.enable or false) {
          "od-sync" = "onedrive-force-sync";
          "od-status" = "onedrive-status";
          "force-onedrive" = "onedrive-force-sync";
        });
      programs.zsh.shellAliases = lib.mkDefault (cfg.shellAliases //
        lib.optionalAttrs (config.targets.wsl.enable or false) {
          "od-sync" = "onedrive-force-sync";
          "od-status" = "onedrive-status";
          "force-onedrive" = "onedrive-force-sync";
        });

      # Let Home Manager install and manage itself
      programs.home-manager.enable = true;

      # Disable input method entirely to avoid fcitx5 package issues
      i18n.inputMethod.enable = false;
      i18n.inputMethod.type = null;

      # Enable profile management for standalone mode
      targets.genericLinux.enable = mkDefault true;

      # Font configuration for proper emoji and Nerd Font rendering
      fonts.fontconfig.enable = mkForce true;

      # Enable/disable modules based on configuration
      programs.git.enable = cfg.enableGit;
      programs.tmux.enable = cfg.enableTmux;

      # Pass terminal verification configuration to the module
      terminalVerification = {
        enable = cfg.terminalVerification.enable;
        verbose = cfg.terminalVerification.verbose;
        warnOnMisconfiguration = cfg.terminalVerification.warnOnMisconfiguration;
      };

      # Pass validated scripts configuration to the module (conditional)
      validatedScripts = mkIf cfg.enableValidatedScripts {
        enable = cfg.enableValidatedScripts;
        enableBashScripts = cfg.enableValidatedScripts; # Ensure bash scripts are enabled
        # Enable PowerShell scripts on WSL systems where they can coordinate with Windows
        enablePowerShellScripts = config.targets.wsl.enable or false;
      };

      programs.claude-code = {
        enable = cfg.enableClaudeCode;
        defaultModel = "opus";
        accounts = {
          max = {
            enable = true;
            displayName = "Claude Max Account";
          };
          pro = {
            enable = true;
            displayName = "Claude Pro Account";
            model = "sonnet";
          };
        };
        statusline = {
          enable = true;
          style = "powerline"; # Enable colored statusline with powerline symbols
          enableAllStyles = true; # Install all styles for testing
          testMode = true; # Enable test mode for validation
        };
        mcpServers = {
          context7.enable = true;
          sequentialThinking.enable = true; # Now using TypeScript version via npx
          nixos.enable = true; # Using uvx to run mcp-nixos Python package
          # mcpFilesystem.enable = false;  # Disabled - requires fixing FastMCP/watchfiles issue
          # cliMcpServer.enable = false;  # Claude Code has built-in CLI capability
        };
      };

      # Yazi file manager configuration
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        plugins = {
          toggle-pane = pkgs.yaziPlugins.toggle-pane;
          mediainfo = pkgs.yaziPlugins.mediainfo;
          glow = pkgs.yaziPlugins.glow;
          miller = pkgs.yaziPlugins.miller;
          ouch = pkgs.yaziPlugins.ouch;
        };
        initLua = ../files/yazi-init.lua;
        settings = {
          # Full settings spec at https://yazi-rs.github.io/docs/configuration/yazi
          log = {
            enabled = true;
          };
          mgr = {
            linemode = "compact_meta";
            ratio = [ 1 3 5 ];
            show_hidden = true;
            show_symlink = true;
            sort_by = "mtime"; # natural, size
            sort_dir_first = true;
            sort_reverse = true;
            sort_sensitive = true;
            mouse_events = [ "click" "scroll" "touch" "move" ];
          };
        };
      };

      # Container tools configuration (conditional)
      programs.podman-tools = {
        enable = cfg.enableContainerSupport;
        enableCompose = true;
        aliases = {
          docker = "podman";
          d = "podman";
          dc = "podman-compose";
        };
      };

      # Unified files module configuration (always enabled)
      homeFiles.enable = true;
    }
  ];
}
