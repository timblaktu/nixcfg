# Shared MCP server definitions for claude-code and opencode modules
# This provides canonical server definitions that both tools transform to their format
{ lib, ... }:

with lib;

rec {
  # Helper to create a canonical MCP server definition
  # This is tool-agnostic; per-tool modules transform to their JSON format
  mkMcpServer =
    { command
    , args ? [ ]
    , env ? { }
    , type ? "stdio"
    , # stdio, sse, or streamable-http (for opencode)
      timeout ? 300
    , retries ? 3
    , description ? ""
    ,
    }: {
      inherit command args env type timeout retries description;
    };

  # =============================================================================
  # CANONICAL MCP SERVER DEFINITIONS
  # =============================================================================
  # These are the shared definitions. Each tool's mcp-servers.nix transforms
  # these to the appropriate JSON format.

  # NixOS package/option search server
  nixos = {
    mkConfig = { cacheTtl ? 3600, debug ? false }: mkMcpServer {
      command = "nix";
      args = [ "run" "github:utensils/mcp-nixos" "--" ];
      env = {
        MCP_NIXOS_CLEANUP_ORPHANS = "true";
        MCP_NIXOS_CACHE_TTL = toString cacheTtl;
      } // optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "NixOS package and option search";
    };
  };

  # Sequential thinking - TypeScript version (official @modelcontextprotocol)
  sequentialThinking = {
    mkConfig = { timeout ? 600, debug ? false }: mkMcpServer {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-sequential-thinking" ];
      inherit timeout;
      env = optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "Enhanced reasoning via sequential thinking";
    };
  };

  # Sequential thinking - Python/UV version (for future development)
  sequentialThinkingPython = {
    mkConfig = { timeout ? 600, debug ? false }: mkMcpServer {
      command = "sequential-thinking-mcp"; # Requires wrapper script
      args = [ ];
      inherit timeout;
      env = optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "Enhanced reasoning (Python/UV port)";
    };
  };

  # Context7 - advanced context management
  context7 = {
    mkConfig = { debug ? false }: mkMcpServer {
      command = "npx";
      args = [ "-y" "@upstash/context7-mcp" ];
      env = optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "Advanced context management via Context7";
    };
  };

  # Serena - AI-powered project assistant
  serena = {
    mkConfig = { context ? "ide-assistant", debug ? false }: mkMcpServer {
      command = "nix";
      args = [ "run" "github:oraios/serena" "--" "start-mcp-server" "--transport" "stdio" "--context" context ];
      env = optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "AI-powered project assistant and context-aware IDE helper";
    };
  };

  # Brave Search
  brave = {
    mkConfig = { apiKey, searchCount ? 10, debug ? false }: mkMcpServer {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-brave-search" ];
      env = {
        BRAVE_API_KEY = apiKey;
        BRAVE_SEARCH_COUNT = toString searchCount;
      } // optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "Brave Search integration";
    };
  };

  # Puppeteer - web automation
  puppeteer = {
    mkConfig = { headless ? true, debug ? false }: mkMcpServer {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-puppeteer" ];
      env = {
        PUPPETEER_HEADLESS = toString headless;
      } // optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "Web automation via Puppeteer";
    };
  };

  # GitHub integration
  github = {
    mkConfig = { token, defaultBranch ? "main", debug ? false }: mkMcpServer {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-github" ];
      env = {
        GITHUB_PERSONAL_ACCESS_TOKEN = token;
        GITHUB_DEFAULT_BRANCH = defaultBranch;
      } // optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "GitHub repository integration";
    };
  };

  # GitLab integration
  gitlab = {
    mkConfig = { url ? "https://gitlab.com", token ? null, debug ? false }: mkMcpServer {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-gitlab" ];
      env = {
        GITLAB_URL = url;
      } // optionalAttrs (token != null) {
        GITLAB_TOKEN = token;
      } // optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "GitLab repository integration";
    };
  };

  # Filesystem server
  filesystem = {
    mkConfig = { allowedPaths ? [ "/tmp" ], debug ? false }: mkMcpServer {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-filesystem" ] ++ allowedPaths;
      env = optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "MCP filesystem server";
    };
  };

  # CLI MCP server
  cliMcpServer = {
    mkConfig = { allowedDir ? "/tmp", debug ? false }: mkMcpServer {
      command = "nix";
      args = [ "run" "--accept-flake-config" "github:timblaktu/cli-mcp-server" "--" ];
      env = {
        ALLOWED_DIR = allowedDir;
      } // optionalAttrs debug {
        DEBUG = "*";
        NODE_ENV = "development";
      };
      description = "CLI operations server (useful for Claude Desktop)";
    };
  };

  # =============================================================================
  # TRANSFORMATION HELPERS
  # =============================================================================
  # These help per-tool modules transform canonical defs to their JSON format

  # Transform canonical server config to Claude Code JSON format
  # Claude Code uses: { command, args, env, timeout?, retries? }
  toClaudeCodeFormat = name: serverCfg: {
    inherit (serverCfg) command args timeout retries;
    env = serverCfg.env // {
      # Claude Code always adds these debug flags from cfg.debug
    };
  };

  # Transform canonical server config to OpenCode JSON format
  # OpenCode uses: { type, command, args, env? }
  toOpenCodeFormat = name: serverCfg: {
    inherit (serverCfg) type command args;
  } // optionalAttrs (serverCfg.env != { }) {
    env = serverCfg.env;
  };
}
