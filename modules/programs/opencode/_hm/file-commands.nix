# OpenCode file-based slash commands
# Deploys custom .md command files to each account's commands/ directory
# Built-in commands (e.g. /plans) are handled via JSON in lib.nix defaultCommands
{ config, lib, ... }:

with lib;

let
  cfg = config.programs.opencode;
  inherit (cfg) nixcfgPath;
  runtimePath = "${nixcfgPath}/opencode-runtime";

in
{
  options.programs.opencode.fileCommands = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable file-based slash commands (.md files deployed to commands/)";
    };

    custom = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          category = mkOption {
            type = types.str;
            default = "custom";
            description = "Command category (subdirectory name)";
          };
          content = mkOption {
            type = types.lines;
            description = "Markdown content for the command file";
          };
        };
      });
      default = { };
      description = "Custom file-based commands as name -> { category, content }";
    };
  };

  config = mkIf (cfg.enable && cfg.fileCommands.enable) {
    # Deploy file-based commands via activation script
    home.activation.opencodeFileCommands = lib.hm.dag.entryAfter [ "opencodeConfigTemplates" ] ''
      echo "Deploying OpenCode file-based commands..."

      ${concatStringsSep "\n" (mapAttrsToList (accountName: account: ''
        if [[ "${toString account.enable}" == "1" ]]; then
          accountDir="${runtimePath}/.opencode-${accountName}"

          ${concatStringsSep "\n" (mapAttrsToList (cmdName: cmdDef:
            let
              targetDir = "$accountDir/commands/${cmdDef.category}";
              targetFile = "${targetDir}/${cmdName}.md";
              contentFile = builtins.toFile "opencode-cmd-${cmdName}.md" cmdDef.content;
            in ''
              $DRY_RUN_CMD mkdir -p "${targetDir}"
              $DRY_RUN_CMD cp "${contentFile}" "${targetFile}"
              $DRY_RUN_CMD chmod 644 "${targetFile}"
            ''
          ) cfg.fileCommands.custom)}

          echo "  Deployed commands to ${accountName}"
        fi
      '') cfg.accounts)}

      echo "OpenCode file-based commands deployed"
    '';
  };
}
