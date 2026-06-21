{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;

  # Canonical list of all CC hook events. When upstream adds events, add one
  # string here — the rest of the module (custom default, base structure,
  # hasHooks gate) derives from this list automatically.
  hookEvents = [
    "PreToolUse"
    "PostToolUse"
    "Stop"
    "SubagentStop"
    "StopFailure"
    "UserPromptSubmit"
    "SessionStart"
    "SessionEnd"
    "PreCompact"
    "PostCompact"
    "CwdChanged"
    "FileChanged"
    "ConfigChange"
    "PermissionDenied"
    "TaskCreated"
    "TaskCompleted"
    "WorktreeCreate"
    "WorktreeRemove"
    "InstructionsLoaded"
    "Elicitation"
    "ElicitationResult"
    "Notification"
    "SubagentStart"
    "TeammateIdle"
    "Setup"
  ];

  mkHook =
    { matcher
    , type ? "command"
    , command ? null
    , script ? null
    , env ? { }
    , timeout ? 60
    , continueOnError ? true
    }: {
      inherit matcher;
      hooks = [
        ({
          inherit type timeout;
        } // (if command != null
        then { inherit command; }
        else { inherit script; })
        // (optionalAttrs (env != { }) { inherit env; })
        // (optionalAttrs continueOnError { continueOnError = true; }))
      ];
    };

  # Plan 044 T3 — SessionStart plan-rehydration hook. The bash body lives in its
  # own file so its ${...} expansions need no Nix escaping; the Nix wrapper only
  # prepends the runtime PATH. builtins.readFile inserts the file content
  # verbatim (it is NOT re-scanned for Nix interpolation).
  resumeHookScript = pkgs.writeShellScript "claude-resume-hook"
    (''
      export PATH=${makeBinPath [ pkgs.jq pkgs.fd pkgs.coreutils pkgs.gawk pkgs.gnugrep ]}:$PATH
    '' + builtins.readFile ./resume-hook.sh);

in
{
  options.programs.claude-code.hooks = {
    formatting = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable auto-formatting hooks";
      };
      commands = mkOption {
        type = types.attrsOf types.str;
        default = {
          py = "${pkgs.black}/bin/black \"$file_path\" 2>/dev/null || true";
          nix = "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt \"$file_path\" 2>/dev/null || true";
          js = "${pkgs.prettier}/bin/prettier --write \"$file_path\" 2>/dev/null || true";
          json = "${pkgs.prettier}/bin/prettier --write \"$file_path\" 2>/dev/null || true";
          rs = "${pkgs.rustfmt}/bin/rustfmt \"$file_path\" 2>/dev/null || true";
          go = "${pkgs.go}/bin/gofmt -w \"$file_path\" 2>/dev/null || true";
        };
        description = "Formatting commands by file extension";
      };
    };

    linting = {
      enable = mkEnableOption "linting hooks";
      commands = mkOption {
        type = types.attrsOf types.str;
        default = {
          py = "${pkgs.python3Packages.pylint}/bin/pylint \"$file_path\" 2>/dev/null || true";
          js = "${pkgs.eslint}/bin/eslint \"$file_path\" 2>/dev/null || true";
        };
        description = "Linting commands by file extension";
      };
    };

    security = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable security hooks";
      };
      blockedPatterns = mkOption {
        type = types.listOf types.str;
        default = [ "\\\\.env" "\\\\.secrets" "id_rsa" "\\\\.key$" ];
        description = "File patterns to block access to";
      };
    };

    git = {
      enable = mkEnableOption "git integration hooks";
      autoStage = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically stage modified files";
      };
      autoCommit = mkEnableOption "automatically commit changes";
    };

    testing = {
      enable = mkEnableOption "test automation hooks";
      sourcePattern = mkOption {
        type = types.str;
        default = "src/.*\\\\.(py|js|ts)$";
        description = "Pattern for source files that trigger tests";
      };
      command = mkOption {
        type = types.str;
        default = "npm test 2>/dev/null || pytest 2>/dev/null || true";
        description = "Test command to run";
      };
    };

    logging = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable logging hooks";
      };
      logPath = mkOption {
        type = types.str;
        default = "$CLAUDE_CONFIG_DIR/logs/tool-usage.log";
        description = "Path to log file";
      };
      verbose = mkEnableOption "include tool inputs in logs";
    };

    notifications = {
      enable = mkEnableOption "notification hooks";
      matcher = mkOption {
        type = types.str;
        default = "";
        description = "Event matcher for notifications";
      };
      title = mkOption {
        type = types.str;
        default = "Claude Code";
        description = "Notification title";
      };
      message = mkOption {
        type = types.str;
        default = "Finished working in current project";
        description = "Notification message";
      };
    };

    development = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable development workflow hooks";
      };
      flakeCheck = mkOption {
        type = types.bool;
        default = true;
        description = "Run nix flake check after editing flake.nix";
      };
      autoFormat = mkOption {
        type = types.bool;
        default = true;
        description = "Auto-format files before editing";
      };
    };

    custom = mkOption {
      type = types.attrs;
      default = lib.genAttrs hookEvents (_: [ ]);
      description = "Custom hook definitions. Keys are CC hook event names (see hookEvents list).";
    };

    resume = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable the SessionStart plan-rehydration hook (plan 044). On
          startup/resume/compact it surfaces the active plan's next task
          (.claude/active-plan), else .claude/HANDOFF.md, else the latest prior
          per-cwd transcript's last assistant message, as factual session-start
          context. The PUSH half of a dual-channel resume design; the next-task
          skill and the readable handoff files are the PULL backstop.
        '';
      };
    };
  };

  config.programs.claude-code._internal.hooks = mkMerge [
    # Base hook structure — scaffold every known event so categorized and
    # custom hooks can merge into any slot.
    (lib.genAttrs hookEvents (_: [ ]))

    # Development workflow hooks
    (mkIf cfg.hooks.development.enable {
      PreToolUse = [
        # Auto-format files before editing
        (mkIf cfg.hooks.development.autoFormat (mkHook {
          matcher = "Edit|Write|MultiEdit";
          command = ''
            file_path="$1"
            case "$file_path" in
              *.nix)   ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt "$file_path" 2>/dev/null || true ;;
              *.py)    ${pkgs.black}/bin/black "$file_path" 2>/dev/null || true ;;
              *.rs)    ${pkgs.rustfmt}/bin/rustfmt "$file_path" 2>/dev/null || true ;;
              *.js|*.json) ${pkgs.prettier}/bin/prettier --write "$file_path" 2>/dev/null || true ;;
            esac
          '';
          continueOnError = true;
          timeout = 10;
        }))
      ];

      PostToolUse = [
        # Run flake check after editing flake.nix
        (mkIf cfg.hooks.development.flakeCheck (mkHook {
          matcher = "Edit.*flake\\.nix|Write.*flake\\.nix";
          command = ''
            if [ -f flake.nix ]; then
              echo "🔍 Running nix flake check after flake.nix change..."
              ${pkgs.nix}/bin/nix flake check --no-build 2>/dev/null || {
                echo "⚠️  Flake check failed - please review manually"
                exit 0  # Don't fail the hook
              }
              echo "✅ Flake check passed"
            fi
          '';
          continueOnError = true;
          timeout = 30;
        }))

        # Auto-stage files in flake projects
        (mkIf cfg.hooks.git.autoStage (mkHook {
          matcher = "Edit|Write|MultiEdit";
          command = ''
            if [ -f flake.nix ] && [ -d .git ]; then
              file_path="$1"
              if [ -n "$file_path" ] && [ -f "$file_path" ]; then
                ${pkgs.git}/bin/git add "$file_path" 2>/dev/null || true
                echo "📁 Auto-staged: $file_path"
              fi
            fi
          '';
          continueOnError = true;
          timeout = 5;
        }))
      ];
    })

    # Security hooks
    (mkIf cfg.hooks.security.enable {
      PreToolUse = [
        (mkHook {
          matcher = "Read|Edit|Write";
          command = ''
            file_path="$1"
            for pattern in ${toString cfg.hooks.security.blockedPatterns}; do
              if echo "$file_path" | grep -qE "$pattern"; then
                echo "🚫 Security: Access blocked to sensitive file pattern: $pattern"
                exit 1
              fi
            done
          '';
          continueOnError = false;
          timeout = 5;
        })
      ];
    })

    # Logging hooks
    (mkIf cfg.hooks.logging.enable {
      PostToolUse = [
        (mkHook {
          matcher = ".*";
          command = ''
            mkdir -p "$(dirname "${cfg.hooks.logging.logPath}")"
            echo "$(date): Tool used in $(pwd)" >> "${cfg.hooks.logging.logPath}"
          '';
          continueOnError = true;
          timeout = 5;
        })
      ];
    })

    # Plan 044 T3 — SessionStart plan-rehydration hook (push half of dual-channel
    # resume). Matches startup/resume/compact so the active plan's next task is
    # re-surfaced on a fresh session and after a long session scrolls/compacts the
    # once-injected context away.
    (mkIf cfg.hooks.resume.enable {
      SessionStart = [
        (mkHook {
          matcher = "startup|resume|compact";
          command = "${resumeHookScript}";
          continueOnError = true;
          timeout = 10;
        })
      ];
    })
  ];
}
