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

          # ===== MEMORY COMMANDS =====
          # Bare /cleanmemory (top-level, no namespace): curate + prune MEMORY.md
          # and its topic files by relevance. Deployed to every enabled account.
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/cleanmemory.md" = {
              text = builtins.readFile (commandsBasePath + "/cleanmemory.md");
            };
          }
          # /memcheck (+ /memhealth alias): READ-ONLY memory health report - sizes vs
          # the harness caps (24.4KB / 200 lines), orphan topic files, stale/leak
          # signals, GREEN/AMBER/RED verdict. The read-only sibling of /cleanmemory
          # (check -> clean). Both aliases share the one body.
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/memcheck.md" = {
              text = builtins.readFile (commandsBasePath + "/memcheck.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/memhealth.md" = {
              text = builtins.readFile (commandsBasePath + "/memcheck.md");
            };
          }

          # ===== REORIENT COMMAND (+ aliases) =====
          # Bare /reorient (top-level): cold-start re-orientation to the active
          # plan's durable objective, where-we-are, what-remains, and an on-track
          # vs in-the-weeds self-audit. Read-only. Traces BOTH the git lineage to
          # main AND the gitignored plan/session-history trail. /align-with-objective
          # and /dude-wheres-my-car are aliases wired to the same body.
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/reorient.md" = {
              text = builtins.readFile (commandsBasePath + "/reorient.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/align-with-objective.md" = {
              text = builtins.readFile (commandsBasePath + "/reorient.md");
            };
          }
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/dude-wheres-my-car.md" = {
              text = builtins.readFile (commandsBasePath + "/reorient.md");
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

          # ===== MAINTENANCE COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/maintenance/analyze-package-updates.md" = {
              text = builtins.readFile (commandsBasePath + "/maintenance/analyze-package-updates.md");
            };
          }

          # ===== PLANNING COMMANDS =====
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/planning/plans.md" = {
              text = builtins.readFile (commandsBasePath + "/planning/plans.md");
            };
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/planning/burndownify.md" = {
              text = builtins.readFile (commandsBasePath + "/planning/burndownify.md");
            };
          }

          # ===== SESSION COMMANDS =====
          # Top-level (un-namespaced) so it is invoked as /closesess in any session.
          {
            "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/closesess.md" = {
              text = builtins.readFile (commandsBasePath + "/closesess.md");
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
