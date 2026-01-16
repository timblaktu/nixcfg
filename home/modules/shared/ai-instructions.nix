# Shared AI instruction content for claude-code and opencode modules
# This provides DRY base rules that both tools share, with tool-specific additions
{ lib, ... }:

with lib;

{
  # Base rules that apply to both Claude Code and OpenCode
  # These are tool-agnostic instructions for AI coding assistants
  baseRules = ''
    ## ESSENTIAL RULES

    - ALWAYS Do what has been asked; nothing more, nothing less
    - NEVER create files unless necessary to do what was asked of you
    - ALWAYS prefer editing existing files to creating new ones
    - ALWAYS add documentation to existing markdown files instead of creating new files
    - ALWAYS think deeply about WHERE to write content when performing documentation tasks
    - ALWAYS ASK where to add documentation if there is significant ambiguity or uncertainty
    - ALWAYS use fd to find files and ripgrep (rg) to search files
    - ALWAYS ensure shell commands generated support both bash and zsh syntax
    - ALWAYS ensure shell commands are concise, use minimal comments and empty lines
    - Before finishing, verify your solution addresses all requirements
    - After receiving tool results, carefully reflect on their quality and determine optimal next steps
    - ALWAYS invoke multiple independent tools simultaneously rather than sequentially
  '';

  # Git commit rules shared by both tools
  gitCommitRules = ''
    ## Git Commit Rules

    - NEVER include AI identity in commit messages
    - Do NOT add "Generated with Claude Code" or "Co-Authored-By: Claude" footers
    - Do NOT add "Generated with OpenCode" or similar AI attribution
    - Write commit messages as if authored by the human user
    - Keep commit messages concise and focused on the technical changes
  '';

  # WSL-specific rules (when running in WSL environment)
  wslRules = ''
    ## WSL Environment

    - ALWAYS use `echo "$WSL_DISTRO_NAME"` to determine if running in WSL
    - If running in WSL, access other instances' rootfs at `/mnt/wsl/$WSL_DISTRO_NAME/`
  '';

  # Screenshot/image handling (shared path configuration)
  mkScreenshotRules = screenshotDir: ''
    ## Screenshots

    - When asked to "read", "view", "refer to", or "look at" screenshots, read the most recent N image files from: ${screenshotDir}
  '';

  # Git staging rules for Nix flake projects
  nixFlakeGitRules = ''
    ## Nix Flake Projects

    - ALWAYS stage relevant changed files (`git add --update` + `git add <relevant-untracked-files>`)
  '';

  # MCP server status formatting function
  # Takes a list of { name, status, note } records and formats them for markdown
  formatMcpStatus = servers:
    let
      statusIcon = status:
        if status == "enabled" then "+"
        else if status == "disabled" then "-"
        else if status == "conditional" then "?"
        else "?";
      formatServer = server:
        "- **${server.name}**: ${statusIcon server.status} ${server.note or ""}";
    in
    ''
      ### MCP Servers (Current Status)

      ${concatStringsSep "\n" (map formatServer servers)}
    '';

  # Generate full memory content for a tool
  # Arguments:
  #   toolName: "Claude Code" or "OpenCode"
  #   config: tool configuration (for MCP status, etc.)
  #   extraContent: tool-specific additional content
  mkMemoryContent = { toolName, screenshotDir ? null, mcpServers ? [ ], extraContent ? "" }:
    let
      baseContent = ''
        # ${toolName} Configuration for User

        ${baseRules}

        ${gitCommitRules}

        ${wslRules}

        ${optionalString (screenshotDir != null) (mkScreenshotRules screenshotDir)}

        ${nixFlakeGitRules}

        ${optionalString (mcpServers != []) (formatMcpStatus mcpServers)}

        ${extraContent}
      '';
    in
    baseContent;
}
