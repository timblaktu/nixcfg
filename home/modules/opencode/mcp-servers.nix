# OpenCode MCP Servers Sub-module
# Provides pre-configured MCP servers using shared definitions
# Transforms shared/mcp-server-defs.nix to OpenCode's JSON format
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.opencode-enhanced;
  sharedMcpDefs = import ../shared/mcp-server-defs.nix { inherit lib; };

  # Transform shared MCP server definition to OpenCode format
  # OpenCode uses: { type = "local"; command = [...]; environment = {}; enabled = true; }
  # NOTE: OpenCode uses "enabled" (with 'd'), not "enable"
  # NOTE: OpenCode doesn't support "timeout" at server level
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

in
{
  options.programs.opencode-enhanced.mcpServers = {
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

    # Custom servers (raw configuration matching OpenCode schema)
    custom = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enabled = mkOption {
            type = types.bool;
            default = true;
            description = "Whether this server is enabled";
          };
          type = mkOption {
            type = types.enum [ "local" "remote" ];
            default = "local";
            description = "Server type: local (command) or remote (url)";
          };
          command = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Command to start local server";
          };
          url = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "URL for remote server";
          };
          environment = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Environment variables for the server";
          };
          headers = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "HTTP headers for remote server";
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
    programs.opencode-enhanced._internal.mcpServers =
      let
        # Build pre-configured server configs using if-then-else for JSON serialization
        preConfigured =
          (if cfg.mcpServers.nixos.enable then {
            "mcp-nixos" = toOpencodeFormat (sharedMcpDefs.nixos.mkConfig {
              cacheTtl = cfg.mcpServers.nixos.cacheTtl;
              debug = cfg.debug;
            });
          } else { })
          // (if cfg.mcpServers.sequentialThinking.enable then {
            "sequential-thinking" = toOpencodeFormat (sharedMcpDefs.sequentialThinking.mkConfig {
              timeout = cfg.mcpServers.sequentialThinking.timeout;
              debug = cfg.debug;
            });
          } else { })
          // (if cfg.mcpServers.context7.enable then {
            "context7" = toOpencodeFormat (sharedMcpDefs.context7.mkConfig {
              debug = cfg.debug;
            });
          } else { })
          // (if cfg.mcpServers.serena.enable then {
            "serena" = toOpencodeFormat (sharedMcpDefs.serena.mkConfig {
              context = cfg.mcpServers.serena.context;
              debug = cfg.debug;
            });
          } else { })
          // (if (cfg.mcpServers.brave.enable && cfg.mcpServers.brave.apiKey != "") then {
            "brave-search" = toOpencodeFormat (sharedMcpDefs.brave.mkConfig {
              apiKey = cfg.mcpServers.brave.apiKey;
              searchCount = cfg.mcpServers.brave.searchCount;
              debug = cfg.debug;
            });
          } else { })
          // (if cfg.mcpServers.puppeteer.enable then {
            "puppeteer" = toOpencodeFormat (sharedMcpDefs.puppeteer.mkConfig {
              headless = cfg.mcpServers.puppeteer.headless;
              debug = cfg.debug;
            });
          } else { })
          // (if (cfg.mcpServers.github.enable && cfg.mcpServers.github.token != "") then {
            "github" = toOpencodeFormat (sharedMcpDefs.github.mkConfig {
              token = cfg.mcpServers.github.token;
              debug = cfg.debug;
            });
          } else { })
          // (if cfg.mcpServers.gitlab.enable then {
            "gitlab" = toOpencodeFormat (sharedMcpDefs.gitlab.mkConfig {
              url = cfg.mcpServers.gitlab.url;
              token = cfg.mcpServers.gitlab.token;
              debug = cfg.debug;
            });
          } else { })
          // (if cfg.mcpServers.filesystem.enable then {
            "filesystem" = toOpencodeFormat (sharedMcpDefs.filesystem.mkConfig {
              allowedPaths = cfg.mcpServers.filesystem.allowedPaths;
              debug = cfg.debug;
            });
          } else { });
      in
      preConfigured // cfg.mcpServers.custom;
  };
}
