{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;

  mkMcpServer = {
    command,
    args ? [],
    env ? {},
    debug ? cfg.debug,
    timeout ? 300,
    retries ? 3
  }: {
    inherit command args timeout retries;
    env = env // {
      DEBUG = if debug then "*" else "";
      NODE_ENV = if debug then "development" else "production";
    };
  };

in {
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
        default = false;  # Disabled - using TypeScript version instead
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
        default = ["/tmp"];
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
      default = {};
      description = "Custom MCP server configurations";
    };
  };

  config.programs.claude-code._internal.mcpServers = cfg.mcpServers.custom //
    optionalAttrs cfg.mcpServers.nixos.enable {
      mcp-nixos = mkMcpServer {
        # Use nix run directly to avoid build dependencies
        command = "nix";
        args = ["run" "github:utensils/mcp-nixos" "--"];
        env = {
          MCP_NIXOS_CLEANUP_ORPHANS = "true";
          MCP_NIXOS_CACHE_TTL = toString cfg.mcpServers.nixos.cacheTtl;
        };
      };
    } //
    # Python/UV version - kept for future development but disabled by default
    optionalAttrs cfg.mcpServers.sequentialThinkingPython.enable {
      sequential-thinking-python = mkMcpServer {
        command = "sequential-thinking-mcp";  # Use program name, not store path
        args = [];
        timeout = cfg.mcpServers.sequentialThinkingPython.timeout;
      };
    } //
    # Official TypeScript version from @modelcontextprotocol
    optionalAttrs cfg.mcpServers.sequentialThinking.enable {
      sequential-thinking = mkMcpServer {
        command = "npx";
        args = ["-y" "@modelcontextprotocol/server-sequential-thinking"];
        timeout = cfg.mcpServers.sequentialThinking.timeout;
      };
    } //
    optionalAttrs cfg.mcpServers.context7.enable {
      context7 = mkMcpServer {
        command = "npx";
        args = ["-y" "@upstash/context7-mcp"];
      };
    } //
    optionalAttrs cfg.mcpServers.serena.enable {
      serena = mkMcpServer {
        command = "nix";
        args = ["run" "github:oraios/serena" "--" "start-mcp-server" "--transport" "stdio" "--context" cfg.mcpServers.serena.context];
      };
    } //
    optionalAttrs (cfg.mcpServers.brave.apiKey != null) {
      brave-search = mkMcpServer {
        command = "npx";
        args = ["-y" "@modelcontextprotocol/server-brave-search"];
        env = {
          BRAVE_API_KEY = cfg.mcpServers.brave.apiKey;
          BRAVE_SEARCH_COUNT = toString cfg.mcpServers.brave.searchCount;
        };
      };
    } //
    optionalAttrs cfg.mcpServers.puppeteer.enable {
      puppeteer = mkMcpServer {
        command = "npx";
        args = ["-y" "@modelcontextprotocol/server-puppeteer"];
        env.PUPPETEER_HEADLESS = toString cfg.mcpServers.puppeteer.headless;
      };
    } //
    optionalAttrs (cfg.mcpServers.github.token != null) {
      github = mkMcpServer {
        command = "npx";
        args = ["-y" "@modelcontextprotocol/server-github"];
        env = {
          GITHUB_PERSONAL_ACCESS_TOKEN = cfg.mcpServers.github.token;
          GITHUB_DEFAULT_BRANCH = cfg.mcpServers.github.defaultBranch;
        };
      };
    } //
    optionalAttrs cfg.mcpServers.gitlab.enable {
      gitlab = mkMcpServer {
        command = "npx";
        args = ["-y" "@modelcontextprotocol/server-gitlab"];
        env = { GITLAB_URL = cfg.mcpServers.gitlab.url; } //
              optionalAttrs (cfg.mcpServers.gitlab.token != null) {
                GITLAB_TOKEN = cfg.mcpServers.gitlab.token;
              };
      };
    } //
    optionalAttrs cfg.mcpServers.mcpFilesystem.enable {
      mcp-filesystem = mkMcpServer {
        command = "npx";
        args = ["-y" "@modelcontextprotocol/server-filesystem"] ++ cfg.mcpServers.mcpFilesystem.allowedPaths;
      };
    } //
    optionalAttrs cfg.mcpServers.cliMcpServer.enable {
      cli-mcp-server = mkMcpServer {
        command = "nix";
        args = ["run" "--accept-flake-config" "github:timblaktu/cli-mcp-server" "--"];
        env = {
          ALLOWED_DIR = cfg.mcpServers.cliMcpServer.allowedDir;
        };
      };
    };
}
