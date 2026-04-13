# OpenCode skills module
# Manages skill path configuration and optional file deployment
# Mirrors claude-code's skills.nix pattern
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.opencode;
  skillsCfg = cfg.skills;
  inherit (cfg) nixcfgPath;
  runtimePath = "${nixcfgPath}/opencode-runtime";

  # Custom skill submodule
  customSkillModule = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        description = "Skill description for discovery (shown to OpenCode for triggering)";
      };

      skillContent = mkOption {
        type = types.str;
        description = ''
          SKILL.md content (without frontmatter - it will be generated).
          This is the main instruction content that OpenCode uses when the skill is invoked.
        '';
      };

      referenceContent = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional REFERENCE.md content for extended documentation.";
      };

      extraFiles = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Additional files as filename -> content attrset.";
      };
    };
  };

  # Generate SKILL.md with frontmatter
  mkSkillFile = name: skill: ''
    ---
    name: ${name}
    description: ${skill.description}
    ---

    ${skill.skillContent}
  '';

  # Built-in skill definitions - adr-writer is tool-agnostic
  # Uses CC's skill files since they are tool-agnostic content
  builtinSkillDefs = {
    adr-writer = {
      name = "adr-writer";
      description = "Guide writing Architecture Decision Records (ADRs) following the Design It! methodology. Use when creating ADRs, documenting architecture decisions, recording technical decisions, or when someone asks about ADR format or templates.";
      files = {
        # Reference the CC skill files directly - they are tool-agnostic
        "SKILL.md" = ../../claude-code/_hm/skills/adr-writer/SKILL.md;
        "REFERENCE.md" = ../../claude-code/_hm/skills/adr-writer/REFERENCE.md;
      };
    };
  };

  # Get enabled builtins
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

  # Build skill paths for all deployed skills (relative to account dir)
  deployedSkillPaths = mapAttrsToList
    (name: _: "./skills/${name}")
    allSkills;

in
{
  options.programs.opencode.skills = {
    enable = mkEnableOption "OpenCode skills management";

    builtins = {
      adr-writer = mkOption {
        type = types.bool;
        default = true;
        description = "Enable the ADR writing skill (tool-agnostic, shared with Claude Code).";
      };
    };

    paths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional skill paths to include in opencode.json";
    };

    urls = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Skill URLs to include in opencode.json";
    };

    custom = mkOption {
      type = types.attrsOf customSkillModule;
      default = { };
      description = "Custom skill definitions deployed as SKILL.md files.";
    };
  };

  config = mkIf (cfg.enable && skillsCfg.enable) {
    # Deploy skill files via activation script
    home.activation.opencodeSkillsDeployment = lib.hm.dag.entryAfter [ "opencodeConfigTemplates" ] ''
      echo "Deploying OpenCode skills..."

      ${concatStringsSep "\n" (mapAttrsToList (accountName: account: ''
        if [[ "${toString account.enable}" == "1" ]]; then
          accountSkillsDir="${runtimePath}/.opencode-${accountName}/skills"
          $DRY_RUN_CMD mkdir -p "$accountSkillsDir"

          ${concatStringsSep "\n" (mapAttrsToList (skillName: skillDef: ''
            skillDir="$accountSkillsDir/${skillName}"
            $DRY_RUN_CMD mkdir -p "$skillDir"

            ${concatStringsSep "\n" (mapAttrsToList (fileName: filePath:
              let
                fileMode = if hasSuffix ".py" fileName then "755" else "644";
              in ''
                $DRY_RUN_CMD mkdir -p "$(dirname "$skillDir/${fileName}")"
                $DRY_RUN_CMD cp "${filePath}" "$skillDir/${fileName}"
                $DRY_RUN_CMD chmod ${fileMode} "$skillDir/${fileName}"
              ''
            ) skillDef.files)}

            echo "  Deployed skill: ${skillName} to ${accountName}"
          '') allSkills)}
        fi
      '') cfg.accounts)}

      echo "OpenCode skills deployed"
    '';

    # Wire skills into the JSON config via _internal
    # The main module's mkOpencodeConfig will pick this up
    programs.opencode._internal.skillPaths = deployedSkillPaths ++ skillsCfg.paths;
    programs.opencode._internal.skillUrls = skillsCfg.urls;

    # Assertions
    assertions = [
      {
        assertion = all (name: builtinSkillDefs ? ${name}) (attrNames enabledBuiltins);
        message = "Unknown builtin skill(s) enabled. Available: ${concatStringsSep ", " (attrNames builtinSkillDefs)}";
      }
    ];
  };
}
