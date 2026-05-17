# modules/programs/opencode/opencode.nix
# OpenCode multi-account configuration for home-manager
#
# Provides:
#   flake.modules.homeManager.opencode - Full OpenCode multi-account setup
#
# Features:
#   - Multi-account support (max, pro, work profiles)
#   - MCP server integration
#   - Custom agents and commands
#   - TUI configuration
#   - Bitwarden-based secret management via rbw
#   - WSL integration
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.opencode ];
#   programs.opencode = {
#     enable = true;
#     accounts = { max = { ... }; pro = { ... }; };
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    # Full OpenCode configuration for user environment
    homeManager.opencode = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.programs.opencode;

        # Import shared modules for DRY configuration
        # Location: modules/lib/shared/ (dendritic structure)
        sharedInstructions = import ../../lib/shared/ai-instructions.nix { inherit lib; };

        # Import shared rbw helper library for consistent credential handling
        # Location: modules/lib/ (dendritic structure)
        rbwLib = import ../../lib/rbw.nix { inherit pkgs lib; };

        # Channel-aware DB migration helper for OpenCode session history
        channelMigrate = import ./_hm/channel-migrate.nix { inherit pkgs lib; };

        # nix concurrency guard — cgroup memory limits prevent OOM from concurrent evaluations
        nixGuardedPkg = import ../../lib/nix-guarded.nix { inherit pkgs; };

        # Model discovery script for querying /v1/models endpoints
        discoverModelsPkg = import ./_hm/model-discovery.nix { inherit pkgs; };

        # OpenCode PermissionRule: either a flat action or a pattern-to-action map.
        # Flat:   bash = "allow"
        # Object: bash = { "*" = "allow"; "rm -rf /*" = "deny"; }
        permissionActionType = types.enum [ "allow" "ask" "deny" ];
        permissionRuleType = types.either permissionActionType (types.attrsOf permissionActionType);

        # JSON type for freeform nested attrs (forward-compat)
        jsonType = (pkgs.formats.json { }).type;

        # Provider submodule type — mirrors upstream config.ts:788-847
        providerModule = types.submodule {
          options = {
            name = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Display name for this provider";
            };

            npm = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "npm package implementing the AI SDK provider (e.g. @ai-sdk/openai-compatible)";
            };

            whitelist = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = "Model whitelist — only these models from this provider are available";
            };

            blacklist = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = "Model blacklist — hide these models from this provider";
            };

            models = mkOption {
              type = types.nullOr jsonType;
              default = null;
              description = ''
                Per-model overrides. Keys are model IDs; values are partial model
                objects with optional `variants` sub-key. Uses freeform JSON type
                for forward-compat with upstream schema changes.
              '';
              example = {
                "claude-sonnet-4-5" = {
                  variants = {
                    thinking = { disabled = true; };
                  };
                };
              };
            };

            options = mkOption {
              type = types.nullOr (types.submodule {
                freeformType = jsonType;
                options = {
                  timeout = mkOption {
                    type = types.nullOr (types.either types.ints.positive (types.enum [ false ]));
                    default = null;
                    description = ''
                      Request timeout in milliseconds (default 300000 = 5 min).
                      Set to `false` to disable timeout entirely.
                    '';
                  };

                  chunkTimeout = mkOption {
                    type = types.nullOr types.ints.positive;
                    default = null;
                    description = ''
                      Timeout in milliseconds between streamed SSE chunks.
                      If no chunk arrives within this window, the request is aborted.
                    '';
                  };

                  setCacheKey = mkOption {
                    type = types.nullOr types.bool;
                    default = null;
                    description = "Enable promptCacheKey for this provider (default false)";
                  };

                  enterpriseUrl = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "GitHub Enterprise URL for copilot authentication";
                  };

                  apiKey = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "API key for this provider (prefer env vars or secrets for sensitive values)";
                  };

                  baseURL = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Custom base URL for API requests";
                  };
                };
              });
              default = null;
              description = ''
                Provider options (timeout, caching, auth, etc.). Uses a freeform
                submodule so provider-specific keys (e.g. Bedrock's region, profile,
                endpoint) pass through without explicit Nix option definitions.
              '';
            };
          };
        };

        # Serialize a provider submodule value to JSON-ready attrs, stripping nulls
        mkProviderAttrs = _name: prov:
          let
            optAttrs =
              if prov.options == null then { }
              else
                let
                  raw = prov.options;
                  # Remove null-valued typed options; freeform extras pass through
                  filtered = filterAttrs (_k: v: v != null) raw;
                in
                if filtered == { } then { } else { options = filtered; };
          in
          { }
          // optionalAttrs (prov.name != null) { inherit (prov) name; }
          // optionalAttrs (prov.npm != null) { inherit (prov) npm; }
          // optionalAttrs (prov.whitelist != null) { inherit (prov) whitelist; }
          // optionalAttrs (prov.blacklist != null) { inherit (prov) blacklist; }
          // optionalAttrs (prov.models != null) { inherit (prov) models; }
          // optAttrs;

        # Agent submodule type — mirrors upstream config.ts:521-556
        # Well-known agent names: plan, build (primary); general, explore (subagent);
        # title, summary, compaction (specialized). Arbitrary custom names also allowed.
        agentModule = types.submodule {
          options = {
            description = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Description of when to use this agent";
            };

            model = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Model to use for this agent (null = use default)";
            };

            variant = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Default model variant for this agent (e.g. thinking variant)";
            };

            temperature = mkOption {
              type = types.nullOr types.float;
              default = null;
              description = "Temperature parameter for sampling";
            };

            top_p = mkOption {
              type = types.nullOr types.float;
              default = null;
              description = "Top-p (nucleus) sampling parameter";
            };

            prompt = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Custom system prompt for this agent";
            };

            promptFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = "Path to file containing agent prompt";
            };

            tools = mkOption {
              type = types.attrsOf types.bool;
              default = { };
              description = "Tool enable/disable overrides for this agent (deprecated upstream — prefer permission)";
            };

            disable = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "Disable this agent entirely";
            };

            mode = mkOption {
              type = types.nullOr (types.enum [ "subagent" "primary" "all" ]);
              default = null;
              description = ''
                Agent execution mode:
                - "subagent": runs as a spawned subagent
                - "primary": runs in the main conversation
                - "all": available in both modes
              '';
            };

            hidden = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "Hide from @ autocomplete (only meaningful for subagents)";
            };

            color = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Agent color — either a hex color (#XXXXXX) or a theme color name:
                primary, secondary, accent, success, warning, error, info.
              '';
            };

            steps = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "Max agentic iterations (positive integer)";
            };

            options = mkOption {
              type = types.nullOr jsonType;
              default = null;
              description = "Arbitrary key-value options for this agent (freeform)";
            };

            permission = mkOption {
              type = types.attrsOf permissionRuleType;
              default = { };
              description = "Permission overrides for this agent";
            };
          };
        };

        # Command submodule type
        commandModule = types.submodule {
          options = {
            description = mkOption {
              type = types.str;
              description = "Description of this command";
            };

            template = mkOption {
              type = types.str;
              description = "Command template with optional $ARGUMENTS placeholder";
            };

            agent = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Agent to use for this command";
            };

            model = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Model override for this command";
            };

            subtask = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to run as a subtask";
            };
          };
        };

      in
      {
        # Disable upstream home-manager opencode module to avoid conflicts
        # Our enhanced module provides: multi-account, Bitwarden secrets, MCP integration
        disabledModules = [ "programs/opencode.nix" ];

        imports = [
          ./_hm/mcp-servers.nix
          ./_hm/file-commands.nix
          ./_hm/agent-files.nix
          ./_hm/skills.nix
          ./_hm/tui-json.nix
        ];

        options.programs.opencode = {
          enable = mkEnableOption "OpenCode AI coding assistant";

          package = mkPackageOption pkgs "opencode" { };

          debug = mkEnableOption "debug output for OpenCode";

          # ─────────────────────────────────────────────────────────────────────────
          # MODEL CONFIGURATION
          # ─────────────────────────────────────────────────────────────────────────
          defaultModel = mkOption {
            type = types.str;
            default = "anthropic/claude-sonnet-4-5";
            description = "Default model in provider/model format";
            example = "anthropic/claude-sonnet-4-5";
          };

          smallModel = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Model for lightweight tasks (title generation, summaries)";
            example = "anthropic/claude-haiku-4-5";
          };

          # ─────────────────────────────────────────────────────────────────────────
          # PATH CONFIGURATION
          # ─────────────────────────────────────────────────────────────────────────
          nixcfgPath = mkOption {
            type = types.str;
            default = "${config.home.homeDirectory}/src/nixcfg";
            description = "Path to nixcfg repo containing opencode-runtime directory";
          };

          # ─────────────────────────────────────────────────────────────────────────
          # ACCOUNT PROFILES
          # ─────────────────────────────────────────────────────────────────────────
          accounts = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                enable = mkEnableOption "this OpenCode account profile";

                displayName = mkOption {
                  type = types.str;
                  description = "Display name for this account profile";
                  example = "OpenCode Max";
                };

                provider = mkOption {
                  type = types.enum [ "anthropic" "openai" "openrouter" "ollama" "google" "custom" ];
                  default = "anthropic";
                  description = "Primary provider for this account";
                };

                model = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Model override for this account (null = use defaultModel)";
                };

                api = {
                  baseUrl = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Custom API base URL (for proxies)";
                  };

                  apiKeyEnvVar = mkOption {
                    type = types.str;
                    default = "ANTHROPIC_API_KEY";
                    description = "Environment variable name for API key";
                  };
                };

                extraEnvVars = mkOption {
                  type = types.attrsOf types.str;
                  default = { };
                  description = "Additional environment variables for this account";
                };

                secrets = mkOption {
                  type = types.submodule {
                    options = {
                      bearerToken = mkOption {
                        type = types.submodule {
                          options = {
                            bitwarden = mkOption {
                              type = types.nullOr (types.submodule {
                                options = {
                                  item = mkOption {
                                    type = types.str;
                                    description = "Bitwarden item name containing the bearer token";
                                  };
                                  field = mkOption {
                                    type = types.str;
                                    default = "Password";
                                    description = "Field name in Bitwarden item (default: Password)";
                                  };
                                };
                              });
                              default = null;
                              description = "Bitwarden configuration for bearer token retrieval";
                            };
                          };
                        };
                        default = { };
                        description = "Bearer token configuration for API authentication";
                      };

                      envTokens = mkOption {
                        type = types.attrsOf (types.submodule {
                          options = {
                            bitwarden = mkOption {
                              type = types.submodule {
                                options = {
                                  item = mkOption {
                                    type = types.str;
                                    description = "Bitwarden item name";
                                  };
                                  field = mkOption {
                                    type = types.str;
                                    default = "Password";
                                    description = "Field name in Bitwarden item";
                                  };
                                };
                              };
                              description = "Bitwarden reference for this token";
                            };
                          };
                        });
                        default = { };
                        description = ''
                          Named environment variables to export from Bitwarden at runtime.
                          Key = env var name, value = Bitwarden source.
                          Use this for multi-provider setups needing multiple tokens.
                        '';
                      };
                    };
                  };
                  default = { };
                  description = "Secret management configuration for this account";
                };

                discovery = {
                  enable = mkEnableOption "automatic model discovery from /v1/models endpoints";

                  cacheTtlMinutes = mkOption {
                    type = types.int;
                    default = 30;
                    description = "Cache TTL before re-querying endpoints (minutes)";
                  };

                  timeoutSeconds = mkOption {
                    type = types.int;
                    default = 3;
                    description = "Max seconds to wait for discovery before launching opencode";
                  };
                };
              };
            });
            default = { };
            description = ''
              OpenCode account profiles for concurrent independent sessions.
              Each account gets its own config directory via OPENCODE_CONFIG_DIR.
            '';
          };

          defaultAccount = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default account when running 'opencode' without profile";
          };

          # ─────────────────────────────────────────────────────────────────────────
          # AGENTS
          # ─────────────────────────────────────────────────────────────────────────
          agents = mkOption {
            type = types.attrsOf agentModule;
            default = { };
            description = ''
              Agent definitions (catchall — arbitrary agent names accepted).
              Well-known agents:
              - Primary: plan, build
              - Subagent: general, explore
              - Specialized: title, summary, compaction
              Custom agent names are also accepted.
            '';
            example = {
              plan = { model = "anthropic/claude-sonnet-4-5"; steps = 50; };
              compaction = { model = "anthropic/claude-haiku-4-5"; };
              "my-agent" = { description = "Custom agent"; prompt = "You are a specialist."; mode = "subagent"; color = "#ff6600"; };
            };
          };

          defaultAgent = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default agent to use (plan, build, or custom)";
          };

          # ─────────────────────────────────────────────────────────────────────────
          # COMMANDS
          # ─────────────────────────────────────────────────────────────────────────
          commands = mkOption {
            type = types.attrsOf commandModule;
            default = { };
            description = "Custom slash commands";
          };

          # ─────────────────────────────────────────────────────────────────────────
          # PERMISSIONS
          # ─────────────────────────────────────────────────────────────────────────
          permissions = mkOption {
            type = types.attrsOf permissionRuleType;
            default = { };
            description = ''
              Tool permissions (catchall — arbitrary tool names accepted).
              Keys are tool names, values are either a permission level
              ("allow"/"ask"/"deny") or an object mapping command patterns
              to permission levels (last match wins).

              Well-known tools: read, edit, glob, grep, list, bash, task,
              skill, lsp, todowrite, question, webfetch, websearch,
              codesearch, external_directory, doom_loop.
              Custom/MCP tool names are also accepted (catchall via attrsOf).
            '';
            example = {
              bash = { "*" = "allow"; "rm -rf /*" = "deny"; };
              edit = "allow";
              read = "allow";
              "mcp__myserver__mytool" = "allow";
            };
          };

          # ─────────────────────────────────────────────────────────────────────────
          # INSTRUCTIONS (AGENTS.md)
          # ─────────────────────────────────────────────────────────────────────────
          instructions = {
            files = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Files to include as additional instructions (e.g., CONTRIBUTING.md)";
            };

            extraContent = mkOption {
              type = types.lines;
              default = "";
              description = "Additional content to append to AGENTS.md";
            };
          };

          # ─────────────────────────────────────────────────────────────────────────
          # TUI SETTINGS
          # ─────────────────────────────────────────────────────────────────────────
          # `programs.opencode.tui.*` options are defined in ./_hm/tui-json.nix
          # and written to `tui.json` (NOT `opencode.json`). See Plan 032 T1/T2
          # and the module header comment in tui-json.nix for the rationale.
          #
          # ─────────────────────────────────────────────────────────────────────────
          # FORMATTERS
          # ─────────────────────────────────────────────────────────────────────────
          formatters = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                command = mkOption {
                  type = types.listOf types.str;
                  description = "Formatter command with $FILE placeholder";
                };

                extensions = mkOption {
                  type = types.listOf types.str;
                  description = "File extensions this formatter handles";
                };

                environment = mkOption {
                  type = types.attrsOf types.str;
                  default = { };
                  description = "Environment variables for the formatter";
                };

                disabled = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Whether to disable this formatter";
                };
              };
            });
            default = { };
            description = "Custom code formatters";
          };

          # ─────────────────────────────────────────────────────────────────────────
          # ADVANCED SETTINGS
          # ─────────────────────────────────────────────────────────────────────────
          compaction = {
            auto = mkOption {
              type = types.bool;
              default = true;
              description = "Enable automatic context compaction";
            };

            prune = mkOption {
              type = types.bool;
              default = true;
              description = "Enable automatic context pruning";
            };

            reserved = mkOption {
              type = types.nullOr (types.ints.unsigned);
              default = null;
              description = ''
                Token buffer for compaction. Leaves enough window to avoid
                overflow during compaction. null = omit (use upstream default).
              '';
            };
          };

          watcher = {
            ignore = mkOption {
              type = types.listOf types.str;
              default = [ "node_modules/**" ".git/**" ];
              description = "Glob patterns to ignore in file watcher";
            };
          };

          autoupdate = mkOption {
            type = types.nullOr (types.either types.bool (types.enum [ "notify" ]));
            default = true;
            description = ''
              Auto-update behavior: true (auto-update), false (disable),
              "notify" (show notifications only), or null (omit key; use upstream default).
            '';
          };

          # ─────────────────────────────────────────────────────────────────────────
          # SERVER (opencode serve / web) — Plan 032 T9 / OC-G8
          # ─────────────────────────────────────────────────────────────────────────
          server = {
            port = mkOption {
              type = types.nullOr types.port;
              default = null;
              description = "Port to listen on (opencode serve / web).";
            };
            hostname = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Hostname to listen on.";
            };
            mdns = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "Enable mDNS service discovery.";
            };
            mdnsDomain = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Custom mDNS domain (default upstream: opencode.local).";
            };
            cors = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = "Additional domains to allow for CORS.";
            };
          };

          # ─────────────────────────────────────────────────────────────────────────
          # MISC top-level scalars — Plan 032 T9
          # ─────────────────────────────────────────────────────────────────────────
          snapshot = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = ''
              Enable or disable snapshot tracking. When false, filesystem snapshots
              are not recorded and undo/revert will not restore file changes.
              null = omit (upstream default: true). OC-G15.
            '';
          };

          username = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Custom username displayed in conversations instead of system username.
              OC-G18.
            '';
          };

          share = mkOption {
            type = types.enum [ "manual" "auto" "disabled" ];
            default = "manual";
            description = "Session sharing behavior";
          };

          provider = mkOption {
            type = types.attrsOf providerModule;
            default = { };
            description = ''
              Per-provider configuration keyed by provider ID (e.g. "anthropic",
              "openai", "amazon-bedrock"). Each entry supports whitelist, blacklist,
              models overrides, and options (timeout, caching, auth).
            '';
            example = {
              anthropic = {
                options = {
                  timeout = 600000;
                  chunkTimeout = 30000;
                  setCacheKey = true;
                };
              };
              "amazon-bedrock" = {
                options = {
                  region = "us-east-1";
                  profile = "my-aws-profile";
                };
              };
            };
          };

          disabledProviders = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            description = ''
              Provider IDs to disable. These providers will not be loaded even if
              auto-detected. Takes priority over enabledProviders.
            '';
            example = [ "openai" "gemini" ];
          };

          enabledProviders = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            description = ''
              When set, ONLY these providers will be enabled. All other providers
              are ignored (allowlist mode).
            '';
            example = [ "anthropic" "openai" ];
          };

          enterprise = {
            url = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Enterprise URL for self-hosted deployments";
            };
          };

          experimental = mkOption {
            type = types.submodule {
              freeformType = jsonType;
              options = {
                openTelemetry = mkOption {
                  type = types.nullOr types.bool;
                  default = null;
                  description = "Enable OpenTelemetry spans for AI SDK calls (experimental_telemetry flag)";
                };

                batch_tool = mkOption {
                  type = types.nullOr types.bool;
                  default = null;
                  description = "Enable the batch tool";
                };

                disable_paste_summary = mkOption {
                  type = types.nullOr types.bool;
                  default = null;
                  description = "Disable paste summary generation";
                };

                primary_tools = mkOption {
                  type = types.nullOr (types.listOf types.str);
                  default = null;
                  description = "Tools that should only be available to primary agents";
                };

                continue_loop_on_deny = mkOption {
                  type = types.nullOr types.bool;
                  default = null;
                  description = "Continue the agent loop when a tool call is denied";
                };

                mcp_timeout = mkOption {
                  type = types.nullOr types.ints.positive;
                  default = null;
                  description = "Timeout in milliseconds for MCP requests";
                };
              };
            };
            default = { };
            description = ''
              Experimental features. Typed fields match upstream config.ts:1019-1038.
              Freeform attrs allowed for forward-compat with new upstream experiments.
            '';
          };

          # ─────────────────────────────────────────────────────────────────────────
          # PLUGINS — Plan 032 T13 / OC-G24
          # ─────────────────────────────────────────────────────────────────────────
          plugin = mkOption {
            type = types.listOf (types.either
              types.str
              (types.listOf jsonType));
            default = [ ];
            description = ''
              Top-level plugin specifiers (separate from tui.plugins).
              Each entry is either a plugin name string (npm package or file:// URL)
              or a [name, options] tuple where options is an arbitrary attrset.
              Matches upstream PluginSpec = string | [string, Record<string, unknown>].
            '';
            example = [
              "@opencode/plugin-foo"
              [ "@opencode/plugin-bar" { someOption = true; } ]
            ];
          };

          # ─────────────────────────────────────────────────────────────────────────
          # LSP — Plan 032 T13 / OC-G25
          # ─────────────────────────────────────────────────────────────────────────
          lsp = mkOption {
            type = types.either
              (types.enum [ false ])
              (types.attrsOf (types.submodule {
                options = {
                  command = mkOption {
                    type = types.listOf types.str;
                    description = "LSP server command and arguments";
                    example = [ "typescript-language-server" "--stdio" ];
                  };

                  extensions = mkOption {
                    type = types.nullOr (types.listOf types.str);
                    default = null;
                    description = ''
                      File extensions this LSP server handles.
                      Required for custom servers; optional for built-in server IDs.
                    '';
                  };

                  disabled = mkOption {
                    type = types.nullOr types.bool;
                    default = null;
                    description = "Disable this LSP server";
                  };

                  env = mkOption {
                    type = types.attrsOf types.str;
                    default = { };
                    description = "Environment variables passed to the LSP server process";
                  };

                  initialization = mkOption {
                    type = types.nullOr jsonType;
                    default = null;
                    description = "Initialization options sent to the LSP server (arbitrary JSON)";
                  };
                };
              }));
            default = { };
            description = ''
              LSP server configuration. Set to `false` to disable all LSP integration.
              Otherwise, an attrset keyed by server ID. Built-in server IDs (e.g.
              "typescript") don't require extensions; custom servers must specify them.
              Each server supports env vars and initialization options that round-trip
              to opencode.json. Matches upstream config.ts:962-997.
            '';
            example = {
              typescript = { disabled = true; };
              custom-server = {
                command = [ "my-lsp" "--stdio" ];
                extensions = [ ".myext" ];
                env = { MY_VAR = "value"; };
                initialization = { setting1 = true; };
              };
            };
          };

          # ─────────────────────────────────────────────────────────────────────────
          # INTERNAL OPTIONS
          # ─────────────────────────────────────────────────────────────────────────
          _internal = {
            mcpServers = mkOption {
              type = types.attrs;
              default = { };
              internal = true;
              description = "Processed MCP server configurations";
            };
            skillPaths = mkOption {
              type = types.listOf types.str;
              default = [ ];
              internal = true;
              description = "Aggregated skill paths from skills sub-module";
            };
            skillUrls = mkOption {
              type = types.listOf types.str;
              default = [ ];
              internal = true;
              description = "Aggregated skill URLs from skills sub-module";
            };
          };
        };

        config =
          let
            inherit (cfg) nixcfgPath;
            runtimePath = "${nixcfgPath}/opencode-runtime";

            # Build the MCP configuration from _internal
            mcpConfig = cfg._internal.mcpServers;

            # Build agent configuration — only emit non-null / non-empty fields
            agentConfig = mapAttrs
              (_name: agent: { }
                // optionalAttrs (agent.description != null) { inherit (agent) description; }
                // optionalAttrs (agent.model != null) { inherit (agent) model; }
                // optionalAttrs (agent.variant != null) { inherit (agent) variant; }
                // optionalAttrs (agent.temperature != null) { inherit (agent) temperature; }
                // optionalAttrs (agent.top_p != null) { inherit (agent) top_p; }
                // optionalAttrs (agent.prompt != null) { inherit (agent) prompt; }
                // optionalAttrs (agent.tools != { }) { inherit (agent) tools; }
                // optionalAttrs (agent.disable != null) { inherit (agent) disable; }
                // optionalAttrs (agent.mode != null) { inherit (agent) mode; }
                // optionalAttrs (agent.hidden != null) { inherit (agent) hidden; }
                // optionalAttrs (agent.color != null) { inherit (agent) color; }
                // optionalAttrs (agent.steps != null) { inherit (agent) steps; }
                // optionalAttrs (agent.options != null) { inherit (agent) options; }
                // optionalAttrs (agent.permission != { }) { inherit (agent) permission; })
              cfg.agents;

            # Build command configuration
            commandConfig = mapAttrs
              (_name: cmd: {
                inherit (cmd) description;
                inherit (cmd) template;
              } // optionalAttrs (cmd.agent != null) {
                inherit (cmd) agent;
              } // optionalAttrs (cmd.model != null) {
                inherit (cmd) model;
              } // optionalAttrs cmd.subtask {
                subtask = true;
              })
              cfg.commands;

            # Build formatter configuration
            formatterConfig = mapAttrs
              (_name: fmt: {
                inherit (fmt) command;
                inherit (fmt) extensions;
              } // optionalAttrs (fmt.environment != { }) {
                inherit (fmt) environment;
              } // optionalAttrs fmt.disabled {
                disabled = true;
              })
              cfg.formatters;

            # Generate complete opencode.json for an account
            mkOpencodeConfig = _accountName: accountCfg:
              let
                model = if accountCfg.model != null then accountCfg.model else cfg.defaultModel;
              in
              {
                "$schema" = "https://opencode.ai/config.json";
                inherit model;
              }
              // optionalAttrs (cfg.smallModel != null) { small_model = cfg.smallModel; }
              // optionalAttrs (mcpConfig != { }) { mcp = mcpConfig; }
              // optionalAttrs (agentConfig != { }) { agent = agentConfig; }
              // optionalAttrs (cfg.defaultAgent != null) { default_agent = cfg.defaultAgent; }
              // optionalAttrs (commandConfig != { }) { command = commandConfig; }
              // optionalAttrs (cfg.permissions != { }) { permission = cfg.permissions; }
              // optionalAttrs (cfg.instructions.files != [ ]) { instructions = cfg.instructions.files; }
              # NOTE: tui.*, theme, and keybinds intentionally NOT written here —
              # they live in tui.json, deployed by ./_hm/tui-json.nix. See Plan
              # 032 T1/T2 and the header comment in tui-json.nix for rationale.
              // optionalAttrs (formatterConfig != { }) { formatter = formatterConfig; }
              // (
                let
                  providerAttrs = mapAttrs mkProviderAttrs cfg.provider;
                  nonEmpty = filterAttrs (_: v: v != { }) providerAttrs;
                in
                optionalAttrs (nonEmpty != { }) { provider = nonEmpty; }
              )
              // optionalAttrs (cfg.disabledProviders != null) { disabled_providers = cfg.disabledProviders; }
              // optionalAttrs (cfg.enabledProviders != null) { enabled_providers = cfg.enabledProviders; }
              // (
                let
                  ent = { }
                  // optionalAttrs (cfg.enterprise.url != null) { inherit (cfg.enterprise) url; };
                in
                optionalAttrs (ent != { }) { enterprise = ent; }
              )
              // {
                watcher = {
                  inherit (cfg.watcher) ignore;
                };
                inherit (cfg) share;
              }
              // optionalAttrs (cfg.autoupdate != null) { inherit (cfg) autoupdate; }
              // optionalAttrs (cfg.snapshot != null) { inherit (cfg) snapshot; }
              // optionalAttrs (cfg.username != null) { inherit (cfg) username; }
              // (
                let
                  s = cfg.server;
                  serverAttrs = { }
                  // optionalAttrs (s.port != null) { inherit (s) port; }
                  // optionalAttrs (s.hostname != null) { inherit (s) hostname; }
                  // optionalAttrs (s.mdns != null) { inherit (s) mdns; }
                  // optionalAttrs (s.mdnsDomain != null) { inherit (s) mdnsDomain; }
                  // optionalAttrs (s.cors != null) { inherit (s) cors; };
                in
                optionalAttrs (serverAttrs != { }) { server = serverAttrs; }
              )
              // {
                compaction = {
                  inherit (cfg.compaction) auto prune;
                }
                // optionalAttrs (cfg.compaction.reserved != null) {
                  inherit (cfg.compaction) reserved;
                };
              }
              // (
                let
                  # Strip null leaves from the experimental submodule
                  expFiltered = filterAttrs (_: v: v != null) cfg.experimental;
                in
                optionalAttrs (expFiltered != { }) { experimental = expFiltered; }
              )
              // optionalAttrs (cfg.plugin != [ ]) { inherit (cfg) plugin; }
              // (
                let
                  lspVal = cfg.lsp;
                  # lsp can be `false` (disable all) or an attrset of server configs
                  isDisabled = lspVal == false;
                  isNonEmpty = !isDisabled && lspVal != { };
                  # Strip null/empty leaves from each server config
                  mkLspServer = _name: srv:
                    { inherit (srv) command; }
                    // optionalAttrs (srv.extensions != null) { inherit (srv) extensions; }
                    // optionalAttrs (srv.disabled != null) { inherit (srv) disabled; }
                    // optionalAttrs (srv.env != { }) { inherit (srv) env; }
                    // optionalAttrs (srv.initialization != null) { inherit (srv) initialization; };
                in
                if isDisabled then { lsp = false; }
                else if isNonEmpty then { lsp = mapAttrs mkLspServer lspVal; }
                else { }
              )
              // optionalAttrs (cfg._internal.skillPaths != [ ] || cfg._internal.skillUrls != [ ]) {
                skills = { }
                // optionalAttrs (cfg._internal.skillPaths != [ ]) {
                  paths = cfg._internal.skillPaths;
                }
                // optionalAttrs (cfg._internal.skillUrls != [ ]) {
                  urls = cfg._internal.skillUrls;
                };
              };

            # Generate AGENTS.md content using shared instructions
            mkAgentsMdContent = _accountName:
              let
                mcpServerStatus = map
                  (name: {
                    inherit name;
                    status = "enabled";
                  })
                  (attrNames mcpConfig);
              in
              sharedInstructions.mkMemoryContent sharedInstructions {
                toolName = "OpenCode";
                mcpServers = mcpServerStatus;
                inherit (cfg.instructions) extraContent;
              };

            # Create account-specific config file
            mkConfigFile = accountName: accountCfg:
              pkgs.writeText "opencode-${accountName}.json"
                (builtins.toJSON (mkOpencodeConfig accountName accountCfg));

            # Create AGENTS.md file
            agentsMdFile = accountName:
              pkgs.writeText "AGENTS-${accountName}.md" (mkAgentsMdContent accountName);

            # Create wrapper script for each account
            mkAccountScript = accountName: accountCfg:
              let
                configDir = "${runtimePath}/.opencode-${accountName}";

                # Static env vars
                envVars = {
                  OPENCODE_CONFIG_DIR = configDir;
                } // optionalAttrs (accountCfg.api.baseUrl != null) {
                  ANTHROPIC_BASE_URL = accountCfg.api.baseUrl;
                } // accountCfg.extraEnvVars;

                envExports = concatStringsSep "\n"
                  (mapAttrsToList (k: v: "export ${k}=${escapeShellArg v}") envVars);

                # Bitwarden token fetch logic (if configured)
                # Uses shared rbw library with time-based sync (default 5 min staleness)
                hasBitwardenToken = accountCfg.secrets.bearerToken.bitwarden != null;
                bitwardenFetch = optionalString hasBitwardenToken (
                  let
                    bwItem = accountCfg.secrets.bearerToken.bitwarden.item;
                    bwField = accountCfg.secrets.bearerToken.bitwarden.field;
                  in
                  rbwLib.mkRbwExportWithDiagnostics {
                    item = bwItem;
                    field = if bwField == "" then null else bwField;
                    varName = accountCfg.api.apiKeyEnvVar;
                  }
                );

                # Multi-token fetch via envTokens (for multi-provider setups)
                envTokenFetches = concatStringsSep "\n" (mapAttrsToList
                  (envVarName: tokenCfg:
                    rbwLib.mkRbwExportWithDiagnostics {
                      inherit (tokenCfg.bitwarden) item;
                      field = let f = tokenCfg.bitwarden.field; in if f == "" then null else f;
                      varName = envVarName;
                    }
                  )
                  accountCfg.secrets.envTokens);

                # --- Model discovery ---
                # Detect providers with options.baseURL set and apiKey matching {env:*}
                discoveryCfg = accountCfg.discovery;
                discoverableProviders =
                  if !discoveryCfg.enable then { }
                  else
                    filterAttrs
                      (_name: prov:
                        prov.options != null
                        && prov.options.baseURL or null != null
                        && prov.options.apiKey or null != null
                        && builtins.match "[{]env:(.+)[}]" (prov.options.apiKey) != null
                      )
                      cfg.provider;

                # Extract env var name from {env:NAME} pattern
                extractEnvVar = apiKeyStr:
                  let m = builtins.match "[{]env:(.+)[}]" apiKeyStr;
                  in if m != null then builtins.head m else null;

                # Build static model ID list for a provider
                staticModelIds = prov:
                  if prov.models == null then ""
                  else concatStringsSep "," (attrNames prov.models);

                # Generate the discovery shell snippet
                discoverySnippet = optionalString (discoverableProviders != { }) (
                  let
                    timeoutSec = toString discoveryCfg.timeoutSeconds;
                    cacheTtl = toString discoveryCfg.cacheTtlMinutes;
                    providerCmds = mapAttrsToList
                      (provId: prov:
                        let
                          envVar = extractEnvVar prov.options.apiKey;
                          baseUrl = prov.options.baseURL;
                          staticModels = staticModelIds prov;
                        in
                        ''
                          ${discoverModelsPkg}/bin/opencode-discover-models \
                            --provider-id ${escapeShellArg provId} \
                            --base-url ${escapeShellArg baseUrl} \
                            --api-key-env ${escapeShellArg envVar} \
                            --cache-dir "$_OC_DISC_DIR" \
                            --cache-ttl ${cacheTtl} \
                            --static-models ${escapeShellArg staticModels} &
                          _oc_disc_pids+=($!)
                        ''
                      )
                      discoverableProviders;
                  in
                  ''
                    # --- Model discovery ---
                    _OC_DISC_DIR="$HOME/.cache/opencode-discovery/${accountName}"
                    mkdir -p "$_OC_DISC_DIR"

                    _oc_disc_pids=()
                    ${concatStringsSep "\n" providerCmds}

                    # Wait with timeout
                    for _pid in "''${_oc_disc_pids[@]}"; do
                      timeout ${timeoutSec} tail --pid="$_pid" -f /dev/null 2>/dev/null || true
                    done

                    # Merge cached fragments into OPENCODE_CONFIG_CONTENT
                    if compgen -G "$_OC_DISC_DIR/*.json" >/dev/null 2>&1; then
                      _oc_merged=$(jq -s 'reduce .[] as $item ({}; . * $item)' \
                        "$_OC_DISC_DIR"/*.json 2>/dev/null || echo '{}')
                      if [[ "$_oc_merged" != "{}" ]]; then
                        export OPENCODE_CONFIG_CONTENT="$_oc_merged"
                      fi
                    fi
                  ''
                );
              in
              pkgs.writeShellScriptBin "opencode${accountName}" ''
                #!/usr/bin/env bash
                set -o errexit
                set -o nounset
                set -o pipefail

                # Prepend nix concurrency guard to PATH so agent nix invocations
                # run under systemd cgroup memory limits (prevents OOM from evals)
                export PATH="${nixGuardedPkg}/bin:''$PATH"

                ${envExports}
                ${channelMigrate.mkChannelMigrateSnippet { ocPackage = cfg.package; }}
                ${bitwardenFetch}
                ${envTokenFetches}
                ${discoverySnippet}

                exec ${cfg.package}/bin/opencode "$@"
              '';

          in
          mkIf cfg.enable {
            # Install OpenCode and account wrapper scripts
            home.packages = [
              cfg.package
            ] ++ (mapAttrsToList mkAccountScript
              (filterAttrs (_n: a: a.enable) cfg.accounts));

            # Symlink config directories
            home.file = mkMerge [
              # Account-specific config directories
              (mkMerge (mapAttrsToList
                (_n: account: mkIf account.enable {
                  ".config/opencode-${_n}".source =
                    config.lib.file.mkOutOfStoreSymlink "${runtimePath}/.opencode-${_n}";
                })
                cfg.accounts))

              # Default account symlink
              (mkIf (cfg.defaultAccount != null) {
                ".config/opencode".source =
                  config.lib.file.mkOutOfStoreSymlink "${runtimePath}/.opencode-${cfg.defaultAccount}";
              })
            ];

            # Activation script to deploy configurations
            home.activation.opencodeConfigTemplates = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              # Validate nixcfgPath exists
              if [[ ! -d "${nixcfgPath}" ]]; then
                echo "Error: nixcfgPath does not exist: ${nixcfgPath}"
                echo "Either create the directory or update programs.opencode.nixcfgPath"
                exit 1
              fi

              if [[ ! -w "${nixcfgPath}" ]]; then
                echo "Error: nixcfgPath is not writable: ${nixcfgPath}"
                exit 1
              fi

              $DRY_RUN_CMD mkdir -p ${runtimePath}

              # Helper function
              copy_template() {
                local template="$1"
                local target="$2"
                $DRY_RUN_CMD rm -f "$target"
                $DRY_RUN_CMD cp "$template" "$target"
                $DRY_RUN_CMD chmod 644 "$target"
                echo "Updated: $target"
              }

              # Deploy account configurations
              ${concatStringsSep "\n" (mapAttrsToList (name: account: ''
                if [[ "${toString account.enable}" == "1" ]]; then
                  accountDir="${runtimePath}/.opencode-${name}"
                  echo "Configuring OpenCode account: ${name}"

                  $DRY_RUN_CMD mkdir -p "$accountDir"

                  # Deploy opencode.json
                  copy_template "${mkConfigFile name account}" "$accountDir/opencode.json"

                  # Deploy AGENTS.md (preserve existing if present)
                  ${optionalString (cfg.instructions.extraContent != "" || mcpConfig != {}) ''
                  if [[ -f "$accountDir/AGENTS.md" ]]; then
                    echo "Preserved existing AGENTS.md"
                  else
                    copy_template "${agentsMdFile name}" "$accountDir/AGENTS.md"
                  fi
                  ''}

                  echo "OpenCode account ${name} configured"
                fi
              '') cfg.accounts)}
            '';

            # Shell functions for session management
            programs.bash.initExtra = mkIf (cfg.accounts != { }) (mkAfter ''
              # OpenCode Session Management
              opencode-status() {
                echo "Checking OpenCode sessions..."
                for account in ${concatStringsSep " " (attrNames (filterAttrs (_n: a: a.enable) cfg.accounts))}; do
                  local pidfile="/tmp/opencode-''${account}.pid"
                  if [[ -f "$pidfile" ]]; then
                    local pid=$(cat "$pidfile")
                    if kill -0 "$pid" 2>/dev/null; then
                      echo "OpenCode ($account) is running (PID: $pid)"
                    else
                      echo "Stale pidfile for $account (removing)"
                      rm -f "$pidfile"
                    fi
                  fi
                done
              }
            '');

            programs.zsh.initContent = mkIf (cfg.accounts != { }) (mkAfter ''
              # OpenCode Session Management
              opencode-status() {
                echo "Checking OpenCode sessions..."
                for account in ${concatStringsSep " " (attrNames (filterAttrs (_n: a: a.enable) cfg.accounts))}; do
                  local pidfile="/tmp/opencode-''${account}.pid"
                  if [[ -f "$pidfile" ]]; then
                    local pid=$(cat "$pidfile")
                    if kill -0 "$pid" 2>/dev/null; then
                      echo "OpenCode ($account) is running (PID: $pid)"
                    else
                      echo "Stale pidfile for $account (removing)"
                      rm -f "$pidfile"
                    fi
                  fi
                done
              }
            '');

            # Assertions
            assertions = [
              {
                assertion = cfg.defaultAccount != null -> cfg.accounts ? ${cfg.defaultAccount};
                message = "Default account '${cfg.defaultAccount}' must be defined in accounts";
              }
              {
                assertion = cfg.defaultAccount != null -> cfg.accounts.${cfg.defaultAccount}.enable;
                message = "Default account '${cfg.defaultAccount}' must be enabled";
              }
              {
                assertion = hasPrefix "/" cfg.nixcfgPath;
                message = "nixcfgPath must be an absolute path, got: ${cfg.nixcfgPath}";
              }
            ];
          };
      };
  };
}
