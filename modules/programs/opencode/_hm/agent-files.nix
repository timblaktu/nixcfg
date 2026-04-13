# OpenCode agent file deployment
# Deploys agent .md files (YAML frontmatter + markdown body) to account dirs
# Mirrors claude-code's sub-agents.nix pattern
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.opencode;
  inherit (cfg) nixcfgPath;
  runtimePath = "${nixcfgPath}/opencode-runtime";

  # Generate agent .md file with YAML frontmatter
  mkAgentFile =
    { name
    , description
    , capabilities ? [ ]
    , instructions
    , examples ? [ ]
    , constraints ? [ ]
    , tools ? [ ]
    }: ''
      ---
      name: ${toLower (replaceStrings [" "] ["-"] name)}
      description: ${description}
      ${optionalString (tools != []) ''
        tools:
        ${concatStringsSep "\n" (map (t: "  ${toLower t}: true") tools)}''}
      ---

      # ${name}

      ${description}

      ${optionalString (capabilities != []) ''
        ## Capabilities
        ${concatStringsSep "\n" (map (cap: "- ${cap}") capabilities)}
      ''}

      ## Instructions
      ${instructions}

      ${optionalString (examples != []) ''
        ## Examples
        ${concatStringsSep "\n\n" examples}
      ''}

      ${optionalString (constraints != []) ''
        ## Constraints
        ${concatStringsSep "\n" (map (c: "- ${c}") constraints)}
      ''}
    '';

in
{
  options.programs.opencode.agentFiles = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable file-based agent deployment (.md files to agents/)";
    };

    custom = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            description = "Agent description";
          };
          capabilities = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Agent capabilities";
          };
          instructions = mkOption {
            type = types.lines;
            description = "Agent instructions";
          };
          examples = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Example uses";
          };
          constraints = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Agent constraints";
          };
          tools = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Tools available to this agent (e.g., Bash, Glob, Read)";
          };
        };
      });
      default = { };
      description = "Custom agent definitions deployed as .md files";
    };
  };

  config = mkIf (cfg.enable && cfg.agentFiles.enable) {
    # Deploy agent files via activation script
    home.activation.opencodeAgentFiles = lib.hm.dag.entryAfter [ "opencodeConfigTemplates" ] ''
      echo "Deploying OpenCode agent files..."

      ${concatStringsSep "\n" (mapAttrsToList (accountName: account: ''
        if [[ "${toString account.enable}" == "1" ]]; then
          agentsDir="${runtimePath}/.opencode-${accountName}/agents"
          $DRY_RUN_CMD mkdir -p "$agentsDir"

          ${concatStringsSep "\n" (mapAttrsToList (agentName: agentDef:
            let
              content = mkAgentFile ({
                name = agentName;
              } // agentDef);
              contentFile = pkgs.writeText "opencode-agent-${agentName}.md" content;
            in ''
              $DRY_RUN_CMD cp "${contentFile}" "$agentsDir/${agentName}.md"
              $DRY_RUN_CMD chmod 644 "$agentsDir/${agentName}.md"
            ''
          ) cfg.agentFiles.custom)}

          echo "  Deployed agents to ${accountName}"
        fi
      '') cfg.accounts)}

      echo "OpenCode agent files deployed"
    '';
  };
}
