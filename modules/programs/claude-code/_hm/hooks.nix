{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;

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
          js = "${pkgs.nodePackages.prettier}/bin/prettier --write \"$file_path\" 2>/dev/null || true";
          json = "${pkgs.nodePackages.prettier}/bin/prettier --write \"$file_path\" 2>/dev/null || true";
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
          js = "${pkgs.nodePackages.eslint}/bin/eslint \"$file_path\" 2>/dev/null || true";
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
        default = "$HOME/.claude/logs/tool-usage.log";
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
      default = { PreToolUse = [ ]; PostToolUse = [ ]; SessionStart = [ ]; Stop = [ ]; };
      description = "Custom hook definitions";
    };
  };

  config.programs.claude-code._internal.hooks = mkMerge [
    # Base hook structure
    {
      PreToolUse = [ ];
      PostToolUse = [ ];
      SessionStart = [ ];
      Stop = [ ];
    }

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
              *.js|*.json) ${pkgs.nodePackages.prettier}/bin/prettier --write "$file_path" 2>/dev/null || true ;;
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
  ];
}
