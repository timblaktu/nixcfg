# Claude Code MCP Servers Sub-module
# Provides pre-configured MCP servers using shared definitions
# Transforms shared/mcp-server-defs.nix to Claude Code's JSON format
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;

  # Import shared MCP server definitions for DRY consistency with opencode
  sharedMcpDefs = import ../shared/mcp-server-defs.nix { inherit lib; };

  # Transform shared MCP server definition to Claude Code format
  # Claude Code uses: { command, args, env, timeout?, retries? }
  toClaudeCodeFormat = serverCfg: {
    inherit (serverCfg) command args timeout retries;
    env = (serverCfg.env or { }) // {
      DEBUG = if cfg.debug then "*" else "";
      NODE_ENV = if cfg.debug then "development" else "production";
    };
  };

  # Legacy helper for backward compatibility (servers not yet in shared defs)
  mkMcpServer =
    { command
    , args ? [ ]
    , env ? { }
    , debug ? cfg.debug
    , timeout ? 300
    , retries ? 3
    }: {
      inherit command args timeout retries;
      env = env // {
        DEBUG = if debug then "*" else "";
        NODE_ENV = if debug then "development" else "production";
      };
    };

in
{
  options.programs.claude-code.mcpServers = {
    nixos = {
      enable = mkEnableOption "NixOS package/option search server";
      cacheTtl = mkOption {
        type = types.int;
        default = 3600;
        description = "Cache TTL in seconds";
      };
    };

    # Python/UV port - kept for future development
    sequentialThinkingPython = {
      enable = mkOption {
        type = types.bool;
        default = false; # Disabled - using TypeScript version instead
        description = "Enhanced reasoning (Python/UV port)";
      };
      timeout = mkOption {
        type = types.int;
        default = 600;
        description = "Timeout in seconds";
      };
    };

    # Official TypeScript version from @modelcontextprotocol
    sequentialThinking = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enhanced reasoning (official TypeScript version)";
      };
      timeout = mkOption {
        type = types.int;
        default = 600;
        description = "Timeout in seconds";
      };
    };

    context7.enable = mkEnableOption "context7 for advanced context management";

    serena = {
      enable = mkEnableOption "Serena AI-powered project assistant and context-aware IDE helper";
      context = mkOption {
        type = types.str;
        default = "ide-assistant";
        description = "Context setting for Serena server";
      };
    };

    brave = {
      apiKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Brave Search API key";
      };
      searchCount = mkOption {
        type = types.int;
        default = 10;
        description = "Number of search results";
      };
    };

    puppeteer = {
      enable = mkEnableOption "Puppeteer for web automation";
      headless = mkOption {
        type = types.bool;
        default = true;
        description = "Run in headless mode";
      };
    };

    github = {
      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "GitHub personal access token";
      };
      defaultBranch = mkOption {
        type = types.str;
        default = "main";
        description = "Default branch name";
      };
    };

    gitlab = {
      enable = mkEnableOption "GitLab integration";
      url = mkOption {
        type = types.str;
        default = "https://gitlab.com";
        description = "GitLab instance URL";
      };
      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "GitLab access token";
      };
    };

    mcpFilesystem = {
      enable = mkEnableOption "MCP filesystem server from UV framework";
      allowedPaths = mkOption {
        type = types.listOf types.str;
        default = [ "/tmp" ];
        description = "Allowed filesystem paths";
      };
    };

    cliMcpServer = {
      enable = mkEnableOption "CLI MCP server (not needed for Claude Code, but useful for Claude Desktop)";
      allowedDir = mkOption {
        type = types.str;
        default = "/tmp";
        description = "Allowed directory for CLI operations";
      };
    };

    custom = mkOption {
      type = types.attrs;
      default = { };
      description = "Custom MCP server configurations";
    };
  };

  # Build MCP server configurations using shared definitions where available
  config.programs.claude-code._internal.mcpServers = cfg.mcpServers.custom //
    # NixOS MCP server (using shared definition)
    optionalAttrs cfg.mcpServers.nixos.enable {
      mcp-nixos = toClaudeCodeFormat (sharedMcpDefs.nixos.mkConfig {
        cacheTtl = cfg.mcpServers.nixos.cacheTtl;
        debug = cfg.debug;
      });
    } //
    # Python/UV version - uses shared definition
    optionalAttrs cfg.mcpServers.sequentialThinkingPython.enable {
      sequential-thinking-python = toClaudeCodeFormat (sharedMcpDefs.sequentialThinkingPython.mkConfig {
        timeout = cfg.mcpServers.sequentialThinkingPython.timeout;
        debug = cfg.debug;
      });
    } //
    # Official TypeScript version (using shared definition)
    optionalAttrs cfg.mcpServers.sequentialThinking.enable {
      sequential-thinking = toClaudeCodeFormat (sharedMcpDefs.sequentialThinking.mkConfig {
        timeout = cfg.mcpServers.sequentialThinking.timeout;
        debug = cfg.debug;
      });
    } //
    # Context7 (using shared definition)
    optionalAttrs cfg.mcpServers.context7.enable {
      context7 = toClaudeCodeFormat (sharedMcpDefs.context7.mkConfig {
        debug = cfg.debug;
      });
    } //
    # Serena (using shared definition)
    optionalAttrs cfg.mcpServers.serena.enable {
      serena = toClaudeCodeFormat (sharedMcpDefs.serena.mkConfig {
        context = cfg.mcpServers.serena.context;
        debug = cfg.debug;
      });
    } //
    # Brave Search (using shared definition)
    optionalAttrs (cfg.mcpServers.brave.apiKey != null) {
      brave-search = toClaudeCodeFormat (sharedMcpDefs.brave.mkConfig {
        apiKey = cfg.mcpServers.brave.apiKey;
        searchCount = cfg.mcpServers.brave.searchCount;
        debug = cfg.debug;
      });
    } //
    # Puppeteer (using shared definition)
    optionalAttrs cfg.mcpServers.puppeteer.enable {
      puppeteer = toClaudeCodeFormat (sharedMcpDefs.puppeteer.mkConfig {
        headless = cfg.mcpServers.puppeteer.headless;
        debug = cfg.debug;
      });
    } //
    # GitHub (using shared definition)
    optionalAttrs (cfg.mcpServers.github.token != null) {
      github = toClaudeCodeFormat (sharedMcpDefs.github.mkConfig {
        token = cfg.mcpServers.github.token;
        defaultBranch = cfg.mcpServers.github.defaultBranch;
        debug = cfg.debug;
      });
    } //
    # GitLab (using shared definition)
    optionalAttrs cfg.mcpServers.gitlab.enable {
      gitlab = toClaudeCodeFormat (sharedMcpDefs.gitlab.mkConfig {
        url = cfg.mcpServers.gitlab.url;
        token = cfg.mcpServers.gitlab.token;
        debug = cfg.debug;
      });
    } //
    # Filesystem (using shared definition)
    optionalAttrs cfg.mcpServers.mcpFilesystem.enable {
      mcp-filesystem = toClaudeCodeFormat (sharedMcpDefs.filesystem.mkConfig {
        allowedPaths = cfg.mcpServers.mcpFilesystem.allowedPaths;
        debug = cfg.debug;
      });
    } //
    # CLI MCP server (using shared definition)
    optionalAttrs cfg.mcpServers.cliMcpServer.enable {
      cli-mcp-server = toClaudeCodeFormat (sharedMcpDefs.cliMcpServer.mkConfig {
        allowedDir = cfg.mcpServers.cliMcpServer.allowedDir;
        debug = cfg.debug;
      });
    };
}
