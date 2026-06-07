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
#   - Memory commands for persistent AI guidance
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
          ./_hm/memory-commands.nix
          ./_hm/memory-commands-static.nix
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

            userGlobalMemoryContent = builtins.readFile ./_hm/claude-code-user-memory-template.md;

            memoryUpdateScript = pkgs.writeScriptBin "claude-memory-update" ''
              #!${pkgs.bash}/bin/bash
              set -euo pipefail

              echo "Memory updated, rebuilding claude-code configuration..."
              cd "${nixcfgPath}"

              ${pkgs.git}/bin/git add modules/programs/claude-code/_hm/claude-code-user-memory-template.md
              ${pkgs.git}/bin/git commit -m "Update Claude Code user-global memory" || true

              ${pkgs.home-manager}/bin/home-manager switch --flake .

              echo "Memory updated and propagated to all accounts"
            '';

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

            mkSettingsTemplate = { model, accountApi ? null }: pkgs.writeText "claude-settings.json" (builtins.toJSON (
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

                mergedEnvVars = cfg.environmentVariables // accountEnvVars;

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
                    enableWeakerNestedSandbox enableWeakerNetworkIsolation;
                };
                sandboxJson = sandboxBase
                  // optionalAttrs (sandboxNetwork != { }) { network = sandboxNetwork; }
                  // optionalAttrs (sandboxFilesystem != { }) { filesystem = sandboxFilesystem; };
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
            ));

            mcpTemplate = pkgs.writeText "claude-mcp.json" (builtins.toJSON {
              mcpServers = claudeCodeMcpServers;
            });

            claudeMdTemplate = pkgs.writeText "claude-memory.md" userGlobalMemoryContent;

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
                    } // (account.extraEnvVars or { });
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
                  } // (defaultAcct.extraEnvVars or { });
                }
              )
            );

          in
          mkIf cfg.enable {
            home.packages = with pkgs; optional (cfg.defaultAccount == null) pkgs.claude-code
              ++ [
              (pkgs.writeShellApplication {
                name = "claude-browse";
                text = builtins.readFile ./files/claude-browse;
              })
            ] ++ (with pkgs; [
              nodejs_22
              git
              ripgrep
              fd
              jq
              uv
              memoryUpdateScript
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
            ] ++ wrapperScripts
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
            systemd.user.slices.nix-eval = {
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
            home.activation.clearFailedNixScopes = lib.hm.dag.entryBefore [ "reloadSystemd" ] ''
              ${pkgs.systemd}/bin/systemctl --user reset-failed 'run-*.scope' 2>/dev/null || true
            '';

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
                      inherit (account) extraEnvVars;
                    };
                  }}" "$accountDir/settings.json"
                  echo "Updated settings to v2.0 schema: $accountDir/settings.json"

                  copy_template "${mcpTemplate}" "$accountDir/.mcp.json"
                  echo "Updated MCP servers configuration: $accountDir/.mcp.json"

                  if [[ -f "$accountDir/CLAUDE.md" ]]; then
                    echo "Preserved existing memory file: $accountDir/CLAUDE.md"
                    $DRY_RUN_CMD chmod ${if cfg.memoryCommands.makeWritable then "644" else "444"} "$accountDir/CLAUDE.md"
                  else
                    copy_template "${claudeMdTemplate}" "$accountDir/CLAUDE.md"
                    $DRY_RUN_CMD chmod ${if cfg.memoryCommands.makeWritable then "644" else "444"} "$accountDir/CLAUDE.md"
                    echo "Created memory file: $accountDir/CLAUDE.md"
                  fi

                  if [[ -f "$accountDir/.claude.json" ]]; then
                    echo "Enforcing Nix-managed settings in .claude.json..."

                    jq_args=(--argjson permissions '${builtins.toJSON {
                      inherit (cfg.permissions) allow;
                      inherit (cfg.permissions) deny;
                      inherit (cfg.permissions) ask;
                      inherit (cfg.permissions) defaultMode;
                      inherit (cfg.permissions) additionalDirectories;
                    }}')
                    ${optionalString (cfg.environmentVariables != {}) ''jq_args+=(--argjson env '${builtins.toJSON cfg.environmentVariables}')''}
                    ${optionalString (cfg._internal.statuslineSettings != {}) ''jq_args+=(--argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}')''}
                    ${optionalString (cfg._internal.hooks != {}) ''jq_args+=(--argjson hooks '${builtins.toJSON (filterAttrs (_n: v: v != null) cfg._internal.hooks)}')''}

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
