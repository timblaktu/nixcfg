# OpenCode MCP Servers Sub-module
# Provides pre-configured MCP servers using shared definitions
# Transforms shared/mcp-server-defs.nix to OpenCode's JSON format
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.opencode;

  # Import shared MCP server definitions for DRY consistency with claude-code
  # Location: modules/lib/shared/ (dendritic structure)
  sharedMcpDefs = import ../../../lib/shared/mcp-server-defs.nix { inherit lib; };

  # Transform shared MCP server definition to OpenCode format
  # OpenCode uses: { type = "local"; command = [...]; environment = {}; enabled = true; }
  # NOTE: OpenCode uses "enabled" (with 'd'), not "enable"
  toOpencodeFormat = serverCfg: {
    type = "local";
    command =
      if serverCfg.command == "npx" then
        [ "npx" ] ++ serverCfg.args
      else if serverCfg.command == "nix" then
        [ "nix" ] ++ serverCfg.args
      else
        [ serverCfg.command ] ++ (serverCfg.args or [ ]);
    enabled = true;
  } // optionalAttrs (serverCfg.env or { } != { }) {
    environment = serverCfg.env;
  };

  # Strip null values and empty attrs from a custom server definition so that
  # upstream's .strict() zod schemas (McpLocal, McpRemote) don't reject
  # unexpected keys.  Also recursively cleans nested attrs (e.g. oauth).
  cleanCustomServer = _name: srv:
    let
      # Recursively strip nulls from an attrset (one level deep is sufficient)
      stripNulls = filterAttrs (_: v: v != null);
      stripped = stripNulls srv;
      # Also strip empty attrsets (environment = {}, headers = {})
      cleaned = filterAttrs (_: v: !(builtins.isAttrs v && v == { })) stripped;
      # Also strip empty lists (command = [])
      final = filterAttrs (_: v: !(builtins.isList v && v == [ ])) cleaned;
      # Clean nested oauth attrset if present
    in
    if final ? oauth && builtins.isAttrs final.oauth then
      final // { oauth = stripNulls final.oauth; }
    else
      final;

in
{
  options.programs.opencode.mcpServers = {
    # Pre-configured servers using shared definitions
    nixos = {
      enable = mkEnableOption "NixOS MCP server for package/option search";
      cacheTtl = mkOption {
        type = types.int;
        default = 3600;
        description = "Cache TTL in seconds";
      };
    };

    sequentialThinking = {
      enable = mkEnableOption "Sequential thinking MCP server";
      timeout = mkOption {
        type = types.int;
        default = 600;
        description = "Server timeout in seconds";
      };
    };

    context7 = {
      enable = mkEnableOption "Context7 MCP server";
    };

    serena = {
      enable = mkEnableOption "Serena AI project assistant MCP server";
      context = mkOption {
        type = types.str;
        default = "ide-assistant";
        description = "Serena context mode";
      };
    };

    brave = {
      enable = mkEnableOption "Brave Search MCP server";
      apiKey = mkOption {
        type = types.str;
        default = "";
        description = "Brave API key (use {env:BRAVE_API_KEY} for env var)";
      };
      searchCount = mkOption {
        type = types.int;
        default = 10;
        description = "Number of search results";
      };
    };

    puppeteer = {
      enable = mkEnableOption "Puppeteer web automation MCP server";
      headless = mkOption {
        type = types.bool;
        default = true;
        description = "Run in headless mode";
      };
    };

    github = {
      enable = mkEnableOption "GitHub MCP server";
      token = mkOption {
        type = types.str;
        default = "";
        description = "GitHub PAT (use {env:GITHUB_TOKEN} for env var)";
      };
    };

    gitlab = {
      enable = mkEnableOption "GitLab MCP server";
      url = mkOption {
        type = types.str;
        default = "https://gitlab.com";
        description = "GitLab instance URL";
      };
      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "GitLab token (optional)";
      };
    };

    filesystem = {
      enable = mkEnableOption "Filesystem MCP server";
      allowedPaths = mkOption {
        type = types.listOf types.str;
        default = [ "/tmp" ];
        description = "Paths the server can access";
      };
    };

    cliMcpServer = {
      enable = mkEnableOption "CLI MCP server (useful for OpenCode Desktop, not needed for TUI)";
      allowedDir = mkOption {
        type = types.str;
        default = "/tmp";
        description = "Allowed directory for CLI operations";
      };
    };

    # Custom servers (raw configuration matching OpenCode schema)
    custom = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enabled = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = "Enable or disable the MCP server on startup. null = omit (upstream default: true).";
          };
          type = mkOption {
            type = types.enum [ "local" "remote" ];
            default = "local";
            description = "Server type: local (command) or remote (url)";
          };
          command = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Command to start local server (local type only)";
          };
          url = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "URL for remote server (remote type only)";
          };
          environment = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Environment variables for the server (local type only)";
          };
          headers = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "HTTP headers for remote server (remote type only)";
          };
          timeout = mkOption {
            type = types.nullOr types.ints.positive;
            default = null;
            description = ''
              Timeout in milliseconds for MCP server requests.
              null = omit (upstream default: 5000ms).
              Applies to both local and remote servers.
            '';
          };
          oauth = mkOption {
            type = types.nullOr (types.either
              (types.enum [ false ])
              (types.submodule {
                options = {
                  clientId = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "OAuth client ID. If not provided, dynamic client registration (RFC 7591) is attempted.";
                  };
                  clientSecret = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "OAuth client secret (if required by the authorization server).";
                  };
                  scope = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "OAuth scopes to request during authorization.";
                  };
                };
              })
            );
            default = null;
            description = ''
              OAuth configuration for the MCP server (remote type only).
              Set to `false` to disable OAuth auto-detection.
              Set to `{ clientId = "..."; }` etc. for explicit OAuth config.
              null = omit (upstream uses auto-detection if server requires it).
            '';
          };
        };
      });
      default = { };
      description = "Custom MCP server definitions (matches OpenCode schema directly)";
    };
  };

  config = mkIf cfg.enable {
    # Merge pre-configured servers with custom servers
    # NOTE: Using if-then-else instead of mkIf because this data is JSON-serialized
    # mkIf creates lazy thunks that don't serialize properly to JSON
    programs.opencode._internal.mcpServers =
      let
        # Build pre-configured server configs using if-then-else for JSON serialization
        preConfigured =
          (if cfg.mcpServers.nixos.enable then {
            "mcp-nixos" = toOpencodeFormat (sharedMcpDefs.nixos.mkConfig {
              inherit (cfg.mcpServers.nixos) cacheTtl;
              inherit (cfg) debug;
            });
          } else { })
          // (if cfg.mcpServers.sequentialThinking.enable then {
            "sequential-thinking" = toOpencodeFormat (sharedMcpDefs.sequentialThinking.mkConfig {
              inherit (cfg.mcpServers.sequentialThinking) timeout;
              inherit (cfg) debug;
            });
          } else { })
          // (if cfg.mcpServers.context7.enable then {
            "context7" = toOpencodeFormat (sharedMcpDefs.context7.mkConfig {
              inherit (cfg) debug;
            });
          } else { })
          // (if cfg.mcpServers.serena.enable then {
            "serena" = toOpencodeFormat (sharedMcpDefs.serena.mkConfig {
              inherit (cfg.mcpServers.serena) context;
              inherit (cfg) debug;
            });
          } else { })
          // (if (cfg.mcpServers.brave.enable && cfg.mcpServers.brave.apiKey != "") then {
            "brave-search" = toOpencodeFormat (sharedMcpDefs.brave.mkConfig {
              inherit (cfg.mcpServers.brave) apiKey;
              inherit (cfg.mcpServers.brave) searchCount;
              inherit (cfg) debug;
            });
          } else { })
          // (if cfg.mcpServers.puppeteer.enable then {
            "puppeteer" = toOpencodeFormat (sharedMcpDefs.puppeteer.mkConfig {
              inherit (cfg.mcpServers.puppeteer) headless;
              inherit (cfg) debug;
            });
          } else { })
          // (if (cfg.mcpServers.github.enable && cfg.mcpServers.github.token != "") then {
            "github" = toOpencodeFormat (sharedMcpDefs.github.mkConfig {
              inherit (cfg.mcpServers.github) token;
              inherit (cfg) debug;
            });
          } else { })
          // (if cfg.mcpServers.gitlab.enable then {
            "gitlab" = toOpencodeFormat (sharedMcpDefs.gitlab.mkConfig {
              inherit (cfg.mcpServers.gitlab) url;
              inherit (cfg.mcpServers.gitlab) token;
              inherit (cfg) debug;
            });
          } else { })
          // (if cfg.mcpServers.filesystem.enable then {
            "filesystem" = toOpencodeFormat (sharedMcpDefs.filesystem.mkConfig {
              inherit (cfg.mcpServers.filesystem) allowedPaths;
              inherit (cfg) debug;
            });
          } else { })
          // (if cfg.mcpServers.cliMcpServer.enable then {
            "cli-mcp-server" = toOpencodeFormat (sharedMcpDefs.cliMcpServer.mkConfig {
              inherit (cfg.mcpServers.cliMcpServer) allowedDir;
              inherit (cfg) debug;
            });
          } else { });
      in
      preConfigured // mapAttrs cleanCustomServer cfg.mcpServers.custom;
  };
}
