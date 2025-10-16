# Yazi File Manager Configuration Documentation

This document describes the yazi file manager configuration managed by Home Manager in this nixcfg repository.

## 🔧 Linemode Plugin Resolution (2025-10-15)

### Critical Architecture Understanding: Components vs Plugins

**Problem Resolved**: Custom linemode functions cannot be implemented as separate plugin files (*.yazi directories) because linemode functions are **components**, not plugins.

**Key Insight**: Yazi has two distinct extension mechanisms:
1. **Plugins** (*.yazi directories): For previewers, seekers, and external tools
2. **Components**: Built-in objects that can be extended via `init.lua`

### Solution Architecture

**Implementation Pattern**:
- **Linemode functions** extend the built-in `Linemode` object
- **Must be defined** in `init.lua`, NOT as separate plugin files
- **Configuration via** `programs.yazi.initLua` option in Home Manager

### Current Implementation

#### File Structure
```
home/
├── modules/base.nix              # Yazi configuration
└── files/yazi-init.lua          # Custom linemode functions
```

#### Configuration (`home/modules/base.nix`)
```nix
programs.yazi = {
  enable = true;
  enableZshIntegration = true;
  plugins = {
    # Real plugins (previewers, seekers, tools)
    toggle-pane = pkgs.yaziPlugins.toggle-pane;
    mediainfo = pkgs.yaziPlugins.mediainfo;
    glow = pkgs.yaziPlugins.glow;
    miller = pkgs.yaziPlugins.miller;
    ouch = pkgs.yaziPlugins.ouch;
  };
  initLua = ../files/yazi-init.lua;  # Component extensions
  settings = {
    mgr = {
      linemode = "compact_meta";     # Use custom linemode
      ratio = [ 1 2 5 ];
      show_hidden = true;
      show_symlink = true;
    };
  };
};
```

#### Custom Linemode Function (`home/files/yazi-init.lua`)
```lua
-- Compact metadata linemode for Yazi
-- Displays: [size] [mtime] [permissions] in exactly 20 characters
function Linemode:compact_meta()
  local file = self._file
  
  -- Size formatting (6 chars): "999.9M", "  123K", "    45"
  -- Mtime formatting (10 chars): "MMDDHHMMSS" 
  -- Permissions (4 chars): "0755"
  
  return string.format("%s %s %s", size_str, mtime_str, perm_str)
end
```

### Technical Features

#### Fixed-Width Design
- **Total width**: Exactly 20 characters for consistent alignment
- **Size column**: 6 characters with smart unit conversion (B/K/M/G/T/P)
- **Time column**: 10 characters in MMDDHHMMSS format
- **Permissions**: 4 characters in octal format (0755, 0644, etc.)

#### Smart Size Formatting
```lua
-- Automatic unit conversion with appropriate decimal precision:
-- "    45" (bytes, right-aligned)
-- " 1.23K" (kilobytes with 2 decimals)
-- "12.3M" (megabytes with 1 decimal)
-- " 123M" (megabytes, no decimals)
```

#### Compact Time Display
```lua
-- MMDDHHMMSS format examples:
-- "1015143022" = October 15, 14:30:22
-- "0101000000" = January 1, 00:00:00
```

### Architecture Lessons

#### Plugin vs Component Distinction
- **Plugins** (*.yazi directories): External functionality (previewers, tools)
- **Components**: Extensions to built-in yazi objects (Linemode, Status, etc.)
- **Critical**: Linemode functions are component extensions, not plugins

#### Nix Integration Benefits
- **Declarative Configuration**: All yazi settings managed through Home Manager
- **File Management**: init.lua generated and managed by Nix
- **Version Control**: Configuration changes tracked in git
- **Reproducible**: Same configuration across all systems

#### Development Workflow
1. **Edit** `home/files/yazi-init.lua` for linemode functions
2. **Configure** `programs.yazi` settings in `home/modules/base.nix`
3. **Apply** with `nix run home-manager -- switch --flake '.#tim@hostname'`
4. **Test** by launching yazi and verifying linemode display

### Research Sources
- **Yazi GitHub Discussions**: Confirmed init.lua approach for linemode functions
- **Yazi Source Code**: Verified Linemode object extension mechanism
- **Official Documentation**: Plugin system scope and limitations

### Enhanced Debug Infrastructure (2025-10-15)

#### Debug Configuration Options
```nix
# home/modules/base.nix - Enhanced yazi configuration
yazi = {
  enableDebugMode = true;          # Enable debug logging (default: true)
  aliasDebugToDefault = false;     # Make 'yazi' command use debug wrapper (default: false)
};
```

#### Debug Features
- **Dynamic init.lua generation**: Debug flag controlled via Nix configuration
- **Comprehensive error handling**: pcall() wrappers with detailed error reporting  
- **Enhanced debug wrapper**: `yazi-debug` command with startup diagnostics
- **Toggle utilities**: Quick debug mode switching without rebuilding
- **Shell aliases**: `yzd` (yazi-debug) and conditional `yazi` override

#### Debug Commands Available
```bash
yazi-debug          # Enhanced yazi with startup diagnostics
yzd                 # Short alias for yazi-debug
yazi-toggle-debug   # Quick toggle debug mode in config
```

#### Debug Output Examples
```bash
🔍 Enhanced Yazi Debug Mode
📁 Log file: /home/tim/.local/state/yazi/yazi.log
📂 Config dir: /home/tim/.config/yazi
🔗 init.lua -> /nix/store/.../yazi-init.lua

🚀 Starting yazi...
✅ Yazi started successfully
📋 Recent linemode debug entries:
LINEMODE: === INIT.LUA STARTING ===
LINEMODE: CHA PROPERTIES: len=4096, mtime=1728234567.123, mode=16877
LINEMODE: FINAL PERM: 16877 -> 0755
```

#### Error Recovery Features
- **Silent failure detection**: Catches init.lua errors that break yazi layout
- **Comprehensive diagnostics**: Shows startup errors, log entries, and debug tips
- **Fallback mechanisms**: Graceful degradation when API calls fail
- **Troubleshooting guidance**: Built-in commands for common debug tasks

#### Configurable Debug Levels
```lua
-- init.lua automatically configured based on Nix settings
local DEBUG_ENABLED = true   -- Set via Nix string replacement

local function debug_log(msg)
  if DEBUG_ENABLED then
    ya.dbg("LINEMODE: " .. msg)
  end
end
```

### Status
✅ **Working**: Custom compact_meta linemode active and functional  
✅ **Tested**: Fixed-width output maintains terminal alignment  
✅ **Enhanced**: Comprehensive debug infrastructure with easy toggles
✅ **Resilient**: Error handling prevents silent failures
✅ **Documented**: Complete technical resolution recorded

### Extension Pattern
This pattern applies to any yazi customization that extends built-in objects rather than adding external functionality:

```lua
-- Extend other built-in components:
function Status:custom_status() end      -- Custom status line
function Folder:custom_folder() end      -- Custom folder behavior
function Linemode:another_mode() end     -- Additional linemode
```

All component extensions go in `init.lua`, while external tools use the plugin system (*.yazi directories).