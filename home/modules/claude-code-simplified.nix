{ config, lib, pkgs, nixmcp ? null, ... }:

with lib;

{
  imports = [
    ./claude-code/mcp-servers.nix
    ./claude-code/hooks.nix
    ./claude-code/sub-agents.nix
    ./claude-code/slash-commands.nix
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
        allow = [ "Bash(npm run test:*)" "Bash(nix flake check:*)" "Read(~/.config/*)" ];
        deny = [ "Bash(rm -rf /*)" "Read(.env)" "Write(/etc/passwd)" ];
      };
      description = "Permission rules";
    };
    
    environmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = { CLAUDE_CODE_ENABLE_TELEMETRY = "0"; };
      description = "Environment variables";
    };
    
    experimental = mkOption {
      type = types.attrs;
      default = {};
      description = "Experimental features";
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
    
    # Path to nixcfg runtime directory
    nixcfgPath = "${config.home.homeDirectory}/src/nixcfg";
    runtimePath = "${nixcfgPath}/claude-runtime";
    templatesPath = "${nixcfgPath}/claude-templates";
    
    # Read the memory file content at build time
    userGlobalMemoryContent = builtins.readFile ./claude-code-user-global-memory.md;
    
    # Script to handle memory updates and rebuild
    memoryUpdateScript = pkgs.writeScriptBin "claude-memory-update" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      
      echo "Memory updated, rebuilding claude-code configuration..."
      cd ${nixcfgPath}
      
      # Commit the memory change
      ${pkgs.git}/bin/git add home/modules/claude-code-user-global-memory.md
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
    
    # Base settings configuration
    mkSettingsTemplate = model: pkgs.writeText "claude-settings.json" (builtins.toJSON (let
      hasHooks = cfg._internal.hooks.PreToolUse != null || cfg._internal.hooks.PostToolUse != null || 
                 cfg._internal.hooks.Start != null || cfg._internal.hooks.Stop != null;
      cleanHooks = filterAttrs (n: v: v != null) cfg._internal.hooks;
    in {
      model = model;
    } // optionalAttrs (cfg.permissions != {}) { permissions = cfg.permissions; }
      // optionalAttrs (cfg.environmentVariables != {}) { env = cfg.environmentVariables; }
      // optionalAttrs hasHooks { hooks = cleanHooks; }
      // optionalAttrs (cfg.experimental != {}) { experimental = cfg.experimental; }
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
      mcpServers = removeAttrs cfg._internal.mcpServers [ "mcp-filesystem" "cli-mcp-server" ];
    });

    # CLAUDE.md template
    claudeMdTemplate = pkgs.writeText "claude-memory.md" userGlobalMemoryContent;

    # Generate shell aliases for each account
    accountAliases = lib.flatten (lib.mapAttrsToList (name: account:
      let
        configDir = "${runtimePath}/.claude-${name}";
        
        # Main command for this account
        mainCmd = ''
          claude-${name}() {
            export CLAUDE_CONFIG_DIR="${configDir}"
            echo "🤖 Switching to Claude ${account.displayName}..."
            command claude "$@"
            unset CLAUDE_CONFIG_DIR
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
      in ''
        claude() {
          export CLAUDE_CONFIG_DIR="${configDir}"
          command claude "$@"
          unset CLAUDE_CONFIG_DIR
        }
      ''
    else "";

  in mkIf cfg.enable {
    # Install required packages
    home.packages = with pkgs; [
      nodejs_22 git ripgrep fd jq
      memoryUpdateScript  # Add the memory update script
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
      $DRY_RUN_CMD mkdir -p ${runtimePath}
      
      # Function to safely copy template if target doesn't exist
      copy_template_if_missing() {
        local template="$1"
        local target="$2"
        if [[ ! -f "$target" ]]; then
          $DRY_RUN_CMD cp "$template" "$target"
          echo "Copied template to $target"
        fi
      }

      # Populate each account directory with templates
      ${concatStringsSep "\n" (mapAttrsToList (name: account: ''
        if [[ "${toString account.enable}" == "true" ]]; then
          accountDir="${runtimePath}/.claude-${name}"
          $DRY_RUN_CMD mkdir -p "$accountDir"/{agents,commands,logs,projects,shell-snapshots,statsig,todos}
          
          # Copy templates for Nix-managed configs (only if missing)
          copy_template_if_missing "${mkSettingsTemplate (if account.model != null then account.model else cfg.defaultModel)}" "$accountDir/settings.json"
          copy_template_if_missing "${mcpTemplate}" "$accountDir/mcp.json" 
          copy_template_if_missing "${claudeMdTemplate}" "$accountDir/CLAUDE.md"
        fi
      '') cfg.accounts)}
      
      # Handle base .claude directory 
      baseDir="${runtimePath}/.claude"
      $DRY_RUN_CMD mkdir -p "$baseDir"/{agents,commands,logs,projects,shell-snapshots,statsig,todos}
      copy_template_if_missing "${settingsTemplate}" "$baseDir/settings.json"
      copy_template_if_missing "${mcpTemplate}" "$baseDir/mcp.json"
      copy_template_if_missing "${claudeMdTemplate}" "$baseDir/CLAUDE.md"
    '';
    
    # Add shell initialization for accounts
    programs.bash.initExtra = mkIf (cfg.accounts != {}) (mkAfter ''
      # Claude Code Multi-Account Support
      ${lib.concatStringsSep "\n" accountAliases}
      ${defaultAccountOverride}
    '');
    
    programs.zsh.initContent = mkIf (cfg.accounts != {}) (mkAfter ''
      # Claude Code Multi-Account Support
      ${lib.concatStringsSep "\n" accountAliases}
      ${defaultAccountOverride}
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
    ];
  };
}