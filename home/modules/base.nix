# Parameterized Home Manager base module
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
    ../common/terminal.nix
    ../common/system.nix
    ../common/shell-utils.nix
    ./terminal-verification.nix # WSL Windows Terminal verification
    ./windows-terminal.nix # Windows Terminal settings management (non-destructive merge)
    ./claude-code.nix # Claude Code - enhanced multi-account module (upstream disabled via disabledModules)
    ./opencode.nix # OpenCode - enhanced multi-account module (upstream disabled via disabledModules)
    ./secrets-management.nix # RBW and SOPS configuration
    ./github-auth.nix # GitHub and GitLab authentication (Bitwarden/SOPS)
    ./podman-tools.nix # Container tools configuration
    # Enhanced nix-writers based script management (migrated to unified files)
    # Import ESP-IDF development module
    ../common/esp-idf.nix
    # Import OneDrive utilities module (WSL-specific)
    ../common/onedrive.nix
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

      # Pass terminal verification configuration to the module
      terminalVerification = {
        enable = cfg.terminalVerification.enable;
        verbose = cfg.terminalVerification.verbose;
        warnOnMisconfiguration = cfg.terminalVerification.warnOnMisconfiguration;
      };

      # Validated scripts configuration removed - migrated to unified files

      # ─────────────────────────────────────────────────────────────────────────
      # Claude Code - enhanced multi-account implementation
      # Upstream home-manager module disabled via disabledModules (see top of file)
      # ─────────────────────────────────────────────────────────────────────────
      programs.claude-code = {
        enable = cfg.enableClaudeCode;
        defaultModel = "opus";
        defaultAccount = "max";
        accounts = {
          max = {
            enable = true;
            displayName = "Claude Max Account";
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
          pro = {
            enable = true;
            displayName = "Claude Pro Account";
            model = "sonnet";
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
          work = {
            enable = true;
            displayName = "Work Code-Companion";
            model = "sonnet";
            api = {
              baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
              authMethod = "bearer";
              disableApiKey = true;
              modelMappings = {
                haiku = "devstral";
                sonnet = "qwen-a3b";
                opus = "claude-sonnet-4-5-20250929";
              };
            };
            secrets.bearerToken.bitwarden = {
              item = "PAC Code Companion v2";
              field = "API Key";
            };
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
              ANTHROPIC_DEFAULT_HAIKU_MODEL = "devstral";
              ANTHROPIC_DEFAULT_SONNET_MODEL = "qwen-a3b";
              # ANTHROPIC_DEFAULT_OPUS_MODEL = "kimi-linear-reap-a3b";
              ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-sonnet-4-5-20250929";
              # From https://git.panasonic.aero/platform/sandbox/pac-claude-proxy/-/blob/main/anthropic_proxy.py?ref_type=heads#L29
              # MODEL_MAP = {
              #     "claude-sonnet-4-5-20250929": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
              #     "claude-sonnet-4-5-20250929-v1:0": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
              #     "claude-opus-4-5-20251101": "us.anthropic.claude-opus-4-5-20251101-v1:0",
              #     "claude-opus-4-20250514": "us.anthropic.claude-opus-4-5-20251101-v1:0",
              #     "claude-opus-4-20250514-v3:0": "us.anthropic.claude-opus-4-5-20251101-v1:0",
              #     "claude-sonnet-4-20250514": "us.anthropic.claude-sonnet-4-20250514-v1:0",
              #     "claude-3-7-sonnet-20250219": "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
              #     "claude-3-5-sonnet-20241022": "anthropic.claude-3-5-sonnet-20241022-v2:0",
              #     # Haiku - map to Sonnet (Haiku not available)
              #     "claude-haiku-4-5-20251001": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
              # }
            };
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
        # Task automation - provides run-tasks script and /next-task command
        taskAutomation.enable = true;
        # Skills - provides ADR-writer and custom skills
        skills.enable = true;
        # Custom sub-agents
        subAgents.custom = {
          pdf-indexer = {
            description = "Extract TOC, metadata, and key content from PDF documents. Uses pdftotext via Bash to bypass Read tool token limits. Handles PDFs of any size.";
            tools = [ "Bash" "Glob" ];
            capabilities = [
              "Extract metadata (title, pages, size) using pdfinfo"
              "Extract text content using pdftotext with page range control"
              "Size-based routing: full extraction for small PDFs, TOC-only for large"
              "Structured markdown output with page references"
            ];
            instructions = ''
              ## Why This Agent Exists

              The Read tool has a 25,000 token limit for PDFs, which fails on documents > ~30 pages.
              This agent uses `pdftotext` via Bash to extract text content, bypassing that limitation.

              ## Required Tools

              Use `poppler-utils` via nix-shell:

              ```bash
              nix-shell -p poppler-utils --run 'pdfinfo "file.pdf"'
              nix-shell -p poppler-utils --run 'pdftotext -f 1 -l 10 "file.pdf" -'
              ```

              ## Size-Based Extraction Strategy

              **Small PDFs (≤50 pages):** Extract all pages
              ```bash
              nix-shell -p poppler-utils --run 'pdftotext "PATH" -' 2>/dev/null | head -500
              ```

              **Medium PDFs (51-200 pages):** Extract first 15 pages (usually contains TOC)
              ```bash
              nix-shell -p poppler-utils --run 'pdftotext -f 1 -l 15 "PATH" -' 2>/dev/null
              ```

              **Large PDFs (>200 pages):** Extract first 20 pages only
              ```bash
              nix-shell -p poppler-utils --run 'pdftotext -f 1 -l 20 "PATH" -' 2>/dev/null
              ```

              ## Output Format

              Return structured markdown with:
              - Document title and revision
              - Page count and file size
              - Table of contents with page numbers
              - Document type classification

              ## Handling Multiple PDFs

              Use `fd` to list PDFs first:
              ```bash
              fd -t f -e pdf -e PDF . "DIRECTORY_PATH"
              ```
              Then process each individually.
            '';
            examples = [
              "Index this PDF: /path/to/document.pdf"
              "Index all PDFs in /path/to/docs/ and return a markdown table"
              "Extract the TOC from /path/to/large-manual.pdf"
            ];
          };
        };
      };

      # ─────────────────────────────────────────────────────────────────────────
      # OpenCode - enhanced multi-account implementation
      # Upstream home-manager module disabled via disabledModules (see top of file)
      # Uses shared MCP server definitions for DRY configuration
      # ─────────────────────────────────────────────────────────────────────────
      programs.opencode = {
        enable = cfg.enableClaudeCode; # Enable alongside claude-code
        defaultModel = "anthropic/claude-sonnet-4-5";
        defaultAccount = "max";
        # Provider configuration - API key via environment variable
        provider = {
          anthropic = {
            options = {
              apiKey = "{env:ANTHROPIC_API_KEY}";
            };
          };
          # Custom Code-Companion provider using OpenAI-compatible API
          codecompanion = {
            npm = "@ai-sdk/openai-compatible";
            name = "Code Companion V2";
            options = {
              baseURL = "https://codecompanionv2.d-dp.nextcloud.aero/v1";
              apiKey = "{env:ANTHROPIC_API_KEY}";
            };
            models = {
              "qwen-a3b" = {
                name = "Qwen A3B";
                modalities = {
                  input = [ "text" "image" ];
                  output = [ "text" ];
                };
              };
              "devstral" = { name = "Devstral"; };
              "kimi-linear-reap-a3b" = { name = "Kimi Linear Reap A3B"; };
              "glm-47" = { name = "GLM 47"; };
            };
          };
        };
        accounts = {
          max = {
            enable = true;
            displayName = "OpenCode Max Account";
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
            };
          };
          pro = {
            enable = true;
            displayName = "OpenCode Pro Account";
            model = "anthropic/claude-sonnet-4-5";
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
            };
          };
          work = {
            enable = true;
            displayName = "OpenCode Work Code-Companion";
            provider = "custom";
            model = "codecompanion/qwen-a3b";
            # API config is in the top-level codecompanion provider block
            # We still need the env var name for the wrapper script
            api = {
              apiKeyEnvVar = "ANTHROPIC_API_KEY";
            };
            secrets.bearerToken.bitwarden = {
              item = "PAC Code Companion v2";
              field = "API Key";
            };
            extraEnvVars = {
              DISABLE_TELEMETRY = "1";
            };
          };
        };
        permissions = {
          Bash = "allow";
          Read = "allow";
          Write = "allow";
          Edit = "allow";
          WebFetch = "allow";
          "mcp__context7" = "allow";
          "mcp__mcp-nixos" = "allow";
          "mcp__sequential-thinking" = "allow";
          Search = "deny";
          Find = "deny";
          "Bash(rm -rf /*)" = "deny";
        };
        mcpServers = {
          context7.enable = true;
          sequentialThinking.enable = true;
          nixos.enable = true;
        };
      };

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
