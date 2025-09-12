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
    ./claude-code-statusline.nix
  ];

  options.programs.claude-code = {
    enable = mkEnableOption "Claude Code with simplified mkOutOfStoreSymlink management";
    
    debug = mkEnableOption "debug output for all components";
    
    defaultModel = mkOption {
      type = types.enum ["sonnet" "opus" "haiku"];
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
    
    permissions = mkOption {
      type = types.attrs;
      default = {
        allow = [
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
        deny = [
          "Search"
          "Find"
          "Bash(rm -rf /*)"
        ];
      };
      description = "Permission rules";
    };
    
    environmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = {};  # Empty by default - Claude doesn't persist env in .claude.json
      description = "Environment variables";
    };
    
    experimental = mkOption {
      type = types.attrs;
      default = {};
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

    # Multi-account support options
    accounts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this Claude Code account profile";
          
          displayName = mkOption {
            type = types.str;
            description = "Display name for this account profile";
            example = "Work Account";
          };
          
          model = mkOption {
            type = types.nullOr (types.enum ["sonnet" "opus" "haiku"]);
            default = null;
            description = "Default model for this account (null means use global default)";
          };
          
          aliases = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Additional command aliases for this account";
            example = ["claudework" "cw"];
          };
        };
      });
      default = {};
      description = "Multiple Claude Code account profiles";
      example = literalExpression ''
        {
          pro = {
            enable = true;
            displayName = "Claude Pro Account";
            aliases = ["claudepro" "cp"];
          };
          max = {
            enable = true;
            displayName = "Claude Max Account";
            aliases = ["claudemax" "cm"];
          };
        }
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
        default = {};
        internal = true;
      };
      hooks = mkOption {
        type = types.attrs;
        default = {};
        internal = true;
      };
      subAgentFiles = mkOption {
        type = types.attrs;
        default = {};
        internal = true;
      };
      slashCommandDefs = mkOption {
        type = types.attrs;
        default = {};
        internal = true;
      };
    };
  };
  
  config = let
    cfg = config.programs.claude-code;
    
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
    wslDistroName = if isWSLEnabled then 
      config.targets.wsl.wslDistroName or "NixOS"
    else 
      "NixOS";
    
    # Convert MCP server configs to WSL-compatible format for Claude Desktop
    mkClaudeDesktopServer = name: serverCfg: 
      let
        # Build environment variable prefix for WSL command
        envVars = serverCfg.env or {};
        envPrefix = if isWSLEnabled && envVars != {} then
          lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg (toString v)}") envVars)
        else "";
        
        # For WSL, we need to set env vars in the command since JSON env doesn't pass through
        wslCommand = if envPrefix != "" then
          "sh -c '${envPrefix} exec ${lib.escapeShellArg serverCfg.command} ${lib.concatStringsSep " " (map lib.escapeShellArg serverCfg.args)}'"
        else
          "${serverCfg.command} ${lib.concatStringsSep " " (map lib.escapeShellArg serverCfg.args)}";
      in {
        command = if isWSLEnabled then "C:\\WINDOWS\\system32\\wsl.exe" else serverCfg.command;
        args = if isWSLEnabled then 
          [ "-d" wslDistroName "-e" "sh" "-c" wslCommand ]
        else 
          serverCfg.args;
        env = if isWSLEnabled then {} else (serverCfg.env or {});
      } // (lib.optionalAttrs (serverCfg ? timeout) { inherit (serverCfg) timeout; })
        // (lib.optionalAttrs (serverCfg ? retries) { inherit (serverCfg) retries; });
    
    # Generate Claude Desktop configuration with WSL wrapper
    claudeDesktopMcpServers = lib.mapAttrs mkClaudeDesktopServer cfg._internal.mcpServers;
    
    # Filter MCP servers for Claude Code (exclude Claude Desktop only servers)
    claudeCodeMcpServers = removeAttrs cfg._internal.mcpServers [ "mcp-filesystem" "cli-mcp-server" ];
    
    # Base settings configuration
    mkSettingsTemplate = model: pkgs.writeText "claude-settings.json" (builtins.toJSON (let
      hasHooks = cfg._internal.hooks.PreToolUse != null || cfg._internal.hooks.PostToolUse != null || 
                 cfg._internal.hooks.Start != null || cfg._internal.hooks.Stop != null;
      cleanHooks = filterAttrs (n: v: v != null) cfg._internal.hooks;
      hasStatusline = cfg._internal.statuslineSettings != {};
      hasMcpServers = claudeCodeMcpServers != {};
    in {
      model = model;
    } // optionalAttrs (cfg.permissions != {}) { permissions = cfg.permissions; }
      // optionalAttrs (cfg.environmentVariables != {}) { env = cfg.environmentVariables; }
      // optionalAttrs hasHooks { hooks = cleanHooks; }
      // optionalAttrs (cfg.experimental != {}) { experimental = cfg.experimental; }
      // optionalAttrs hasStatusline cfg._internal.statuslineSettings
      // optionalAttrs hasMcpServers { mcpServers = claudeCodeMcpServers; }
      // optionalAttrs cfg.enableProjectOverrides { 
        projectOverrides = {
          enabled = true;
          searchPaths = cfg.projectOverridePaths;
        };
      }));
    
    # Default settings template
    settingsTemplate = mkSettingsTemplate cfg.defaultModel;

    # MCP configuration template
    mcpTemplate = pkgs.writeText "claude-mcp.json" (builtins.toJSON { 
      mcpServers = claudeCodeMcpServers;
    });

    # CLAUDE.md template
    claudeMdTemplate = pkgs.writeText "claude-memory.md" userGlobalMemoryContent;

    # Enterprise Settings template (top-precedence configuration)
    enterpriseSettingsTemplate = pkgs.writeText "enterprise-managed-settings.json" (builtins.toJSON (let
      hasHooks = cfg._internal.hooks.PreToolUse != null || cfg._internal.hooks.PostToolUse != null || 
                 cfg._internal.hooks.Start != null || cfg._internal.hooks.Stop != null;
      cleanHooks = filterAttrs (n: v: v != null) cfg._internal.hooks;
      hasStatusline = cfg._internal.statuslineSettings != {};
    in {
      # Core Claude Code configuration (enterprise-managed)
      model = cfg.defaultModel;
      
      # Security and permissions (enforced organization-wide)
    } // optionalAttrs (cfg.permissions != {}) { permissions = cfg.permissions; }
      // optionalAttrs (cfg.environmentVariables != {}) { env = cfg.environmentVariables; }
      // optionalAttrs hasHooks { hooks = cleanHooks; }
      // optionalAttrs (cfg.experimental != {}) { experimental = cfg.experimental; }
      // optionalAttrs hasStatusline cfg._internal.statuslineSettings
      // optionalAttrs cfg.enableProjectOverrides { 
        projectOverrides = {
          enabled = true;
          searchPaths = cfg.projectOverridePaths;
        };
      }));

    # Generate shell aliases for each account
    accountAliases = lib.flatten (lib.mapAttrsToList (name: account:
      let
        configDir = "${runtimePath}/.claude-${name}";
        
        # Main command for this account with coalescence and single-instance enforcement
        mainCmd = ''
          claude-${name}() {
            local account="${name}"
            local config_dir="${configDir}"
            local pidfile="/tmp/claude-''${account}.pid"
            
            # Single instance enforcement
            if [[ -f "$pidfile" ]]; then
              local existing_pid=$(cat "$pidfile")
              if kill -0 "$existing_pid" 2>/dev/null; then
                echo "❌ Claude Code (${account.displayName}) is already running (PID: $existing_pid)"
                echo "   Please close the existing session first or use 'kill $existing_pid' to force close"
                return 1
              else
                # Stale pidfile, remove it
                rm -f "$pidfile"
              fi
            fi
            
            # Merge Nix-managed configuration at startup
            local config_file="$config_dir/.claude.json"
            if [[ -f "$config_file" ]]; then
              # Create temp config with Nix-managed fields
              ${pkgs.jq}/bin/jq \
                --argjson mcpServers '${builtins.toJSON claudeCodeMcpServers}' \
                --argjson permissions '${builtins.toJSON cfg.permissions}' \
                ${optionalString (cfg.environmentVariables != {}) "--argjson env '${builtins.toJSON cfg.environmentVariables}'"} \
                --argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}' \
                --argjson hooks '${builtins.toJSON (filterAttrs (n: v: v != null) cfg._internal.hooks)}' \
                '{mcpServers: $mcpServers, permissions: $permissions${optionalString (cfg.environmentVariables != {}) ", env: $env"}, statusLine: $statusLine, hooks: $hooks}' \
                > "$config_file.nix-managed"
              
              # Use mergejson to selectively merge only managed fields
              if mergejson "$config_file" "$config_file.nix-managed" '.' --confirm; then
                echo "✅ Configuration synchronized"
              else
                echo "⚠️  Configuration merge cancelled, continuing with existing config"
              fi
              rm -f "$config_file.nix-managed"
            fi
            
            # Launch Claude Code with proper PID tracking
            export CLAUDE_CONFIG_DIR="$config_dir"
            echo "🤖 Launching Claude ${account.displayName}..."
            
            # Use trap to ensure cleanup even if interrupted
            trap "rm -f '$pidfile'" EXIT INT TERM
            
            # Write wrapper PID (we'll update it with actual PID if we can)
            echo $$ > "$pidfile"
            
            # Launch Claude directly (no background)
            command claude "$@"
            local exit_code=$?
            
            # Cleanup
            rm -f "$pidfile"
            unset CLAUDE_CONFIG_DIR
            trap - EXIT INT TERM
            
            return $exit_code
          }
        '';
        
        # Additional aliases
        aliasCmds = map (alias: ''
          ${alias}() {
            claude-${name} "$@"
          }
        '') account.aliases;
      in
      if account.enable then [mainCmd] ++ aliasCmds else []
    ) cfg.accounts);
    
    # Default claude command override if defaultAccount is set
    defaultAccountOverride = if cfg.defaultAccount != null then
      let
        configDir = "${runtimePath}/.claude-${cfg.defaultAccount}";
        account = cfg.accounts.${cfg.defaultAccount};
      in ''
        claude() {
          local account="${cfg.defaultAccount}"
          local config_dir="${configDir}"
          local pidfile="/tmp/claude-''${account}.pid"
          
          # Single instance enforcement
          if [[ -f "$pidfile" ]]; then
            local existing_pid=$(cat "$pidfile")
            if kill -0 "$existing_pid" 2>/dev/null; then
              echo "❌ Claude Code (${account.displayName}) is already running (PID: $existing_pid)"
              echo "   Please close the existing session first or use 'kill $existing_pid' to force close"
              return 1
            else
              # Stale pidfile, remove it
              rm -f "$pidfile"
            fi
          fi
          
          # Merge Nix-managed configuration at startup
          local config_file="$config_dir/.claude.json"
          if [[ -f "$config_file" ]]; then
            # Create temp config with Nix-managed fields
            ${pkgs.jq}/bin/jq \
              --argjson mcpServers '${builtins.toJSON claudeCodeMcpServers}' \
              --argjson permissions '${builtins.toJSON cfg.permissions}' \
              ${optionalString (cfg.environmentVariables != {}) "--argjson env '${builtins.toJSON cfg.environmentVariables}'"} \
              --argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}' \
              --argjson hooks '${builtins.toJSON (filterAttrs (n: v: v != null) cfg._internal.hooks)}' \
              '{mcpServers: $mcpServers, permissions: $permissions${optionalString (cfg.environmentVariables != {}) ", env: $env"}, statusLine: $statusLine, hooks: $hooks}' \
              > "$config_file.nix-managed"
            
            # Use mergejson to selectively merge only managed fields
            if mergejson "$config_file" "$config_file.nix-managed" '.' --confirm; then
              echo "✅ Configuration synchronized"
            else
              echo "⚠️  Configuration merge cancelled, continuing with existing config"
            fi
            rm -f "$config_file.nix-managed"
          fi
          
          # Launch Claude Code with proper PID tracking
          export CLAUDE_CONFIG_DIR="$config_dir"
          echo "🤖 Launching Claude ${account.displayName}..."
          
          # Use trap to ensure cleanup even if interrupted
          trap "rm -f '$pidfile'" EXIT INT TERM
          
          # Write wrapper PID (we'll update it with actual PID if we can)
          echo $$ > "$pidfile"
          
          # Launch Claude directly (no background)
          command claude "$@"
          local exit_code=$?
          
          # Cleanup
          rm -f "$pidfile"
          unset CLAUDE_CONFIG_DIR
          trap - EXIT INT TERM
          
          return $exit_code
        }
      ''
    else "";

  in mkIf cfg.enable {
    # Install required packages
    home.packages = with pkgs; [
      nodejs_22 git ripgrep fd jq
      uv  # Python package manager with uvx for running Python MCP servers
      memoryUpdateScript  # Add the memory update script
      # JSON merging utility for selective field updates
      (pkgs.writeShellScriptBin "mergejson" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        usage() {
          echo "Usage: mergejson OLD_FILE NEW_FILE JQ_QUERY [--confirm]"
          echo "  Merges selected fields from NEW_FILE into OLD_FILE"
          echo "  JQ_QUERY: jq expression selecting fields to merge"
          echo "  --confirm: prompt before applying changes"
          exit 1
        }
        
        [[ $# -lt 3 ]] && usage
        
        old_file="$1"
        new_file="$2"
        jq_query="$3"
        confirm_flag="''${4:-}"
        
        [[ ! -f "$old_file" ]] && { echo "Error: $old_file not found"; exit 1; }
        [[ ! -f "$new_file" ]] && { echo "Error: $new_file not found"; exit 1; }
        
        extract_tmp=$(mktemp)
        ${jq}/bin/jq "$jq_query" "$new_file" > "$extract_tmp"
        
        ${jq}/bin/jq --slurpfile extract_data "$extract_tmp" \
           '. + $extract_data[0]' \
           "$old_file" > "$old_file.merged"
        
        if ! diff -q "$old_file" "$old_file.merged" >/dev/null 2>&1; then
          if [[ "$confirm_flag" == "--confirm" ]]; then
            echo "Changes detected in: $jq_query"
            read -p "View diff? [y/N]: " choice
            if [[ ''${choice,,} =~ ^y ]]; then
              ${neovim}/bin/nvim -d "$old_file" "$old_file.merged"
              read -p "Apply changes? [y/N]: " apply_choice
              [[ ''${apply_choice,,} =~ ^y ]] || { rm -f "$extract_tmp" "$old_file.merged"; exit 1; }
            fi
          fi
          mv "$old_file.merged" "$old_file"
          # Only show message if running interactively with --confirm
          [[ "$confirm_flag" == "--confirm" ]] && echo "Merged: $jq_query"
        else
          rm -f "$old_file.merged"
        fi
        
        rm -f "$extract_tmp"
      '')
      # Account-specific command scripts
      (pkgs.writeShellScriptBin "claudemax" ''
        # Inline the claude-max function logic instead of trying to source it
        account="max"
        config_dir="${runtimePath}/.claude-max"
        pidfile="/tmp/claude-''${account}.pid"
        
        # Single instance enforcement
        if [[ -f "$pidfile" ]]; then
          existing_pid=$(cat "$pidfile")
          if kill -0 "$existing_pid" 2>/dev/null; then
            echo "❌ Claude Code (Max) is already running (PID: $existing_pid)"
            echo "   Please close the existing session first or use 'kill $existing_pid' to force close"
            exit 1
          else
            # Stale pidfile, remove it
            rm -f "$pidfile"
          fi
        fi
        
        # Merge Nix-managed configuration at startup
        config_file="$config_dir/.claude.json"
        if [[ -f "$config_file" ]]; then
          # Create temp config with Nix-managed fields
          echo 'null' | ${pkgs.jq}/bin/jq \
            --argjson mcpServers '${builtins.toJSON claudeCodeMcpServers}' \
            --argjson permissions '${builtins.toJSON cfg.permissions}' \
            ${optionalString (cfg.environmentVariables != {}) "--argjson env '${builtins.toJSON cfg.environmentVariables}'"} \
            --argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}' \
            --argjson hooks '${builtins.toJSON (filterAttrs (n: v: v != null) cfg._internal.hooks)}' \
            '{mcpServers: $mcpServers, permissions: $permissions${optionalString (cfg.environmentVariables != {}) ", env: $env"}, statusLine: $statusLine, hooks: $hooks}' \
            > "$config_file.nix-managed"
          
          # Use mergejson to selectively merge only managed fields (silent operation)
          if mergejson "$config_file" "$config_file.nix-managed" '.'; then
            # Silent merge - no output unless there's an error
            :
          else
            echo "⚠️  Configuration merge failed"
          fi
          rm -f "$config_file.nix-managed"
        fi
        
        # Launch Claude Code with proper PID tracking
        export CLAUDE_CONFIG_DIR="$config_dir"
        
        # Disable telemetry using documented environment variables
        export DISABLE_TELEMETRY="1"                      # Disable Statsig telemetry (documented)
        export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"  # Disable all non-essential traffic (documented)
        export DISABLE_ERROR_REPORTING="1"                # Disable Sentry error reporting (documented)
        
        echo "🤖 Launching Claude Max..."
        
        # Use trap to ensure cleanup even if interrupted
        trap "rm -f '$pidfile'" EXIT INT TERM
        
        # Write wrapper PID (we'll update it with actual PID if we can)
        echo $$ > "$pidfile"
        
        # Launch Claude directly (no background)
        command claude "$@"
        exit_code=$?
        
        # Cleanup
        rm -f "$pidfile"
        unset CLAUDE_CONFIG_DIR
        trap - EXIT INT TERM
        
        exit $exit_code
      '')
      (pkgs.writeShellScriptBin "claudepro" ''
        # Inline the claude-pro function logic instead of trying to source it
        account="pro"
        config_dir="${runtimePath}/.claude-pro"
        pidfile="/tmp/claude-''${account}.pid"
        
        # Single instance enforcement
        if [[ -f "$pidfile" ]]; then
          existing_pid=$(cat "$pidfile")
          if kill -0 "$existing_pid" 2>/dev/null; then
            echo "❌ Claude Code (Pro) is already running (PID: $existing_pid)"
            echo "   Please close the existing session first or use 'kill $existing_pid' to force close"
            exit 1
          else
            # Stale pidfile, remove it
            rm -f "$pidfile"
          fi
        fi
        
        # Merge Nix-managed configuration at startup
        config_file="$config_dir/.claude.json"
        if [[ -f "$config_file" ]]; then
          # Create temp config with Nix-managed fields
          echo 'null' | ${pkgs.jq}/bin/jq \
            --argjson mcpServers '${builtins.toJSON claudeCodeMcpServers}' \
            --argjson permissions '${builtins.toJSON cfg.permissions}' \
            ${optionalString (cfg.environmentVariables != {}) "--argjson env '${builtins.toJSON cfg.environmentVariables}'"} \
            --argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}' \
            --argjson hooks '${builtins.toJSON (filterAttrs (n: v: v != null) cfg._internal.hooks)}' \
            '{mcpServers: $mcpServers, permissions: $permissions${optionalString (cfg.environmentVariables != {}) ", env: $env"}, statusLine: $statusLine, hooks: $hooks}' \
            > "$config_file.nix-managed"
          
          # Use mergejson to selectively merge only managed fields (silent operation)
          if mergejson "$config_file" "$config_file.nix-managed" '.'; then
            # Silent merge - no output unless there's an error
            :
          else
            echo "⚠️  Configuration merge failed"
          fi
          rm -f "$config_file.nix-managed"
        fi
        
        # Launch Claude Code with proper PID tracking
        export CLAUDE_CONFIG_DIR="$config_dir"
        
        # Disable telemetry using documented environment variables
        export DISABLE_TELEMETRY="1"                      # Disable Statsig telemetry (documented)
        export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"  # Disable all non-essential traffic (documented)
        export DISABLE_ERROR_REPORTING="1"                # Disable Sentry error reporting (documented)
        
        echo "🤖 Launching Claude Pro..."
        
        # Use trap to ensure cleanup even if interrupted
        trap "rm -f '$pidfile'" EXIT INT TERM
        
        # Write wrapper PID (we'll update it with actual PID if we can)
        echo $$ > "$pidfile"
        
        # Launch Claude directly (no background)
        command claude "$@"
        exit_code=$?
        
        # Cleanup
        rm -f "$pidfile"
        unset CLAUDE_CONFIG_DIR
        trap - EXIT INT TERM
        
        exit $exit_code
      '')
    ] ++ optionals (cfg.mcpServers.sequentialThinkingPython.enable or false) [
      # Python/UV version wrapper - only included when explicitly enabled
      (pkgs.writeShellScriptBin "sequential-thinking-mcp" ''
        exec ${nixmcp.packages.${pkgs.system}.sequential-thinking-mcp}/bin/sequential-thinking-mcp "$@"
      '')
    ] ++ optionals cfg.hooks.formatting.enable [
      nixpkgs-fmt black nodePackages.prettier rustfmt go shfmt
    ] ++ optionals cfg.hooks.linting.enable [
      python3Packages.pylint nodePackages.eslint shellcheck
    ] ++ optionals (cfg.hooks.notifications.enable && !stdenv.isDarwin) [
      libnotify
    ];
    
    # Symlink entire config directories to writable locations in nixcfg
    home.file = mkMerge [
      # Main symlinks to runtime directories
      (mkIf (cfg.accounts != {}) (mkMerge (mapAttrsToList (name: account: mkIf account.enable {
        ".claude-${name}".source = config.lib.file.mkOutOfStoreSymlink "${runtimePath}/.claude-${name}";
      }) cfg.accounts)))
      
      # Base .claude directory if no accounts or for fallback
      (mkIf (cfg.accounts == {} || cfg.defaultAccount != null) {
        ".claude".source = config.lib.file.mkOutOfStoreSymlink "${runtimePath}/.claude";
      })
      
      # Claude Desktop configuration (always generated if MCP servers exist)
      (mkIf (cfg._internal.mcpServers != {}) {
        "claude-mcp-config.json".text = builtins.toJSON { mcpServers = claudeDesktopMcpServers; };
      })
    ];

    # Activation script to populate runtime directories with templates
    home.activation.claudeConfigTemplates = lib.hm.dag.entryAfter ["writeBoundary"] ''
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

      # PER-ACCOUNT CONFIGURATION: Deploy settings to each account
      ${concatStringsSep "\n" (mapAttrsToList (name: account: ''
        if [[ "${toString account.enable}" == "true" ]]; then
          accountDir="${runtimePath}/.claude-${name}"
          
          echo "⚙️ Configuring account: ${name}"
          
          # RUNTIME-ONLY: Create directories for session data
          $DRY_RUN_CMD mkdir -p "$accountDir"/{logs,projects,shell-snapshots,statsig,todos,commands}
          
          # SETTINGS: Deploy initial settings with MCP servers, but preserve if exists
          if [[ -f "$accountDir/settings.json" ]]; then
            echo "✅ Preserved existing settings: $accountDir/settings.json"
          else
            copy_template "${mkSettingsTemplate (if account.model != null then account.model else cfg.defaultModel)}" "$accountDir/settings.json"
            echo "🆕 Created initial settings with MCP servers: $accountDir/settings.json"
          fi
          
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
            
            # Use jq with --argjson for safe JSON handling
            # Build jq arguments dynamically
            local jq_args=(--argjson mcpServers '${builtins.toJSON claudeCodeMcpServers}')
            ${optionalString (cfg.permissions != {}) ''jq_args+=(--argjson permissions '${builtins.toJSON cfg.permissions}')''}
            ${optionalString (cfg.environmentVariables != {}) ''jq_args+=(--argjson env '${builtins.toJSON cfg.environmentVariables}')''}
            ${optionalString (cfg._internal.statuslineSettings != {}) ''jq_args+=(--argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}')''}
            ${optionalString (cfg._internal.hooks != {}) ''jq_args+=(--argjson hooks '${builtins.toJSON (filterAttrs (n: v: v != null) cfg._internal.hooks)}')''}
            
            $DRY_RUN_CMD ${pkgs.jq}/bin/jq "''${jq_args[@]}" \
              '. |
              .mcpServers = $mcpServers
              ${optionalString (cfg.permissions != {}) ''| .permissions = $permissions''}
              ${optionalString (cfg.environmentVariables != {}) ''| .env = $env''}
              ${optionalString (cfg._internal.statuslineSettings != {}) ''| .statusLine = $statusLine''}
              ${optionalString (cfg._internal.hooks != {}) ''| .hooks = $hooks''}
              ' "$accountDir/.claude.json" > "$accountDir/.claude.json.tmp"
            
            $DRY_RUN_CMD mv "$accountDir/.claude.json.tmp" "$accountDir/.claude.json"
            echo "✅ Nix-managed settings enforced in .claude.json"
          else
            # Create new file with MCP servers
            echo '${builtins.toJSON { mcpServers = claudeCodeMcpServers; }}' > "$accountDir/.claude.json"
            $DRY_RUN_CMD chmod 644 "$accountDir/.claude.json"
            echo "🆕 Created minimal MCP config: $accountDir/.claude.json"
          fi
          
          echo "✅ Account ${name} configured with statusline support"
        fi
      '') cfg.accounts)}
      
      # FALLBACK BASE .claude DIRECTORY (compatibility/default account support)
      ${optionalString (cfg.accounts == {} || cfg.defaultAccount != null) ''
      baseDir="${runtimePath}/.claude"
      echo "📁 Setting up fallback base directory"
      
      # RUNTIME-ONLY: Create directories for session data
      $DRY_RUN_CMD mkdir -p "$baseDir"/{logs,projects,shell-snapshots,statsig,todos,commands}
      
      # SETTINGS: Deploy base settings with statusline configuration  
      copy_template "${settingsTemplate}" "$baseDir/settings.json"
      
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
        
        # Use jq with --argjson for safe JSON handling
        # Build jq arguments dynamically
        jq_args=(--argjson mcpServers '${builtins.toJSON claudeCodeMcpServers}')
        ${optionalString (cfg.permissions != {}) ''jq_args+=(--argjson permissions '${builtins.toJSON cfg.permissions}')''}
        ${optionalString (cfg.environmentVariables != {}) ''jq_args+=(--argjson env '${builtins.toJSON cfg.environmentVariables}')''}
        ${optionalString (cfg._internal.statuslineSettings != {}) ''jq_args+=(--argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}')''}
        ${optionalString (cfg._internal.hooks != {}) ''jq_args+=(--argjson hooks '${builtins.toJSON (filterAttrs (n: v: v != null) cfg._internal.hooks)}')''}
        
        $DRY_RUN_CMD ${pkgs.jq}/bin/jq "''${jq_args[@]}" \
          '. |
          .mcpServers = $mcpServers
          ${optionalString (cfg.permissions != {}) ''| .permissions = $permissions''}
          ${optionalString (cfg.environmentVariables != {}) ''| .env = $env''}
          ${optionalString (cfg._internal.statuslineSettings != {}) ''| .statusLine = $statusLine''}
          ${optionalString (cfg._internal.hooks != {}) ''| .hooks = $hooks''}
          ' "$baseDir/.claude.json" > "$baseDir/.claude.json.tmp"
        
        $DRY_RUN_CMD mv "$baseDir/.claude.json.tmp" "$baseDir/.claude.json"
        echo "✅ Nix-managed settings enforced in .claude.json"
      else
        # Create new file with MCP servers
        echo '${builtins.toJSON { mcpServers = claudeCodeMcpServers; }}' > "$baseDir/.claude.json"
        $DRY_RUN_CMD chmod 644 "$baseDir/.claude.json"
        echo "🆕 Created minimal MCP config: $baseDir/.claude.json"
      fi
      
      echo "✅ Base directory configured with statusline support"
      ''}
    '';
    
    # Add shell initialization for accounts
    programs.bash.initExtra = mkIf (cfg.accounts != {}) (mkAfter ''
      # Claude Code Multi-Account Support
      ${lib.concatStringsSep "\n" accountAliases}
      ${defaultAccountOverride}
      
      # Helper function to check Claude Code session status
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
    
    programs.zsh.initContent = mkIf (cfg.accounts != {}) (mkAfter ''
      # Claude Code Multi-Account Support
      ${lib.concatStringsSep "\n" accountAliases}
      ${defaultAccountOverride}
      
      # Helper function to check Claude Code session status
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
    
    programs.fish.shellInit = mkIf (cfg.accounts != {}) (mkAfter (
      let
        # Convert bash functions to fish syntax
        bashToFish = bashCmd: 
          let
            lines = lib.splitString "\n" bashCmd;
            funcLine = builtins.head lines;
            funcName = lib.head (lib.splitString "(" funcLine);
            bodyLines = builtins.tail lines;
            body = lib.concatStringsSep "\n" (lib.init bodyLines); # Remove closing }
            fishBody = lib.replaceStrings 
              ["export " "unset " "command " "$@" "echo "]
              ["set -gx " "set -e " "" "$argv" "echo "]
              body;
          in ''
            function ${funcName}
              ${fishBody}
            end
          '';
      in ''
        # Claude Code Multi-Account Support
        ${lib.concatStringsSep "\n" (map bashToFish (accountAliases ++ lib.optional (defaultAccountOverride != "") defaultAccountOverride))}
      ''
    ));
    
    # Assertions
    assertions = [
      {
        assertion = cfg.hooks.notifications.enable -> 
          (pkgs.stdenv.isDarwin || config.home.packages or [] != []);
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
