{ config, lib, ... }:

with lib;

let
  cfg = config.programs.claude-code-enhanced;

  mkSubAgent =
    { name
    , description
    , capabilities
    , instructions
    , examples ? [ ]
    , constraints ? [ ]
    }: {
      text = ''
        ---
        name: ${lib.toLower (lib.replaceStrings [" "] ["-"] name)}
        description: ${description}
        ---
      
        # ${name}
      
        ${description}
      
        ## Capabilities
        ${concatStringsSep "\n" (map (cap: "- ${cap}") capabilities)}
      
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
    };

in
{
  options.programs.claude-code-enhanced.subAgents = {
    codeSearcher = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable code searcher sub-agent";
      };
      instructions = mkOption {
        type = types.lines;
        default = ''
          Use Chain of Density (CoD) summarization for code analysis.
          Prioritize semantic understanding over literal matching.
          Maintain context across multiple file searches.
        '';
        description = "Instructions for code searcher";
      };
      examples = mkOption {
        type = types.listOf types.str;
        default = [
          "Find all API endpoints in the codebase"
          "Identify security vulnerabilities in authentication"
        ];
        description = "Example queries";
      };
    };

    memoryBank = {
      enable = mkEnableOption "memory bank sub-agent";
      instructions = mkOption {
        type = types.lines;
        default = ''
          Maintain project context in CLAUDE-*.md files.
          Track decisions, patterns, and troubleshooting.
          Update context files after significant changes.
        '';
        description = "Instructions for memory bank";
      };
    };

    architect = {
      enable = mkEnableOption "architect sub-agent";
      instructions = mkOption {
        type = types.lines;
        default = ''
          Analyze system architecture and design patterns.
          Suggest improvements based on best practices.
          Consider performance, security, and maintainability.
        '';
        description = "Instructions for architect";
      };
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
        };
      });
      default = { };
      description = "Custom sub-agent definitions";
    };
  };

  config.programs.claude-code-enhanced._internal.subAgentFiles = mkMerge [
    (mkIf cfg.subAgents.codeSearcher.enable {
      ".claude/agents/code-searcher.md" = mkSubAgent {
        name = "Code Searcher";
        description = "Efficient codebase analysis with Chain of Density (CoD) support for minimal token usage";
        capabilities = [
          "Rapid code pattern identification"
          "Multi-file analysis with context preservation"
          "Semantic code understanding"
          "Dependency tracking"
        ];
        instructions = cfg.subAgents.codeSearcher.instructions;
        examples = cfg.subAgents.codeSearcher.examples;
      };
    })

    (mkIf cfg.subAgents.memoryBank.enable {
      ".claude/agents/memory-bank.md" = mkSubAgent {
        name = "Memory Bank Synchronizer";
        description = "Maintains project context across sessions";
        capabilities = [
          "Context persistence"
          "Pattern recognition"
          "Decision tracking"
          "Knowledge base management"
        ];
        instructions = cfg.subAgents.memoryBank.instructions;
      };
    })

    (mkIf cfg.subAgents.architect.enable {
      ".claude/agents/architect.md" = mkSubAgent {
        name = "System Architect";
        description = "Architecture analysis and design recommendations";
        capabilities = [
          "System design evaluation"
          "Pattern recommendation"
          "Dependency analysis"
          "Performance optimization suggestions"
        ];
        instructions = cfg.subAgents.architect.instructions;
      };
    })

    (listToAttrs (mapAttrsToList
      (name: agent:
        nameValuePair ".claude/agents/${name}.md" (mkSubAgent ({
          inherit name;
        } // agent))
      )
      cfg.subAgents.custom))
  ];
}
