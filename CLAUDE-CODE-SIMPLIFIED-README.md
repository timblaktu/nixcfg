# Claude Code Simplified Configuration

## Overview

This simplified Claude Code configuration uses a pure `mkOutOfStoreSymlink` approach to manage entire `.claude-*` directories as writable locations within your nixcfg repository, while maintaining full Nix declarative management.

## Key Features

- **Pure mkOutOfStoreSymlink**: Entire config directories symlinked to nixcfg
- **Configurable Repository Path**: No hardcoded paths, works anywhere
- **Multi-Account Support**: Separate configs with different models per account
- **Runtime + Nix Coexistence**: Writable runtime data alongside Nix templates
- **Automatic Templates**: Configuration files generated from Nix on first use

## Configuration

### Basic Setup

```nix
programs.claude-code = {
  enable = true;
  defaultModel = "sonnet";
  
  accounts = {
    pro = {
      enable = true;
      displayName = "Claude Pro Account";
      model = "opus";
      aliases = ["claudepro" "cp"];
    };
    max = {
      enable = true;
      displayName = "Claude Max Account";
      model = "sonnet";
      aliases = ["claudemax" "cm"];
    };
  };
  
  defaultAccount = "pro";
};
```

### Custom Repository Path

If your nixcfg repository is not at `~/src/nixcfg`, configure the path:

```nix
programs.claude-code = {
  enable = true;
  nixcfgPath = "/path/to/your/nix-config";  # Custom path
  # ... rest of config
};
```

## Directory Structure

```
nixcfg/
├── claude-runtime/                    # Git-trackable runtime data
│   ├── .claude-pro/
│   │   ├── .claude.json              # ✅ Writable runtime data
│   │   ├── .credentials.json         # ✅ Writable auth tokens
│   │   ├── settings.json             # ✅ Nix-generated templates
│   │   ├── mcp.json                  # ✅ Nix-generated MCP config
│   │   ├── CLAUDE.md                 # ✅ Nix-generated memory
│   │   └── projects/, todos/, logs/  # ✅ Writable directories
│   ├── .claude-max/                  # Same structure
│   └── .claude/                      # Base configuration
└── home/modules/claude-code.nix       # ✅ Simplified Nix module
```

## Usage

### Account Commands

```bash
# Use Claude Pro account
claude-pro

# Use Claude Max account  
claude-max

# Use aliases
claudepro
cp

# Default account (if configured)
claude
```

### Memory Management

```bash
# Edit user-global memory
/nixmemory

# Add to memory
/nixremember "Use TypeScript for new files"

# Aliases also work
/usermemory
/globalmemory
/userremember "content"
/globalremember "content"
```

## Benefits

### For Users
- **Simple**: Single symlink pattern for all accounts
- **Portable**: No hardcoded paths, works with any repo location
- **Flexible**: Easy to add new accounts or customize paths
- **Familiar**: Normal Claude Code usage with multi-account support

### For Developers  
- **Maintainable**: Clean, single-pattern implementation
- **Extensible**: Easy to add new template types or accounts
- **Debuggable**: Clear separation of Nix vs runtime data
- **Version Controlled**: Runtime data can be tracked in git

## Migration

If moving your nixcfg repository:

1. **Update configuration**:
   ```nix
   programs.claude-code.nixcfgPath = "/new/path/to/nixcfg";
   ```

2. **Move runtime data**:
   ```bash
   mv /old/path/nixcfg/claude-runtime /new/path/nixcfg/
   ```

3. **Rebuild**:
   ```bash
   nix run home-manager -- switch --flake .
   ```

The configuration automatically adapts to the new location without any hardcoded path issues.

## Technical Details

- **Path Resolution**: Uses `programs.claude-code.nixcfgPath` option
- **Template Generation**: Activation script populates configs on first use  
- **Symlink Chain**: `~/.claude-pro -> nix-store -> nixcfg/claude-runtime/.claude-pro`
- **Data Separation**: Runtime data writable, templates read from Nix store
- **Multi-Account**: Each account gets isolated runtime directory

This approach provides the perfect balance of Nix declarative management with Claude Code's runtime requirements.