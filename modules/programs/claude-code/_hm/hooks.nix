{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;

  # Plan 050 T3 - shared per-pane tmux command-status writer. Imported from
  # modules/lib so the claude-code and tmux modules share ONE implementation
  # (no cross-config reads). Replaces the previously-inlined tmuxStateScript.
  # T5: the CC tmuxStatus source now folds through mkProgramSource (which resolves
  # the writer binary itself), so no direct `mkHelper` bin reference is needed here.
  tmuxCmdState = import ../../../lib/tmux-cmd-state.nix { inherit pkgs lib; };

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

  # Plan 056 P11.3/P11.5 — git global-option prefix. A `git` subcommand can be
  # preceded by global options that take an argument (`git -C DIR commit`,
  # `git -c k=v push`, `git --git-dir=D commit`, `git --work-tree=W commit`).
  # The original detection greps required the subcommand to IMMEDIATELY follow
  # `git`, so `git -C DIR commit` on main slipped past blockCommitOnMain (the
  # b5aefa0 fix resolved the -C dir but the detection never fired for it — the
  # exact cross-worktree case P11 audits). Interpolating this fragment right
  # after `git[[:space:]]+` tolerates ONLY these recognized global options (each
  # consuming its argument), so `git branch commit-x` / `git commit -m "add -f"`
  # do NOT false-match while `git -C DIR commit` does. Kept deliberately narrow
  # (real global-option shapes, not a blanket `.*`) to avoid message-content FPs.
  gitGlobalOpts = "(-C[[:space:]]+[^[:space:]]+[[:space:]]+|-c[[:space:]]+[^[:space:]]+[[:space:]]+|--git-dir[=[:space:]][^[:space:]]+[[:space:]]+|--work-tree[=[:space:]][^[:space:]]+[[:space:]]+)*";

  # Plan 056 P11 — shared prelude prepended to every blocking session-workflow
  # hook. Unifies three concerns the P11 review standardized:
  #   * the uniform CLAUDE_HOOKS_BYPASS launch-time escape hatch (unchanged);
  #   * gr_log (P11.6 observability) — appends one tab-separated line per
  #     guardrail activation (`<iso-ts>\t<verdict>\t<rule>`) to
  #     $CLAUDE_GUARDRAIL_LOG (default <config-or-home>/logs/guardrails.log), so
  #     an operator can inspect which guardrail fired and why. Best-effort: any
  #     logging failure is swallowed and never affects the block decision;
  #   * gr_block (hard block: exit 2 + the message on stderr, fed back to the
  #     model — the exit-2 convention needs continueOnError=false at the group);
  #   * gr_gate (P11.2 judgment-gate) — for the two JUDGMENT rules (commit-on-main,
  #     task-complete sign-off) emit a structured permissionDecision:"ask" so the
  #     OPERATOR approves the call in-the-moment when an interactive controlling
  #     terminal is present, instead of a hard block that needs a launch-time env
  #     var. Fails SAFE: it only asks when it POSITIVELY detects a writable
  #     /dev/tty AND CLAUDE_HOOKS_NONINTERACTIVE is unset — otherwise it degrades
  #     to gr_block. A headless/burndown launcher (no operator) has no controlling
  #     tty, so it hard-blocks deterministically; such launchers may also set
  #     CLAUDE_HOOKS_NONINTERACTIVE=1 to force hard-block even if a tty leaks.
  #     NOTE: whether CC honors "ask" identically across versions is verified for
  #     v2.1+ (plan 056 P11.2); the /dev/tty probe is verified live at P10.
  # Every gr_block/gr_gate message follows the four-part contract
  # (WHAT / WHY / TO PROCEED NOW / TO AVOID IN FUTURE) and links the guide
  # docs/claude-code-session-guardrails.md.
  guardrailPrelude = ''
    [ -n "$CLAUDE_HOOKS_BYPASS" ] && exit 0
    __gr_log="''${CLAUDE_GUARDRAIL_LOG:-''${CLAUDE_CONFIG_DIR:-$HOME}/logs/guardrails.log}"
    gr_log() {
      { ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$__gr_log")" \
          && printf '%s\t%s\t%s\n' "$(${pkgs.coreutils}/bin/date -Iseconds 2>/dev/null)" "$2" "$1" >> "$__gr_log"; } 2>/dev/null || true
    }
    gr_block() {
      gr_log "$1" BLOCK
      printf '%s\n' "$2" >&2
      exit 2
    }
    gr_gate() {
      if [ -z "$CLAUDE_HOOKS_NONINTERACTIVE" ] && { true >/dev/tty; } 2>/dev/null; then
        gr_log "$1" ASK
        ${pkgs.jq}/bin/jq -cn --arg r "$2" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
        exit 0
      fi
      gr_block "$1" "$2"
    }
  '';

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

    # Plan 056 P4 — Class-A git-safety interlocks. Each sub-rule is a PreToolUse
    # Bash hook that parses `.tool_input.command` (jq stdin) and `exit 2`
    # (continueOnError=false) to BLOCK a dangerous git invocation, feeding an
    # instructive message back to the model. Every block honors the uniform
    # `CLAUDE_HOOKS_BYPASS` env-var escape hatch so a bad matcher can never lock
    # the operator out of committing mid-session. A sub-rule fires only when BOTH
    # `gitSafety.enable` AND its own sub-toggle are true (per-rule toggleability).
    # Subsumes plan 017's `--no-verify` design as `blockNoVerify` (do NOT author a
    # parallel hook). Hooks are MODULE-GLOBAL (deploy to every enabled account) —
    # see the false-positive analysis in plan 056's "P3 design" section. Defaults
    # are for the eventual P6 adoption; the category is not enabled on the live
    # host until then.
    gitSafety = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Master switch for the git-safety PreToolUse interlocks (Plan 056).
          When true, each individually-toggleable sub-rule below (that is itself
          true) installs a blocking Bash hook. Set false to disable the whole
          category regardless of the sub-toggles.
        '';
      };
      blockNoVerify = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Block `git commit`/`git push --no-verify` (and the `-n`/combined
          short forms on `git commit`, where `-n` = --no-verify; NOT on
          `git push`, where `-n` = --dry-run). Subsumes plan 017 I1. Prevents
          skipping pre-commit/pre-push hooks under flake-check-timeout pressure.
        '';
      };
      blockAttribution = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Block `git commit` whose message carries an AI-attribution LEAK
          signature (`Co-Authored-By:` trailer, `Generated with [Claude Code]`,
          `claude.ai/code`, the anthropic noreply address, or the 🤖 emoji).
          Deliberately does NOT match bare `Claude`/`Anthropic` — this repo's
          commit messages mention them constantly, so a brand matcher would
          false-positive on nearly every commit. Real incident: 11 public
          commits leaked Co-Authored-By trailers (memory
          project_ai_attribution_leak).
        '';
      };
      blockCommitOnMain = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Block `git commit`/`git push` when the current branch (from
          `git symbolic-ref --short HEAD` in the tool cwd) is `main` or
          `master`. Detached HEAD falls through to allow. Enforces the project
          CRITICAL "NEVER WORK ON MAIN OR MASTER" rule mechanically. Largest
          blast radius of the category (fires host-wide for every repo/account);
          throwaway-on-main repos use the bypass env var.

          Plan 056 P11.2 — this is a JUDGMENT gate: when an interactive
          controlling terminal is present it emits a structured
          permissionDecision:"ask" so the operator approves the commit
          in-the-moment (no relaunch needed), and falls back to a hard block
          when headless or when CLAUDE_HOOKS_NONINTERACTIVE=1 is set (burndown /
          any no-operator launcher). P11.3/P11.5 — the detection tolerates git
          global options, so `git -C DIR commit`/`git -c k=v commit` on main are
          caught (previously they slipped past). Every activation is recorded to
          $CLAUDE_GUARDRAIL_LOG (P11.6 observability).
        '';
      };
      blockAddForce = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Block `git add -f`/`--force` (respect .gitignore; never force-add).
        '';
      };
      blockAddSessionState = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Plan 057 T5 — block a `git add` that explicitly targets the
          per-worktree runtime dir `.session-state/` (or a path under it). Those
          files (`active-plan`, `HANDOFF.md`) are per-worktree session state that
          must NEVER be committed; they are already gitignored machine-wide
          (`**/.session-state/`), so this is a SUSPENDER over that belt for the
          case a repo re-tracks plans (opting `user-plans/` back in) and a stray
          explicit add reaches under `.session-state/`. FALSE-POSITIVE analysis:
          fires only when the literal token `.session-state` appears as a path
          argument to `git add` (terminated by `/`, whitespace, or end); a normal
          `git add user-plans/...`, `git add -A`, `git add .`, or a path like
          `.session-state-notes.txt` (different terminator) is NOT blocked.
          Honors the uniform `CLAUDE_HOOKS_BYPASS` escape.
        '';
      };
    };

    # Plan 056 P4 — Class-A/B bash-safety interlock. Blocks with an instructive
    # message; NEVER auto-rewrites the command (the RTK rewrite experiment
    # silently corrupted output and was disabled host-wide — memory
    # rtk-grep-false-negative-disabled). Same PreToolUse Bash + jq-stdin + exit 2
    # + `CLAUDE_HOOKS_BYPASS` conventions as gitSafety.
    bashSafety = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Master switch for the bash-safety PreToolUse interlocks (Plan 056).
        '';
      };
      blockBareRm = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Block a bare `rm`/`cp`/`mv` (no `-f`/`--force`) in any `;`/`&&`/`||`/`|`
          segment of a Bash command. The user's shell aliases these to the
          interactive `-i` form, which HANGS in non-interactive tool subshells
          waiting for a prompt that never comes. The block message tells the
          model to re-run WITH `-f`; the command is NOT auto-rewritten (RTK
          lesson). Per-segment head-word test — `rmdir`, `git rm`, `xargs rm`,
          `sudo rm`, `find -exec rm` are NOT caught (their head word differs).
        '';
      };
    };

    # Plan 056 P7 — secret-dump prevention interlocks. Mechanical enforcement of
    # the standing rule memory `never-dump-secrets-to-agent-context` (no
    # `rbw --full`/vault dumps/secret-env echoes into the transcript, context, or
    # files). Same PreToolUse Bash + jq-stdin + exit 2 + `CLAUDE_HOOKS_BYPASS`
    # conventions as gitSafety/bashSafety; safety-critical → default block. The
    # design is FP-aware (DUAL-USE): a piped `rbw get X | tool --password-stdin`
    # and a `$(rbw get X)` capture PASS; only forms that render a secret into the
    # transcript/context/a file block. See plan 056 "P7 design" for the full
    # false-positive analysis + the [DECISION] Tim 2026-09-13 block.
    secretSafety = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Master switch for the secret-dump prevention PreToolUse interlocks
          (Plan 056 P7). Each sub-rule below installs its blocking hook only when
          both this master switch AND the sub-toggle are true.
        '';
      };
      blockVaultDump = mkOption {
        type = types.bool;
        default = true;
        description = ''
          P7a — block `rbw` invocations that render vault contents into the agent
          context/files: `rbw --full`/`rbw get --full` (dumps every field incl.
          notes — the exact incident form) is blocked unconditionally; a
          retrieval `rbw get`/`rbw code` is blocked only when its output is NOT
          consumed by a pipe (`rbw get X | tool`) or a command substitution
          (`$(rbw get X)`/backticks) — i.e. bare display or a `> file` redirect.
          Dual-use `rbw get X | tool --password-stdin` PASSES. Management
          subcommands (`sync`/`lock`/`unlock`/`login`/`list`/`generate`) are
          untouched.
        '';
      };
      blockSecretEnvEcho = mkOption {
        type = types.bool;
        default = true;
        description = ''
          P7b — block `echo`/`printf` of a secret-shaped shell variable
          (`$NAME`/`''${NAME}` where NAME matches TOKEN/SECRET/PASSWORD/PASSPHRASE/
          API_KEY/ACCESS_KEY/PRIVATE_KEY/CREDENTIAL) and `printenv SECRETVAR`.
          Matching on the `$`-prefixed variable reference keeps false positives
          near-zero (literal text like "token refresh done" is not matched). The
          legitimate auth-token prefix `GH_TOKEN=$(gh auth token) git push` is a
          command-prefix assignment, NOT an echo, so it PASSES. Bare `env`/`set -x`
          are deliberately NOT blocked (too common in legit debugging).
        '';
      };
    };

    # Plan 056 P5 — session-workflow process-gates (the "hard process-gates"
    # research). Unlike gitSafety/bashSafety (safety-critical → default block),
    # these are WORKFLOW-discipline gates with softer predicates and real
    # ergonomic cost, so each sub-rule defaults OFF: P6 opts them in (warn-first)
    # after a trial. Both implemented sub-rules are PreToolUse Edit|MultiEdit|Write
    # hooks that inspect a plan-file status transition (`.tool_input.file_path`
    # under `user-plans/`, `.new_string`/`.content`/`.edits[].new_string`
    # vs `.old_string`/`.edits[].old_string`, all via jq-stdin) and `exit 2`
    # (continueOnError=false) to BLOCK, honoring the uniform `CLAUDE_HOOKS_BYPASS`
    # escape hatch. See plan 056 "P5 findings" for the full feasibility analysis.
    #
    # DELIBERATELY NOT IMPLEMENTED — P5b mandatory-handoff-before-stop: there is
    # NO blockable "session is ending" event (SessionEnd cannot block; Stop fires
    # per-turn), and a SessionEnd advisory-warn cannot change behavior (its stdout
    # goes to the debug log, invisible to Claude). [DECISION] Tim 2026-09-08:
    # keep handoff-before-stop SOFT — rely on CLAUDE.md discipline + the plan-044
    # SessionStart resume hook. (Full rationale in plan 056 "P5 findings" P5b.)
    planIntegrity = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Master switch for the Plan 056 P5 session-workflow process-gates.
          Each sub-rule below defaults OFF and installs its blocking hook only
          when both this master switch AND the sub-toggle are true.
        '';
      };
      requireSignoffBeforeComplete = mkOption {
        type = types.bool;
        default = true;
        description = ''
          P5a — block an Edit/MultiEdit/Write that flips a task in a
          `user-plans/*.md` file to `TASK:COMPLETE` (a net-new
          completion) UNLESS the `CLAUDE_TASK_SIGNOFF` env var is set. That var
          can only be set at `claude` LAUNCH time (verified 2026-09-08: a
          mid-session `export` in a Bash tool call is INVISIBLE to a later hook,
          because hooks fork from claude's launch env) — so the model cannot
          self-certify; only the operator can attest a Present/STOP review
          happened. Enforces memory `next-task-present-stop-artifact-gate`
          mechanically. Trade-off: session-global (green-lights every completion
          that session), not per-task.

          Default `true` since Plan 056 P6 ([DECISION] Tim 2026-09-09: enable
          both P5 gates as hard blocks). MODULE-GLOBAL CAVEAT: this fires for
          every account/consumer of this module, including the shared dev-team
          images (plan 052). Consumers who do NOT use the `/next-task`
          Present/STOP workflow should set this false in their own config, since
          it will otherwise block every plan-file `TASK:COMPLETE` edit unless
          `CLAUDE_TASK_SIGNOFF` was exported at launch.

          Plan 056 P11.2 — this is a JUDGMENT gate: with an interactive
          controlling terminal it emits permissionDecision:"ask" so the operator
          can approve the completion in-the-moment after a Present/STOP review;
          headless or CLAUDE_HOOKS_NONINTERACTIVE=1 (burndown) falls back to the
          hard block, preserving the launch-time `CLAUDE_TASK_SIGNOFF`
          attestation. Activations are logged to $CLAUDE_GUARDRAIL_LOG.
        '';
      };
      enforceStatusTransitions = mkOption {
        type = types.bool;
        default = true;
        description = ''
          P5c — block an Edit/MultiEdit/Write on a `user-plans/*.md` file
          that (a) skips `TASK:PENDING`→`TASK:COMPLETE` directly (mark
          IN_PROGRESS first) or (b) introduces a `TASK:COMPLETE` with no
          `(YYYY-MM-DD)` completion date. Pure textual predicates on the edit;
          enforces the transition SHAPE, not whether the DoD is truly met.

          Default `true` since Plan 056 P6 ([DECISION] Tim 2026-09-09: enable
          both P5 gates as hard blocks). Low false-positive surface (plan-file
          path + specific transition shapes). MODULE-GLOBAL: fires for every
          account/consumer; consumers who do not use the numbered-plan
          `TASK:` cursor can set this false.
        '';
      };
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
          (.session-state/active-plan), else .session-state/HANDOFF.md, else the latest prior
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

  # Plan 050 T5 (decision D9) — Claude Code as a declarative command-status SOURCE.
  # A program declares its event->state map in ITS OWN namespace; the module folds
  # that through the shared lib's mkProgramSource into its native hook mechanism
  # (mkHook/mergeHookSets below) and publishes a read-only introspection entry into
  # programs.tmux.commandStatus.sources.claude-code. Replaces the former
  # programs.claude-code.hooks.tmuxStatus.enable (which hard-coded the three
  # event->state mappings inline).
  options.programs.claude-code.tmuxStatus = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Drive the tmux per-pane command-status marker (@cmd_state; see
        programs.tmux.commandStatus) from Claude Code lifecycle events, so a tmux
        window running Claude shows its state at a glance. With the default
        `events` map: running/working (amber) on prompt submit, attention
        (magenta, blinking) on a Notification (Claude wants input or permission),
        and done (green) when it stops. done/attention are suppressed on the
        ACTIVE pane (you are already looking at it) so only background panes raise
        a marker. The hook is a no-op outside tmux, so it is harmless when Claude
        runs elsewhere. NOTE: hooks are module-global (deployed to every account).
      '';
    };
    events = mkOption {
      type = types.attrsOf types.str;
      default = {
        SessionStart = "clear";
        UserPromptSubmit = "running";
        Notification = "attention";
        Stop = "done";
        StopFailure = "done";
      };
      description = ''
        Map of Claude Code hook event name -> command-status target: one of the
        canonical states (programs.tmux.commandStatus.states:
        attention/error/running/done) OR the special `clear` target, which unsets
        the marker regardless of window focus. Each entry installs a CC hook that
        calls the shared `tmux-cmd-state` writer with the mapped target.

        The default map makes the CC source authoritative over the pane's marker
        for the whole session, so a `running` set by the shell's preexec when you
        launched `claude` (which the shell's precmd can never clear while claude
        holds the foreground) is retracted as soon as CC is idle:
          - SessionStart    -> clear    (CC is ready/idle; clears the launch-time amber)
          - UserPromptSubmit -> running (amber; a turn is in flight)
          - Notification    -> attention (magenta; Claude wants input/permission)
          - Stop            -> done      (green completion marker on background panes)
          - StopFailure     -> done      (a turn that ended abnormally still clears running)

        Overriding this is how you re-map or extend which CC events raise which
        marker without touching hook plumbing; an unknown target is a build-time
        error naming the offending event.
      '';
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
            # CC passes tool-call data as JSON on stdin; $1 is never set. Read
            # the target path from .tool_input.file_path so formatting actually
            # runs. `// empty` + trailing `exit 0` guarantee a clean exit (no
            # spurious non-blocking-error notice on non-file / non-match tools).
            file_path="$(${pkgs.jq}/bin/jq -r '.tool_input.file_path // empty' 2>/dev/null)"
            case "$file_path" in
              *.nix)   ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt "$file_path" 2>/dev/null || true ;;
              *.py)    ${pkgs.black}/bin/black "$file_path" 2>/dev/null || true ;;
              *.rs)    ${pkgs.rustfmt}/bin/rustfmt "$file_path" 2>/dev/null || true ;;
              *.js|*.json) ${pkgs.prettier}/bin/prettier --write "$file_path" 2>/dev/null || true ;;
            esac
            exit 0
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
                # CC passes tool-call data as JSON on stdin; $1 is never set.
                file_path="$(${pkgs.jq}/bin/jq -r '.tool_input.file_path // empty' 2>/dev/null)"
                if [ -n "$file_path" ] && [ -f "$file_path" ]; then
                  ${pkgs.git}/bin/git add "$file_path" 2>/dev/null || true
                  echo "📁 Auto-staged: $file_path"
                fi
              fi
              exit 0
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
              # CC passes tool-call data as JSON on stdin; $1 is never set. Read
              # the real target path so the block actually fires (with $1 empty
              # this hook silently never matched). Exit 2 is the CC convention
              # that BLOCKS a PreToolUse call and feeds stderr back to the model;
              # the old `exit 1` was a bug — a non-blocking error that printed
              # "Access blocked" yet let the edit through. Plan 056 P11: adopt the
              # shared prelude (bypass + gr_log observability + four-part message).
              ${guardrailPrelude}
              file_path="$(${pkgs.jq}/bin/jq -r '.tool_input.file_path // empty' 2>/dev/null)"
              for pattern in ${toString cfg.hooks.security.blockedPatterns}; do
                if echo "$file_path" | ${pkgs.gnugrep}/bin/grep -qE "$pattern"; then
                  gr_block "security.blockedPattern" "🚫 security: refusing to touch '$file_path' — it matches the sensitive-file pattern '$pattern'. WHY: secrets/keys must never be read into or written from the agent context. TO PROCEED NOW: work with a non-sensitive file; if this is a false match, narrow programs.claude-code.hooks.security.blockedPatterns, or relaunch claude with CLAUDE_HOOKS_BYPASS=1. TO AVOID IN FUTURE: keep secrets out of the paths the agent operates on. See docs/claude-code-session-guardrails.md."
                fi
              done
              exit 0
            '';
            continueOnError = false;
            timeout = 5;
          })
        ];
      };

      # Plan 056 P4 — git-safety interlocks (Class A). Each sub-rule is a
      # PreToolUse Bash block: jq-stdin `.tool_input.command`, `exit 2` +
      # continueOnError=false, uniform `CLAUDE_HOOKS_BYPASS` escape hatch, Nix
      # store paths for every binary. `ifFilter` narrows blast radius but
      # correctness rests on the in-script grep (matcher="Bash" + discrimination)
      # since runtime honoring of the `"if"` predicate is unverified in-tree. All
      # four sub-rules union onto PreToolUse via lib.optional. See plan 056 "P3
      # design" for the per-rule false-positive analysis.
      gitSafetyHooks = lib.optionalAttrs cfg.hooks.gitSafety.enable {
        PreToolUse =
          # blockNoVerify — subsumes plan 017 I1. --no-verify on commit|push,
          # and -n/combined short forms on commit ONLY (on push -n=--dry-run).
          (lib.optional cfg.hooks.gitSafety.blockNoVerify (mkHook {
            matcher = "Bash";
            ifFilter = "Bash(git *)";
            command = ''
              ${guardrailPrelude}
              cmd="$(${pkgs.jq}/bin/jq -r '.tool_input.command // empty' 2>/dev/null)"
              [ -z "$cmd" ] && exit 0
              if printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE 'git[[:space:]]+${gitGlobalOpts}(commit|push)\b[^;&|]*--no-verify'; then
                gr_block "gitSafety.blockNoVerify" "🚫 gitSafety: refusing 'git commit/push --no-verify'. WHY: it skips the pre-commit/pre-push hooks that keep the tree valid. TO PROCEED NOW: run the command without --no-verify; if a hook is genuinely broken, fix it at its source, or relaunch claude with CLAUDE_HOOKS_BYPASS=1 for a one-off. TO AVOID IN FUTURE: keep the hooks fast enough to run every time (plan 056 P11.4 removed the slow flake-check from pre-commit). See docs/claude-code-session-guardrails.md."
              fi
              # -n / combined short forms (e.g. -an) on git commit only.
              if printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE 'git[[:space:]]+${gitGlobalOpts}commit\b[^;&|]*[[:space:]]-[a-zA-Z]*n'; then
                gr_block "gitSafety.blockNoVerify" "🚫 gitSafety: refusing '-n' (--no-verify) on git commit. WHY: it skips the pre-commit hooks that keep the tree valid. TO PROCEED NOW: drop -n and commit normally, or relaunch claude with CLAUDE_HOOKS_BYPASS=1. TO AVOID IN FUTURE: prefer long flags so intent is explicit and hooks always run. See docs/claude-code-session-guardrails.md."
              fi
              exit 0
            '';
            continueOnError = false;
            timeout = 5;
          }))
          # blockAttribution — leak-signature only (NOT bare brand words).
          ++ (lib.optional cfg.hooks.gitSafety.blockAttribution (mkHook {
            matcher = "Bash";
            ifFilter = "Bash(git commit*)";
            command = ''
              ${guardrailPrelude}
              cmd="$(${pkgs.jq}/bin/jq -r '.tool_input.command // empty' 2>/dev/null)"
              [ -z "$cmd" ] && exit 0
              # only intercept when a git command is present
              printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE '(^|[;&|])[[:space:]]*git[[:space:]]' || exit 0
              if printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qiE 'co-authored-by:|generated with (\[)?claude|claude\.ai/code|noreply@anthropic\.com|🤖'; then
                gr_block "gitSafety.blockAttribution" "🚫 gitSafety: this commit carries an AI-attribution marker (Co-Authored-By / 'Generated with Claude' / claude.ai / anthropic noreply / 🤖). WHY: commits must appear solely human-authored — 11 public commits once leaked Co-Authored-By trailers and listed Claude as a repo contributor (memory project_ai_attribution_leak). TO PROCEED NOW: remove the trailer/boilerplate from the message and re-commit; for a deliberate meta-commit that quotes the marker, relaunch claude with CLAUDE_HOOKS_BYPASS=1. TO AVOID IN FUTURE: never add attribution trailers to commit messages. See docs/claude-code-session-guardrails.md."
              fi
              exit 0
            '';
            continueOnError = false;
            timeout = 5;
          }))
          # blockCommitOnMain — checks the branch of the directory the git command
          # TARGETS, not the session's launch cwd. Resolving the target dir is what
          # lets a cross-worktree commit (`cd DIR && git …` or `git -C DIR …`)
          # check DIR's branch; before this it always read the session cwd and
          # false-blocked commits into a feature-branch worktree from a main cwd.
          ++ (lib.optional cfg.hooks.gitSafety.blockCommitOnMain (mkHook {
            matcher = "Bash";
            ifFilter = "Bash(git *)";
            command = ''
              ${guardrailPrelude}
              cmd="$(${pkgs.jq}/bin/jq -r '.tool_input.command // empty' 2>/dev/null)"
              [ -z "$cmd" ] && exit 0
              printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE 'git[[:space:]]+${gitGlobalOpts}(commit|push)\b' || exit 0
              # Resolve the directory the git command operates in, so the branch
              # test follows the command instead of the session cwd. Precedence:
              # `git -C DIR` (most explicit) > a leading `cd DIR` > the hook's cwd.
              # If DIR cannot be resolved, `git -C` fails and branch is empty →
              # fall through to allow (fail-open: never lock the operator out).
              dir="."
              cdarg="$(printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -oE '\bcd[[:space:]]+[^[:space:]&;|]+' | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.gnused}/bin/sed -E 's/^cd[[:space:]]+//')"
              [ -n "$cdarg" ] && dir="$cdarg"
              carg="$(printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]&;|]+' | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.gnused}/bin/sed -E 's/^git[[:space:]]+-C[[:space:]]+//')"
              [ -n "$carg" ] && dir="$carg"
              # strip surrounding quotes; expand a leading ~ (a quoted arg is not
              # tilde-expanded by the shell, so we do it explicitly).
              dir="$(printf '%s' "$dir" | ${pkgs.coreutils}/bin/tr -d "\"'" | ${pkgs.gnused}/bin/sed "s|^~|$HOME|")"
              branch="$(${pkgs.git}/bin/git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)"
              case "$branch" in
                main|master)
                  gr_gate "gitSafety.blockCommitOnMain" "🚫 gitSafety: refusing a commit/push — the repo at '$dir' is on protected branch '$branch'. WHY: the NEVER-WORK-ON-MAIN rule. TO PROCEED NOW: approve at the prompt if this is intentional, OR switch that repo to a feature branch (git -C '$dir' switch -c my-feature), OR run the commit yourself via the ! prefix (which does not pass through this hook), OR relaunch claude with CLAUDE_HOOKS_BYPASS=1. TO AVOID IN FUTURE: launch the session from the worktree you intend to commit in. See docs/claude-code-session-guardrails.md." ;;
              esac
              exit 0
            '';
            continueOnError = false;
            timeout = 5;
          }))
          # blockAddForce — respect .gitignore; never force-add.
          ++ (lib.optional cfg.hooks.gitSafety.blockAddForce (mkHook {
            matcher = "Bash";
            ifFilter = "Bash(git add*)";
            command = ''
              ${guardrailPrelude}
              cmd="$(${pkgs.jq}/bin/jq -r '.tool_input.command // empty' 2>/dev/null)"
              [ -z "$cmd" ] && exit 0
              if printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE 'git[[:space:]]+${gitGlobalOpts}add\b[^;&|]*([[:space:]]-[a-zA-Z]*f\b|[[:space:]]--force\b)'; then
                gr_block "gitSafety.blockAddForce" "🚫 gitSafety: refusing 'git add -f/--force'. WHY: it overrides .gitignore and can stage build output, secrets, or runtime state that must never be tracked. TO PROCEED NOW: stage only the intended paths (git add <path>); if a file is wrongly ignored, fix .gitignore instead, or relaunch claude with CLAUDE_HOOKS_BYPASS=1. TO AVOID IN FUTURE: never force-add — adjust .gitignore rather than overriding it. See docs/claude-code-session-guardrails.md."
              fi
              exit 0
            '';
            continueOnError = false;
            timeout = 5;
          }))
          # blockAddSessionState (Plan 057 T5) — never stage per-worktree runtime
          # state. Fires only when the literal token `.session-state` appears as a
          # path arg to `git add`, terminated by `/`, whitespace, or end-of-arg —
          # so `git add user-plans/...`, `git add -A`, `git add .`, and a path
          # like `.session-state-notes.txt` do NOT trip it. Suspender over the
          # machine-wide `**/.session-state/` gitignore belt.
          ++ (lib.optional cfg.hooks.gitSafety.blockAddSessionState (mkHook {
            matcher = "Bash";
            ifFilter = "Bash(git add*)";
            command = ''
              ${guardrailPrelude}
              cmd="$(${pkgs.jq}/bin/jq -r '.tool_input.command // empty' 2>/dev/null)"
              [ -z "$cmd" ] && exit 0
              # must be a `git add`, and its argument list must reference the
              # .session-state dir as a path token (terminated by / whitespace $).
              if printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE 'git[[:space:]]+${gitGlobalOpts}add\b[^;&|]*(^|[[:space:]/])\.session-state(/|$|[[:space:]])'; then
                gr_block "gitSafety.blockAddSessionState" "🚫 gitSafety: refusing to stage '.session-state/'. WHY: it holds per-worktree session runtime state (active-plan, HANDOFF.md) that must never be committed — it is gitignored machine-wide (memory keep-core-trim-ceremony-userplans / plan 057). TO PROCEED NOW: stage only the intended paths (e.g. git add user-plans/<plan>.md); if you truly must track a file here, relaunch claude with CLAUDE_HOOKS_BYPASS=1. TO AVOID IN FUTURE: never add .session-state — it is per-worktree, not shared. See docs/claude-code-session-guardrails.md."
              fi
              exit 0
            '';
            continueOnError = false;
            timeout = 5;
          }));
      };

      # Plan 056 P4 — bash-safety interlock (Class A/B). Block-with-message,
      # NEVER rewrite (RTK lesson). Per-segment head-word test so a force flag in
      # one segment cannot mask a bare rm/cp/mv in another. POSIX-only (no
      # bashisms): split on shell separators via `tr`, iterate in a `{ … }` group
      # whose exit status the parent re-raises (avoids the `cmd | while` subshell
      # gotcha where an inner `exit 2` cannot terminate the parent).
      bashSafetyHooks = lib.optionalAttrs cfg.hooks.bashSafety.enable {
        PreToolUse = lib.optional cfg.hooks.bashSafety.blockBareRm (mkHook {
          matcher = "Bash";
          command = ''
            ${guardrailPrelude}
            cmd="$(${pkgs.jq}/bin/jq -r '.tool_input.command // empty' 2>/dev/null)"
            [ -z "$cmd" ] && exit 0
            # Split on ; & | (single chars — this also breaks && and || into
            # empty-plus-real segments, which is harmless). Examine each segment
            # independently. The trailing \n is REQUIRED: without it `read` drops
            # the final (only) segment of a separator-less command like `rm foo`.
            printf '%s\n' "$cmd" | ${pkgs.coreutils}/bin/tr ';&|' '\n' | {
              while IFS= read -r seg; do
                # first whitespace-delimited word of the segment
                # shellcheck disable=SC2086
                set -- $seg
                head=$1
                case "$head" in
                  rm|cp|mv)
                    forced=0
                    for tok in "$@"; do
                      case "$tok" in
                        --force|-*f*) forced=1 ;;
                      esac
                    done
                    if [ "$forced" -eq 0 ]; then
                      gr_block "bashSafety.blockBareRm" "🚫 bashSafety: bare '$head' detected (no -f). WHY: your shell aliases rm/cp/mv to the interactive -i form, which HANGS in a non-interactive tool shell waiting for a prompt that never comes. TO PROCEED NOW: re-run WITH -f (e.g. $head -f ...) — it is NOT auto-rewritten by design (RTK lesson); if this is a false positive, relaunch claude with CLAUDE_HOOKS_BYPASS=1. TO AVOID IN FUTURE: always pass -f to rm/cp/mv in tool commands. See docs/claude-code-session-guardrails.md."
                    fi
                    ;;
                esac
              done
              exit 0
            }
            status=$?
            [ "$status" -eq 2 ] && exit 2
            exit 0
          '';
          continueOnError = false;
          timeout = 5;
        });
      };

      # Plan 056 P7 — secret-dump prevention interlocks. PreToolUse Bash hooks,
      # jq-stdin `.tool_input.command`, exit 2 + continueOnError=false, uniform
      # `CLAUDE_HOOKS_BYPASS` escape. FP-aware (dual-use): a piped/`$(...)`-captured
      # `rbw get` and a `GH_TOKEN=$(gh auth token) git push` prefix PASS; only forms
      # that render a secret into the transcript/context/a file block.
      secretSafetyHooks = lib.optionalAttrs cfg.hooks.secretSafety.enable {
        PreToolUse =
          # blockVaultDump (P7a) — rbw --full always; unpiped/uncaptured rbw get|code.
          (lib.optional cfg.hooks.secretSafety.blockVaultDump (mkHook {
            matcher = "Bash";
            ifFilter = "Bash(rbw *)";
            command = ''
              ${guardrailPrelude}
              cmd="$(${pkgs.jq}/bin/jq -r '.tool_input.command // empty' 2>/dev/null)"
              [ -z "$cmd" ] && exit 0
              # only intercept rbw commands (word boundary handles $(rbw…/`rbw…/; rbw…)
              printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE '(^|[^[:alnum:]_])rbw([[:space:]]|$)' || exit 0
              # --full dumps every field (incl. notes) — blocked unconditionally
              if printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE '(^|[[:space:]])--full([[:space:]]|=|$)'; then
                gr_block "secretSafety.blockVaultDump" "🚫 secretSafety: 'rbw --full' dumps every field (including notes) into the agent context. WHY: vault contents must never reach the transcript/context/files (memory never-dump-secrets-to-agent-context). TO PROCEED NOW: retrieve one field and pipe it straight to the consumer — rbw get NAME | tool --password-stdin; relaunch claude with CLAUDE_HOOKS_BYPASS=1 only if unavoidable. TO AVOID IN FUTURE: never render secrets; always pipe or capture them. See docs/claude-code-session-guardrails.md."
              fi
              # retrieval subcommands that emit secret material
              if printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE 'rbw[[:space:]]+(get|code)\b'; then
                # ALLOW when consumed: piped to a command, or captured via $(...)/backticks
                printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE 'rbw[[:space:]]+(get|code)\b[^|]*[|]' && exit 0
                printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE '[$]\([^)]*rbw[[:space:]]+(get|code)\b' && exit 0
                printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE '`[^`]*rbw[[:space:]]+(get|code)\b' && exit 0
                gr_block "secretSafety.blockVaultDump" "🚫 secretSafety: unpiped 'rbw get/code' prints the secret into the agent context (or into a file via '>'). WHY: secrets must never be rendered to the transcript/context/files (memory never-dump-secrets-to-agent-context). TO PROCEED NOW: pipe it to the consumer — rbw get NAME | tool --password-stdin — or capture it with \$(rbw get NAME); relaunch claude with CLAUDE_HOOKS_BYPASS=1 to override. TO AVOID IN FUTURE: always consume rbw output via a pipe or command-substitution. See docs/claude-code-session-guardrails.md."
              fi
              exit 0
            '';
            continueOnError = false;
            timeout = 5;
          }))
          # blockSecretEnvEcho (P7b) — echo/printf of $SECRETVAR, printenv SECRETVAR.
          ++ (lib.optional cfg.hooks.secretSafety.blockSecretEnvEcho (mkHook {
            matcher = "Bash";
            command = ''
              ${guardrailPrelude}
              cmd="$(${pkgs.jq}/bin/jq -r '.tool_input.command // empty' 2>/dev/null)"
              [ -z "$cmd" ] && exit 0
              SECRE='(TOKEN|SECRET|PASSWORD|PASSWD|PASSPHRASE|API[_-]?KEY|ACCESS[_-]?KEY|PRIVATE[_-]?KEY|CREDENTIAL)'
              # echo/printf referencing $SECRETVAR or ''${SECRETVAR}
              if printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qiE '(^|[;&|[:space:]])(echo|printf)\b[^;&|]*[$][{]?[A-Za-z_]*'"$SECRE"; then
                gr_block "secretSafety.blockSecretEnvEcho" "🚫 secretSafety: echo/printf of a secret-shaped variable leaks its value into the agent context. WHY: secrets must never be rendered to the transcript/context (memory never-dump-secrets-to-agent-context). TO PROCEED NOW: pass it straight to the consumer instead of echoing it (e.g. GH_TOKEN=\$(gh auth token) git push); relaunch claude with CLAUDE_HOOKS_BYPASS=1 to override. TO AVOID IN FUTURE: never echo secret-shaped variables. See docs/claude-code-session-guardrails.md."
              fi
              # printenv NAME where NAME is secret-shaped
              if printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -qiE '(^|[;&|[:space:]])printenv\b[^;&|]*[A-Za-z_]*'"$SECRE"; then
                gr_block "secretSafety.blockSecretEnvEcho" "🚫 secretSafety: printenv of a secret-shaped variable leaks its value into the agent context. WHY: secrets must never be rendered to the transcript/context (memory never-dump-secrets-to-agent-context). TO PROCEED NOW: reference the variable directly in the consuming command instead of printing it; relaunch claude with CLAUDE_HOOKS_BYPASS=1 to override. TO AVOID IN FUTURE: never printenv secret-shaped variables. See docs/claude-code-session-guardrails.md."
              fi
              exit 0
            '';
            continueOnError = false;
            timeout = 5;
          }));
      };

      # Plan 056 P5 — session-workflow process-gates. Both sub-rules are
      # PreToolUse Edit|MultiEdit|Write hooks that gate a plan-file status
      # transition. The jq expression normalises across the three tool shapes:
      # new text = .new_string (Edit) // .content (Write) // .edits[].new_string
      # (MultiEdit); old text = .old_string // .edits[].old_string. "Net-new
      # completion" = new has MORE TASK:COMPLETE lines than old (so re-writing an
      # already-complete row does not trip the gate). Default OFF (P6 opts in).
      planIntegrityHooks = lib.optionalAttrs cfg.hooks.planIntegrity.enable {
        PreToolUse =
          # requireSignoffBeforeComplete (P5a) — CLAUDE_TASK_SIGNOFF attestation.
          (lib.optional cfg.hooks.planIntegrity.requireSignoffBeforeComplete (mkHook {
            matcher = "Edit|MultiEdit|Write";
            command = ''
              ${guardrailPrelude}
              # Read stdin ONCE — jq is invoked 3x below and each read would
              # otherwise drain the pipe, leaving later reads empty.
              input="$(cat)"
              fp="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.tool_input.file_path // empty' 2>/dev/null)"
              case "$fp" in */user-plans/*.md) ;; *) exit 0 ;; esac
              new="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '[.tool_input.new_string // empty, .tool_input.content // empty, (.tool_input.edits[]?.new_string // empty)] | join("\n")' 2>/dev/null)"
              old="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '[.tool_input.old_string // empty, (.tool_input.edits[]?.old_string // empty)] | join("\n")' 2>/dev/null)"
              cn="$(printf '%s' "$new" | ${pkgs.gnugrep}/bin/grep -c 'TASK:COMPLETE')"
              co="$(printf '%s' "$old" | ${pkgs.gnugrep}/bin/grep -c 'TASK:COMPLETE')"
              [ "$cn" -gt "$co" ] || exit 0            # not a net-new completion
              [ -n "$CLAUDE_TASK_SIGNOFF" ] && exit 0  # operator attested sign-off (launch-time only)
              gr_gate "planIntegrity.requireSignoffBeforeComplete" "🚫 planIntegrity: marking a task TASK:COMPLETE needs a Present/STOP review first (memory next-task-present-stop-artifact-gate). WHY: artifact-producing tasks must be shown to the operator before they are certified done. TO PROCEED NOW: approve this completion at the prompt if you have already reviewed the artifact; otherwise present it + the defaults, get sign-off, and relaunch with CLAUDE_TASK_SIGNOFF=1 (or CLAUDE_HOOKS_BYPASS=1 to override). TO AVOID IN FUTURE: launch task-completing sessions with CLAUDE_TASK_SIGNOFF=1 only after the Present/STOP review. See docs/claude-code-session-guardrails.md."
            '';
            continueOnError = false;
            timeout = 5;
          }))
          # enforceStatusTransitions (P5c) — legal shape: no PENDING→COMPLETE
          # skip; a new COMPLETE must carry a (YYYY-MM-DD) date.
          ++ (lib.optional cfg.hooks.planIntegrity.enforceStatusTransitions (mkHook {
            matcher = "Edit|MultiEdit|Write";
            command = ''
              ${guardrailPrelude}
              # Read stdin ONCE (jq invoked 3x — see requireSignoffBeforeComplete).
              input="$(cat)"
              fp="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.tool_input.file_path // empty' 2>/dev/null)"
              case "$fp" in */user-plans/*.md) ;; *) exit 0 ;; esac
              new="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '[.tool_input.new_string // empty, .tool_input.content // empty, (.tool_input.edits[]?.new_string // empty)] | join("\n")' 2>/dev/null)"
              old="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '[.tool_input.old_string // empty, (.tool_input.edits[]?.old_string // empty)] | join("\n")' 2>/dev/null)"
              cn="$(printf '%s' "$new" | ${pkgs.gnugrep}/bin/grep -c 'TASK:COMPLETE')"
              co="$(printf '%s' "$old" | ${pkgs.gnugrep}/bin/grep -c 'TASK:COMPLETE')"
              [ "$cn" -gt "$co" ] || exit 0            # no net-new completion → nothing to check
              # (a) illegal skip: old had PENDING and NO IN_PROGRESS (so this edit
              # jumps a pending row straight to complete). The no-IN_PROGRESS guard
              # avoids FP on multi-row edits that legitimately advance another row.
              if printf '%s' "$old" | ${pkgs.gnugrep}/bin/grep -q 'TASK:PENDING' \
                 && ! printf '%s' "$old" | ${pkgs.gnugrep}/bin/grep -q 'TASK:IN_PROGRESS'; then
                gr_block "planIntegrity.enforceStatusTransitions" "🚫 planIntegrity: illegal status skip PENDING→COMPLETE. WHY: a task must pass through TASK:IN_PROGRESS so the plan cursor and audit trail stay consistent. TO PROCEED NOW: mark the row TASK:IN_PROGRESS first, then TASK:COMPLETE in a later edit; relaunch claude with CLAUDE_HOOKS_BYPASS=1 to override. TO AVOID IN FUTURE: follow the PENDING→IN_PROGRESS→COMPLETE sequence. See docs/claude-code-session-guardrails.md."
              fi
              # (b) dateless COMPLETE.
              if ! printf '%s' "$new" | ${pkgs.gnugrep}/bin/grep -qE '\(20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)'; then
                gr_block "planIntegrity.enforceStatusTransitions" "🚫 planIntegrity: a new TASK:COMPLETE must record a date, e.g. (2026-09-15). WHY: completion dates are the plan's audit trail. TO PROCEED NOW: add the (YYYY-MM-DD) date next to COMPLETE; relaunch claude with CLAUDE_HOOKS_BYPASS=1 to override. TO AVOID IN FUTURE: always stamp a completion date when marking a task complete. See docs/claude-code-session-guardrails.md."
              fi
              exit 0
            '';
            continueOnError = false;
            timeout = 5;
          }));
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

      # Plan 050 T5 (D9) — drive the tmux command-status marker from CC lifecycle
      # events via the shared per-program SOURCE generator. `mkProgramSource`
      # turns cfg.tmuxStatus.events ({ UserPromptSubmit = "running"; ... }) into
      # per-event calls to the ONE shared `tmux-cmd-state` writer, validating each
      # mapped state against the lib's canonical stateNames at eval time. We fold
      # those commands into CC's native hook shape (mkHook per event), killing the
      # previously hand-inlined event->state map. Default map preserves prior
      # behavior: UserPromptSubmit->running, Notification->attention, Stop->done
      # (done/attention suppressed on the active pane by the writer).
      tmuxStatusHooks = lib.optionalAttrs cfg.tmuxStatus.enable (
        let src = tmuxCmdState.mkProgramSource { events = cfg.tmuxStatus.events; };
        in lib.mapAttrs
          (_ev: command: [ (mkHook { matcher = ""; inherit command; continueOnError = true; timeout = 5; }) ])
          src.commands
      );
    in
    mergeHookSets [
      # Base scaffold — every known event present so cleanHooks/hasHooks can
      # gate on any slot and custom hooks can land in any event.
      (lib.genAttrs hookEvents (_: [ ]))
      developmentHooks
      securityHooks
      gitSafetyHooks
      bashSafetyHooks
      secretSafetyHooks
      planIntegrityHooks
      loggingHooks
      resumeHooks
      rtkHooks
      tmuxStatusHooks
      # Plan 046 T5 — user-defined custom hooks. Freeform attrs keyed by event
      # name; concatenated alongside the categorized hooks so users can express
      # arbitrary entry types (http, mcp_tool, prompt, agent) and per-entry
      # fields the categorized hooks above don't model. (Previously defined as
      # an option but never serialized.)
      cfg.hooks.custom
    ];

  # Plan 050 T5 refinement (supersedes D9 step 4): the CC module does NOT auto-write
  # its event map into programs.tmux.commandStatus.sources. That cross-module publish
  # was designed as "read-only introspection with no eval-order coupling", but a WRITE
  # to another module's option still requires that option to be DECLARED in the eval,
  # and claude-code composes standalone (e.g. with upstream home-manager `programs.tmux`,
  # which has no `commandStatus`) — the write then fails with "option does not exist",
  # and an `mkIf (config.programs.tmux ? commandStatus)` guard does NOT suppress it
  # (the module system still records the unmatched definition path). The declaration
  # coupling is irreducible, so the auto-publish is dropped for dendritic
  # composability. The event->state map remains fully introspectable at its source of
  # truth: programs.claude-code.tmuxStatus.events. A host that wants the unified
  # registry view can set programs.tmux.commandStatus.sources.claude-code by hand.
}
