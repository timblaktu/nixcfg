{ config, lib, pkgs, ... }:

{
  imports = [
    ./claude-code.nix
  ];

  # Enable Claude Code with MCP servers
  programs.claude-code = {
    enable = true;
    debug = false;

    # Enable static commands (eliminates git churn from symlinks)
    staticCommands.enable = true;

    # Enable MCP servers
    mcpServers = {
      # Enable sequential thinking - now using official TypeScript version
      sequentialThinking.enable = true; # Using @modelcontextprotocol/server-sequential-thinking via npx

      # Python/UV version disabled but preserved for future development
      sequentialThinkingPython.enable = false;

      # MCP NixOS server - using direct flake input
      nixos.enable = true; # Using built mcp-nixos package from mcp-nixos flake input

      # Enable context7 for context management
      context7.enable = true;

      # Serena AI-powered project assistant and context-aware IDE helper
      serena = {
        enable = false;
        context = "ide-assistant"; # or other context as needed
      };

      # MCP filesystem server - Claude Desktop only (not needed for Claude Code)
      mcpFilesystem.enable = true; # Using @modelcontextprotocol/server-filesystem via npx

      # CLI MCP server - Claude Desktop only (not needed for Claude Code)
      cliMcpServer.enable = true; # Using cli-mcp-server package via npx
    };

    # Enable hooks for development workflow
    hooks = {
      security.enable = true;
      formatting.enable = true;
      logging.enable = true;
    };

    # Enable sub-agents
    subAgents = {
      codeSearcher.enable = true;
    };

    # Enable slash commands
    slashCommands = {
      documentation.enable = true;
      security.enable = true;
      refactoring.enable = true;
      context.enable = true;
    };
  };
}
