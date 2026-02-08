# Parameterized Home Manager base module
#
# DEPRECATED: This module is being migrated to the dendritic system types pattern.
# New configurations should use the layered system types instead:
#   - homeManager.home-minimal (core HM setup)
#   - homeManager.home-default (packages, fonts, environment)
#   - homeManager.home-cli (git, tmux, shell tools)
#   - homeManager.home-desktop (yazi, GUI applications)
#
# Migration path:
#   1. Import the appropriate system type: inputs.self.modules.homeManager.home-cli
#   2. Set options using the new namespaces: homeMinimal.*, homeDefault.*, homeCli.*
#   3. For feature-specific config (claude-code, opencode), use dedicated feature modules
#
# This module will be removed in Phase 6 of Plan 019.
# See: .claude/user-plans/019-dendritic-migration.md
#
{ config, lib, pkgs, inputs ? null, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
  # Disable upstream home-manager modules to avoid namespace conflicts.
  # Our custom claude-code.nix and opencode.nix modules provide significantly
  # more functionality (multi-account support, categorized hooks, statusline
  # variants, MCP server helpers, WSL integration, etc.) than the basic upstream
  # versions. By disabling the upstream modules, we can use the standard
  # programs.claude-code and programs.opencode namespaces instead of requiring
  # awkward -enhanced suffixes.
  #
  # Feature comparison: See docs/claude-code-module-comparison.md
  # Upstream contribution plan: See home/modules/claude-code/UPSTREAM-CONTRIBUTION-PLAN.md
  disabledModules = [
    "programs/claude-code.nix" # Upstream: 441 lines, basic features
    "programs/opencode.nix" # Upstream: 262 lines, basic features
  ];

  imports = [
    # git.nix migrated to modules/programs/git/ (dendritic pattern)
    # tmux.nix migrated to modules/programs/tmux/ (dendritic pattern)
    # nixvim.nix migrated to modules/programs/neovim/ (dendritic pattern)
    # Legacy common modules (moved from home/common/ - Plan 019 Task 6.3)
    ./legacy-common/environment.nix
    ./legacy-common/aliases.nix
    # Import both files modules - they will be conditionally enabled
    ./files
    ../files
    ./legacy-common/development.nix
    ./legacy-common/terminal.nix
    ./legacy-common/system.nix
    ./legacy-common/shell-utils.nix
    ./terminal-verification.nix # WSL Windows Terminal verification
    ./windows-terminal.nix # Windows Terminal settings management (non-destructive merge)
    # claude-code.nix migrated to modules/programs/claude-code/ (dendritic pattern)
    # opencode.nix migrated to modules/programs/opencode/ (dendritic pattern)
    # secrets-management.nix migrated to modules/programs/secrets-management/ (dendritic pattern)
    # github-auth.nix migrated to modules/programs/github-auth/ (dendritic pattern)
    ./gitlab-auth.nix # GitLab authentication (Bitwarden/SOPS)
    ./git-auth-helpers.nix # Combined git auth helpers (refresh-git-creds)
    ./podman-tools.nix # Container tools configuration
    # Enhanced nix-writers based script management (migrated to unified files)
    # Import ESP-IDF development module
    ./legacy-common/esp-idf.nix
    # Import OneDrive utilities module (WSL-specific)
    ./legacy-common/onedrive.nix
  ];

  options.homeBase = {
    # User information - DEPRECATED: Use homeMinimal.username and homeMinimal.homeDirectory
    # These options are now read-only aliases for backward compatibility.
    # New configurations should use homeMinimal.* directly.
    username = mkOption {
      type = types.str;
      default = config.homeMinimal.username;
      defaultText = "config.homeMinimal.username";
      description = "DEPRECATED: Use homeMinimal.username. Username for Home Manager.";
      example = "myuser";
    };

    homeDirectory = mkOption {
      type = types.str;
      default = config.homeMinimal.homeDirectory;
      defaultText = "config.homeMinimal.homeDirectory";
      description = "DEPRECATED: Use homeMinimal.homeDirectory. Home directory path.";
      example = "/home/myuser";
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
        ffmpegthumbnailer
        file
        fzf
        glow
        jq
        htop
        imagemagick
        inotify-tools
        lbzip2
        markitdown
        marker-pdf
        (pkgs.callPackage ../../pkgs/tomd { })
        nix-diff
        nixfmt-rfc-style
        openssl
        openssl.dev
        pkg-config
        poppler
        resvg
        ripgrep
        speedtest
        stress-ng
        tree
        ueberzugpp
        unzip
        yt-dlp
        zoxide
        p7zip

        rbw
        pinentry-curses
        sops
        nerd-fonts.caskaydia-mono
        cascadia-code
        noto-fonts-color-emoji
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

    enableTerminal = mkOption {
      type = types.bool;
      default = true;
      description = "Enable terminal configuration and font setup tools";
    };

    enableSystem = mkOption {
      type = types.bool;
      default = true;
      description = "Enable system administration and bootstrap tools";
    };

    enableShellUtils = mkOption {
      type = types.bool;
      default = true;
      description = "Enable shell utilities and library functions";
    };

    enableEspIdf = mkOption {
      type = types.bool;
      default = false;
      description = "Enable ESP-IDF development environment with FHS compatibility";
    };

    enableOneDriveUtils = mkOption {
      type = types.bool;
      default = false;
      description = "Enable OneDrive utilities for WSL environments";
    };

    # enableValidatedScripts option removed - all scripts migrated to unified files


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
      # Assertions - now handled by homeMinimal module
      # The homeMinimal module validates username and homeDirectory
      assertions = [ ];

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
        file = {
          # Glow markdown renderer configuration
          ".config/glow/glow.yml".source = ../files/glow.yml;
        };

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

      # Nix configuration moved to dendritic home-minimal module
      # (modules/system/types/1-minimal/minimal.nix)

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

      # GNU Parallel with citation notice silenced
      programs.parallel = {
        enable = true;
        will-cite = true; # Accept citation policy to avoid first-run prompt
      };

      # Disable version mismatch check between Home Manager and Nixpkgs
      # This is because we're using Home Manager master with nixos-unstable
      home.enableNixpkgsReleaseCheck = false;

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
      programs.tmux.autoReload.enable = cfg.enableTmux; # Auto-reload on HM generation change

      # Pass terminal verification configuration to the module
      terminalVerification = {
        enable = cfg.terminalVerification.enable;
        verbose = cfg.terminalVerification.verbose;
        warnOnMisconfiguration = cfg.terminalVerification.warnOnMisconfiguration;
      };

      # Validated scripts configuration removed - migrated to unified files

      # ─────────────────────────────────────────────────────────────────────────
      # Claude Code - MIGRATED to host files (Task 6.4.3)
      # Configuration now lives in each host's home.nix using lib.claudeCode presets
      # See: modules/flake-parts/lib.nix for preset definitions
      # ─────────────────────────────────────────────────────────────────────────

      # ─────────────────────────────────────────────────────────────────────────
      # OpenCode - MIGRATED to host files (Task 6.4.4)
      # Configuration now lives in each host's home.nix using lib.openCode presets
      # See: modules/flake-parts/lib.nix for preset definitions
      # ─────────────────────────────────────────────────────────────────────────

      # Yazi file manager configuration
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        plugins = {
          toggle-pane = pkgs.yaziPlugins.toggle-pane;
          mediainfo = pkgs.yaziPlugins.mediainfo;
          # Override glow plugin to use dynamic width instead of hardcoded 55
          glow = pkgs.yaziPlugins.glow.overrideAttrs (old: {
            postPatch = ''
              # Replace main.lua with our patched version
              cp ${../files/yazi-glow-main.lua} main.lua
            '';
          });
          miller = pkgs.yaziPlugins.miller;
          ouch = pkgs.yaziPlugins.ouch;
          # Additional useful plugins
          chmod = pkgs.yaziPlugins.chmod;
          full-border = pkgs.yaziPlugins.full-border;
          git = pkgs.yaziPlugins.git;
          smart-enter = pkgs.yaziPlugins.smart-enter;
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
          preview = {
            tab_size = 2;
            max_width = 600;
            max_height = 900;
            cache_dir = "";
            image_delay = 30;
            image_filter = "triangle";
            image_quality = 75;
            wrap = "no";
          };
          plugin = {
            prepend_previewers = [
              {
                name = "*.md";
                run = "glow";
              }
            ];
          };
          opener = {
            edit = [
              {
                run = ''$EDITOR "$1"'';
                desc = "$EDITOR";
                block = true;
                for = "unix";
              }
            ];
            open = [
              {
                run = ''explorer.exe "$1"'';
                desc = "Open in Windows Explorer";
                for = "unix";
              }
            ];
          };
        };
        keymap = {
          mgr.prepend_keymap = [
            # WSL2 clipboard integration - override default copy commands to use clip.exe
            {
              on = "cc";
              run = [ ''shell -- echo "$1" | clip.exe'' "copy path" ];
              desc = "Copy absolute path to Windows clipboard";
            }
            {
              on = "cd";
              run = [ ''shell -- echo "$1" | clip.exe'' "copy dirname" ];
              desc = "Copy directory path to Windows clipboard";
            }
            {
              on = "cf";
              run = [ ''shell -- echo "$1" | clip.exe'' "copy filename" ];
              desc = "Copy filename to Windows clipboard";
            }
            {
              on = "cn";
              run = [ ''shell -- echo "$1" | clip.exe'' "copy name_without_ext" ];
              desc = "Copy name without extension to Windows clipboard";
            }
            # Additional useful keybindings
            {
              on = "T";
              run = "plugin --sync toggle-pane";
              desc = "Toggle preview pane";
            }
            {
              on = "<C-s>";
              run = "plugin --sync smart-enter";
              desc = "Smart enter (enter dir or open file)";
            }
            {
              on = "cM";
              run = "plugin --sync chmod";
              desc = "Change file permissions";
            }
          ];
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
