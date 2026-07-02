# Skills module for Claude Code
# Manages built-in and custom skills that extend Claude's capabilities
#
# Skills are deployed to each account's skills/ directory and are
# automatically discovered by Claude Code.
#
# Usage:
#   programs.claude-code.skills = {
#     enable = true;
#     builtins.adr-writer = true;  # Enable the ADR writing skill
#     custom = {
#       my-skill = {
#         description = "Does something useful";
#         skillContent = "# My Skill\n\nContent here...";
#       };
#     };
#   };

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;
  skillsCfg = cfg.skills;
  inherit (cfg) nixcfgPath;
  runtimePath = "${nixcfgPath}/claude-runtime";

  # Built-in skill definitions - files stored alongside this module
  builtinSkillDefs = {
    adr-writer = {
      name = "adr-writer";
      description = "Guide writing Architecture Decision Records (ADRs) following the Design It! methodology. Use when creating ADRs, documenting architecture decisions, recording technical decisions, or when someone asks about ADR format or templates.";
      files = {
        "SKILL.md" = ./skills/adr-writer/SKILL.md;
        "REFERENCE.md" = ./skills/adr-writer/REFERENCE.md;
      };
    };
    mikrotik-management = {
      name = "mikrotik-management";
      description = "Automate Mikrotik RouterOS configuration for VLANs, bridges, ports, and IP addressing. Use for network infrastructure setup, switch configuration, or RouterOS management tasks.";
      files = {
        "SKILL.md" = ./skills/mikrotik-management/SKILL.md;
        "REFERENCE.md" = ./skills/mikrotik-management/REFERENCE.md;
        "test-cases.md" = ./skills/mikrotik-management/test-cases.md;
        "examples/README.md" = ./skills/mikrotik-management/examples/README.md;
        "commands/README.md" = ./skills/mikrotik-management/commands/README.md;
      };
    };
    diagram = {
      name = "diagram";
      description = "Create, edit, and convert diagrams. Auto-selects format: Mermaid for simple flows/trees, DrawIO for complex architecture/comparisons. Supports .drawio, .drawio.svg, Mermaid, and ASCII input. Use for architecture diagrams, flowcharts, visualizations, or any diagram task.";
      files = {
        "SKILL.md" = ./skills/diagram/SKILL.md;
        "REFERENCE.md" = ./skills/diagram/REFERENCE.md;
        "drawio_gen.py" = ./skills/diagram/drawio_gen.py;
        # Deterministic structural linter (pre-render gate) and Graphviz
        # auto-layout for dense graphs. Vendored+adapted from drawio-skill (MIT).
        "validate.py" = ./skills/diagram/validate.py;
        "autolayout.py" = ./skills/diagram/autolayout.py;
        # Official draw.io shape search + AI/LLM brand logos. Scripts MIT;
        # bundled data Apache-2.0 (shapes) / MIT (icon names) — see data/.
        "shapesearch.py" = ./skills/diagram/shapesearch.py;
        "aiicons.py" = ./skills/diagram/aiicons.py;
        "data/shape-index.json.gz" = ./skills/diagram/data/shape-index.json.gz;
        "data/lobe-icons.json" = ./skills/diagram/data/lobe-icons.json;
        "data/SHAPE-INDEX-NOTICE.md" = ./skills/diagram/data/SHAPE-INDEX-NOTICE.md;
      };
    };
    screencast = {
      name = "screencast";
      description = "Record terminal sessions and post-process them into standalone, narration-free screencasts. Use when asked to record a terminal demo, capture a CLI session for a presentation, compress/annotate a recording, turn a session into a GIF/MP4, or embed a terminal recording in an HTML deck. Built on asciinema + agg + ffmpeg.";
      files = {
        "SKILL.md" = ./skills/screencast/SKILL.md;
        "scripts/record.sh" = ./skills/screencast/scripts/record.sh;
        "scripts/annotate.py" = ./skills/screencast/scripts/annotate.py;
        "scripts/embed.sh" = ./skills/screencast/scripts/embed.sh;
      };
    };
  };

  # Custom skill submodule
  customSkillModule = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        description = "Skill description for discovery (shown to Claude for triggering)";
        example = "Generate commit messages following conventional commits format";
      };

      skillContent = mkOption {
        type = types.str;
        description = ''
          SKILL.md content (without frontmatter - it will be generated).
          This is the main instruction content that Claude uses when the skill is invoked.
        '';
        example = ''
          # Commit Message Generator

          ## Instructions
          1. Analyze the staged changes
          2. Generate a conventional commit message
          ...
        '';
      };

      referenceContent = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Optional REFERENCE.md content for extended documentation.
          Use for detailed guidance that would make SKILL.md too long.
        '';
      };

      # ─────────────────────────────────────────────────────────────────────
      # Plan 046 T6 — enriched SKILL.md frontmatter. Field names verified
      # against code.claude.com/docs/en/skills (2026-06-24). All optional and
      # emitted only when set, so the generated frontmatter stays minimal.
      # Upstream merged custom slash commands INTO skills, so these fields also
      # cover command-style frontmatter (argument-hint/arguments/model/...).
      # ─────────────────────────────────────────────────────────────────────
      whenToUse = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Extra context for when Claude should invoke the skill (trigger
          phrases / example requests). Serializes as the `when_to_use`
          frontmatter key; appended to `description` in the skill listing
          (counts toward the 1,536-char cap). Null = omit.
        '';
      };

      argumentHint = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "[issue-number] [format]";
        description = "Autocomplete hint for expected arguments (`argument-hint`).";
      };

      arguments = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "issue branch";
        description = ''
          Named positional arguments for `$name` substitution in the skill
          body (`arguments` frontmatter key). Space-separated string; names map
          to argument positions in order.
        '';
      };

      allowedTools = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [ "Read" "Grep" "Bash(git status *)" ];
        description = ''
          Tools Claude may use without prompting while this skill is active
          (`allowed-tools`). Rendered as a YAML list. Null = omit.
        '';
      };

      disallowedTools = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [ "AskUserQuestion" ];
        description = ''
          Tools removed from Claude's pool while this skill is active
          (`disallowed-tools`). Rendered as a YAML list. Null = omit.
        '';
      };

      model = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "haiku";
        description = ''
          Model to use while this skill is active (`model`). Same values as
          `/model`, or `inherit`. Null = omit (inherit session model).
        '';
      };

      disableModelInvocation = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Set true to prevent Claude from auto-loading this skill
          (`disable-model-invocation`); only `/name` invocation works.
          Null = omit (upstream default false).
        '';
      };

      userInvocable = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Set false to hide the skill from the `/` menu (`user-invocable`);
          use for background knowledge. Null = omit (upstream default true).
        '';
      };

      effort = mkOption {
        type = types.nullOr (types.enum [ "low" "medium" "high" "xhigh" "max" ]);
        default = null;
        description = "Effort level while this skill is active (`effort`).";
      };

      context = mkOption {
        type = types.nullOr (types.enum [ "fork" ]);
        default = null;
        description = ''
          Set to `fork` to run the skill in a forked subagent context
          (`context`). The skill body becomes the subagent's prompt.
        '';
      };

      agent = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "Explore";
        description = "Subagent type to use when `context: fork` is set (`agent`).";
      };

      paths = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [ "src/**/*.ts" ];
        description = ''
          Glob patterns limiting when the skill auto-activates (`paths`).
          Rendered as a YAML list. Null = omit.
        '';
      };

      shell = mkOption {
        type = types.nullOr (types.enum [ "bash" "powershell" ]);
        default = null;
        description = ''
          Shell for inline `` !`command` `` blocks in this skill (`shell`).
          `powershell` requires CLAUDE_CODE_USE_POWERSHELL_TOOL=1.
        '';
      };

      hooks = mkOption {
        type = types.attrs;
        default = { };
        description = ''
          Hooks scoped to this skill's lifecycle (`hooks` frontmatter key).
          Freeform attrs serialized as inline JSON (valid YAML flow). Empty
          attrset = omit. See the hooks reference for the entry format.
        '';
      };

      extraFiles = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = ''
          Additional files as filename -> content attrset.
          Useful for templates, examples, or configuration files.
        '';
        example = {
          "templates/feature.md" = "# Feature Template\n...";
          "examples/good-commit.md" = "feat(auth): add OAuth support\n...";
        };
      };
    };
  };

  # Render one frontmatter value as YAML. Scalars inline; lists/attrs as JSON
  # flow style (valid YAML), so structured fields (allowed-tools, paths, hooks)
  # serialize without a hand-rolled YAML emitter.
  mkFmValue = v:
    if isBool v then (if v then "true" else "false")
    else if isList v then builtins.toJSON v
    else if isAttrs v then builtins.toJSON v
    else if isInt v || isFloat v then toString v
    else toString v;

  # Build a frontmatter block from ordered { name; value; } pairs, dropping
  # null values and empty attrsets/lists so only set fields are emitted.
  mkFrontmatter = pairs:
    concatStringsSep "\n"
      (map (p: "${p.name}: ${mkFmValue p.value}")
        (filter (p: p.value != null && p.value != { } && p.value != [ ]) pairs));

  # Generate SKILL.md with enriched frontmatter from custom skill options
  # (Plan 046 T6). Order mirrors the upstream docs frontmatter reference.
  mkSkillFile = name: skill: ''
    ---
    ${mkFrontmatter [
      { name = "name"; value = name; }
      { name = "description"; value = skill.description; }
      { name = "when_to_use"; value = skill.whenToUse; }
      { name = "argument-hint"; value = skill.argumentHint; }
      { name = "arguments"; value = skill.arguments; }
      { name = "allowed-tools"; value = skill.allowedTools; }
      { name = "disallowed-tools"; value = skill.disallowedTools; }
      { name = "model"; value = skill.model; }
      { name = "disable-model-invocation"; value = skill.disableModelInvocation; }
      { name = "user-invocable"; value = skill.userInvocable; }
      { name = "effort"; value = skill.effort; }
      { name = "context"; value = skill.context; }
      { name = "agent"; value = skill.agent; }
      { name = "paths"; value = skill.paths; }
      { name = "shell"; value = skill.shell; }
      { name = "hooks"; value = skill.hooks; }
    ]}
    ---

    ${skill.skillContent}
  '';

  # Get list of enabled builtin skills
  enabledBuiltins = filterAttrs (_name: enabled: enabled) skillsCfg.builtins;

  # Combine builtin and custom skills
  allSkills = (mapAttrs
    (name: _: {
      inherit (builtinSkillDefs.${name}) files;
      isBuiltin = true;
    })
    enabledBuiltins) // (mapAttrs
    (name: skill: {
      files = {
        "SKILL.md" = pkgs.writeText "${name}-SKILL.md" (mkSkillFile name skill);
      } // optionalAttrs (skill.referenceContent != null) {
        "REFERENCE.md" = pkgs.writeText "${name}-REFERENCE.md" skill.referenceContent;
      } // (mapAttrs
        (fileName: content: pkgs.writeText "${name}-${replaceStrings ["/"] ["-"] fileName}" content)
        skill.extraFiles);
      isBuiltin = false;
    })
    skillsCfg.custom);

in
{
  options.programs.claude-code.skills = {
    enable = mkEnableOption "Claude Code skills management";

    builtins = {
      adr-writer = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable the ADR (Architecture Decision Record) writing skill.
          Helps create well-structured ADRs following the "Design It!" methodology.
        '';
      };
      mikrotik-management = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable the Mikrotik RouterOS management skill for network infrastructure configuration.
          Automates switch configuration including VLANs, bridges, ports, and IP addressing.
        '';
      };
      diagram = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable the diagram creation and editing skill.
          Auto-selects Mermaid for simple diagrams, DrawIO for complex architecture.
          Supports .drawio, .drawio.svg, Mermaid, and ASCII input formats.
        '';
      };
      screencast = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable the screencast skill: record terminal sessions with asciinema and
          post-process them (compress idle gaps, add title cards + scrubber markers)
          into standalone, narration-free screencasts that embed in an HTML deck or
          export to GIF/MP4. Pulls asciinema, agg, ffmpeg, and vhs into the profile.
        '';
      };
    };

    custom = mkOption {
      type = types.attrsOf customSkillModule;
      default = { };
      description = ''
        Custom skill definitions.
        Each skill is deployed as a directory with SKILL.md and optional supporting files.
      '';
      example = literalExpression ''
        {
          commit-message = {
            description = "Generate conventional commit messages from staged changes";
            skillContent = '''
              # Commit Message Generator

              Generate commit messages following the Conventional Commits specification.

              ## Format
              <type>(<scope>): <description>

              [optional body]

              [optional footer(s)]
            ''';
          };
        }
      '';
    };
  };

  config = mkIf (cfg.enable && skillsCfg.enable) {
    # Toolchain for the screencast skill (record/annotate/embed/export).
    home.packages = lib.optionals skillsCfg.builtins.screencast [
      pkgs.asciinema # record / convert / play terminal sessions
      pkgs.asciinema-agg # .cast -> animated GIF
      pkgs.ffmpeg # GIF -> MP4/WebM
      pkgs.vhs # optional: scripted deterministic .tape recordings
    ];

    # Extend the activation script to deploy skills
    home.activation.claudeSkillsDeployment = lib.hm.dag.entryAfter [ "claudeConfigTemplates" ] ''
      echo "🎯 Deploying Claude Code skills..."

      # Known skill names for pruning stale directories
      declaredSkills=(${concatStringsSep " " (attrNames allSkills)})

      # Deploy skills to each enabled account
      ${concatStringsSep "\n" (mapAttrsToList (accountName: account: ''
        if [[ "${toString account.enable}" == "1" ]]; then
          accountSkillsDir="${runtimePath}/.claude-${accountName}/skills"
          $DRY_RUN_CMD mkdir -p "$accountSkillsDir"

          # Prune skill directories that are no longer declared
          if [[ -d "$accountSkillsDir" ]]; then
            for existing in "$accountSkillsDir"/*/; do
              [[ -d "$existing" ]] || continue
              skillName="$(basename "$existing")"
              found=0
              for declared in "''${declaredSkills[@]}"; do
                if [[ "$skillName" == "$declared" ]]; then
                  found=1
                  break
                fi
              done
              if [[ "$found" -eq 0 ]]; then
                echo "  🗑️  Removing stale skill: $skillName from ${accountName}"
                $DRY_RUN_CMD rm -rf "$existing"
              fi
            done
          fi

          ${concatStringsSep "\n" (mapAttrsToList (skillName: skillDef: ''
            skillDir="$accountSkillsDir/${skillName}"
            $DRY_RUN_CMD mkdir -p "$skillDir"

            ${concatStringsSep "\n" (mapAttrsToList (fileName: filePath:
              let
                # Handle both path (builtins) and derivation (custom) files
                sourceFile = if isPath filePath then filePath else filePath;
                # Script files need executable permission
                fileMode = if hasSuffix ".py" fileName || hasSuffix ".sh" fileName then "755" else "644";
              in ''
                # Create parent directories if needed (for nested paths like templates/foo.md)
                $DRY_RUN_CMD mkdir -p "$(dirname "$skillDir/${fileName}")"
                $DRY_RUN_CMD cp "${sourceFile}" "$skillDir/${fileName}"
                $DRY_RUN_CMD chmod ${fileMode} "$skillDir/${fileName}"
              ''
            ) skillDef.files)}

            echo "  ✅ Deployed skill: ${skillName} to ${accountName}"
          '') allSkills)}
        fi
      '') cfg.accounts)}

      # Also deploy to base .claude directory if defaultAccount is set
      ${optionalString (cfg.defaultAccount != null) ''
        baseSkillsDir="${runtimePath}/.claude/skills"
        $DRY_RUN_CMD mkdir -p "$baseSkillsDir"

        # Prune stale skills from base directory
        if [[ -d "$baseSkillsDir" ]]; then
          for existing in "$baseSkillsDir"/*/; do
            [[ -d "$existing" ]] || continue
            skillName="$(basename "$existing")"
            found=0
            for declared in "''${declaredSkills[@]}"; do
              if [[ "$skillName" == "$declared" ]]; then
                found=1
                break
              fi
            done
            if [[ "$found" -eq 0 ]]; then
              echo "  🗑️  Removing stale skill: $skillName from base"
              $DRY_RUN_CMD rm -rf "$existing"
            fi
          done
        fi

        ${concatStringsSep "\n" (mapAttrsToList (skillName: skillDef: ''
          skillDir="$baseSkillsDir/${skillName}"
          $DRY_RUN_CMD mkdir -p "$skillDir"

          ${concatStringsSep "\n" (mapAttrsToList (fileName: filePath:
            let
              fileMode = if hasSuffix ".py" fileName || hasSuffix ".sh" fileName then "755" else "644";
            in ''
            $DRY_RUN_CMD mkdir -p "$(dirname "$skillDir/${fileName}")"
            $DRY_RUN_CMD cp "${filePath}" "$skillDir/${fileName}"
            $DRY_RUN_CMD chmod ${fileMode} "$skillDir/${fileName}"
          '') skillDef.files)}

          echo "  ✅ Deployed skill: ${skillName} to base"
        '') allSkills)}
      ''}

      echo "✅ Skills deployment complete"
    '';

    # Add assertions for skill validation
    assertions = [
      {
        assertion = all (name: builtinSkillDefs ? ${name}) (attrNames enabledBuiltins);
        message = "Unknown builtin skill(s) enabled. Available: ${concatStringsSep ", " (attrNames builtinSkillDefs)}";
      }
    ];
  };
}
