# Claude Code Nix Modules

This directory contains Nix modules for configuring Claude Code with advanced features including MCP servers, slash commands, and multi-account support.

## Modules Overview

### Core Functionality
- **`mcp-servers.nix`** - MCP (Model Context Protocol) server configurations
- **`slash-commands.nix`** - Custom slash command definitions
- **`sub-agents.nix`** - Sub-agent configurations for specialized tasks
- **`hooks.nix`** - Automation hooks for pre/post actions

### Memory Commands
- **`memory-commands.nix`** - Original symlink-based implementation (deprecated)
- **`memory-commands-static.nix`** - Static wrapper implementation (current)

## The Slash Command Evolution (2025-09-01)

### The Problem
Home-manager's default behavior creates symlinks from git-tracked locations to Nix store paths. For slash commands:
```
claude-runtime/.claude-pro/commands/nixmemory.sh -> /nix/store/hash/nixmemory
```

Every `home-manager switch` generates new store paths (even with identical content), causing git to detect changes in symlink targets. This created constant, meaningless git noise.

### The Solution: Static Wrappers
We redesigned slash commands to use a two-tier architecture:

1. **Static wrapper files** (in git repo):
   ```bash
   #!/usr/bin/env bash
   exec claude-nixmemory "$@"
   ```
   These never change, eliminating git churn.

2. **PATH commands** (installed by Nix):
   ```nix
   claudeNixmemoryCmd = pkgs.writeShellApplication {
     name = "claude-nixmemory";
     # ... implementation
   };
   ```
   These update transparently via `home.packages`.

### Why This Works
- **Claude Code** just executes `.sh` files - doesn't care if they're symlinks or static files
- **Unix PATH** resolution finds the actual commands
- **Git** sees static files that never change
- **Nix** still manages and updates the implementation

### Enabling Static Commands
```nix
programs.claude-code = {
  enable = true;
  memoryCommands.enable = true;
  staticCommands.enable = true;  # Enable static wrappers
};
```

## Architecture Principles

### 1. Separation of Concerns
- **Interface** (static files in repo) vs **Implementation** (commands on PATH)
- **Configuration** (Nix modules) vs **Runtime** (Claude Code execution)

### 2. Git-Friendly Design
- Minimize files that change frequently
- Use static content where possible
- Leverage PATH for dynamic resolution

### 3. Multi-Account Support
- Each account (`claude-pro`, `claude-max`) gets its own command directory
- Commands detect account via `CLAUDE_ACCOUNT` environment variable
- Shared implementation, account-specific data

## Files and Documentation

### Implementation Files
- `memory-commands-static.nix` - Installs actual commands to PATH when staticCommands.enable = true
- `memory-commands.nix` - Creates symlink-based commands when staticCommands.enable = false
- Static wrapper files in `claude-runtime/.claude-*/commands/` - Committed to git, never change

### Documentation
- `SLASH-COMMANDS-MIGRATION.md` - Migration guide from symlinks to static wrappers
- `CONFIGURATION-COALESCENCE.md` - How Nix manages Claude Code configuration
- `../../CLAUDE.md` - Main documentation with issue tracking and solutions

## Maintenance

### Static Wrapper Files
The files in `claude-runtime/.claude-*/commands/*.sh` are now static files committed to git.
They contain simple 3-line wrappers:
```bash
#!/usr/bin/env bash
exec claude-nixmemory "$@"
```

**Important**: These files must be manually maintained if you:
- Add new slash commands
- Rename existing commands
- Add new Claude Code accounts

To regenerate them, temporarily set `staticCommands.enable = false`, rebuild, 
then manually replace symlinks with their content.

## Testing Commands

```bash
# Verify commands are installed
which claude-nixmemory
which claude-nixremember

# Test functionality
claude-nixmemory          # Opens memory file
claude-nixremember "test" # Adds to memory

# Check file types (should be regular files, not symlinks)
file claude-runtime/.claude-pro/commands/*.sh

# Verify no git changes after rebuild
home-manager switch && git status claude-runtime/
```

## Future Improvements

1. **Extend pattern** - Apply static wrapper approach to all slash commands
2. **Command discovery** - Auto-generate command list from PATH
3. **Version checking** - Ensure wrapper/command compatibility
4. **Hot reload** - Update commands without restart

## Troubleshooting

### Commands not found
```bash
# Ensure home-manager configuration includes the module
grep -r "memory-commands-static" ~/.config/home-manager/

# Check if staticCommands is enabled
nix eval '.#homeConfigurations."$USER@$HOST".config.programs.claude-code.staticCommands.enable'
```

### Git still showing changes
```bash
# Ensure you're using static implementation
ls -la claude-runtime/.claude-*/commands/*.sh
# Should show regular files, not symlinks (->)

# If still symlinks, enable static commands and rebuild
programs.claude-code.staticCommands.enable = true;
```

## Key Takeaways

The transition from symlinks to static wrappers demonstrates important Nix patterns:

1. **Not everything needs to be a symlink** - Sometimes static files with PATH-based indirection is better
2. **Git integration matters** - Design with version control in mind
3. **Simple is sustainable** - 3-line wrapper scripts are easy to understand and maintain
4. **Unix patterns are timeless** - PATH resolution has worked for 50+ years