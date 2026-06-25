{ config, lib, ... }:

with lib;

let
  cfg = config.programs.claude-code;

  # Plan 046 T6 — full subagent frontmatter. Field names + casing verified
  # against code.claude.com/docs/en/sub-agents (2026-06-24): the JSON --agents
  # form lists `description, prompt, tools, disallowedTools, model,
  # permissionMode, mcpServers, hooks, maxTurns, skills, initialPrompt, memory,
  # effort, background, isolation, color`. Only set fields are emitted. Lists
  # (tools/disallowedTools) render comma-separated per the docs; structured
  # fields (skills/mcpServers/hooks) and initialPrompt render as JSON (valid
  # YAML flow).
  mkSubAgent =
    { name
    , description
    , capabilities ? [ ]
    , instructions ? ""
    , examples ? [ ]
    , constraints ? [ ]
    , tools ? [ ]
    , disallowedTools ? [ ]
    , model ? null
    , color ? null
    , permissionMode ? null
    , maxTurns ? null
    , skills ? [ ]
    , mcpServers ? { }
    , memory ? null
    , background ? null
    , effort ? null
    , isolation ? null
    , initialPrompt ? null
    , hooks ? { }
    }:
    let
      fmLines = filter (l: l != null) [
        "name: ${lib.toLower (lib.replaceStrings [" "] ["-"] name)}"
        "description: ${description}"
        (if tools != [ ] then "tools: ${concatStringsSep ", " tools}" else null)
        (if disallowedTools != [ ] then "disallowedTools: ${concatStringsSep ", " disallowedTools}" else null)
        (if model != null then "model: ${model}" else null)
        (if color != null then "color: ${color}" else null)
        (if permissionMode != null then "permissionMode: ${permissionMode}" else null)
        (if maxTurns != null then "maxTurns: ${toString maxTurns}" else null)
        (if skills != [ ] then "skills: ${builtins.toJSON skills}" else null)
        (if mcpServers != { } then "mcpServers: ${builtins.toJSON mcpServers}" else null)
        (if memory != null then "memory: ${memory}" else null)
        (if background != null then "background: ${lib.boolToString background}" else null)
        (if effort != null then "effort: ${effort}" else null)
        (if isolation != null then "isolation: ${isolation}" else null)
        (if initialPrompt != null then "initialPrompt: ${builtins.toJSON initialPrompt}" else null)
        (if hooks != { } then "hooks: ${builtins.toJSON hooks}" else null)
      ];
    in
    {
      text = ''
        ---
        ${concatStringsSep "\n" fmLines}
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
  options.programs.claude-code.subAgents = {
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
          tools = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Tools available to this agent (e.g., Bash, Glob, Read)";
          };

          # Plan 046 T6 — full subagent frontmatter surface.
          disallowedTools = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Tools to deny, removed from the inherited/specified list
              (`disallowedTools`). Applied before `tools`.
            '';
          };
          model = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "inherit";
            description = "Model for this agent (`inherit`/`sonnet`/`opus`/`haiku`).";
          };
          color = mkOption {
            type = types.nullOr (types.enum [ "blue" "cyan" "green" "yellow" "magenta" "red" ]);
            default = null;
            description = "UI color for the subagent (`color`).";
          };
          permissionMode = mkOption {
            type = types.nullOr (types.enum [ "default" "acceptEdits" "auto" "dontAsk" "bypassPermissions" "plan" ]);
            default = null;
            description = ''
              Permission mode (`permissionMode`). Ignored for plugin subagents.
            '';
          };
          maxTurns = mkOption {
            type = types.nullOr types.ints.positive;
            default = null;
            description = "Maximum agentic turns before the subagent stops (`maxTurns`).";
          };
          skills = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Skills preloaded into the subagent's context at startup
              (`skills`). Rendered as a YAML list.
            '';
          };
          mcpServers = mkOption {
            type = types.attrs;
            default = { };
            description = ''
              MCP servers available to this subagent (`mcpServers`): each entry
              is a string reference to a configured server or an inline server
              config. Freeform attrs serialized as inline JSON. Ignored for
              plugin subagents.
            '';
          };
          memory = mkOption {
            type = types.nullOr (types.enum [ "user" "project" "local" ]);
            default = null;
            description = "Persistent memory scope enabling cross-session learning (`memory`).";
          };
          background = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = "Always run this subagent as a background task (`background`).";
          };
          effort = mkOption {
            type = types.nullOr (types.enum [ "low" "medium" "high" "xhigh" "max" ]);
            default = null;
            description = "Effort level while this subagent is active (`effort`).";
          };
          isolation = mkOption {
            type = types.nullOr (types.enum [ "worktree" ]);
            default = null;
            description = ''
              Set to `worktree` to run the subagent in an isolated git worktree
              (`isolation`), branched from the default branch.
            '';
          };
          initialPrompt = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Auto-submitted first user turn when this agent runs as the main
              session agent (`initialPrompt`).
            '';
          };
          hooks = mkOption {
            type = types.attrs;
            default = { };
            description = ''
              Hooks scoped to this subagent's lifecycle (`hooks`). Freeform
              attrs serialized as inline JSON. Ignored for plugin subagents.
            '';
          };
        };
      });
      default = { };
      description = "Custom sub-agent definitions";
    };
  };

  config.programs.claude-code._internal.subAgentFiles = mkMerge [
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
        inherit (cfg.subAgents.codeSearcher) instructions;
        inherit (cfg.subAgents.codeSearcher) examples;
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
        inherit (cfg.subAgents.memoryBank) instructions;
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
        inherit (cfg.subAgents.architect) instructions;
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
