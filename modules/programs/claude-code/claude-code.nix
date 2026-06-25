# modules/programs/claude-code/claude-code.nix
# Claude Code multi-account configuration for home-manager
#
# Provides:
#   flake.modules.homeManager.claude-code - Full Claude Code multi-account setup
#
# Features:
#   - Multi-account support (max, pro, work profiles)
#   - MCP server integration
#   - Categorized hooks system
#   - Custom slash commands, skills, sub-agents
#   - Task automation
#   - Git commands integration
#   - Statusline variants (powerline, minimal, context, box, fast)
#   - Nix-managed account CLAUDE.md (per-account from shared template)
#   - WSL integration with clipboard support
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.claude-code ];
#   programs.claude-code = {
#     enable = true;
#     accounts = { max = { ... }; pro = { ... }; };
#   };
#
# Known upstream limitations (Plan 032):
#   - Editor / vim mode is NOT exposable via settings.json. Upstream removed
#     the persistent setting in v2.1.91; it is now a runtime `/config` toggle
#     only. There is no nix option for it. See docs/ai-tool-feature-comparison.md
#     §5 (CC-G18). To use vim-style input bindings, run Claude Code and toggle
#     via the `/config` slash command at runtime.
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    # Full Claude Code configuration for user environment
    homeManager.claude-code = { config, lib, pkgs, nixmcp ? null, ... }:
      with lib;
      {
        # Disable upstream home-manager claude-code module to avoid conflicts
        # Our enhanced module provides: multi-account, categorized hooks, statusline, MCP, WSL integration
        disabledModules = [ "programs/claude-code.nix" ];

        imports = [
          ./_hm/mcp-servers.nix
          ./_hm/hooks.nix
          ./_hm/sub-agents.nix
          ./_hm/slash-commands.nix
          ./_hm/task-automation.nix
          ./_hm/skills.nix
          ./_hm/git-commands.nix
          ./_hm/extended-commands.nix
          ./_hm/statusline.nix
        ];

        options.programs.claude-code = {
          enable = mkEnableOption "Claude Code Enhanced - feature-rich multi-account Claude Code management";

          debug = mkEnableOption "debug output for all components";

          defaultModel = mkOption {
            type = types.enum [ "sonnet" "opus" "haiku" ];
            default = "sonnet";
            description = "Default Claude model";
          };

          aiGuidance = mkOption {
            type = types.lines;
            default = ''
              * After receiving tool results, carefully reflect on their quality and determine optimal next steps
              * For maximum efficiency, invoke multiple independent tools simultaneously rather than sequentially
              * Before finishing, verify your solution addresses all requirements
              * Do what has been asked; nothing more, nothing less
              * NEVER create files unless absolutely necessary
              * ALWAYS prefer editing existing files to creating new ones
              * NEVER proactively create documentation unless explicitly requested

              ## Git Commit Rules

              * NEVER include Claude's identity or involvement in commit messages
              * Do NOT add "Generated with Claude Code" or "Co-Authored-By: Claude" footers
              * Write commit messages as if authored by the human user
              * Keep commit messages concise and focused on the technical changes
            '';
            description = "Core AI guidance principles";
          };

          enableProjectOverrides = mkOption {
            type = types.bool;
            default = true;
            description = "Allow project-specific configuration overrides";
          };

          projectOverridePaths = mkOption {
            type = types.listOf types.str;
            default = [ ".claude/settings.json" ".claude.json" "claude.config.json" ];
            description = "Paths to search for project-specific settings";
          };

          permissions = {
            allow = mkOption {
              type = types.listOf types.str;
              default = [
                "Bash"
                "mcp__context7"
                "mcp__mcp-nixos"
                "mcp__sequential-thinking"
                "mcp__serena"
                "Read"
                "Write"
                "Edit"
                "WebFetch"
              ];
              description = "List of tools/patterns to allow";
            };

            deny = mkOption {
              type = types.listOf types.str;
              default = [
                "Search"
                "Find"
                "Bash(rm -rf /*)"
              ];
              description = "List of tools/patterns to deny";
            };

            ask = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "List of tools/patterns to ask permission for";
            };

            defaultMode = mkOption {
              type = types.enum [ "acceptEdits" "bypassPermissions" "default" "plan" ];
              default = "default";
              description = "Default permission mode for tools not explicitly listed";
            };

            additionalDirectories = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional directories to grant access to";
            };

            # Plan 032 T4 — CC-G2. Serializes as
            # permissions.disableBypassPermissionsMode in settings.json.
            # Upstream documents the value "disable" (CHANGELOG v-ish, see
            # examples/settings/settings-strict.json). Typed as nullOr str to
            # remain forward-compatible with any new enum values.
            disableBypassPermissionsMode = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "disable";
              description = ''
                Hide the bypass permissions mode from the picker. Null =
                upstream default. Known value: "disable".
              '';
            };
          };

          # ─────────────────────────────────────────────────────────────────────
          # Plan 032 T4 — CC governance / managed-settings options
          # (CC-G3..CC-G7). Every key here serializes to the *top level* of
          # settings.json (not nested under "governance") — the nix-side
          # grouping is for ergonomics only. All leaves default to null so we
          # only emit keys the user sets. Structured values use the JSON
          # freeform type for forward-compat with upstream schema additions.
          # Keys verified against ~/src/claude-code/examples/settings/
          # settings-strict.json + CHANGELOG entries in
          # docs/ai-tool-feature-comparison.md §2.4.
          # ─────────────────────────────────────────────────────────────────────
          governance =
            let
              jsonType = (pkgs.formats.json { }).type;
            in
            {
              allowManagedPermissionRulesOnly = mkOption {
                type = types.nullOr types.bool;
                default = null;
                description = "Only apply permission rules from managed settings.";
              };
              allowManagedHooksOnly = mkOption {
                type = types.nullOr types.bool;
                default = null;
                description = "Only run hooks defined in managed settings.";
              };
              allowedMcpServers = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                description = "Allowlist of MCP servers (managed policy).";
              };
              deniedMcpServers = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                description = "Denylist of MCP servers (managed policy).";
              };
              strictKnownMarketplaces = mkOption {
                type = types.nullOr jsonType;
                default = null;
                description = ''
                  Marketplace allowlist. Upstream accepts a list of objects
                  with hostPattern/pathPattern entries; freeform JSON type is
                  used here for forward-compat.
                '';
              };
              allowedChannelPlugins = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                description = "Channel plugin allowlist for team/enterprise admins.";
              };
              enabledPlugins = mkOption {
                type = types.nullOr jsonType;
                default = null;
                description = "Plugins forcibly enabled by managed settings.";
              };
              pluginTrustMessage = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Extra message appended to the plugin trust warning.";
              };
              forceRemoteSettingsRefresh = mkOption {
                type = types.nullOr types.bool;
                default = null;
                description = ''
                  Block CLI startup until remote managed settings are freshly
                  fetched; exit if fetch fails (fail-closed).
                '';
              };
            };

          # ─────────────────────────────────────────────────────────────────────
          # Plan 032 T5 — CC security/UX scalar settings.
          # All default to null so we only emit keys the user actually sets,
          # leaving upstream defaults in place. Keys verified against
          # ~/src/claude-code/CHANGELOG.md (commit hashes recorded in
          # docs/ai-tool-feature-comparison.md §1).
          # ─────────────────────────────────────────────────────────────────────
          voice = {
            enable = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Enable voice mode (push-to-talk). Serializes as top-level
                `voiceEnabled` in settings.json. Null = upstream default (off).
              '';
            };

            language = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "japanese";
              description = ''
                Claude's response language and STT dictation language.
                Serializes as top-level `language` in settings.json.
                Null = upstream default (English).
              '';
            };
          };

          display.showThinkingSummaries = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = ''
              Show thinking summaries in interactive sessions. Upstream
              changed the default to false; set true to restore the prior
              behavior. Null = upstream default.
            '';
          };

          cleanupPeriodDays = mkOption {
            type = types.nullOr types.ints.positive;
            default = null;
            description = ''
              Days to retain transcript and tool-result files before cleanup.
              Upstream rejects 0 — use a positive integer or leave null for
              the upstream default.
            '';
          };

          security = {
            disableSkillShellExecution = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Disable inline shell execution in skills, custom slash
                commands, and plugin commands. Null = upstream default
                (enabled).
              '';
            };

            disableDeepLinkRegistration = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Prevent registration of the `claude-cli://` protocol handler.
                Null = upstream default.
              '';
            };
          };

          # ─────────────────────────────────────────────────────────────────────
          # Plan 046 T5 — top-level hook gating settings. Serialize FLAT at the
          # top level of settings.json (the nix-side `hookSettings` grouping is
          # ergonomic only). Verified against code.claude.com/docs/en/hooks
          # (2026-06-24): the real top-level keys are `disableAllHooks` and
          # `allowedHttpHookUrls`; `allowManagedHooksOnly` already lives under
          # `governance`. The plan's `httpHookAllowedEnvVars` is NOT a top-level
          # key — the per-entry `allowedEnvVars` field on http hooks (supported
          # via mkHook / freeform `hooks.custom`) is the documented mechanism.
          # ─────────────────────────────────────────────────────────────────────
          hookSettings = {
            disableAllHooks = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Temporarily disable all hooks without removing them. Respects the
                managed-settings hierarchy (managed hooks set by policy still
                run). Null = upstream default (hooks enabled).
              '';
            };
            allowedHttpHookUrls = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = ''
                Allowlist of URLs permitted for `http`-type hooks (a managed-
                settings security control). Null = upstream default (no
                allowlist restriction).
              '';
            };
          };

          # ─────────────────────────────────────────────────────────────────────
          # Plan 046 T6 — plugin marketplace + skill-listing settings. Serialize
          # FLAT at the top level of settings.json (the nix-side grouping is
          # ergonomic only). Keys verified against code.claude.com/docs/en/settings
          # + plugin-marketplaces (2026-06-24). Note: managed `enabledPlugins` /
          # `strictKnownMarketplaces` already live under `governance`; this block
          # adds the NON-managed `extraKnownMarketplaces` plus the skill-listing
          # budget knobs. All default null/{} so nothing is emitted unless set.
          # ─────────────────────────────────────────────────────────────────────
          plugins = {
            extraKnownMarketplaces = mkOption {
              type = types.nullOr (pkgs.formats.json { }).type;
              default = null;
              example = literalExpression ''
                {
                  company-tools.source = { source = "github"; repo = "your-org/claude-plugins"; };
                }
              '';
              description = ''
                Marketplaces registered automatically without the user running
                `/plugin marketplace add`. An attrset keyed by marketplace name,
                each with a `source` object (e.g. `{ source = "github"; repo =
                "org/repo"; }`). Freeform JSON for forward-compat. Null = omit.
              '';
            };
          };

          skillSettings = {
            disableBundled = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Disable bundled skills/workflows (`disableBundledSkills`).
                Built-in slash commands stay typable but hidden from the model;
                plugin and `.claude/skills/` skills are unaffected. Null = omit.
              '';
            };
            maxDescriptionChars = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              example = 2048;
              description = ''
                Per-skill cap on combined `description` + `when_to_use` text the
                model sees each turn (`maxSkillDescriptionChars`). Upstream
                default 1536. Null = omit.
              '';
            };
            listingBudgetFraction = mkOption {
              type = types.nullOr (types.either types.float types.int);
              default = null;
              example = 0.5;
              description = ''
                Fraction of the context budget allotted to the skill listing
                (`skillListingBudgetFraction`). Null = omit (upstream default).
              '';
            };
          };

          # ─────────────────────────────────────────────────────────────────────
          # Plan 032 T3 — CC sandbox.* subtree (CC-G1).
          # Keys verified against ~/src/claude-code/examples/settings/
          # settings-bash-sandbox.json and CHANGELOG entries referenced in
          # docs/ai-tool-feature-comparison.md §2.2. All leaves default to null
          # so we only emit the keys the user sets; nested `network` and
          # `filesystem` submodules are freeformType-enabled for forward-compat.
          # ─────────────────────────────────────────────────────────────────────
          sandbox = {
            enabled = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "Master switch for the Bash sandbox. Null = upstream default.";
            };
            failIfUnavailable = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "Exit Claude Code if the sandbox runtime is not available (CHANGELOG v2.1.83).";
            };
            autoAllowBashIfSandboxed = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "Auto-approve Bash commands when the sandbox is active.";
            };
            allowUnsandboxedCommands = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "Allow commands that cannot be sandboxed to still run.";
            };
            excludedCommands = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = "Commands that bypass the sandbox entirely.";
            };
            enableWeakerNestedSandbox = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "Enable a weaker nested sandbox when nesting is detected.";
            };
            enableWeakerNetworkIsolation = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "TLS bypass / weaker network isolation (macOS, CHANGELOG v2.1.70).";
            };
            # Plan 046 T7 — verified against code.claude.com/docs/en/sandboxing
            # (2026-06-24). allowAppleEvents (bool, v2.1.181; macOS, user/managed/
            # CLI scope only — project settings ignored). credentials (object, not a
            # bool, v2.1.187): { files = [ { path; mode = "deny"; } ]; envVars =
            # [ { name; mode = "deny"; } ]; } — "deny" is currently the only mode.
            allowAppleEvents = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Allow sandboxed commands to send Apple Events on macOS
                (`sandbox.allowAppleEvents`, v2.1.181) so tools like `open` and
                `osascript` work. Weakens isolation — see the docs. Honored only
                from user/managed/CLI settings. Null = upstream default (blocked).
              '';
            };
            credentials = mkOption {
              type = types.nullOr (pkgs.formats.json { }).type;
              default = null;
              example = literalExpression ''
                {
                  files = [ { path = "~/.aws/credentials"; mode = "deny"; } { path = "~/.ssh"; mode = "deny"; } ];
                  envVars = [ { name = "GITHUB_TOKEN"; mode = "deny"; } ];
                }
              '';
              description = ''
                Credential files / env vars sandboxed commands must not access
                (`sandbox.credentials`, v2.1.187). An object with `files`
                (`[{ path; mode = "deny"; }]`) and `envVars`
                (`[{ name; mode = "deny"; }]`); "deny" is the only supported mode.
                Freeform JSON for forward-compat. Null = omit.
              '';
            };
            network = mkOption {
              default = { };
              description = "Sandbox network controls. Freeform attrset for forward-compat.";
              type = types.submodule {
                freeformType = (pkgs.formats.json { }).type;
                options = {
                  allowUnixSockets = mkOption {
                    type = types.nullOr (types.listOf types.str);
                    default = null;
                    description = "Allowed unix socket paths.";
                  };
                  allowAllUnixSockets = mkOption {
                    type = types.nullOr types.bool;
                    default = null;
                    description = "Allow all unix sockets.";
                  };
                  allowLocalBinding = mkOption {
                    type = types.nullOr types.bool;
                    default = null;
                    description = "Allow binding to local network interfaces.";
                  };
                  allowedDomains = mkOption {
                    type = types.nullOr (types.listOf types.str);
                    default = null;
                    description = "Allowed outbound domains.";
                  };
                  httpProxyPort = mkOption {
                    type = types.nullOr types.port;
                    default = null;
                    description = "HTTP proxy port.";
                  };
                  socksProxyPort = mkOption {
                    type = types.nullOr types.port;
                    default = null;
                    description = "SOCKS proxy port.";
                  };
                };
              };
            };
            filesystem = mkOption {
              default = { };
              description = "Sandbox filesystem controls (CHANGELOG v2.1.70/v2.1.77). Freeform.";
              type = types.submodule {
                freeformType = (pkgs.formats.json { }).type;
                options = {
                  allowWrite = mkOption {
                    type = types.nullOr (types.listOf types.str);
                    default = null;
                    description = "Whitelist of paths Claude may write to.";
                  };
                  denyRead = mkOption {
                    type = types.nullOr (types.listOf types.str);
                    default = null;
                    description = "Blacklist of paths Claude may not read from.";
                  };
                  allowRead = mkOption {
                    type = types.nullOr (types.listOf types.str);
                    default = null;
                    description = "Re-allow reads within otherwise-denied regions.";
                  };
                };
              };
            };
          };

          prompt.includeGitInstructions = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = ''
              Include the built-in commit/PR workflow instructions in
              Claude's system prompt. Set false to suppress (also exposable
              via `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` env var). Null =
              upstream default.
            '';
          };

          # ─────────────────────────────────────────────────────────────────────
          # Plan 032 T6 — apiKeyHelper, worktree.sparsePaths, modelOverrides
          # (CC-G14, CC-G15, CC-G16). Keys verified against
          # ~/src/claude-code/CHANGELOG.md entries.
          # ─────────────────────────────────────────────────────────────────────
          apiKeyHelper = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "/path/to/get-api-key.sh";
            description = ''
              Path to a script that prints an API key on stdout. Claude
              Code calls this instead of reading ANTHROPIC_API_KEY; the
              returned key has a 5-minute TTL before re-invocation. Useful
              for vault-backed or rotating credentials. Null = upstream
              default (use env var / OAuth).
            '';
          };

          worktree.sparsePaths = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            example = [ "src/frontend" "packages/shared" ];
            description = ''
              Directories to include when `claude --worktree` creates a
              sparse-checkout working tree. Useful in large monorepos to
              avoid checking out unrelated subtrees. Serializes as
              `worktree.sparsePaths` in settings.json. Null = full
              checkout (upstream default).
            '';
          };

          modelOverrides = mkOption {
            type = types.nullOr (types.attrsOf types.str);
            default = null;
            example = {
              opus = "arn:aws:bedrock:us-east-1:123456:inference-profile/my-opus";
              sonnet = "arn:aws:bedrock:us-east-1:123456:inference-profile/my-sonnet";
            };
            description = ''
              Map model picker entries to custom provider model IDs (e.g.
              Bedrock inference profile ARNs). Keys are the picker names
              (opus, sonnet, haiku); values are the provider-specific
              model identifiers. Null = upstream defaults.
            '';
          };

          # ─────────────────────────────────────────────────────────────────────
          # Plan 046 T4 — model selection surface (fallback chain / allowlist /
          # Fable family / custom picker entry). The three settings keys
          # (`fallbackModel`, `availableModels`, `enforceAvailableModels`)
          # serialize flat at the top level of settings.json. The Fable + custom
          # option keys are environment variables injected into the settings.json
          # `env` block (global, applied to every account) and the wrappers.
          # Names verified against code.claude.com/docs/en/model-config and
          # ~/src/claude-code/CHANGELOG.md (2026-06-24). All leaves default
          # null/empty so we only emit what the user sets.
          # ─────────────────────────────────────────────────────────────────────
          models = {
            fallback = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              example = [ "claude-sonnet-4-6" "claude-haiku-4-5" ];
              description = ''
                Ordered availability-fallback chain → settings.json
                `fallbackModel`. Each entry is a model name or alias; "default"
                expands to the account-type default. Max 3 entries (asserted).
                Null = upstream default (no chain). Needs CC ≥ 2.1.166.
              '';
            };
            available = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              example = [ "sonnet" "haiku" ];
              description = ''
                Allowlist of selectable models → settings.json `availableModels`.
                Entries match a family ("sonnet"), a version prefix
                ("claude-sonnet-4-5"), or a full model ID. Null = unrestricted.
              '';
            };
            enforceAvailable = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Extend the `models.available` allowlist to the Default picker
                option → settings.json `enforceAvailableModels`. Requires a
                non-empty `models.available`; CC ≥ 2.1.175. Null = upstream
                default.
              '';
            };
            fable = {
              model = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Fable alias / Default-fallback target → env
                  `ANTHROPIC_DEFAULT_FABLE_MODEL` (CC ≥ 2.1.170). Set to your
                  provider-specific Fable 5 model ID on Bedrock/Vertex/Foundry
                  so automatic content-fallback can identify it.
                '';
              };
              name = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Fable picker label → env `ANTHROPIC_DEFAULT_FABLE_MODEL_NAME`.";
              };
              description = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Fable picker description → env `ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION`.";
              };
              supports = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Override effort/thinking capability detection for the pinned
                  Fable model → env `ANTHROPIC_DEFAULT_FABLE_MODEL_SUPPORTS`.
                '';
              };
            };
            customOption = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Extra `/model` picker entry → env `ANTHROPIC_CUSTOM_MODEL_OPTION`.
                Use to surface a non-Claude / custom model ID in the picker.
              '';
            };
          };

          # ─────────────────────────────────────────────────────────────────────
          # Plan 046 T7 — reliability / unattended-run knobs. The version-floor
          # keys (autoUpdatesChannel/minimumVersion/required{Min,Max}imumVersion)
          # serialize FLAT at the top level of settings.json. The retry / safe-mode
          # knobs are environment variables folded into the settings `env` block
          # AND every wrapper (global, all accounts). Names verified against
          # code.claude.com/docs/en/settings + the raw upstream CHANGELOG
          # (2026-06-24): CLAUDE_CODE_MAX_RETRIES (cap 15, v2.1.186),
          # CLAUDE_CODE_RETRY_WATCHDOG (v2.1.186), CLAUDE_CODE_SAFE_MODE /
          # --safe-mode (v2.1.169); autoUpdatesChannel (stable|latest),
          # minimumVersion, requiredMinimumVersion / requiredMaximumVersion
          # (managed-only). All leaves null so we emit only what the user sets.
          # ─────────────────────────────────────────────────────────────────────
          reliability = {
            maxRetries = mkOption {
              type = types.nullOr (types.ints.between 0 15);
              default = null;
              description = ''
                Max API-error retry attempts → env CLAUDE_CODE_MAX_RETRIES.
                Upstream caps this at 15 (v2.1.186). For unattended runs prefer
                `retryWatchdog` over a high value — a long retry budget can mask a
                hung stream. Null = upstream default.
              '';
            };
            retryWatchdog = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Enable the streaming retry watchdog → env
                CLAUDE_CODE_RETRY_WATCHDOG=1 (when true). The recommended
                reliability control for unattended/automated sessions (v2.1.186).
                Null = upstream default (unset).
              '';
            };
            safeMode = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = ''
                Start Claude Code with all customizations disabled → env
                CLAUDE_CODE_SAFE_MODE=1 (when true), equivalent to the
                `--safe-mode` flag (v2.1.169). Null = upstream default (off).
              '';
            };
            autoUpdatesChannel = mkOption {
              type = types.nullOr (types.enum [ "stable" "latest" ]);
              default = null;
              description = ''
                Release channel for auto-updates → settings.json
                `autoUpdatesChannel`. "stable" trails ~1 week and skips known
                major regressions; "latest" (upstream default) is the newest
                release. Null = upstream default.
              '';
            };
            minimumVersion = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "2.1.190";
              description = ''
                Floor that blocks background auto-updates and `claude update`
                from installing below this version → settings.json
                `minimumVersion`. Does NOT block startup. Null = omit.
              '';
            };
            requiredMinimumVersion = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Managed-settings-only floor that blocks STARTUP below this version
                (older versions exit at launch) → settings.json
                `requiredMinimumVersion`. Null = omit.
              '';
            };
            requiredMaximumVersion = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Managed-settings-only ceiling that blocks STARTUP above this
                version → settings.json `requiredMaximumVersion`. Null = omit.
              '';
            };
          };

          # Plan 046 T7 — MCP timeout / output env. Folded into the settings `env`
          # block + wrappers (global). MCP_TIMEOUT (server startup, ms),
          # MCP_TOOL_TIMEOUT (per tool call, ms), MAX_MCP_OUTPUT_TOKENS (token cap),
          # CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT (remote tool idle abort, ms; v2.1.187).
          # Names verified against the CHANGELOG + the env-var reference (2026-06-24).
          mcpRuntime = {
            timeout = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "MCP server startup timeout in ms → env MCP_TIMEOUT.";
            };
            toolTimeout = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "MCP tool-call timeout in ms → env MCP_TOOL_TIMEOUT.";
            };
            maxOutputTokens = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "Max tokens for a single MCP tool result → env MAX_MCP_OUTPUT_TOKENS.";
            };
            toolIdleTimeout = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = ''
                Abort a remote MCP tool call after this many ms of no response →
                env CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT (v2.1.187). Null = upstream
                default (5 min).
              '';
            };
          };

          # Plan 046 T7 — interaction/UX settings (flat top-level settings.json).
          # Verified against code.claude.com/docs/en/settings (2026-06-24).
          ux = {
            outputStyle = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "Explanatory";
              description = ''
                Output style adjusting the system prompt → settings.json
                `outputStyle`. Built-ins include "Explanatory"/"Learning"; custom
                styles live under an `output-styles/` dir. Null = upstream default.
              '';
            };
            effortLevel = mkOption {
              type = types.nullOr (types.enum [ "low" "medium" "high" "xhigh" ]);
              default = null;
              description = ''
                Persisted reasoning effort level → settings.json `effortLevel`
                (also set by `/effort`). Null = upstream default.
              '';
            };
            editorMode = mkOption {
              type = types.nullOr (types.enum [ "normal" "vim" ]);
              default = null;
              description = ''
                Prompt key-binding mode → settings.json `editorMode`. NOTE: Plan
                032 recorded this as a runtime-only `/config` toggle (removed in
                v2.1.91); upstream has since re-added the persistent setting —
                verified present on the current docs (2026-06-24). Null = upstream
                default ("normal").
              '';
            };
          };

          # Plan 046 T7 — commit/PR attribution. CRITICAL: this repo forbids ALL
          # AI attribution (CLAUDE.md). `includeCoAuthoredBy` therefore DEFAULTS TO
          # false (not null) — the one intentional non-null default in this module —
          # so the generated settings.json ALWAYS suppresses the "Co-Authored-By:
          # Claude" byline upstream would otherwise add. `attribution` is a freeform
          # escape hatch for custom HUMAN-ONLY bylines (sub-keys commit/pr/
          # sessionUrl); never put an AI-identity marker in it.
          attribution = mkOption {
            type = types.nullOr (pkgs.formats.json { }).type;
            default = null;
            example = { commit = ""; pr = ""; };
            description = ''
              settings.json `attribution` object customizing commit/PR bylines
              (sub-keys `commit`, `pr`, `sessionUrl`). Freeform for forward-compat.
              Keep human-only — NEVER include an AI-identity marker. Null = omit
              (the `includeCoAuthoredBy = false` default already suppresses the
              Claude trailer).
            '';
          };
          includeCoAuthoredBy = mkOption {
            type = types.nullOr types.bool;
            default = false;
            description = ''
              Whether Claude Code appends "Co-Authored-By: Claude" to commits/PRs
              it creates → settings.json `includeCoAuthoredBy` (deprecated alias of
              `attribution`, still honored). DEFAULTS TO false to enforce this
              repo's absolute no-AI-attribution rule; the value is always emitted
              so the guarantee is explicit and auditable. Set null to omit entirely
              (upstream default is true — NOT recommended in this repo).
            '';
          };

          # Plan 046 T7 — keybindings.json deployment. Freeform JSON written to
          # each enabled account's `$CLAUDE_CONFIG_DIR/keybindings.json`. Structure
          # (verified, code.claude.com/docs/en/keybindings): an object with a
          # `bindings` array of { context; bindings = { "<keys>" = "<action>"|null; } }.
          keybindings = mkOption {
            type = types.nullOr (pkgs.formats.json { }).type;
            default = null;
            example = literalExpression ''
              {
                bindings = [
                  { context = "Chat"; bindings = { "ctrl+s" = null; "ctrl+e" = "chat:externalEditor"; }; }
                ];
              }
            '';
            description = ''
              Contents of `keybindings.json`, deployed into every enabled account's
              config dir (which the wrapper sets as CLAUDE_CONFIG_DIR). Null = no
              file deployed (upstream defaults). See
              code.claude.com/docs/en/keybindings for the action/context catalog.
            '';
          };

          environmentVariables = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Environment variables";
          };

          experimental = mkOption {
            type = types.attrs;
            default = { };
            description = "Experimental features";
          };

          settingsExtra = mkOption {
            type = (pkgs.formats.json { }).type;
            default = { };
            example = { spinnerTipsEnabled = false; };
            description = ''
              Plan 046 escape hatch. Arbitrary settings.json keys deep-merged
              LAST into the generated per-account settings.json, so you can set
              or override ANY upstream Claude Code setting - including keys this
              module does not model yet - without a module change. On a leaf
              conflict, settingsExtra wins over the module-built value.
            '';
          };

          enterpriseSettings = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable Enterprise Managed Settings (configured at NixOS system level)";
            };

            path = mkOption {
              type = types.str;
              default = "/etc/claude-code/managed-settings.json";
              description = "Path to enterprise managed settings file (requires root)";
            };
          };

          nixcfgPath = mkOption {
            type = types.str;
            default = "${config.home.homeDirectory}/src/nixcfg";
            description = "Path to the nixcfg repository containing claude-runtime directory";
            example = "/home/user/projects/my-nixos-config";
          };

          accounts = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                enable = mkEnableOption "this Claude Code account profile";

                displayName = mkOption {
                  type = types.str;
                  description = "Display name for this account profile";
                  example = "Claude Max Account";
                };

                model = mkOption {
                  type = types.nullOr (types.enum [ "sonnet" "opus" "haiku" ]);
                  default = null;
                  description = "Default model for this account (null means use global default)";
                };

                api = {
                  baseUrl = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = ''
                      Custom API base URL for this account.
                      Set to null (default) to use the standard Anthropic API.
                    '';
                    example = "https://api.example.com/v1";
                  };

                  authMethod = mkOption {
                    type = types.enum [ "api-key" "bearer" "bedrock" ];
                    default = "api-key";
                    description = ''
                      Authentication method for this account:
                      - "api-key": Standard Anthropic API key (ANTHROPIC_API_KEY)
                      - "bearer": Bearer token authentication (ANTHROPIC_AUTH_TOKEN)
                      - "bedrock": AWS Bedrock authentication
                    '';
                  };

                  disableApiKey = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Set ANTHROPIC_API_KEY to an empty string.
                      Required by some proxy servers that reject requests with API keys.
                    '';
                  };

                  modelMappings = mkOption {
                    type = types.attrsOf types.str;
                    default = { };
                    description = ''
                      Map Claude model names to proxy-specific model names.
                    '';
                    example = {
                      sonnet = "devstral";
                      opus = "devstral";
                      haiku = "qwen-a3b";
                    };
                  };
                };

                secrets = {
                  bearerToken = mkOption {
                    type = types.nullOr (types.submodule {
                      options = {
                        bitwarden = mkOption {
                          type = types.submodule {
                            options = {
                              item = mkOption {
                                type = types.str;
                                description = "Bitwarden item name containing the token";
                                example = "AI-Proxy-Token";
                              };
                              field = mkOption {
                                type = types.str;
                                description = "Field name within the Bitwarden item";
                                example = "bearer_token";
                              };
                            };
                          };
                          description = "Bitwarden reference for retrieving the bearer token via rbw";
                        };
                      };
                    });
                    default = null;
                    description = "Secret management for bearer token authentication.";
                  };
                };

                extraEnvVars = mkOption {
                  type = types.attrsOf types.str;
                  default = { };
                  description = "Additional environment variables to set for this account.";
                  example = {
                    DISABLE_TELEMETRY = "1";
                    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
                  };
                };

                # ─────────────────────────────────────────────────────────────
                # Plan 046 T4 — per-account provider / auth backend. Each enabled
                # provider emits its documented Claude Code env vars into BOTH the
                # account wrapper script and the settings.json `env` block. Env
                # var names verified against code.claude.com/docs (amazon-bedrock,
                # google-vertex-ai, microsoft-foundry, model-config) on
                # 2026-06-24. Defaults off/null so nothing is emitted unless set.
                # Note: CC speaks only the Anthropic Messages API, so these select
                # the transport for Claude/Anthropic models (direct, Bedrock,
                # Vertex, Mantle, Foundry); non-Claude models are out of scope.
                # ─────────────────────────────────────────────────────────────
                provider = {
                  bedrock = {
                    enable = mkOption {
                      type = types.bool;
                      default = false;
                      description = "Route this account through Amazon Bedrock → CLAUDE_CODE_USE_BEDROCK=1.";
                    };
                    baseUrl = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Custom Bedrock endpoint → ANTHROPIC_BEDROCK_BASE_URL.";
                    };
                    skipAuth = mkOption {
                      type = types.bool;
                      default = false;
                      description = "Skip Bedrock SigV4 auth (gateway supplies credentials) → CLAUDE_CODE_SKIP_BEDROCK_AUTH=1.";
                    };
                    serviceTier = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Bedrock service tier → ANTHROPIC_BEDROCK_SERVICE_TIER.";
                    };
                  };
                  vertex = {
                    enable = mkOption {
                      type = types.bool;
                      default = false;
                      description = "Route through Google Vertex AI → CLAUDE_CODE_USE_VERTEX=1.";
                    };
                    baseUrl = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Custom Vertex endpoint → ANTHROPIC_VERTEX_BASE_URL.";
                    };
                    projectId = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "GCP project ID → ANTHROPIC_VERTEX_PROJECT_ID.";
                    };
                    region = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Vertex region → CLOUD_ML_REGION.";
                    };
                  };
                  mantle = {
                    enable = mkOption {
                      type = types.bool;
                      default = false;
                      description = "Bedrock-via-Mantle endpoint → CLAUDE_CODE_USE_MANTLE=1.";
                    };
                    baseUrl = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Mantle endpoint → ANTHROPIC_BEDROCK_MANTLE_BASE_URL.";
                    };
                  };
                  foundry = {
                    enable = mkOption {
                      type = types.bool;
                      default = false;
                      description = "Route through Microsoft Foundry → CLAUDE_CODE_USE_FOUNDRY=1.";
                    };
                    resource = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Azure resource name → ANTHROPIC_FOUNDRY_RESOURCE.";
                    };
                    baseUrl = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Full Foundry base URL (alternative to resource) → ANTHROPIC_FOUNDRY_BASE_URL.";
                    };
                  };
                  customHeaders = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    example = "X-Org: acme, X-Env: prod";
                    description = "Extra HTTP headers on every API request → ANTHROPIC_CUSTOM_HEADERS.";
                  };
                  extraEnv = mkOption {
                    type = types.attrsOf types.str;
                    default = { };
                    description = ''
                      Escape hatch for any additional provider/auth env not
                      modeled above (e.g. Claude-Platform-on-AWS / Anthropic-AWS,
                      ANTHROPIC_FOUNDRY_API_KEY). Emitted verbatim into the
                      wrapper + settings env.
                    '';
                  };
                };

                # ─────────────────────────────────────────────────────────────
                # Plan 046 T13 — per-account gateway model discovery. When the
                # account is routed through an Anthropic-Messages LLM gateway
                # (provider.* or api.baseUrl pointing at the gateway), Claude
                # Code can query the gateway's /v1/models endpoint at startup and
                # add the returned models to the `/model` picker, gated by
                # CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1. Verified against
                # code.claude.com/docs/en/{model-config,llm-gateway} on
                # 2026-06-24: needs CC >= 2.1.129; caches to
                # ~/.claude/cache/gateway-models.json (refreshed each startup);
                # ONLY model IDs beginning with `claude`/`anthropic` are added
                # (so this surfaces just the Claude subset of a CCv2/Bedrock
                # catalog — non-Claude IDs must be added manually via
                # models.customOption / models.available). Off by default; the
                # env var is emitted ONLY for accounts that opt in, into both the
                # account wrapper and its settings.json `env` block.
                # ─────────────────────────────────────────────────────────────
                discovery = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Enable gateway model discovery for this account →
                      env `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1`. Only
                      effective when this account talks to an Anthropic-Messages
                      LLM gateway (it does not run for Bedrock/Vertex pass-through
                      endpoints, nor when the base URL is unset / api.anthropic.com).
                      Surfaces only the `claude`/`anthropic` subset of the
                      gateway's catalogue. Requires Claude Code >= 2.1.129.
                    '';
                  };
                };
              };
            });
            default = { };
            description = "Claude Code account profiles.";
          };

          defaultAccount = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default account to use when running 'claude' without profile";
          };

          _internal = {
            mcpServers = mkOption {
              type = types.attrs;
              default = { };
              internal = true;
            };
            hooks = mkOption {
              type = types.attrs;
              default = { };
              internal = true;
            };
            subAgentFiles = mkOption {
              type = types.attrs;
              default = { };
              internal = true;
            };
            slashCommandDefs = mkOption {
              type = types.attrs;
              default = { };
              internal = true;
            };
          };
        };

        config =
          let
            cfg = config.programs.claude-code;
            inherit (cfg) nixcfgPath;
            runtimePath = "${nixcfgPath}/claude-runtime";

            # JSON serialized for safe embedding inside a SINGLE-QUOTED shell
            # string. builtins.toJSON can emit a literal apostrophe (e.g. a hook
            # command body containing "Don't"), which would otherwise terminate
            # the surrounding '...' early and break the activation script. Each
            # ' is rewritten to the canonical '\'' (close-quote, escaped-quote,
            # reopen-quote) sequence. Used by the .claude.json enforcement block.
            shJson = v: replaceStrings [ "'" ] [ "'\\''" ] (builtins.toJSON v);

            # Plan 046 T4 — translate one account's provider/auth options into the
            # documented Claude Code env vars. Only emits keys for enabled
            # providers / set values; merged into BOTH the wrapper script and the
            # settings.json `env` block so the chosen transport is applied
            # whichever path Claude Code reads.
            providerEnv = p:
              (optionalAttrs p.bedrock.enable { CLAUDE_CODE_USE_BEDROCK = "1"; })
              // (optionalAttrs (p.bedrock.baseUrl != null) { ANTHROPIC_BEDROCK_BASE_URL = p.bedrock.baseUrl; })
              // (optionalAttrs p.bedrock.skipAuth { CLAUDE_CODE_SKIP_BEDROCK_AUTH = "1"; })
              // (optionalAttrs (p.bedrock.serviceTier != null) { ANTHROPIC_BEDROCK_SERVICE_TIER = p.bedrock.serviceTier; })
              // (optionalAttrs p.vertex.enable { CLAUDE_CODE_USE_VERTEX = "1"; })
              // (optionalAttrs (p.vertex.baseUrl != null) { ANTHROPIC_VERTEX_BASE_URL = p.vertex.baseUrl; })
              // (optionalAttrs (p.vertex.projectId != null) { ANTHROPIC_VERTEX_PROJECT_ID = p.vertex.projectId; })
              // (optionalAttrs (p.vertex.region != null) { CLOUD_ML_REGION = p.vertex.region; })
              // (optionalAttrs p.mantle.enable { CLAUDE_CODE_USE_MANTLE = "1"; })
              // (optionalAttrs (p.mantle.baseUrl != null) { ANTHROPIC_BEDROCK_MANTLE_BASE_URL = p.mantle.baseUrl; })
              // (optionalAttrs p.foundry.enable { CLAUDE_CODE_USE_FOUNDRY = "1"; })
              // (optionalAttrs (p.foundry.resource != null) { ANTHROPIC_FOUNDRY_RESOURCE = p.foundry.resource; })
              // (optionalAttrs (p.foundry.baseUrl != null) { ANTHROPIC_FOUNDRY_BASE_URL = p.foundry.baseUrl; })
              // (optionalAttrs (p.customHeaders != null) { ANTHROPIC_CUSTOM_HEADERS = p.customHeaders; })
              // p.extraEnv;

            # Plan 046 T13 — per-account gateway model discovery env. Opt-in;
            # emits the single discovery toggle only for accounts that enable it,
            # merged into BOTH the wrapper and the settings.json `env` block
            # (same dual path as providerEnv).
            discoveryEnv = d:
              optionalAttrs d.enable { CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1"; };

            # Plan 046 T4 — global model-presentation env (Fable family + custom
            # picker option). Applies to all accounts; merged into the settings
            # `env` block and the wrappers.
            modelGlobalEnv =
              (optionalAttrs (cfg.models.fable.model != null) { ANTHROPIC_DEFAULT_FABLE_MODEL = cfg.models.fable.model; })
              // (optionalAttrs (cfg.models.fable.name != null) { ANTHROPIC_DEFAULT_FABLE_MODEL_NAME = cfg.models.fable.name; })
              // (optionalAttrs (cfg.models.fable.description != null) { ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION = cfg.models.fable.description; })
              // (optionalAttrs (cfg.models.fable.supports != null) { ANTHROPIC_DEFAULT_FABLE_MODEL_SUPPORTS = cfg.models.fable.supports; })
              // (optionalAttrs (cfg.models.customOption != null) { ANTHROPIC_CUSTOM_MODEL_OPTION = cfg.models.customOption; });

            # Plan 046 T7 — global reliability / MCP-runtime env. Applies to all
            # accounts; folded into the settings `env` block and every wrapper,
            # exactly like modelGlobalEnv. Bool flags emit "1" when true (the
            # module-wide convention, matching providerEnv).
            reliabilityEnv =
              (optionalAttrs (cfg.reliability.maxRetries != null) { CLAUDE_CODE_MAX_RETRIES = toString cfg.reliability.maxRetries; })
              // (optionalAttrs (cfg.reliability.retryWatchdog == true) { CLAUDE_CODE_RETRY_WATCHDOG = "1"; })
              // (optionalAttrs (cfg.reliability.safeMode == true) { CLAUDE_CODE_SAFE_MODE = "1"; })
              // (optionalAttrs (cfg.mcpRuntime.timeout != null) { MCP_TIMEOUT = toString cfg.mcpRuntime.timeout; })
              // (optionalAttrs (cfg.mcpRuntime.toolTimeout != null) { MCP_TOOL_TIMEOUT = toString cfg.mcpRuntime.toolTimeout; })
              // (optionalAttrs (cfg.mcpRuntime.maxOutputTokens != null) { MAX_MCP_OUTPUT_TOKENS = toString cfg.mcpRuntime.maxOutputTokens; })
              // (optionalAttrs (cfg.mcpRuntime.toolIdleTimeout != null) { CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT = toString cfg.mcpRuntime.toolIdleTimeout; });

            userGlobalMemoryTemplate = builtins.readFile ./_hm/claude-code-user-memory-template.md;

            # Per-account CLAUDE.md: substitute {{ACCOUNT}} with the account name.
            # Plan 046 T11 — when RTK is enabled, append an `@RTK.md` reference so
            # Claude Code auto-loads the co-deployed RTK.md context file (mirrors
            # what `rtk init -g` adds to ~/.claude/CLAUDE.md).
            mkClaudeMdTemplate = name:
              let
                accountLabel = lib.toUpper name;
                base = builtins.replaceStrings [ "{{ACCOUNT}}" ] [ accountLabel ] userGlobalMemoryTemplate;
                rtkRef = lib.optionalString
                  (cfg.hooks.rtk.enable && cfg.hooks.rtk.contextFile != null)
                  "\n\n@RTK.md\n";
                content = base + rtkRef;
              in
              pkgs.writeText "claude-memory-${name}.md" content;

            isWSLEnabled = config.targets.wsl.enable or false;
            wslDistroName =
              if isWSLEnabled then
                config.targets.wsl.wslDistroName or "NixOS"
              else
                "NixOS";

            mkClaudeDesktopServer = _name: serverCfg:
              let
                envVars = serverCfg.env or { };
                envPrefix =
                  if isWSLEnabled && envVars != { } then
                    lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg (toString v)}") envVars)
                  else "";
                wslCommand =
                  if envPrefix != "" then
                    "sh -c '${envPrefix} exec ${lib.escapeShellArg serverCfg.command} ${lib.concatStringsSep " " (map lib.escapeShellArg serverCfg.args)}'"
                  else
                    "${serverCfg.command} ${lib.concatStringsSep " " (map lib.escapeShellArg serverCfg.args)}";
              in
              {
                command = if isWSLEnabled then "C:\\WINDOWS\\system32\\wsl.exe" else serverCfg.command;
                args =
                  if isWSLEnabled then
                    [ "-d" wslDistroName "-e" "sh" "-c" wslCommand ]
                  else
                    serverCfg.args;
                env = if isWSLEnabled then { } else (serverCfg.env or { });
              } // (lib.optionalAttrs (serverCfg ? timeout) { inherit (serverCfg) timeout; })
              // (lib.optionalAttrs (serverCfg ? retries) { inherit (serverCfg) retries; });

            claudeDesktopMcpServers = lib.mapAttrs mkClaudeDesktopServer cfg._internal.mcpServers;
            claudeCodeMcpServers = removeAttrs cfg._internal.mcpServers [ "mcp-filesystem" "cli-mcp-server" ];

            mkSettingsTemplate = { model, accountApi ? null }: pkgs.writeText "claude-settings.json" (builtins.toJSON (lib.recursiveUpdate
              (
                let
                  # Filter out null and empty-list event slots so only populated
                  # hooks are serialized.  Fixes prior bug: gate checked only 4
                  # events (with a typo — "Start" instead of "SessionStart").
                  cleanHooks = filterAttrs (_n: v: v != null && v != [ ]) cfg._internal.hooks;
                  hasHooks = cleanHooks != { };
                  hasStatusline = cfg._internal.statuslineSettings != { };

                  permissionsV2 = {
                    inherit (cfg.permissions) allow;
                    inherit (cfg.permissions) deny;
                    inherit (cfg.permissions) ask;
                    inherit (cfg.permissions) defaultMode;
                    inherit (cfg.permissions) additionalDirectories;
                  } // optionalAttrs (cfg.permissions.disableBypassPermissionsMode != null) {
                    inherit (cfg.permissions) disableBypassPermissionsMode;
                  };

                  # Plan 032 T4 — governance keys serialize flat at top level.
                  governanceJson = filterAttrs (_n: v: v != null) {
                    inherit (cfg.governance)
                      allowManagedPermissionRulesOnly
                      allowManagedHooksOnly
                      allowedMcpServers
                      deniedMcpServers
                      strictKnownMarketplaces
                      allowedChannelPlugins
                      enabledPlugins
                      pluginTrustMessage
                      forceRemoteSettingsRefresh;
                  };

                  accountEnvVars =
                    if accountApi == null then { }
                    else
                      (optionalAttrs (accountApi.baseUrl or null != null) {
                        ANTHROPIC_BASE_URL = accountApi.baseUrl;
                      })
                      // (lib.mapAttrs'
                        (model: mapping: lib.nameValuePair "ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL" mapping)
                        (accountApi.modelMappings or { }))
                      // (accountApi.extraEnvVars or { });

                  # Plan 046 T4/T7 — fold global model env (Fable/custom option)
                  # and reliability/MCP env in below account-specific env.
                  # accountEnvVars already carries the per-account provider env
                  # (via accountApi.extraEnvVars).
                  mergedEnvVars = cfg.environmentVariables // modelGlobalEnv // reliabilityEnv // accountEnvVars;

                  # Plan 032 T3 — serialize sandbox.* subtree, stripping nulls.
                  stripNulls = attrs: filterAttrs (_n: v: v != null) attrs;
                  sandboxNetwork = stripNulls {
                    inherit (cfg.sandbox.network)
                      allowUnixSockets allowAllUnixSockets allowLocalBinding
                      allowedDomains httpProxyPort socksProxyPort;
                  };
                  sandboxFilesystem = stripNulls {
                    inherit (cfg.sandbox.filesystem) allowWrite denyRead allowRead;
                  };
                  sandboxBase = stripNulls {
                    inherit (cfg.sandbox)
                      enabled failIfUnavailable autoAllowBashIfSandboxed
                      allowUnsandboxedCommands excludedCommands
                      enableWeakerNestedSandbox enableWeakerNetworkIsolation
                      # Plan 046 T7 — sandbox.allowAppleEvents (scalar)
                      allowAppleEvents;
                  };
                  sandboxJson = sandboxBase
                    // optionalAttrs (sandboxNetwork != { }) { network = sandboxNetwork; }
                    // optionalAttrs (sandboxFilesystem != { }) { filesystem = sandboxFilesystem; }
                    # Plan 046 T7 — sandbox.credentials (object)
                    // optionalAttrs (cfg.sandbox.credentials != null) { inherit (cfg.sandbox) credentials; };

                  # Plan 046 T7 — reliability version-floor + UX + attribution
                  # settings (flat top-level). includeCoAuthoredBy defaults to
                  # false (never null) so it is ALWAYS emitted, guaranteeing no
                  # AI-attribution trailer (CLAUDE.md absolute rule).
                  t7Json = filterAttrs (_n: v: v != null) {
                    inherit (cfg.reliability)
                      autoUpdatesChannel minimumVersion
                      requiredMinimumVersion requiredMaximumVersion;
                    inherit (cfg.ux) outputStyle effortLevel editorMode;
                    inherit (cfg) attribution includeCoAuthoredBy;
                  };
                in
                {
                  inherit model;
                  permissions = permissionsV2;
                }
                // optionalAttrs (mergedEnvVars != { }) { env = mergedEnvVars; }
                // optionalAttrs hasHooks { hooks = cleanHooks; }
                // optionalAttrs (cfg.experimental != { }) { inherit (cfg) experimental; }
                // optionalAttrs hasStatusline cfg._internal.statuslineSettings
                // optionalAttrs cfg.enableProjectOverrides {
                  projectOverrides = {
                    enabled = true;
                    searchPaths = cfg.projectOverridePaths;
                  };
                }
                # Plan 032 T5 — security/UX scalar settings (only emit when set)
                // optionalAttrs (cfg.voice.enable != null) {
                  voiceEnabled = cfg.voice.enable;
                }
                // optionalAttrs (cfg.voice.language != null) {
                  inherit (cfg.voice) language;
                }
                // optionalAttrs (cfg.display.showThinkingSummaries != null) {
                  inherit (cfg.display) showThinkingSummaries;
                }
                // optionalAttrs (cfg.cleanupPeriodDays != null) {
                  inherit (cfg) cleanupPeriodDays;
                }
                // optionalAttrs (cfg.security.disableSkillShellExecution != null) {
                  inherit (cfg.security) disableSkillShellExecution;
                }
                // optionalAttrs (cfg.security.disableDeepLinkRegistration != null) {
                  inherit (cfg.security) disableDeepLinkRegistration;
                }
                // optionalAttrs (cfg.prompt.includeGitInstructions != null) {
                  inherit (cfg.prompt) includeGitInstructions;
                }
                # Plan 032 T6 — apiKeyHelper, worktree.sparsePaths, modelOverrides
                // optionalAttrs (cfg.apiKeyHelper != null) {
                  inherit (cfg) apiKeyHelper;
                }
                // optionalAttrs (cfg.worktree.sparsePaths != null) {
                  worktree = { inherit (cfg.worktree) sparsePaths; };
                }
                // optionalAttrs (cfg.modelOverrides != null) {
                  inherit (cfg) modelOverrides;
                }
                # Plan 032 T3 — sandbox.* subtree
                // optionalAttrs (sandboxJson != { }) { sandbox = sandboxJson; }
                # Plan 032 T4 — governance keys (flat top-level)
                // governanceJson
                # Plan 046 T4 — model selection settings (flat top-level)
                // optionalAttrs (cfg.models.fallback != null) {
                  fallbackModel = cfg.models.fallback;
                }
                // optionalAttrs (cfg.models.available != null) {
                  availableModels = cfg.models.available;
                }
                // optionalAttrs (cfg.models.enforceAvailable != null) {
                  enforceAvailableModels = cfg.models.enforceAvailable;
                }
                # Plan 046 T5 — hook gating settings (flat top-level)
                // optionalAttrs (cfg.hookSettings.disableAllHooks != null) {
                  inherit (cfg.hookSettings) disableAllHooks;
                }
                // optionalAttrs (cfg.hookSettings.allowedHttpHookUrls != null) {
                  inherit (cfg.hookSettings) allowedHttpHookUrls;
                }
                # Plan 046 T6 — plugin marketplace + skill-listing settings (flat top-level)
                // optionalAttrs (cfg.plugins.extraKnownMarketplaces != null) {
                  inherit (cfg.plugins) extraKnownMarketplaces;
                }
                // optionalAttrs (cfg.skillSettings.disableBundled != null) {
                  disableBundledSkills = cfg.skillSettings.disableBundled;
                }
                // optionalAttrs (cfg.skillSettings.maxDescriptionChars != null) {
                  maxSkillDescriptionChars = cfg.skillSettings.maxDescriptionChars;
                }
                // optionalAttrs (cfg.skillSettings.listingBudgetFraction != null) {
                  skillListingBudgetFraction = cfg.skillSettings.listingBudgetFraction;
                }
                # Plan 046 T7 — reliability / UX / attribution settings (flat top-level)
                // t7Json
              )
              # Plan 046 T3 — settingsExtra escape hatch (deep-merged last; wins on conflict)
              cfg.settingsExtra));

            mcpTemplate = pkgs.writeText "claude-mcp.json" (builtins.toJSON {
              mcpServers = claudeCodeMcpServers;
            });

            # Plan 046 T7 — keybindings.json (deployed per-account into the config
            # dir = CLAUDE_CONFIG_DIR). Only referenced when cfg.keybindings != null,
            # so the writeText is never built otherwise (lazy).
            keybindingsTemplate = pkgs.writeText "claude-keybindings.json"
              (builtins.toJSON cfg.keybindings);

            # Plan 046 T11 — RTK.md context file (deployed per-account into the
            # config dir when RTK is enabled and a contextFile is set; lazy).
            rtkMdTemplate = pkgs.writeText "RTK.md" cfg.hooks.rtk.contextFile;

            claudeMdTemplates = mapAttrs (name: _: mkClaudeMdTemplate name)
              (filterAttrs (_n: a: a.enable) cfg.accounts);

            agentTemplates = mapAttrs
              (name: agent:
                pkgs.writeText "claude-agent-${builtins.baseNameOf name}" agent.text
              )
              cfg._internal.subAgentFiles;

            # Import wrapper generation library
            claudeLib = import ./_hm/lib.nix { inherit lib pkgs config; };

            # Generate wrapper scripts for each enabled account
            wrapperScripts = lib.mapAttrsToList
              (name: account:
                pkgs.writers.writeBashBin "claude${name}" (
                  claudeLib.mkClaudeWrapperScript {
                    account = name;
                    inherit (account) displayName;
                    configDir = "${runtimePath}/.claude-${name}";
                    claudeBin = "${pkgs.claude-code}/bin/claude";
                    api = account.api or { };
                    secrets = account.secrets or { };
                    extraEnvVars = {
                      DISABLE_TELEMETRY = "1";
                      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
                      DISABLE_ERROR_REPORTING = "1";
                    } // modelGlobalEnv // reliabilityEnv // (account.extraEnvVars or { })
                    # Plan 046 T4 — per-account provider/auth env (authoritative path)
                    // providerEnv account.provider
                    # Plan 046 T13 — per-account gateway model discovery toggle
                    // discoveryEnv account.discovery;
                  }
                )
              )
              (lib.filterAttrs (_n: a: a.enable) cfg.accounts);

            # Bare 'claude' wrapper that routes to defaultAccount's config dir,
            # preventing Claude Code from falling back to ~/.claude (which caused
            # double-loading of CLAUDE.md and cross-account contamination).
            defaultWrapper = lib.optional (cfg.defaultAccount != null) (
              let
                defaultAcct = cfg.accounts.${cfg.defaultAccount};
              in
              pkgs.writers.writeBashBin "claude" (
                claudeLib.mkClaudeWrapperScript {
                  account = cfg.defaultAccount;
                  inherit (defaultAcct) displayName;
                  configDir = "${runtimePath}/.claude-${cfg.defaultAccount}";
                  claudeBin = "${pkgs.claude-code}/bin/claude";
                  api = defaultAcct.api or { };
                  secrets = defaultAcct.secrets or { };
                  extraEnvVars = {
                    DISABLE_TELEMETRY = "1";
                    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
                    DISABLE_ERROR_REPORTING = "1";
                  } // modelGlobalEnv // reliabilityEnv // (defaultAcct.extraEnvVars or { })
                  # Plan 046 T4 — per-account provider/auth env (authoritative path)
                  // providerEnv defaultAcct.provider
                  # Plan 046 T13 — per-account gateway model discovery toggle
                  // discoveryEnv defaultAcct.discovery;
                }
              )
            );

          in
          mkIf cfg.enable {
            home.packages = with pkgs; optional (cfg.defaultAccount == null) pkgs.claude-code
              ++ (with pkgs; [
              nodejs_22
              git
              ripgrep
              fd
              jq
              uv
            ]) ++ optionals (cfg.mcpServers.sequentialThinkingPython.enable or false) [
              (pkgs.writers.writeBashBin "sequential-thinking-mcp" ''
                exec ${nixmcp.packages.${pkgs.stdenv.hostPlatform.system}.sequential-thinking-mcp}/bin/sequential-thinking-mcp "$@"
              '')
            ] ++ optionals cfg.hooks.formatting.enable [
              nixpkgs-fmt
              black
              prettier
              rustfmt
              go
              shfmt
            ] ++ optionals cfg.hooks.linting.enable [
              python3Packages.pylint
              eslint
              shellcheck
            ] ++ optionals (cfg.hooks.notifications.enable && !stdenv.isDarwin) [
              libnotify
            ]
              # Plan 046 T11 — put the RTK binary on PATH when packaged (else the
              # hook resolves `rtk` from the ambient PATH and no-ops if absent).
              ++ optional (cfg.hooks.rtk.package != null) cfg.hooks.rtk.package
              ++ wrapperScripts
              ++ defaultWrapper;

            home.file = mkMerge [
              (mkMerge (mapAttrsToList
                (_n: account: mkIf account.enable {
                  ".claude-${_n}".source = config.lib.file.mkOutOfStoreSymlink "${runtimePath}/.claude-${_n}";
                })
                cfg.accounts))

              # NOTE: ~/.claude symlink intentionally removed to prevent Claude Code
              # from loading CLAUDE.md twice (once via CLAUDE_CONFIG_DIR, once via
              # ~/.claude fallback). Bare 'claude' now uses defaultWrapper instead.

              (mkIf (cfg._internal.mcpServers != { }) {
                "claude-mcp-config.json".text = builtins.toJSON { mcpServers = claudeDesktopMcpServers; };
              })
            ];

            # Aggregate memory ceiling for ALL concurrent nix scopes combined.
            # Individual scopes get per-eval limits (MemoryHigh=65%/MemoryMax=75%
            # in nix-guarded.sh); this slice caps the total and integrates with
            # systemd-oomd for pressure-based adaptive killing.
            #
            # Tuned 2026-04-18: nix flake check peaks at ~16.6G on 27.4G RAM.
            # Previous 60%/75% was below single-eval peak, causing oomd kills.
            #
            # MemoryHigh (80%): Soft aggregate ceiling. Kernel throttles (reclaims
            #   pages) when combined RSS of all scopes in this slice exceeds this.
            #   Set above single-eval peak so one eval runs without throttling;
            #   two concurrent evals will exceed and trigger pressure.
            # MemoryMax (90%): Hard aggregate ceiling. Kernel OOM-kills a process
            #   if combined RSS reaches this. Safety net for truly runaway usage.
            # ManagedOOMMemoryPressure=kill: Register this slice with systemd-oomd.
            #   When memory pressure (PSI) exceeds the configured threshold (80%,
            #   set system-wide via slice.d/overrides.conf) for the configured
            #   duration, oomd selects and kills a process within this slice.
            # ManagedOOMMemoryPressureDurationSec (60s): How long sustained pressure
            #   must exceed the threshold before oomd acts. Raised from default 30s
            #   to tolerate brief swap spikes during legitimate large evaluations.
            # Linux-only: systemd user slices + systemd-oomd have no Darwin
            # equivalent (pkgs.systemd is linux-only, so referencing it below would
            # break aarch64-darwin evaluation). mkIf defers the content so it is
            # never forced off-Linux.
            systemd.user.slices.nix-eval = mkIf (!pkgs.stdenv.isDarwin) {
              Unit.Description = "Memory-limited slice for nix evaluations";
              Slice = {
                MemoryHigh = "80%";
                MemoryMax = "90%";
                ManagedOOMMemoryPressure = "kill";
                ManagedOOMMemoryPressureDurationSec = "60s";
              };
            };

            # Clear failed transient scopes from OOM-killed nix evaluations.
            # When the cgroup guard kills a runaway eval, systemd-run's transient
            # scope transitions to "failed", which makes the user session "degraded"
            # and triggers noisy warnings during HM activation. These scopes are
            # ephemeral and not restartable — the failure was already logged to the
            # journal (journalctl --user -u nix-eval.slice). Clearing them before
            # reloadSystemd suppresses the false alarm.
            home.activation.clearFailedNixScopes = mkIf (!pkgs.stdenv.isDarwin)
              (lib.hm.dag.entryBefore [ "reloadSystemd" ] ''
                ${pkgs.systemd}/bin/systemctl --user reset-failed 'run-*.scope' 2>/dev/null || true
              '');

            home.activation.claudeConfigTemplates = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              if [[ ! -d "${nixcfgPath}" ]]; then
                echo "Error: nixcfgPath does not exist: ${nixcfgPath}"
                echo "Either create the directory or update programs.claude-code.nixcfgPath"
                exit 1
              fi

              if [[ ! -w "${nixcfgPath}" ]]; then
                echo "Error: nixcfgPath is not writable: ${nixcfgPath}"
                exit 1
              fi

              $DRY_RUN_CMD mkdir -p ${runtimePath}

              copy_template() {
                local template="$1"
                local target="$2"
                $DRY_RUN_CMD rm -f "$target"
                $DRY_RUN_CMD cp "$template" "$target"
                $DRY_RUN_CMD chmod 644 "$target"
                echo "Updated template: $target"
              }

              ${optionalString cfg.enterpriseSettings.enable ''
              echo "Enterprise Settings managed by NixOS system configuration at /etc/claude-code/managed-settings.json"

              if [[ -f "/etc/claude-code/managed-settings.json" ]]; then
                echo "Enterprise Settings found at system level - configuration will use top precedence"
              else
                echo "Warning: Enterprise Settings enabled but /etc/claude-code/managed-settings.json not found"
                echo "    Enterprise settings should be configured at the NixOS system level"
              fi
              ''}

              ${concatStringsSep "\n" (mapAttrsToList (name: account: ''
                if [[ "${toString account.enable}" == "1" ]]; then
                  accountDir="${runtimePath}/.claude-${name}"
                  echo "Configuring account: ${name}"

                  $DRY_RUN_CMD mkdir -p "$accountDir"/{logs,projects,shell-snapshots,statsig,todos,commands}

                  copy_template "${mkSettingsTemplate {
                    model = if account.model != null then account.model else cfg.defaultModel;
                    accountApi = {
                      inherit (account.api) baseUrl;
                      inherit (account.api) modelMappings;
                      # Plan 046 T4 — provider/auth env folds in with extraEnvVars
                      # so the settings.json `env` block carries it too.
                      # Plan 046 T13 — gateway discovery toggle folds in alongside.
                      extraEnvVars = account.extraEnvVars // providerEnv account.provider
                        // discoveryEnv account.discovery;
                    };
                  }}" "$accountDir/settings.json"
                  echo "Updated settings to v2.0 schema: $accountDir/settings.json"

                  copy_template "${mcpTemplate}" "$accountDir/.mcp.json"
                  echo "Updated MCP servers configuration: $accountDir/.mcp.json"

                  copy_template "${
                    claudeMdTemplates.${name} or (mkClaudeMdTemplate name)
                  }" "$accountDir/CLAUDE.md"

                  ${optionalString (cfg.keybindings != null) ''
                  copy_template "${keybindingsTemplate}" "$accountDir/keybindings.json"
                  echo "Deployed keybindings.json: $accountDir/keybindings.json"
                  ''}

                  ${optionalString (cfg.hooks.rtk.enable && cfg.hooks.rtk.contextFile != null) ''
                  copy_template "${rtkMdTemplate}" "$accountDir/RTK.md"
                  echo "Deployed RTK.md: $accountDir/RTK.md"
                  ''}

                  if [[ -f "$accountDir/.claude.json" ]]; then
                    echo "Enforcing Nix-managed settings in .claude.json..."

                    jq_args=(--argjson permissions '${shJson {
                      inherit (cfg.permissions) allow;
                      inherit (cfg.permissions) deny;
                      inherit (cfg.permissions) ask;
                      inherit (cfg.permissions) defaultMode;
                      inherit (cfg.permissions) additionalDirectories;
                    }}')
                    ${optionalString (cfg.environmentVariables != {}) ''jq_args+=(--argjson env '${shJson cfg.environmentVariables}')''}
                    ${optionalString (cfg._internal.statuslineSettings != {}) ''jq_args+=(--argjson statusLine '${shJson cfg._internal.statuslineSettings.statusLine}')''}
                    ${optionalString (cfg._internal.hooks != {}) ''jq_args+=(--argjson hooks '${shJson (filterAttrs (_n: v: v != null) cfg._internal.hooks)}')''}

                    $DRY_RUN_CMD ${pkgs.jq}/bin/jq "''${jq_args[@]}" \
                      '. |
                      .permissions = $permissions
                      ${optionalString (cfg.environmentVariables != {}) ''| .env = $env''}
                      ${optionalString (cfg._internal.statuslineSettings != {}) ''| .statusLine = $statusLine''}
                      ${optionalString (cfg._internal.hooks != {}) ''| .hooks = $hooks''}
                      ' "$accountDir/.claude.json" > "$accountDir/.claude.json.tmp"

                    $DRY_RUN_CMD mv "$accountDir/.claude.json.tmp" "$accountDir/.claude.json"
                    echo "Nix-managed settings enforced in .claude.json"
                  else
                    echo '{}' > "$accountDir/.claude.json"
                    $DRY_RUN_CMD chmod 644 "$accountDir/.claude.json"
                    echo "Created minimal runtime config: $accountDir/.claude.json"
                  fi

                  ${optionalString (cfg._internal.subAgentFiles != {}) ''
                  $DRY_RUN_CMD mkdir -p "$accountDir/agents"
                  ${concatStringsSep "\n" (mapAttrsToList (_path: template: ''
                  copy_template "${template}" "$accountDir/agents/${builtins.baseNameOf _path}"
                  '') agentTemplates)}
                  echo "Deployed ${toString (length (attrNames cfg._internal.subAgentFiles))} sub-agent(s)"
                  ''}

                  echo "Account ${name} configured with statusline support"
                fi
              '') cfg.accounts)}

              # NOTE: Base fallback directory (${runtimePath}/.claude) is no longer
              # created. Bare 'claude' wrapper now uses the defaultAccount's directory
              # directly. If an orphaned .claude directory exists on disk from a
              # previous activation, it can be safely removed.
            '';

            programs.bash.initExtra = mkIf (cfg.accounts != { }) (mkAfter ''
              # Claude Code Session Management
              claude-status() {
                local found_sessions=false
                echo "Checking Claude Code sessions..."

                for account in ${lib.concatStringsSep " " (lib.attrNames (lib.filterAttrs (_n: a: a.enable) cfg.accounts))}; do
                  local pidfile="/tmp/claude-''${account}.pid"
                  if [[ -f "$pidfile" ]]; then
                    local pid=$(cat "$pidfile")
                    if kill -0 "$pid" 2>/dev/null; then
                      echo "Claude Code ($account) is running (PID: $pid)"
                      found_sessions=true
                    else
                      echo "Stale pidfile for $account (removing)"
                      rm -f "$pidfile"
                    fi
                  fi
                done

                if [[ "$found_sessions" == "false" ]]; then
                  echo "No Claude Code sessions are currently running"
                fi
              }

              claude-close() {
                local account="''${1:-}"
                if [[ -z "$account" ]]; then
                  echo "Usage: claude-close <account>"
                  echo "Available accounts: ${lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_n: a: a.enable) cfg.accounts))}"
                  return 1
                fi

                local pidfile="/tmp/claude-''${account}.pid"
                if [[ -f "$pidfile" ]]; then
                  local pid=$(cat "$pidfile")
                  if kill -0 "$pid" 2>/dev/null; then
                    echo "Closing Claude Code ($account) session (PID: $pid)..."
                    kill "$pid"
                    sleep 1
                    if kill -0 "$pid" 2>/dev/null; then
                      echo "Process still running, forcing termination..."
                      kill -9 "$pid"
                    fi
                    rm -f "$pidfile"
                    echo "Claude Code ($account) session closed"
                  else
                    echo "Process not found, removing stale pidfile"
                    rm -f "$pidfile"
                  fi
                else
                  echo "No Claude Code ($account) session found"
                fi
              }
            '');

            programs.zsh.initContent = mkIf (cfg.accounts != { }) (mkAfter ''
              # Claude Code Session Management
              claude-status() {
                local found_sessions=false
                echo "Checking Claude Code sessions..."

                for account in max pro; do
                  local pidfile="/tmp/claude-''${account}.pid"
                  if [[ -f "$pidfile" ]]; then
                    local pid=$(cat "$pidfile")
                    if kill -0 "$pid" 2>/dev/null; then
                      echo "Claude Code ($account) is running (PID: $pid)"
                      found_sessions=true
                    else
                      echo "Stale pidfile for $account (removing)"
                      rm -f "$pidfile"
                    fi
                  fi
                done

                if [[ "$found_sessions" == "false" ]]; then
                  echo "No Claude Code sessions are currently running"
                fi
              }

              claude-close() {
                local account="''${1:-}"
                if [[ -z "$account" ]]; then
                  echo "Usage: claude-close <account>"
                  echo "Available accounts: ${lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_n: a: a.enable) cfg.accounts))}"
                  return 1
                fi

                local pidfile="/tmp/claude-''${account}.pid"
                if [[ -f "$pidfile" ]]; then
                  local pid=$(cat "$pidfile")
                  if kill -0 "$pid" 2>/dev/null; then
                    echo "Closing Claude Code ($account) session (PID: $pid)..."
                    kill "$pid"
                    sleep 1
                    if kill -0 "$pid" 2>/dev/null; then
                      echo "Process still running, forcing termination..."
                      kill -9 "$pid"
                    fi
                    rm -f "$pidfile"
                    echo "Claude Code ($account) session closed"
                  else
                    echo "Process not found, removing stale pidfile"
                    rm -f "$pidfile"
                  fi
                else
                  echo "No Claude Code ($account) session found"
                fi
              }
            '');

            assertions = [
              {
                assertion = cfg.hooks.notifications.enable ->
                  (pkgs.stdenv.isDarwin || config.home.packages or [ ] != [ ]);
                message = "Notifications require either macOS or a Linux notification daemon";
              }
              {
                assertion = cfg.defaultAccount != null -> cfg.accounts ? ${cfg.defaultAccount};
                message = "Default account '${cfg.defaultAccount}' must be defined in accounts";
              }
              {
                assertion = cfg.defaultAccount != null -> cfg.accounts.${cfg.defaultAccount}.enable;
                message = "Default account '${cfg.defaultAccount}' must be enabled";
              }
              {
                # Plan 046 T4 — upstream fallbackModel accepts at most 3 entries.
                assertion = cfg.models.fallback == null || builtins.length cfg.models.fallback <= 3;
                message = "programs.claude-code.models.fallback accepts at most 3 entries";
              }
              {
                assertion = lib.hasPrefix "/" cfg.nixcfgPath;
                message = "nixcfgPath must be an absolute path, got: ${cfg.nixcfgPath}";
              }
              {
                assertion = builtins.isString cfg.nixcfgPath && cfg.nixcfgPath != "";
                message = "nixcfgPath cannot be empty";
              }
            ];
          };
      };
  };
}
