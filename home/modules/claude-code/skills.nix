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
  nixcfgPath = cfg.nixcfgPath;
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

  # Generate SKILL.md with frontmatter from custom skill options
  mkSkillFile = name: skill: ''
    ---
    name: ${name}
    description: ${skill.description}
    ---

    ${skill.skillContent}
  '';

  # Get list of enabled builtin skills
  enabledBuiltins = filterAttrs (name: enabled: enabled) skillsCfg.builtins;

  # Combine builtin and custom skills
  allSkills = (mapAttrs
    (name: _: {
      files = builtinSkillDefs.${name}.files;
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
    # Extend the activation script to deploy skills
    home.activation.claudeSkillsDeployment = lib.hm.dag.entryAfter [ "claudeConfigTemplates" ] ''
      echo "🎯 Deploying Claude Code skills..."

      # Deploy skills to each enabled account
      ${concatStringsSep "\n" (mapAttrsToList (accountName: account: ''
        if [[ "${toString account.enable}" == "1" ]]; then
          accountSkillsDir="${runtimePath}/.claude-${accountName}/skills"
          $DRY_RUN_CMD mkdir -p "$accountSkillsDir"

          ${concatStringsSep "\n" (mapAttrsToList (skillName: skillDef: ''
            skillDir="$accountSkillsDir/${skillName}"
            $DRY_RUN_CMD mkdir -p "$skillDir"

            ${concatStringsSep "\n" (mapAttrsToList (fileName: filePath:
              let
                # Handle both path (builtins) and derivation (custom) files
                sourceFile = if isPath filePath then filePath else filePath;
              in ''
                # Create parent directories if needed (for nested paths like templates/foo.md)
                $DRY_RUN_CMD mkdir -p "$(dirname "$skillDir/${fileName}")"
                $DRY_RUN_CMD cp "${sourceFile}" "$skillDir/${fileName}"
                $DRY_RUN_CMD chmod 644 "$skillDir/${fileName}"
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

        ${concatStringsSep "\n" (mapAttrsToList (skillName: skillDef: ''
          skillDir="$baseSkillsDir/${skillName}"
          $DRY_RUN_CMD mkdir -p "$skillDir"

          ${concatStringsSep "\n" (mapAttrsToList (fileName: filePath: ''
            $DRY_RUN_CMD mkdir -p "$(dirname "$skillDir/${fileName}")"
            $DRY_RUN_CMD cp "${filePath}" "$skillDir/${fileName}"
            $DRY_RUN_CMD chmod 644 "$skillDir/${fileName}"
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
