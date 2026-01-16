# OpenCode MCP Servers Sub-module
# Provides pre-configured MCP servers using shared definitions
# Transforms shared/mcp-server-defs.nix to OpenCode's JSON format
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.opencode;
  sharedMcpDefs = import ../shared/mcp-server-defs.nix { inherit lib; };

  # Transform shared MCP server definition to OpenCode format
  # OpenCode uses: { type = "local"; command = [...]; environment = {}; }
  toOpencodeFormat = serverCfg: {
    type = "local";
    command =
      if serverCfg.command == "npx" then
        [ "npx" ] ++ serverCfg.args
      else if serverCfg.command == "nix" then
        [ "nix" ] ++ serverCfg.args
      else
        [ serverCfg.command ] ++ (serverCfg.args or [ ]);
    enable = true;
  } // optionalAttrs (serverCfg.env or { } != { }) {
    environment = serverCfg.env;
  } // optionalAttrs (serverCfg.timeout or null != null) {
    timeout = serverCfg.timeout * 1000; # Convert seconds to milliseconds
  };

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

    # Custom servers (raw configuration)
    custom = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
          };
          type = mkOption {
            type = types.enum [ "local" "remote" ];
            default = "local";
          };
          command = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          url = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          environment = mkOption {
            type = types.attrsOf types.str;
            default = { };
          };
          headers = mkOption {
            type = types.attrsOf types.str;
            default = { };
          };
          timeout = mkOption {
            type = types.nullOr types.int;
            default = null;
          };
        };
      });
      default = { };
      description = "Custom MCP server definitions";
    };
  };

  config = mkIf cfg.enable {
    # Merge pre-configured servers with custom servers
    programs.opencode._internal.mcpServers =
      let
        # Build pre-configured server configs
        preConfigured = {
          "mcp-nixos" = mkIf cfg.mcpServers.nixos.enable
            (toOpencodeFormat (sharedMcpDefs.nixos.mkConfig {
              cacheTtl = cfg.mcpServers.nixos.cacheTtl;
              debug = cfg.debug;
            }));

          "sequential-thinking" = mkIf cfg.mcpServers.sequentialThinking.enable
            (toOpencodeFormat (sharedMcpDefs.sequentialThinking.mkConfig {
              timeout = cfg.mcpServers.sequentialThinking.timeout;
              debug = cfg.debug;
            }));

          "context7" = mkIf cfg.mcpServers.context7.enable
            (toOpencodeFormat (sharedMcpDefs.context7.mkConfig {
              debug = cfg.debug;
            }));

          "serena" = mkIf cfg.mcpServers.serena.enable
            (toOpencodeFormat (sharedMcpDefs.serena.mkConfig {
              context = cfg.mcpServers.serena.context;
              debug = cfg.debug;
            }));

          "brave-search" = mkIf (cfg.mcpServers.brave.enable && cfg.mcpServers.brave.apiKey != "")
            (toOpencodeFormat (sharedMcpDefs.brave.mkConfig {
              apiKey = cfg.mcpServers.brave.apiKey;
              searchCount = cfg.mcpServers.brave.searchCount;
              debug = cfg.debug;
            }));

          "puppeteer" = mkIf cfg.mcpServers.puppeteer.enable
            (toOpencodeFormat (sharedMcpDefs.puppeteer.mkConfig {
              headless = cfg.mcpServers.puppeteer.headless;
              debug = cfg.debug;
            }));

          "github" = mkIf (cfg.mcpServers.github.enable && cfg.mcpServers.github.token != "")
            (toOpencodeFormat (sharedMcpDefs.github.mkConfig {
              token = cfg.mcpServers.github.token;
              debug = cfg.debug;
            }));

          "gitlab" = mkIf cfg.mcpServers.gitlab.enable
            (toOpencodeFormat (sharedMcpDefs.gitlab.mkConfig {
              url = cfg.mcpServers.gitlab.url;
              token = cfg.mcpServers.gitlab.token;
              debug = cfg.debug;
            }));

          "filesystem" = mkIf cfg.mcpServers.filesystem.enable
            (toOpencodeFormat (sharedMcpDefs.filesystem.mkConfig {
              allowedPaths = cfg.mcpServers.filesystem.allowedPaths;
              debug = cfg.debug;
            }));
        };

        # Filter out disabled servers and merge with custom
        enabledPreConfigured = filterAttrs (n: v: v != false && v != null) preConfigured;
      in
      enabledPreConfigured // cfg.mcpServers.custom;
  };
}
