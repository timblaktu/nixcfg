{ config, lib, pkgs, nixmcp ? null, ... }:

with lib;

{
  imports = [
    ./claude-code/mcp-servers.nix
    ./claude-code/hooks.nix
    ./claude-code/sub-agents.nix
    ./claude-code/slash-commands.nix
    ./claude-code/memory-commands.nix
    ./claude-code/memory-commands-static.nix
    ./claude-code/task-automation.nix
    ./claude-code/skills.nix
    ./claude-code-statusline.nix
  ];

  # NOTE: Renamed from programs.claude-code to programs.claude-code-enhanced
  # to avoid conflict with upstream home-manager's programs.claude-code module.
  # See docs/claude-code-upstream-contribution-plan.md for migration strategy.
  options.programs.claude-code-enhanced = {
    enable = mkEnableOption "Claude Code Enhanced - feature-rich multi-account Claude Code management";

    debug = mkEnableOption "debug output for all components";

    defaultModel = mkOption {
      type = types.enum [ "sonnet" "opus" "haiku" ];
      default = "sonnet";
      description = "Default Claude model";
    };

    aiGuidance = mkOption {
      type = types.lines;
      default = ''
        * After receiving tool results, carefully reflect on their quality and determine optimal next steps
        * For maximum efficiency, invoke multiple independent tools simultaneously rather than sequentially
        * Before finishing, verify your solution addresses all requirements
        * Do what has been asked; nothing more, nothing less
        * NEVER create files unless absolutely necessary
        * ALWAYS prefer editing existing files to creating new ones
        * NEVER proactively create documentation unless explicitly requested
        
        ## Git Commit Rules
        
        * NEVER include Claude's identity or involvement in commit messages
        * Do NOT add "Generated with Claude Code" or "Co-Authored-By: Claude" footers
        * Write commit messages as if authored by the human user
        * Keep commit messages concise and focused on the technical changes
      '';
      description = "Core AI guidance principles";
    };

    enableProjectOverrides = mkOption {
      type = types.bool;
      default = true;
      description = "Allow project-specific configuration overrides";
    };

    projectOverridePaths = mkOption {
      type = types.listOf types.str;
      default = [ ".claude/settings.json" ".claude.json" "claude.config.json" ];
      description = "Paths to search for project-specific settings";
    };

    permissions = {
      allow = mkOption {
        type = types.listOf types.str;
        default = [
          "Bash"
          "mcp__context7"
          "mcp__mcp-nixos"
          "mcp__sequential-thinking"
          "mcp__serena"
          "Read"
          "Write"
          "Edit"
          "WebFetch"
        ];
        description = "List of tools/patterns to allow";
      };

      deny = mkOption {
        type = types.listOf types.str;
        default = [
          "Search"
          "Find"
          "Bash(rm -rf /*)"
        ];
        description = "List of tools/patterns to deny";
      };

      ask = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of tools/patterns to ask permission for";
      };

      defaultMode = mkOption {
        type = types.enum [ "acceptEdits" "bypassPermissions" "default" "plan" ];
        default = "default";
        description = "Default permission mode for tools not explicitly listed";
      };

      additionalDirectories = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional directories to grant access to";
      };
    };

    environmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = { }; # Empty by default - Claude doesn't persist env in .claude.json
      description = "Environment variables";
    };

    experimental = mkOption {
      type = types.attrs;
      default = { };
      description = "Experimental features";
    };

    enterpriseSettings = {
      enable = mkOption {
        type = types.bool;
        default = true; # Enabled - managed at NixOS system level
        description = "Enable Enterprise Managed Settings (configured at NixOS system level)";
      };

      path = mkOption {
        type = types.str;
        default = "/etc/claude-code/managed-settings.json";
        description = "Path to enterprise managed settings file (requires root)";
      };
    };

    nixcfgPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/src/nixcfg";
      description = "Path to the nixcfg repository containing claude-runtime directory";
      example = "/home/user/projects/my-nixos-config";
    };

    # Account profiles with API proxy and secrets support
    accounts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          # ─── Existing Options (preserved) ─────────────────────────
          enable = mkEnableOption "this Claude Code account profile";

          displayName = mkOption {
            type = types.str;
            description = "Display name for this account profile";
            example = "Claude Max Account";
          };

          model = mkOption {
            type = types.nullOr (types.enum [ "sonnet" "opus" "haiku" ]);
            default = null;
            description = "Default model for this account (null means use global default)";
          };

          # ─── NEW: API Configuration ───────────────────────────────
          api = {
            baseUrl = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Custom API base URL for this account.
                Set to null (default) to use the standard Anthropic API.
                Example: "https://codecompanionv2.d-dp.nextcloud.aero"
              '';
              example = "https://api.example.com/v1";
            };

            authMethod = mkOption {
              type = types.enum [ "api-key" "bearer" "bedrock" ];
              default = "api-key";
              description = ''
                Authentication method for this account:
                - "api-key": Standard Anthropic API key (ANTHROPIC_API_KEY)
                - "bearer": Bearer token authentication (ANTHROPIC_AUTH_TOKEN)
                - "bedrock": AWS Bedrock authentication
              '';
            };

            disableApiKey = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Set ANTHROPIC_API_KEY to an empty string.
                Required by some proxy servers that reject requests with API keys.
              '';
            };

            modelMappings = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = ''
                Map Claude model names to proxy-specific model names.
                Keys are Claude model names (sonnet, opus, haiku).
                Values are the proxy model identifiers.
              '';
              example = {
                sonnet = "devstral";
                opus = "devstral";
                haiku = "qwen-a3b";
              };
            };
          };

          # ─── NEW: Secrets Configuration ───────────────────────────
          secrets = {
            bearerToken = mkOption {
              type = types.nullOr (types.submodule {
                options = {
                  bitwarden = mkOption {
                    type = types.submodule {
                      options = {
                        item = mkOption {
                          type = types.str;
                          description = "Bitwarden item name containing the token";
                          example = "Code-Companion";
                        };
                        field = mkOption {
                          type = types.str;
                          description = "Field name within the Bitwarden item";
                          example = "bearer_token";
                        };
                      };
                    };
                    description = "Bitwarden reference for retrieving the bearer token via rbw";
                  };
                };
              });
              default = null;
              description = ''
                Secret management for bearer token authentication.
                On Nix-managed hosts, tokens are retrieved via rbw (Bitwarden CLI).
                On Termux, tokens are read from ~/.secrets/claude-<account>-token files.
              '';
            };
          };

          # ─── NEW: Extra Environment Variables ─────────────────────
          extraEnvVars = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = ''
              Additional environment variables to set for this account.
              These are exported before launching Claude Code.
            '';
            example = {
              DISABLE_TELEMETRY = "1";
              CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
              DISABLE_ERROR_REPORTING = "1";
            };
          };
        };
      });
      default = { };
      description = ''
        Claude Code account profiles.
        Each account can have its own API configuration, secrets, and environment.
        Common accounts: max, pro, work
      '';
    };

    defaultAccount = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default account to use when running 'claude' without profile";
    };


    # Internal options for module communication
    _internal = {
      mcpServers = mkOption {
        type = types.attrs;
        default = { };
        internal = true;
      };
      hooks = mkOption {
        type = types.attrs;
        default = { };
        internal = true;
      };
      subAgentFiles = mkOption {
        type = types.attrs;
        default = { };
        internal = true;
      };
      slashCommandDefs = mkOption {
        type = types.attrs;
        default = { };
        internal = true;
      };
    };
  };

  config =
    let
      cfg = config.programs.claude-code-enhanced;

      # Use the configurable nixcfg path
      nixcfgPath = cfg.nixcfgPath;
      runtimePath = "${nixcfgPath}/claude-runtime";
      templatesPath = "${nixcfgPath}/claude-templates";

      # Read the memory file content at build time
      userGlobalMemoryContent = builtins.readFile ./claude-code-user-memory-template.md;

      # Script to handle memory updates and rebuild
      memoryUpdateScript = pkgs.writeScriptBin "claude-memory-update" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
      
        echo "Memory updated, rebuilding claude-code configuration..."
        cd "${nixcfgPath}"
      
        # Commit the memory change
        ${pkgs.git}/bin/git add home/modules/claude-code-user-memory-template.md
        ${pkgs.git}/bin/git commit -m "Update Claude Code user-global memory" || true
      
        # Rebuild home-manager configuration
        ${pkgs.home-manager}/bin/home-manager switch --flake .
      
        echo "✅ Memory updated and propagated to all accounts"
      '';

      # WSL environment detection for Claude Desktop
      isWSLEnabled = config.targets.wsl.enable or false;
      wslDistroName =
        if isWSLEnabled then
          config.targets.wsl.wslDistroName or "NixOS"
        else
          "NixOS";

      # Convert MCP server configs to WSL-compatible format for Claude Desktop
      mkClaudeDesktopServer = name: serverCfg:
        let
          # Build environment variable prefix for WSL command
          envVars = serverCfg.env or { };
          envPrefix =
            if isWSLEnabled && envVars != { } then
              lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg (toString v)}") envVars)
            else "";

          # For WSL, we need to set env vars in the command since JSON env doesn't pass through
          wslCommand =
            if envPrefix != "" then
              "sh -c '${envPrefix} exec ${lib.escapeShellArg serverCfg.command} ${lib.concatStringsSep " " (map lib.escapeShellArg serverCfg.args)}'"
            else
              "${serverCfg.command} ${lib.concatStringsSep " " (map lib.escapeShellArg serverCfg.args)}";
        in
        {
          command = if isWSLEnabled then "C:\\WINDOWS\\system32\\wsl.exe" else serverCfg.command;
          args =
            if isWSLEnabled then
              [ "-d" wslDistroName "-e" "sh" "-c" wslCommand ]
            else
              serverCfg.args;
          env = if isWSLEnabled then { } else (serverCfg.env or { });
        } // (lib.optionalAttrs (serverCfg ? timeout) { inherit (serverCfg) timeout; })
        // (lib.optionalAttrs (serverCfg ? retries) { inherit (serverCfg) retries; });

      # Generate Claude Desktop configuration with WSL wrapper
      claudeDesktopMcpServers = lib.mapAttrs mkClaudeDesktopServer cfg._internal.mcpServers;

      # Filter MCP servers for Claude Code (exclude Claude Desktop only servers)
      claudeCodeMcpServers = removeAttrs cfg._internal.mcpServers [ "mcp-filesystem" "cli-mcp-server" ];

      # Base settings configuration
      mkSettingsTemplate = model: pkgs.writeText "claude-settings.json" (builtins.toJSON (
        let
          hasHooks = cfg._internal.hooks.PreToolUse != null || cfg._internal.hooks.PostToolUse != null ||
            cfg._internal.hooks.Start != null || cfg._internal.hooks.Stop != null;
          cleanHooks = filterAttrs (n: v: v != null) cfg._internal.hooks;
          hasStatusline = cfg._internal.statuslineSettings != { };

          # Build v2.0 permissions object
          permissionsV2 = {
            allow = cfg.permissions.allow;
            deny = cfg.permissions.deny;
            ask = cfg.permissions.ask;
            defaultMode = cfg.permissions.defaultMode;
            additionalDirectories = cfg.permissions.additionalDirectories;
          };
        in
        {
          model = model;
          permissions = permissionsV2;
        }
        // optionalAttrs (cfg.environmentVariables != { }) { env = cfg.environmentVariables; }
        // optionalAttrs hasHooks { hooks = cleanHooks; }
        // optionalAttrs (cfg.experimental != { }) { experimental = cfg.experimental; }
        // optionalAttrs hasStatusline cfg._internal.statuslineSettings
        // optionalAttrs cfg.enableProjectOverrides {
          projectOverrides = {
            enabled = true;
            searchPaths = cfg.projectOverridePaths;
          };
        }
      ));

      # Default settings template
      settingsTemplate = mkSettingsTemplate cfg.defaultModel;

      # MCP configuration template
      mcpTemplate = pkgs.writeText "claude-mcp.json" (builtins.toJSON {
        mcpServers = claudeCodeMcpServers;
      });

      # CLAUDE.md template
      claudeMdTemplate = pkgs.writeText "claude-memory.md" userGlobalMemoryContent;

      # Sub-agent file templates (from sub-agents.nix)
      agentTemplates = mapAttrs
        (name: agent:
          pkgs.writeText "claude-agent-${builtins.baseNameOf name}" agent.text
        )
        cfg._internal.subAgentFiles;

      # Enterprise Settings template (top-precedence configuration)
      enterpriseSettingsTemplate = pkgs.writeText "enterprise-managed-settings.json" (builtins.toJSON (
        let
          hasHooks = cfg._internal.hooks.PreToolUse != null || cfg._internal.hooks.PostToolUse != null ||
            cfg._internal.hooks.Start != null || cfg._internal.hooks.Stop != null;
          cleanHooks = filterAttrs (n: v: v != null) cfg._internal.hooks;
          hasStatusline = cfg._internal.statuslineSettings != { };

          # Build v2.0 permissions object
          permissionsV2 = {
            allow = cfg.permissions.allow;
            deny = cfg.permissions.deny;
            ask = cfg.permissions.ask;
            defaultMode = cfg.permissions.defaultMode;
            additionalDirectories = cfg.permissions.additionalDirectories;
          };
        in
        {
          # Core Claude Code configuration (enterprise-managed)
          model = cfg.defaultModel;

          # Security and permissions (enforced organization-wide)
          permissions = permissionsV2;
        }
        // optionalAttrs (cfg.environmentVariables != { }) { env = cfg.environmentVariables; }
        // optionalAttrs hasHooks { hooks = cleanHooks; }
        // optionalAttrs (cfg.experimental != { }) { experimental = cfg.experimental; }
        // optionalAttrs hasStatusline cfg._internal.statuslineSettings
        // optionalAttrs cfg.enableProjectOverrides {
          projectOverrides = {
            enabled = true;
            searchPaths = cfg.projectOverridePaths;
          };
        }
      ));

    in
    mkIf cfg.enable {
      # Install required packages
      home.packages = with pkgs; [
        nodejs_22
        git
        ripgrep
        fd
        jq
        uv # Python package manager with uvx for running Python MCP servers
        memoryUpdateScript # Add the memory update script
        # Account-specific command scripts now provided by validated-scripts module
      ] ++ [
      ] ++ optionals (cfg.mcpServers.sequentialThinkingPython.enable or false) [
        # Python/UV version wrapper - only included when explicitly enabled
        (pkgs.writers.writeBashBin "sequential-thinking-mcp" ''
          exec ${nixmcp.packages.${pkgs.system}.sequential-thinking-mcp}/bin/sequential-thinking-mcp "$@"
        '')
      ] ++ optionals cfg.hooks.formatting.enable [
        nixpkgs-fmt
        black
        nodePackages.prettier
        rustfmt
        go
        shfmt
      ] ++ optionals cfg.hooks.linting.enable [
        python3Packages.pylint
        nodePackages.eslint
        shellcheck
      ] ++ optionals (cfg.hooks.notifications.enable && !stdenv.isDarwin) [
        libnotify
      ];

      # Symlink config directories to writable locations in nixcfg
      home.file = mkMerge [
        # Account-specific directories from cfg.accounts
        (mkMerge (mapAttrsToList
          (name: account: mkIf account.enable {
            ".claude-${name}".source = config.lib.file.mkOutOfStoreSymlink "${runtimePath}/.claude-${name}";
          })
          cfg.accounts))

        # Base .claude directory if defaultAccount is set
        (mkIf (cfg.defaultAccount != null) {
          ".claude".source = config.lib.file.mkOutOfStoreSymlink "${runtimePath}/.claude-${cfg.defaultAccount}";
        })

        # Claude Desktop configuration (always generated if MCP servers exist)
        (mkIf (cfg._internal.mcpServers != { }) {
          "claude-mcp-config.json".text = builtins.toJSON { mcpServers = claudeDesktopMcpServers; };
        })

      ];

      # Activation script to populate runtime directories with templates
      home.activation.claudeConfigTemplates = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Validate nixcfg path exists and is writable
        if [[ ! -d "${nixcfgPath}" ]]; then
          echo "❌ Error: nixcfgPath does not exist: ${nixcfgPath}"
          echo "Either create the directory or update programs.claude-code.nixcfgPath"
          exit 1
        fi
      
        if [[ ! -w "${nixcfgPath}" ]]; then
          echo "❌ Error: nixcfgPath is not writable: ${nixcfgPath}"
          exit 1
        fi
      
        $DRY_RUN_CMD mkdir -p ${runtimePath}
      
        # Function to copy template with writable permissions (always updates)
        copy_template() {
          local template="$1"
          local target="$2"
          $DRY_RUN_CMD rm -f "$target"  # Remove read-only file first
          $DRY_RUN_CMD cp "$template" "$target"
          $DRY_RUN_CMD chmod 644 "$target"
          echo "Updated template: $target"
        }

        ${optionalString cfg.enterpriseSettings.enable ''
        # ENTERPRISE SETTINGS: Managed at NixOS system level
        echo "📋 Enterprise Settings managed by NixOS system configuration at /etc/claude-code/managed-settings.json"
      
        if [[ -f "/etc/claude-code/managed-settings.json" ]]; then
          echo "✅ Enterprise Settings found at system level - configuration will use top precedence"
        else
          echo "⚠️ Warning: Enterprise Settings enabled but /etc/claude-code/managed-settings.json not found"
          echo "    Enterprise settings should be configured at the NixOS system level"
        fi
        ''}

        # ACCOUNT CONFIGURATION: Deploy settings for each enabled account
        ${concatStringsSep "\n" (mapAttrsToList (name: account: ''
          if [[ "${toString account.enable}" == "1" ]]; then
            accountDir="${runtimePath}/.claude-${name}"
            echo "⚙️ Configuring account: ${name}"
          
            # RUNTIME-ONLY: Create directories for session data
            $DRY_RUN_CMD mkdir -p "$accountDir"/{logs,projects,shell-snapshots,statsig,todos,commands}
          
            # SETTINGS: Always deploy v2.0 schema settings (migration-safe)
            copy_template "${mkSettingsTemplate (if account.model != null then account.model else cfg.defaultModel)}" "$accountDir/settings.json"
            echo "🔧 Updated settings to v2.0 schema: $accountDir/settings.json"
          
            # MCP SERVERS: Always deploy separate .mcp.json file (v2.0 schema)
            copy_template "${mcpTemplate}" "$accountDir/.mcp.json"
            echo "🔧 Updated MCP servers configuration: $accountDir/.mcp.json"
          
            # MEMORY: Deploy CLAUDE.md with correct permissions
            if [[ -f "$accountDir/CLAUDE.md" ]]; then
              echo "✅ Preserved existing memory file: $accountDir/CLAUDE.md"
              # Ensure it has correct permissions
              $DRY_RUN_CMD chmod ${if cfg.memoryCommands.makeWritable then "644" else "444"} "$accountDir/CLAUDE.md"
            else
              copy_template "${claudeMdTemplate}" "$accountDir/CLAUDE.md"
              $DRY_RUN_CMD chmod ${if cfg.memoryCommands.makeWritable then "644" else "444"} "$accountDir/CLAUDE.md"
              echo "🆕 Created memory file: $accountDir/CLAUDE.md"
            fi
          
            # Enforce all Nix-managed settings in .claude.json (preserving runtime data)
            if [[ -f "$accountDir/.claude.json" ]]; then
              echo "🔧 Enforcing Nix-managed settings in .claude.json..."
            
              # Use jq with --argjson for safe JSON handling (v2.0: no MCP servers in .claude.json)
              # Build jq arguments dynamically
              jq_args=(--argjson permissions '${builtins.toJSON {
                allow = cfg.permissions.allow;
                deny = cfg.permissions.deny;
                ask = cfg.permissions.ask;
                defaultMode = cfg.permissions.defaultMode;
                additionalDirectories = cfg.permissions.additionalDirectories;
              }}')
              ${optionalString (cfg.environmentVariables != {}) ''jq_args+=(--argjson env '${builtins.toJSON cfg.environmentVariables}')''}
              ${optionalString (cfg._internal.statuslineSettings != {}) ''jq_args+=(--argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}')''}
              ${optionalString (cfg._internal.hooks != {}) ''jq_args+=(--argjson hooks '${builtins.toJSON (filterAttrs (n: v: v != null) cfg._internal.hooks)}')''}
            
              $DRY_RUN_CMD ${pkgs.jq}/bin/jq "''${jq_args[@]}" \
                '. |
                .permissions = $permissions
                ${optionalString (cfg.environmentVariables != {}) ''| .env = $env''}
                ${optionalString (cfg._internal.statuslineSettings != {}) ''| .statusLine = $statusLine''}
                ${optionalString (cfg._internal.hooks != {}) ''| .hooks = $hooks''}
                ' "$accountDir/.claude.json" > "$accountDir/.claude.json.tmp"
            
              $DRY_RUN_CMD mv "$accountDir/.claude.json.tmp" "$accountDir/.claude.json"
              echo "✅ Nix-managed settings enforced in .claude.json"
            else
              # Create new file without MCP servers (v2.0: MCP in separate .mcp.json)
              echo '{}' > "$accountDir/.claude.json"
              $DRY_RUN_CMD chmod 644 "$accountDir/.claude.json"
              echo "🆕 Created minimal runtime config: $accountDir/.claude.json"
            fi

            # SUB-AGENTS: Deploy agent files to agents directory
            ${optionalString (cfg._internal.subAgentFiles != {}) ''
            $DRY_RUN_CMD mkdir -p "$accountDir/agents"
            ${concatStringsSep "\n" (mapAttrsToList (path: template: ''
            copy_template "${template}" "$accountDir/agents/${builtins.baseNameOf path}"
            '') agentTemplates)}
            echo "🤖 Deployed ${toString (length (attrNames cfg._internal.subAgentFiles))} sub-agent(s)"
            ''}

            echo "✅ Account ${name} configured with statusline support"
          fi
        '') cfg.accounts)}

        # FALLBACK BASE .claude DIRECTORY (for default account support)
        ${optionalString (cfg.defaultAccount != null) ''
        baseDir="${runtimePath}/.claude"
        echo "📁 Setting up fallback base directory"
      
        # RUNTIME-ONLY: Create directories for session data
        $DRY_RUN_CMD mkdir -p "$baseDir"/{logs,projects,shell-snapshots,statsig,todos,commands}
      
        # SETTINGS: Deploy base settings (v2.0 schema without MCP servers)
        copy_template "${settingsTemplate}" "$baseDir/settings.json"
      
        # MCP SERVERS: Always deploy separate .mcp.json file (v2.0 schema)
        copy_template "${mcpTemplate}" "$baseDir/.mcp.json"
        echo "🔧 Updated MCP servers configuration: $baseDir/.mcp.json"
      
        # MEMORY: Deploy CLAUDE.md with correct permissions
        if [[ -f "$baseDir/CLAUDE.md" ]]; then
          echo "✅ Preserved existing memory file: $baseDir/CLAUDE.md"
          # Ensure it has correct permissions
          $DRY_RUN_CMD chmod ${if cfg.memoryCommands.makeWritable then "644" else "444"} "$baseDir/CLAUDE.md"
        else
          copy_template "${claudeMdTemplate}" "$baseDir/CLAUDE.md"
          $DRY_RUN_CMD chmod ${if cfg.memoryCommands.makeWritable then "644" else "444"} "$baseDir/CLAUDE.md"
          echo "🆕 Created memory file: $baseDir/CLAUDE.md"
        fi
      
        # Enforce all Nix-managed settings in .claude.json (preserving runtime data)
        if [[ -f "$baseDir/.claude.json" ]]; then
          echo "🔧 Enforcing Nix-managed settings in .claude.json..."
        
          # Use jq with --argjson for safe JSON handling (v2.0: no MCP servers in .claude.json)
          # Build jq arguments dynamically
          jq_args=(--argjson permissions '${builtins.toJSON {
            allow = cfg.permissions.allow;
            deny = cfg.permissions.deny;
            ask = cfg.permissions.ask;
            defaultMode = cfg.permissions.defaultMode;
            additionalDirectories = cfg.permissions.additionalDirectories;
          }}')
          ${optionalString (cfg.environmentVariables != {}) ''jq_args+=(--argjson env '${builtins.toJSON cfg.environmentVariables}')''}
          ${optionalString (cfg._internal.statuslineSettings != {}) ''jq_args+=(--argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}')''}
          ${optionalString (cfg._internal.hooks != {}) ''jq_args+=(--argjson hooks '${builtins.toJSON (filterAttrs (n: v: v != null) cfg._internal.hooks)}')''}
        
          $DRY_RUN_CMD ${pkgs.jq}/bin/jq "''${jq_args[@]}" \
            '. |
            .permissions = $permissions
            ${optionalString (cfg.environmentVariables != {}) ''| .env = $env''}
            ${optionalString (cfg._internal.statuslineSettings != {}) ''| .statusLine = $statusLine''}
            ${optionalString (cfg._internal.hooks != {}) ''| .hooks = $hooks''}
            ' "$baseDir/.claude.json" > "$baseDir/.claude.json.tmp"
        
          $DRY_RUN_CMD mv "$baseDir/.claude.json.tmp" "$baseDir/.claude.json"
          echo "✅ Nix-managed settings enforced in .claude.json"
        else
          # Create new file without MCP servers (v2.0: MCP in separate .mcp.json)
          echo '{}' > "$baseDir/.claude.json"
          $DRY_RUN_CMD chmod 644 "$baseDir/.claude.json"
          echo "🆕 Created minimal runtime config: $baseDir/.claude.json"
        fi

        # SUB-AGENTS: Deploy agent files to agents directory
        ${optionalString (cfg._internal.subAgentFiles != {}) ''
        $DRY_RUN_CMD mkdir -p "$baseDir/agents"
        ${concatStringsSep "\n" (mapAttrsToList (path: template: ''
        copy_template "${template}" "$baseDir/agents/${builtins.baseNameOf path}"
        '') agentTemplates)}
        echo "🤖 Deployed ${toString (length (attrNames cfg._internal.subAgentFiles))} sub-agent(s)"
        ''}

        echo "✅ Base directory configured with statusline support"
        ''}
      '';

      # Add shell functions for claude-status and claude-close using cfg.accounts
      programs.bash.initExtra = mkIf (cfg.accounts != { }) (mkAfter ''
        # Claude Code Session Management
        claude-status() {
          local found_sessions=false
          echo "🔍 Checking Claude Code sessions..."
        
          for account in ${lib.concatStringsSep " " (lib.attrNames (lib.filterAttrs (n: a: a.enable) cfg.accounts))}; do
            local pidfile="/tmp/claude-''${account}.pid"
            if [[ -f "$pidfile" ]]; then
              local pid=$(cat "$pidfile")
              if kill -0 "$pid" 2>/dev/null; then
                echo "✅ Claude Code ($account) is running (PID: $pid)"
                found_sessions=true
              else
                echo "⚠️  Stale pidfile for $account (removing)"
                rm -f "$pidfile"
              fi
            fi
          done
        
          if [[ "$found_sessions" == "false" ]]; then
            echo "📭 No Claude Code sessions are currently running"
          fi
        }
      
        # Helper function to force-close a Claude Code session
        claude-close() {
          local account="''${1:-}"
          if [[ -z "$account" ]]; then
            echo "Usage: claude-close <account>"
            echo "Available accounts: ${lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (n: a: a.enable) cfg.accounts))}"
            return 1
          fi
        
          local pidfile="/tmp/claude-''${account}.pid"
          if [[ -f "$pidfile" ]]; then
            local pid=$(cat "$pidfile")
            if kill -0 "$pid" 2>/dev/null; then
              echo "🛑 Closing Claude Code ($account) session (PID: $pid)..."
              kill "$pid"
              sleep 1
              if kill -0 "$pid" 2>/dev/null; then
                echo "⚠️  Process still running, forcing termination..."
                kill -9 "$pid"
              fi
              rm -f "$pidfile"
              echo "✅ Claude Code ($account) session closed"
            else
              echo "⚠️  Process not found, removing stale pidfile"
              rm -f "$pidfile"
            fi
          else
            echo "❌ No Claude Code ($account) session found"
          fi
        }
      '');

      programs.zsh.initContent = mkIf (cfg.accounts != { }) (mkAfter ''
        # Claude Code Session Management
        claude-status() {
          local found_sessions=false
          echo "🔍 Checking Claude Code sessions..."
        
          for account in max pro; do
            local pidfile="/tmp/claude-''${account}.pid"
            if [[ -f "$pidfile" ]]; then
              local pid=$(cat "$pidfile")
              if kill -0 "$pid" 2>/dev/null; then
                echo "✅ Claude Code ($account) is running (PID: $pid)"
                found_sessions=true
              else
                echo "⚠️  Stale pidfile for $account (removing)"
                rm -f "$pidfile"
              fi
            fi
          done
        
          if [[ "$found_sessions" == "false" ]]; then
            echo "📭 No Claude Code sessions are currently running"
          fi
        }
      
        # Helper function to force-close a Claude Code session
        claude-close() {
          local account="''${1:-}"
          if [[ -z "$account" ]]; then
            echo "Usage: claude-close <account>"
            echo "Available accounts: ${lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (n: a: a.enable) cfg.accounts))}"
            return 1
          fi
        
          local pidfile="/tmp/claude-''${account}.pid"
          if [[ -f "$pidfile" ]]; then
            local pid=$(cat "$pidfile")
            if kill -0 "$pid" 2>/dev/null; then
              echo "🛑 Closing Claude Code ($account) session (PID: $pid)..."
              kill "$pid"
              sleep 1
              if kill -0 "$pid" 2>/dev/null; then
                echo "⚠️  Process still running, forcing termination..."
                kill -9 "$pid"
              fi
              rm -f "$pidfile"
              echo "✅ Claude Code ($account) session closed"
            else
              echo "⚠️  Process not found, removing stale pidfile"
              rm -f "$pidfile"
            fi
          else
            echo "❌ No Claude Code ($account) session found"
          fi
        }
      '');

      # Assertions
      assertions = [
        {
          assertion = cfg.hooks.notifications.enable ->
            (pkgs.stdenv.isDarwin || config.home.packages or [ ] != [ ]);
          message = "Notifications require either macOS or a Linux notification daemon";
        }
        {
          assertion = cfg.defaultAccount != null -> cfg.accounts ? ${cfg.defaultAccount};
          message = "Default account '${cfg.defaultAccount}' must be defined in accounts";
        }
        {
          assertion = cfg.defaultAccount != null -> cfg.accounts.${cfg.defaultAccount}.enable;
          message = "Default account '${cfg.defaultAccount}' must be enabled";
        }
        {
          assertion = lib.hasPrefix "/" cfg.nixcfgPath;
          message = "nixcfgPath must be an absolute path, got: ${cfg.nixcfgPath}";
        }
        {
          assertion = builtins.isString cfg.nixcfgPath && cfg.nixcfgPath != "";
          message = "nixcfgPath cannot be empty";
        }
      ];
    };
}
