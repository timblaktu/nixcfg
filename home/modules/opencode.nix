# OpenCode Home Manager Module
# Declarative configuration for the OpenCode AI coding assistant
# https://opencode.ai/
#
# This module follows the same multi-account pattern as claude-code.nix
# and shares configuration through the shared/ modules for DRY benefits.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.opencode-enhanced;

  # Import shared modules for DRY configuration
  sharedInstructions = import ./shared/ai-instructions.nix { inherit lib; };
  sharedMcpDefs = import ./shared/mcp-server-defs.nix { inherit lib; };

  # Agent submodule type
  agentModule = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        description = "Description of what this agent does";
      };

      model = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Model to use for this agent (null = use default)";
      };

      prompt = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom system prompt for this agent";
      };

      promptFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing agent prompt";
      };

      tools = mkOption {
        type = types.attrsOf types.bool;
        default = { };
        description = "Tool enable/disable overrides for this agent";
      };

      permission = mkOption {
        type = types.attrsOf (types.enum [ "allow" "ask" "deny" ]);
        default = { };
        description = "Permission overrides for this agent";
      };
    };
  };

  # Command submodule type
  commandModule = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        description = "Description of this command";
      };

      template = mkOption {
        type = types.str;
        description = "Command template with optional $ARGUMENTS placeholder";
      };

      agent = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Agent to use for this command";
      };

      model = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Model override for this command";
      };

      subtask = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to run as a subtask";
      };
    };
  };

in
{
  imports = [
    ./opencode/mcp-servers.nix
  ];

  # Named opencode-enhanced to avoid conflict with upstream home-manager programs.opencode
  options.programs.opencode-enhanced = {
    enable = mkEnableOption "OpenCode AI coding assistant";

    package = mkPackageOption pkgs "opencode" { };

    debug = mkEnableOption "debug output for OpenCode";

    # ─────────────────────────────────────────────────────────────────────────
    # MODEL CONFIGURATION
    # ─────────────────────────────────────────────────────────────────────────
    defaultModel = mkOption {
      type = types.str;
      default = "anthropic/claude-sonnet-4-5";
      description = "Default model in provider/model format";
      example = "anthropic/claude-sonnet-4-5";
    };

    smallModel = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Model for lightweight tasks (title generation, summaries)";
      example = "anthropic/claude-haiku-4-5";
    };

    # ─────────────────────────────────────────────────────────────────────────
    # PATH CONFIGURATION
    # ─────────────────────────────────────────────────────────────────────────
    nixcfgPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/src/nixcfg";
      description = "Path to nixcfg repo containing opencode-runtime directory";
    };

    # ─────────────────────────────────────────────────────────────────────────
    # ACCOUNT PROFILES
    # ─────────────────────────────────────────────────────────────────────────
    accounts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this OpenCode account profile";

          displayName = mkOption {
            type = types.str;
            description = "Display name for this account profile";
            example = "OpenCode Max";
          };

          provider = mkOption {
            type = types.enum [ "anthropic" "openai" "openrouter" "ollama" "google" "custom" ];
            default = "anthropic";
            description = "Primary provider for this account";
          };

          model = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Model override for this account (null = use defaultModel)";
          };

          api = {
            baseUrl = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Custom API base URL (for proxies)";
            };

            apiKeyEnvVar = mkOption {
              type = types.str;
              default = "ANTHROPIC_API_KEY";
              description = "Environment variable name for API key";
            };
          };

          extraEnvVars = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Additional environment variables for this account";
          };
        };
      });
      default = { };
      description = ''
        OpenCode account profiles for concurrent independent sessions.
        Each account gets its own config directory via OPENCODE_CONFIG_DIR.
      '';
    };

    defaultAccount = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default account when running 'opencode' without profile";
    };

    # ─────────────────────────────────────────────────────────────────────────
    # AGENTS
    # ─────────────────────────────────────────────────────────────────────────
    agents = mkOption {
      type = types.attrsOf agentModule;
      default = { };
      description = "Custom agent definitions";
    };

    defaultAgent = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default agent to use (plan, build, or custom)";
    };

    # ─────────────────────────────────────────────────────────────────────────
    # COMMANDS
    # ─────────────────────────────────────────────────────────────────────────
    commands = mkOption {
      type = types.attrsOf commandModule;
      default = { };
      description = "Custom slash commands";
    };

    # ─────────────────────────────────────────────────────────────────────────
    # PERMISSIONS
    # ─────────────────────────────────────────────────────────────────────────
    permissions = mkOption {
      type = types.attrsOf (types.enum [ "allow" "ask" "deny" ]);
      default = { };
      description = ''
        Tool permissions. Keys are tool names, values are permission levels.
        Built-in tools: read, edit, glob, grep, list, bash, task, web, etc.
      '';
      example = {
        edit = "ask";
        bash = "ask";
        web = "allow";
      };
    };

    # ─────────────────────────────────────────────────────────────────────────
    # INSTRUCTIONS (AGENTS.md)
    # ─────────────────────────────────────────────────────────────────────────
    instructions = {
      files = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Files to include as additional instructions (e.g., CONTRIBUTING.md)";
      };

      extraContent = mkOption {
        type = types.lines;
        default = "";
        description = "Additional content to append to AGENTS.md";
      };
    };

    # ─────────────────────────────────────────────────────────────────────────
    # TUI SETTINGS
    # ─────────────────────────────────────────────────────────────────────────
    tui = {
      scrollSpeed = mkOption {
        type = types.int;
        default = 3;
        description = "Scroll speed in the TUI";
      };

      scrollAcceleration = mkOption {
        type = types.bool;
        default = true;
        description = "Enable scroll acceleration";
      };

      diffStyle = mkOption {
        type = types.enum [ "auto" "unified" "side-by-side" ];
        default = "auto";
        description = "Diff display style";
      };

      theme = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Theme name (null = default)";
      };
    };

    # ─────────────────────────────────────────────────────────────────────────
    # FORMATTERS
    # ─────────────────────────────────────────────────────────────────────────
    formatters = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          command = mkOption {
            type = types.listOf types.str;
            description = "Formatter command with $FILE placeholder";
          };

          extensions = mkOption {
            type = types.listOf types.str;
            description = "File extensions this formatter handles";
          };

          environment = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Environment variables for the formatter";
          };

          disabled = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to disable this formatter";
          };
        };
      });
      default = { };
      description = "Custom code formatters";
    };

    # ─────────────────────────────────────────────────────────────────────────
    # ADVANCED SETTINGS
    # ─────────────────────────────────────────────────────────────────────────
    compaction = {
      auto = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic context compaction";
      };

      prune = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic context pruning";
      };
    };

    watcher = {
      ignore = mkOption {
        type = types.listOf types.str;
        default = [ "node_modules/**" ".git/**" ];
        description = "Glob patterns to ignore in file watcher";
      };
    };

    autoupdate = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic updates";
    };

    share = mkOption {
      type = types.enum [ "manual" "auto" "disabled" ];
      default = "manual";
      description = "Session sharing behavior";
    };

    provider = mkOption {
      type = types.attrs;
      default = { };
      description = "Provider-specific configuration (timeouts, caching, etc.)";
    };

    experimental = mkOption {
      type = types.attrs;
      default = { };
      description = "Experimental features";
    };

    # ─────────────────────────────────────────────────────────────────────────
    # INTERNAL OPTIONS
    # ─────────────────────────────────────────────────────────────────────────
    _internal = {
      mcpServers = mkOption {
        type = types.attrs;
        default = { };
        internal = true;
        description = "Processed MCP server configurations";
      };
    };
  };

  config =
    let
      nixcfgPath = cfg.nixcfgPath;
      runtimePath = "${nixcfgPath}/opencode-runtime";

      # Build the MCP configuration from _internal
      mcpConfig = cfg._internal.mcpServers;

      # Build agent configuration
      agentConfig = mapAttrs
        (name: agent: {
          description = agent.description;
        } // optionalAttrs (agent.model != null) {
          model = agent.model;
        } // optionalAttrs (agent.prompt != null) {
          prompt = agent.prompt;
        } // optionalAttrs (agent.tools != { }) {
          tools = agent.tools;
        } // optionalAttrs (agent.permission != { }) {
          permission = agent.permission;
        })
        cfg.agents;

      # Build command configuration
      commandConfig = mapAttrs
        (name: cmd: {
          description = cmd.description;
          template = cmd.template;
        } // optionalAttrs (cmd.agent != null) {
          agent = cmd.agent;
        } // optionalAttrs (cmd.model != null) {
          model = cmd.model;
        } // optionalAttrs cmd.subtask {
          subtask = true;
        })
        cfg.commands;

      # Build formatter configuration
      formatterConfig = mapAttrs
        (name: fmt: {
          command = fmt.command;
          extensions = fmt.extensions;
        } // optionalAttrs (fmt.environment != { }) {
          environment = fmt.environment;
        } // optionalAttrs fmt.disabled {
          disabled = true;
        })
        cfg.formatters;

      # Generate complete opencode.json for an account
      mkOpencodeConfig = accountName: accountCfg:
        let
          model = if accountCfg.model != null then accountCfg.model else cfg.defaultModel;
        in
        {
          "$schema" = "https://opencode.ai/config.json";
          inherit model;
        }
        // optionalAttrs (cfg.smallModel != null) { small_model = cfg.smallModel; }
        // optionalAttrs (mcpConfig != { }) { mcp = mcpConfig; }
        // optionalAttrs (agentConfig != { }) { agent = agentConfig; }
        // optionalAttrs (cfg.defaultAgent != null) { default_agent = cfg.defaultAgent; }
        // optionalAttrs (commandConfig != { }) { command = commandConfig; }
        // optionalAttrs (cfg.permissions != { }) { permission = cfg.permissions; }
        // optionalAttrs (cfg.instructions.files != [ ]) { instructions = cfg.instructions.files; }
        // optionalAttrs (cfg.tui.theme != null) { theme = cfg.tui.theme; }
        // {
          tui = {
            scroll_speed = cfg.tui.scrollSpeed;
            scroll_acceleration = { enabled = cfg.tui.scrollAcceleration; };
            diff_style = cfg.tui.diffStyle;
          };
        }
        // optionalAttrs (formatterConfig != { }) { formatter = formatterConfig; }
        // optionalAttrs (cfg.provider != { }) { provider = cfg.provider; }
        // {
          watcher = {
            ignore = cfg.watcher.ignore;
          };
          autoupdate = cfg.autoupdate;
          share = cfg.share;
        };

      # Generate AGENTS.md content using shared instructions
      mkAgentsMdContent = accountName:
        let
          mcpServerStatus = map
            (name: {
              inherit name;
              status = "enabled";
            })
            (attrNames mcpConfig);
        in
        sharedInstructions.mkMemoryContent sharedInstructions {
          toolName = "OpenCode";
          screenshotDir = "/mnt/c/Users/tblack/OneDrive/Pictures/Screenshots 1";
          mcpServers = mcpServerStatus;
          extraContent = cfg.instructions.extraContent;
        };

      # Create account-specific config file
      mkConfigFile = accountName: accountCfg:
        pkgs.writeText "opencode-${accountName}.json"
          (builtins.toJSON (mkOpencodeConfig accountName accountCfg));

      # Create AGENTS.md file
      agentsMdFile = accountName:
        pkgs.writeText "AGENTS-${accountName}.md" (mkAgentsMdContent accountName);

      # Create wrapper script for each account
      mkAccountScript = accountName: accountCfg:
        let
          configDir = "${runtimePath}/.opencode-${accountName}";
          envVars = {
            OPENCODE_CONFIG_DIR = configDir;
          } // optionalAttrs (accountCfg.api.baseUrl != null) {
            "${accountCfg.api.apiKeyEnvVar}_BASE_URL" = accountCfg.api.baseUrl;
          } // accountCfg.extraEnvVars;

          envExports = concatStringsSep "\n"
            (mapAttrsToList (k: v: "export ${k}=${escapeShellArg v}") envVars);
        in
        pkgs.writeShellScriptBin "opencode-${accountName}" ''
          #!/usr/bin/env bash
          ${envExports}
          exec ${cfg.package}/bin/opencode "$@"
        '';

    in
    mkIf cfg.enable {
      # Install OpenCode and account wrapper scripts
      home.packages = [
        cfg.package
      ] ++ (mapAttrsToList mkAccountScript
        (filterAttrs (n: a: a.enable) cfg.accounts));

      # Symlink config directories
      home.file = mkMerge [
        # Account-specific config directories
        (mkMerge (mapAttrsToList
          (name: account: mkIf account.enable {
            ".config/opencode-${name}".source =
              config.lib.file.mkOutOfStoreSymlink "${runtimePath}/.opencode-${name}";
          })
          cfg.accounts))

        # Default account symlink
        (mkIf (cfg.defaultAccount != null) {
          ".config/opencode".source =
            config.lib.file.mkOutOfStoreSymlink "${runtimePath}/.opencode-${cfg.defaultAccount}";
        })
      ];

      # Activation script to deploy configurations
      home.activation.opencodeConfigTemplates = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Validate nixcfgPath exists
        if [[ ! -d "${nixcfgPath}" ]]; then
          echo "Error: nixcfgPath does not exist: ${nixcfgPath}"
          echo "Either create the directory or update programs.opencode.nixcfgPath"
          exit 1
        fi

        if [[ ! -w "${nixcfgPath}" ]]; then
          echo "Error: nixcfgPath is not writable: ${nixcfgPath}"
          exit 1
        fi

        $DRY_RUN_CMD mkdir -p ${runtimePath}

        # Helper function
        copy_template() {
          local template="$1"
          local target="$2"
          $DRY_RUN_CMD rm -f "$target"
          $DRY_RUN_CMD cp "$template" "$target"
          $DRY_RUN_CMD chmod 644 "$target"
          echo "Updated: $target"
        }

        # Deploy account configurations
        ${concatStringsSep "\n" (mapAttrsToList (name: account: ''
          if [[ "${toString account.enable}" == "1" ]]; then
            accountDir="${runtimePath}/.opencode-${name}"
            echo "Configuring OpenCode account: ${name}"

            $DRY_RUN_CMD mkdir -p "$accountDir"

            # Deploy opencode.json
            copy_template "${mkConfigFile name account}" "$accountDir/opencode.json"

            # Deploy AGENTS.md (preserve existing if present)
            ${optionalString (cfg.instructions.extraContent != "" || mcpConfig != {}) ''
            if [[ -f "$accountDir/AGENTS.md" ]]; then
              echo "Preserved existing AGENTS.md"
            else
              copy_template "${agentsMdFile name}" "$accountDir/AGENTS.md"
            fi
            ''}

            echo "OpenCode account ${name} configured"
          fi
        '') cfg.accounts)}
      '';

      # Shell functions for session management
      programs.bash.initExtra = mkIf (cfg.accounts != { }) (mkAfter ''
        # OpenCode Session Management
        opencode-status() {
          echo "Checking OpenCode sessions..."
          for account in ${concatStringsSep " " (attrNames (filterAttrs (n: a: a.enable) cfg.accounts))}; do
            local pidfile="/tmp/opencode-''${account}.pid"
            if [[ -f "$pidfile" ]]; then
              local pid=$(cat "$pidfile")
              if kill -0 "$pid" 2>/dev/null; then
                echo "OpenCode ($account) is running (PID: $pid)"
              else
                echo "Stale pidfile for $account (removing)"
                rm -f "$pidfile"
              fi
            fi
          done
        }
      '');

      programs.zsh.initContent = mkIf (cfg.accounts != { }) (mkAfter ''
        # OpenCode Session Management
        opencode-status() {
          echo "Checking OpenCode sessions..."
          for account in ${concatStringsSep " " (attrNames (filterAttrs (n: a: a.enable) cfg.accounts))}; do
            local pidfile="/tmp/opencode-''${account}.pid"
            if [[ -f "$pidfile" ]]; then
              local pid=$(cat "$pidfile")
              if kill -0 "$pid" 2>/dev/null; then
                echo "OpenCode ($account) is running (PID: $pid)"
              else
                echo "Stale pidfile for $account (removing)"
                rm -f "$pidfile"
              fi
            fi
          done
        }
      '');

      # Assertions
      assertions = [
        {
          assertion = cfg.defaultAccount != null -> cfg.accounts ? ${cfg.defaultAccount};
          message = "Default account '${cfg.defaultAccount}' must be defined in accounts";
        }
        {
          assertion = cfg.defaultAccount != null -> cfg.accounts.${cfg.defaultAccount}.enable;
          message = "Default account '${cfg.defaultAccount}' must be enabled";
        }
        {
          assertion = hasPrefix "/" cfg.nixcfgPath;
          message = "nixcfgPath must be an absolute path, got: ${cfg.nixcfgPath}";
        }
      ];
    };
}
