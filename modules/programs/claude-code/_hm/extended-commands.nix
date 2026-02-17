# Extended Claude Code slash commands
# Source files are co-located with this module in ./commands/
{ config, lib, ... }:

with lib;

let
  cfg = config.programs.claude-code;

  # Base path to command content files (co-located with this module)
  # This module is at: home/modules/claude-code/extended-commands.nix
  # Commands are at: home/modules/claude-code/commands/
  commandsBasePath = ./commands;

in
{
  options.programs.claude-code.extendedCommands = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable extended slash commands (anthropic, architecture, security, etc.)";
    };
  };

  config = mkIf (cfg.enable && cfg.extendedCommands.enable) {
    # Deploy all extended commands to each account's commands directory
    home.file = lib.mkMerge (lib.flatten (mapAttrsToList
      (name: account:
        if account.enable then [
          # ===== ANTHROPIC COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/anthropic/apply-thinking-to.md" = {
              text = builtins.readFile (commandsBasePath + "/anthropic/apply-thinking-to.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/anthropic/convert-to-todowrite-tasklist-prompt.md" = {
              text = builtins.readFile (commandsBasePath + "/anthropic/convert-to-todowrite-tasklist-prompt.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/anthropic/update-memory-bank.md" = {
              text = builtins.readFile (commandsBasePath + "/anthropic/update-memory-bank.md");
            };
          }

          # ===== ARCHITECTURE COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/architecture/explain-architecture-pattern.md" = {
              text = builtins.readFile (commandsBasePath + "/architecture/explain-architecture-pattern.md");
            };
          }

          # ===== CCUSAGE COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/ccusage/ccusage-daily.md" = {
              text = builtins.readFile (commandsBasePath + "/ccusage/ccusage-daily.md");
            };
          }

          # ===== CLEANUP COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/cleanup/cleanup-context.md" = {
              text = builtins.readFile (commandsBasePath + "/cleanup/cleanup-context.md");
            };
          }

          # ===== DOCUMENTATION COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/documentation/create-readme-section.md" = {
              text = builtins.readFile (commandsBasePath + "/documentation/create-readme-section.md");
            };
          }

          # ===== PROMPT ENGINEERING COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/promptengineering/batch-operations-prompt.md" = {
              text = builtins.readFile (commandsBasePath + "/promptengineering/batch-operations-prompt.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/promptengineering/convert-to-test-driven-prompt.md" = {
              text = builtins.readFile (commandsBasePath + "/promptengineering/convert-to-test-driven-prompt.md");
            };
          }

          # ===== REFACTOR COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/refactor/refactor-code.md" = {
              text = builtins.readFile (commandsBasePath + "/refactor/refactor-code.md");
            };
          }

          # ===== SECURITY COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/security/check-best-practices.md" = {
              text = builtins.readFile (commandsBasePath + "/security/check-best-practices.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/security/secure-prompts.md" = {
              text = builtins.readFile (commandsBasePath + "/security/secure-prompts.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/security/security-audit.md" = {
              text = builtins.readFile (commandsBasePath + "/security/security-audit.md");
            };
          }

          # ===== PLANNING COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/planning/plans.md" = {
              text = builtins.readFile (commandsBasePath + "/planning/plans.md");
            };
          }

          # ===== SECURITY TEST EXAMPLES =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/security/test-examples/test-advanced-injection.md" = {
              text = builtins.readFile (commandsBasePath + "/security/test-examples/test-advanced-injection.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/security/test-examples/test-authority-claims.md" = {
              text = builtins.readFile (commandsBasePath + "/security/test-examples/test-authority-claims.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/security/test-examples/test-basic-role-override.md" = {
              text = builtins.readFile (commandsBasePath + "/security/test-examples/test-basic-role-override.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/security/test-examples/test-css-hiding.md" = {
              text = builtins.readFile (commandsBasePath + "/security/test-examples/test-css-hiding.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/security/test-examples/test-encoding-attacks.md" = {
              text = builtins.readFile (commandsBasePath + "/security/test-examples/test-encoding-attacks.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/security/test-examples/test-invisible-chars.md" = {
              text = builtins.readFile (commandsBasePath + "/security/test-examples/test-invisible-chars.md");
            };
          }
        ] else [ ]
      )
      cfg.accounts));
  };
}
