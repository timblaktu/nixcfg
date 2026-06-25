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
    "PostToolUseFailure" # Plan 046 T5 — after a tool call fails
    "PostToolBatch" # Plan 046 T5 — after a batch of parallel tool calls resolves
    "PermissionRequest" # Plan 046 T5 — when a permission dialog appears
    "Stop"
    "SubagentStop"
    "StopFailure"
    "UserPromptSubmit"
    "UserPromptExpansion" # Plan 046 T5 — when a command expands into a prompt
    "MessageDisplay" # Plan 046 T5 — while assistant message text is displayed
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

  # Plan 046 T5 — build one hook group ({matcher; hooks=[entry];}). Supports
  # every CC hook ENTRY type (command/http/mcp_tool/prompt/agent) and the common
  # per-entry fields (if/async/asyncRewake/once/timeout/statusMessage/shell).
  # Only the fields actually passed are emitted, so the rendered entry matches
  # the upstream schema for the chosen type. `ifFilter` serializes to the
  # reserved JSON key "if" (a Nix keyword, hence the rename + quoting).
  mkHook =
    { matcher
    , type ? "command"
      # command-type
    , command ? null
    , script ? null
    , args ? null
    , shell ? null
      # http-type
    , url ? null
    , headers ? null
    , allowedEnvVars ? null
      # mcp_tool-type
    , server ? null
    , tool ? null
    , input ? null
      # prompt/agent-type
    , prompt ? null
    , model ? null
      # common per-entry fields
    , ifFilter ? null
    , async ? null
    , asyncRewake ? null
    , once ? null
    , statusMessage ? null
    , env ? { }
    , timeout ? 60
    , continueOnError ? true
    }: {
      inherit matcher;
      hooks = [
        ({ inherit type timeout; }
          // (optionalAttrs (command != null) { inherit command; })
          // (optionalAttrs (script != null) { inherit script; })
          // (optionalAttrs (args != null) { inherit args; })
          // (optionalAttrs (shell != null) { inherit shell; })
          // (optionalAttrs (url != null) { inherit url; })
          // (optionalAttrs (headers != null) { inherit headers; })
          // (optionalAttrs (allowedEnvVars != null) { inherit allowedEnvVars; })
          // (optionalAttrs (server != null) { inherit server; })
          // (optionalAttrs (tool != null) { inherit tool; })
          // (optionalAttrs (input != null) { inherit input; })
          // (optionalAttrs (prompt != null) { inherit prompt; })
          // (optionalAttrs (model != null) { inherit model; })
          // (optionalAttrs (ifFilter != null) { "if" = ifFilter; })
          // (optionalAttrs (async != null) { inherit async; })
          // (optionalAttrs (asyncRewake != null) { inherit asyncRewake; })
          // (optionalAttrs (once != null) { inherit once; })
          // (optionalAttrs (statusMessage != null) { inherit statusMessage; })
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

  # Plan 046 T11 — RTK-Tokensave PreToolUse Bash hook (graceful pass-through).
  # RTK (`rtk hook claude`) reads the Bash tool-call JSON on stdin and emits a
  # filtered/rewritten version on stdout, cutting tokens before output reaches
  # the model (per docs/claude-code-codecompanion-parity-verdict.md §2b). We do
  # NOT run `rtk init -g` (it clobbers ~/.claude/{settings.json,CLAUDE.md} and
  # assumes ~/.claude, conflicting with CLAUDE_CONFIG_DIR) — the hook is wired
  # declaratively here instead.
  #
  # The hook MUST NEVER block a Bash call. When `rtk` is unavailable the script
  # is a no-op: it emits nothing and exits 0, so Claude Code runs the original
  # command unchanged. When `hooks.rtk.package` is set the binary is always
  # present, so we delegate unconditionally; otherwise we resolve `rtk` from
  # PATH at hook time and degrade gracefully if absent.
  rtkBin =
    if cfg.hooks.rtk.package != null
    then "${cfg.hooks.rtk.package}/bin/rtk"
    else "rtk";
  rtkHookScript = pkgs.writeShellScript "claude-rtk-hook" (
    if cfg.hooks.rtk.package != null then ''
      exec ${rtkBin} hook claude
    '' else ''
      if command -v rtk >/dev/null 2>&1; then
        exec rtk hook claude
      fi
      # rtk absent — pass-through no-op (never block the Bash call).
      exit 0
    ''
  );

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
      description = ''
        Custom hook definitions. Keys are CC hook event names (see hookEvents
        list); each value is a list of hook groups ({matcher; hooks=[entry];}).
        Freeform attrs, so any entry type the schema accepts (command/http/
        mcp_tool/prompt/agent) and any per-entry field can be expressed
        directly. Merged LAST into the rendered hooks (Plan 046 T5 wired this
        through — previously defined but never serialized).
      '';
      example = lib.literalExpression ''
        {
          PreToolUse = [{
            matcher = "Bash";
            hooks = [{
              type = "http";
              url = "http://localhost:8080/pre-tool";
              "if" = "Bash(git *)";
            }];
          }];
        }
      '';
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

    # Plan 046 T11 — RTK-Tokensave (PAC AI Rust Token Killer) integration.
    rtk = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable the RTK-Tokensave `PreToolUse` `Bash` hook (`rtk hook claude`),
          which filters/rewrites shell-command output to cut tokens before it
          reaches the model. Wired declaratively (NOT via `rtk init -g`, which
          clobbers ~/.claude and conflicts with CLAUDE_CONFIG_DIR).

          NOTE: hooks are module-global (the same settings.json hooks block is
          deployed to every account), so enabling this applies the hook to ALL
          enabled accounts on the host. Intended to be turned on for the work
          host. The hook degrades to a pass-through no-op when `rtk` is absent
          (see `package`), so it is harmless on hosts without RTK installed.
        '';
      };

      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = ''
          RTK binary package. When set, its `bin/rtk` is added to the Claude
          Code PATH and the hook delegates to it unconditionally. When null
          (default), `rtk` is resolved from PATH at hook time and the hook is a
          graceful pass-through no-op if it is not found (so a Bash call is
          never blocked). RTK lives in a credential-gated GitLab repo
          (`git.panasonic.aero/pac/pac-ai-rtk-tokensave`); the work layer
          supplies the binary on PATH, hence the default leaves it unpackaged.
        '';
      };

      contextFile = mkOption {
        type = types.nullOr types.lines;
        default = ''
          # RTK-Tokensave

          This session uses PAC AI RTK-Tokensave: a `PreToolUse` Bash hook
          (`rtk hook claude`) rewrites/filters the output of shell commands
          (git, cargo, pytest, docker, grep, and 100+ others) before it reaches
          the model, reducing token usage substantially. Command behavior is
          unchanged; only the captured output the model sees is condensed.

          See `docs/claude-code-codecompanion-parity-verdict.md` section 2b.
        '';
        description = ''
          Contents of `RTK.md`, deployed into each enabled account's config dir
          and referenced via `@RTK.md` from the generated `CLAUDE.md` (mirroring
          what `rtk init -g` would add) when `rtk.enable` is true. Set to null
          to deploy no context file. The default is a documented stub; the work
          layer can override it with RTK's canonical content.
        '';
      };
    };
  };

  # Plan 046 T5 — assemble hooks by CONCATENATING per-event lists across all
  # contributors. `_internal.hooks` is `types.attrs`, whose native merge is a
  # right-biased `//` that keeps only the LAST contributor's value for any
  # shared event key. Under the previous `mkMerge`, that silently dropped every
  # categorized hook except the last one to touch each event (e.g. security's
  # PreToolUse clobbered development's; logging's PostToolUse clobbered the
  # flake-check/auto-stage hooks). We therefore build the union explicitly with
  # `zipAttrsWith concatLists` and assign once, so every enabled category AND
  # user `custom` hooks coexist on the same event. Inner conditional hooks use
  # `lib.optional` (a list of 0|1) instead of list-embedded `mkIf` (which the
  # `types.attrs` merge would not have filtered).
  config.programs.claude-code._internal.hooks =
    let
      mergeHookSets = lib.zipAttrsWith (_: lib.concatLists);

      developmentHooks = lib.optionalAttrs cfg.hooks.development.enable {
        # Auto-format files before editing
        PreToolUse = lib.optional cfg.hooks.development.autoFormat (mkHook {
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
        });

        PostToolUse =
          # Run flake check after editing flake.nix
          (lib.optional cfg.hooks.development.flakeCheck (mkHook {
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
          ++ (lib.optional cfg.hooks.git.autoStage (mkHook {
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
          }));
      };

      securityHooks = lib.optionalAttrs cfg.hooks.security.enable {
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
      };

      loggingHooks = lib.optionalAttrs cfg.hooks.logging.enable {
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
      };

      # Plan 044 T3 — SessionStart plan-rehydration hook (push half of dual-
      # channel resume). Matches startup/resume/compact so the active plan's
      # next task is re-surfaced on a fresh session and after a long session
      # scrolls/compacts the once-injected context away.
      resumeHooks = lib.optionalAttrs cfg.hooks.resume.enable {
        SessionStart = [
          (mkHook {
            matcher = "startup|resume|compact";
            command = "${resumeHookScript}";
            continueOnError = true;
            timeout = 10;
          })
        ];
      };

      # Plan 046 T11 — RTK-Tokensave PreToolUse Bash hook. continueOnError keeps
      # a non-zero RTK exit from blocking the tool call; the script itself is a
      # no-op when `rtk` is absent (see rtkHookScript above).
      rtkHooks = lib.optionalAttrs cfg.hooks.rtk.enable {
        PreToolUse = [
          (mkHook {
            matcher = "Bash";
            command = "${rtkHookScript}";
            continueOnError = true;
            timeout = 30;
          })
        ];
      };
    in
    mergeHookSets [
      # Base scaffold — every known event present so cleanHooks/hasHooks can
      # gate on any slot and custom hooks can land in any event.
      (lib.genAttrs hookEvents (_: [ ]))
      developmentHooks
      securityHooks
      loggingHooks
      resumeHooks
      rtkHooks
      # Plan 046 T5 — user-defined custom hooks. Freeform attrs keyed by event
      # name; concatenated alongside the categorized hooks so users can express
      # arbitrary entry types (http, mcp_tool, prompt, agent) and per-entry
      # fields the categorized hooks above don't model. (Previously defined as
      # an option but never serialized.)
      cfg.hooks.custom
    ];
}
