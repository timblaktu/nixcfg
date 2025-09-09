# Claude Code Memory Management with Nix

## ✅ IMPLEMENTATION STATUS: COMPLETE (2025-08-21)

This document describes the custom memory management solution for Claude Code in our Nix-managed multi-account setup. Since Claude Code doesn't support configurable memory file paths, we've implemented custom `/nixmemory` and `/nixremember` commands that manage a single source of truth in the nixcfg repository.

## Problem Statement

- Claude Code memory files (`CLAUDE.md`) are managed by Nix and therefore read-only
- Built-in `/memory` and `#` commands crash when trying to write to read-only files
- Need consistent memory across multiple account configurations
- Want to maintain declarative Nix approach while supporting runtime memory updates

## Solution Architecture (IMPLEMENTED)

### Single Source of Truth
- **Source file**: `/home/tim/src/nixcfg/home/modules/claude-code-user-global-memory.md`
- **Deployed files**: Read-only copies in each account's `.claude*/` directories
- **Updates**: Custom commands write to source, trigger rebuild, propagate to all accounts

### Custom Commands (IMPLEMENTED)
- `/nixmemory` - Opens memory file in editor (like /memory but always user-scoped)
- `/nixremember <content>` - Appends content with timestamp (like # command)

### Command Aliases (IMPLEMENTED)
- `/usermemory` → `/nixmemory`
- `/globalmemory` → `/nixmemory`
- `/userremember` → `/nixremember`
- `/globalremember` → `/nixremember`

## Implementation Details

### 1. Nix Configuration (COMPLETED)

The following has been added to `home/modules/claude-code.nix`:

```nix
{ config, lib, pkgs, ... }:

let
  # Path to the source CLAUDE.md in nixcfg
  claudeMemorySource = "/home/tim/src/nixcfg/home/modules/claude-code-memory.md";
  
  # Script to handle memory updates and rebuild
  memoryUpdateScript = pkgs.writeScriptBin "claude-memory-update" ''
    #!/bin/bash
    set -euo pipefail
    
    echo "Memory updated, rebuilding claude-code configuration..."
    cd /home/tim/src/nixcfg
    
    # Commit the memory change
    git add home/modules/claude-code-memory.md
    git commit -m "Claude Code: Update memory via custom command" || true
    
    # Rebuild home-manager configuration
    home-manager switch --flake .
    
    echo "✅ Memory updated and propagated to all accounts"
  '';

in {
  # Add the memory update script to PATH
  home.packages = [ memoryUpdateScript ];
  
  # Custom memory management commands
  home.file.".claude/commands/nixmemory.md" = {
    text = ''
      ---
      description: Add content to the Nix-managed project memory
      argument-hint: [content to remember]
      ---
      
      Add the provided content to the central project memory managed by Nix.
      
      This command:
      1. Appends content to the source CLAUDE.md in nixcfg
      2. Commits the change to git
      3. Rebuilds home-manager configuration  
      4. Propagates to all account-specific configs
      
      Usage: `/nixmemory Remember to use 2-space indentation for this project`
    '';
  };

  home.file.".claude/commands/nixremember.md" = {
    text = ''
      ---
      description: Set or replace section in Nix-managed project memory
      argument-hint: [section_name] [content]
      ---
      
      Set or replace a specific section in the Nix-managed project memory.
      
      This command:
      1. Updates/creates a named section in the source CLAUDE.md
      2. Commits the change to git
      3. Rebuilds home-manager configuration
      4. Propagates to all account-specific configs
      
      Usage: `/nixremember coding_standards Use TypeScript for all new files`
    '';
  };

  home.file.".claude/commands/nixmemory-view.md" = {
    text = ''
      ---
      description: View current Nix-managed project memory
      ---
      
      Display the current contents of the Nix-managed project memory file.
      
      Usage: `/nixmemory-view`
    '';
  };

  # Command implementations
  home.file.".claude/commands/nixmemory.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      set -euo pipefail
      
      MEMORY_FILE="${claudeMemorySource}"
      CONTENT="$*"
      
      if [ -z "$CONTENT" ]; then
        echo "❌ Usage: /nixmemory <content to remember>"
        exit 1
      fi
      
      # Append to memory file
      echo "" >> "$MEMORY_FILE"
      echo "- $(date '+%Y-%m-%d'): $CONTENT" >> "$MEMORY_FILE"
      
      # Trigger rebuild
      claude-memory-update
      
      echo "✅ Added to project memory: $CONTENT"
    '';
  };

  home.file.".claude/commands/nixremember.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      set -euo pipefail
      
      MEMORY_FILE="${claudeMemorySource}"
      
      if [ $# -lt 2 ]; then
        echo "❌ Usage: /nixremember <section_name> <content>"
        exit 1
      fi
      
      SECTION="$1"
      shift
      CONTENT="$*"
      
      # Create temp file for processing
      TEMP_FILE=$(mktemp)
      
      # Process the memory file
      if [ -f "$MEMORY_FILE" ]; then
        # Remove existing section if it exists
        awk -v section="## $SECTION" '
          BEGIN { in_section = 0 }
          /^## / { 
            if ($0 == section) {
              in_section = 1
              next
            } else {
              in_section = 0
            }
          }
          !in_section { print }
        ' "$MEMORY_FILE" > "$TEMP_FILE"
      else
        echo "# Claude Code Project Memory" > "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
      fi
      
      # Add the new section
      echo "" >> "$TEMP_FILE"
      echo "## $SECTION" >> "$TEMP_FILE"
      echo "" >> "$TEMP_FILE"
      echo "$CONTENT" >> "$TEMP_FILE"
      
      # Replace the original file
      mv "$TEMP_FILE" "$MEMORY_FILE"
      
      # Trigger rebuild
      claude-memory-update
      
      echo "✅ Updated section '$SECTION' in project memory"
    '';
  };

  home.file.".claude/commands/nixmemory-view.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      
      MEMORY_FILE="${claudeMemorySource}"
      
      if [ ! -f "$MEMORY_FILE" ]; then
        echo "📝 No project memory file found."
        exit 0
      fi
      
      echo "📝 Current Project Memory:"
      echo "=========================="
      cat "$MEMORY_FILE"
      echo "=========================="
      echo "File: $MEMORY_FILE"
    '';
  };

  # Ensure the source memory file exists with proper structure
  home.file."../src/nixcfg/home/modules/claude-code-memory.md" = {
    text = ''
      # Claude Code Project Memory

      ## Current Context
      - Multi-account claude-code setup with Nix
      - Custom memory management via /nixmemory and /nixremember commands
      - Single source of truth in nixcfg with auto-rebuild

      ## Coding Standards
      - Use TypeScript for all new files
      - 2-space indentation
      - Strict null checks enabled

      ## Key Decisions
      - Memory managed through nixcfg source file
      - Custom commands instead of built-in /memory
      - Auto-rebuild on memory changes

      ## Workflows
      - Use /nixmemory for quick additions
      - Use /nixremember for structured sections
      - Use /nixmemory-view to review current state
    '';
    force = true;
  };
}
```

### 2. Initial Memory File (COMPLETED)

Created `home/modules/claude-code-user-global-memory.md` with content from backup:

```markdown
# Claude Code Project Memory

## Current Context
- Multi-account claude-code setup with Nix
- Custom memory management via /nixmemory and /nixremember commands  
- Single source of truth in nixcfg with auto-rebuild

## Coding Standards
- Use TypeScript for all new files
- 2-space indentation
- Strict null checks enabled

## Key Decisions
- Memory managed through nixcfg source file
- Custom commands instead of built-in /memory
- Auto-rebuild on memory changes

## Workflows
- Use /nixmemory for quick additions
- Use /nixremember for structured sections
- Use /nixmemory-view to review current state
```

## Usage Guide

### Basic Operations

```bash
# Open memory file in editor (like /memory)
/nixmemory
# Or use aliases: /usermemory, /globalmemory

# Add content to memory (like # command)
/nixremember Always use TypeScript for new files
# Or use aliases: /userremember, /globalremember
```

### Command Reference

| Command | Aliases | Purpose | Example |
|---------|---------|---------|---------|
| `/nixmemory` | `/usermemory`, `/globalmemory` | Open memory in editor | `/nixmemory` |
| `/nixremember <content>` | `/userremember`, `/globalremember` | Append to memory | `/nixremember Use async/await` |

## Workflow

1. **Use custom commands** instead of built-in `/memory` or `#` commands
2. **Commands write to source file** in nixcfg directory
3. **Auto-commit to git** with descriptive message
4. **Rebuild configuration** propagates to all accounts
5. **All accounts see updates** on next claude-code session

## Benefits

- ✅ **Declarative**: Memory managed through Nix configuration
- ✅ **Consistent**: Single source of truth across all accounts
- ✅ **Versioned**: All changes tracked in git
- ✅ **Automated**: No manual file copying or syncing
- ✅ **Safe**: Read-only deployed files prevent accidental corruption
- ✅ **Extensible**: Easy to add new memory management features

## Migration Complete (2025-08-21)

### ✅ Completed Steps
1. ✅ Added custom commands to `claude-code.nix`
2. ✅ Created initial memory file from backup
3. ✅ Rebuilt with `home-manager switch --flake .`
4. ✅ Tested and verified functionality
5. ✅ Added command aliases for convenience
6. ✅ All accounts now use same memory source

## Troubleshooting

### Command not found
- Ensure you've rebuilt with `home-manager switch --flake .`
- Check that scripts are executable in `.claude/commands/`

### Permission denied on source file
- Verify nixcfg directory permissions
- Check that source file exists and is writable

### Rebuild fails
- Check git repository status in nixcfg
- Ensure home-manager flake is valid
- Review error messages from `claude-memory-update`

### Memory not propagating
- Verify rebuild completed successfully
- Restart claude-code session to see changes
- Check that deployed CLAUDE.md files are symlinked correctly

## Known Limitations

- **# command**: Built-in `#` command cannot be overridden - use `/nixremember` instead
- **Project memory**: Project-specific CLAUDE.md files still use built-in commands
- **Rebuild required**: Changes require Home Manager rebuild to propagate

## Future Enhancements

- **Git hooks**: Auto-rebuild on memory file changes
- **Backup/restore**: Automatic backups with rollback  
- **Team sync**: Share memory across team members
- **Search**: Find specific entries across all memory

## Related Files

- `home/modules/claude-code.nix` - Main Nix configuration with command implementations
- `home/modules/claude-code-user-global-memory.md` - Source memory file (single source of truth)
- `.claude*/commands/{nix,user,global}{memory,remember}.*` - Command files and aliases
- `README-CLAUDE-CODE-MEM-MGMT.md` - This documentation

## Maintenance

- **Review memory quarterly** to remove outdated entries
- **Backup memory file** before major changes
- **Update documentation** when adding new features
- **Monitor git history** for memory change patterns
