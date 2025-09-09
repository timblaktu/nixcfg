# Claude Code Configuration for User

## Custom Memory Management Commands (Implemented 2025-08-21)

### Available Commands
- `/nixmemory` - Opens user-global memory file in editor (like /memory but always user-scoped)
- `/nixremember <content>` - Appends content to memory (like # command but for Nix-managed memory)

### Command Aliases
- `/usermemory` → `/nixmemory`
- `/globalmemory` → `/nixmemory`  
- `/userremember` → `/nixremember`
- `/globalremember` → `/nixremember`

### Important Notes
- These commands write to user-global CLAUDE.md file in each account directory
- Changes auto-commit to git and rebuild to propagate to all accounts
- Built-in `/memory` and `#` commands will fail on read-only files - use the /nix* versions instead
- This file is the single source of truth for all Claude Code account configurations

## AI Guidance

### ESSENTIAL PATHS
- SCREENSHOT_DIR: `/mnt/wsl/tblack-t14-nixos/mnt/c/Users/tblack/OneDrive/Pictures/Screenshots 1`

### RULES

- ALWAYS Do what has been asked; nothing more, nothing less
- NEVER create files unless necessary to do what was asked of you
- ALWAYS prefer editing existing files to creating new ones
- ALWAYS add documentation to existing markdown files instead of creating new files 
- ALWAYS think deeply about WHERE to write content when performing documentation tasks
- ALWAYS ASK where to add documentation if there is significant ambiguity or uncertainty
- ALWAYS use fd to find files and ripgrep (rg) to search files.
- NEVER include claude's identity when generating git commit messages
- ALWAYS OMIT claude's identity when generating git commit messages
- ALWAYS ensure shell commands generated for the user to run support the syntax and features of the user's $SHELL 
- ALWAYS ensure shell commands generated for the user to run are concise, use minimal comments and empty lines, and are composed into minimal number of logically-grouped compound command blocks
- ALWAYS After receiving tool results, carefully reflect on their quality and determine optimal next steps
- ALWAYS invoke multiple independent tools simultaneously, using sub-agents when available, rather than sequentially
- Before finishing, verify your solution addresses all requirements
- ALWAYS use `echo "$WSL_DISTRO_NAME"` to determine if you're running in WSL, and what WSL instance you and/or your MCP servers are running in.
- If running in WSL, you can access other WSL instances' rootfs mounted at `/mnt/wsl/$WSL_DISTRO_NAME/`
- When I ask you to "read", "view", "refer to", or "look at" screenshots, you read that most recent N image files from SCREENSHOT_DIR
- ALWAYS stage relevant changed files when in projects using nix flakes (`git add --update` + `git add <relevant-untracked-files>`)

## Active Configuration

### Model
- Default: sonnet
- Debug mode: disabled

### MCP Servers (Current Status - TEMPLATE)

- **sequential-thinking**: ✅ Status varies by deployment
- **context7**: ✅ Working - using @upstash/context7-mcp package
- **mcp-nixos**: ⚠️ Disabled - Local overlay watchfiles test failures (GitHub builds work)
- **mcp-filesystem**: ⚠️ Disabled - Local overlay watchfiles test failures (GitHub builds work)
- **cli-mcp-server**: ✅ Not needed - Claude Code has built-in CLI functionality

### Sub-Agents
- code-searcher

### Slash Commands
- /documentation generate-readme
    - /documentation api-docs
- /security audit
    - /security secrets-scan
- /refactor extract-function
    - /refactor rename-symbol
- /context cleanup
    - /context save
    - /context load

### Active Hooks
- Security checks: 
- Auto-formatting: 
- Linting: 
- Git integration: 
- Testing: 
- Logging: 
- Notifications: 

## Performance Tips

- Use sub-agents for specialized tasks to reduce token usage
- Leverage slash commands for common operations
- Enable caching where appropriate
- Use project overrides for context-specific settings

## Troubleshooting

- Check logs at: ~/.claude/logs/tool-usage.log
- Debug mode: Set `programs.claude-code.debug = true`
- MCP server issues: Check `/tmp/claude_desktop.log` and `~/AppData/Roaming/Claude/logs/`
- Hook failures: Review hook timeout settings
- MCP Documentation: See `home/modules/README-MCP.md` for detailed troubleshooting
