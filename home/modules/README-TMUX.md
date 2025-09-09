# Tmux Configuration Documentation

This document describes the tmux configuration managed by Home Manager in this nixcfg repository.

## 🔧 Plugin Architecture Improvement (2025-08-31)

### Major Infrastructure Fix: Proper Nix Derivation Paths

**Problem Resolved**: Eliminated hardcoded plugin paths that caused tmux-resurrect session restoration failures

**Key Changes**:
- ✅ **Replaced Hardcoded Paths**: All `~/.tmux/plugins/tmux-resurrect/scripts/` references now use proper Nix derivations
- ✅ **Build-Time Validation**: Plugin availability verified at build time, not runtime
- ✅ **Future-Proof**: Plugin paths automatically update with Nix store changes
- ✅ **Follows Best Practices**: Uses `${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/`

**Architecture Benefits**:
- **Robust Session Restoration**: tmux-resurrect now works reliably across system rebuilds
- **No Plugin Installation Required**: All plugins managed through Nix derivations
- **Build-Time Path Resolution**: Eliminates runtime path lookup failures
- **Declarative Plugin Management**: Plugin versions controlled by nixpkgs

## 🎉 Session Picker v2 - Simplified with Adaptive Layout (2025-08-31)

### Latest Simplification: Clean Adaptive Column Display
- 🔍 **Hidden Metadata**: Sessions contain hidden searchable fields for comprehensive search
- 📊 **Adaptive Columns**: 1-4 columns automatically adjust to terminal width
- 🎯 **Predictable Format**: Consistent display without "smart compression" complexity

### What You Can Search For
Type any of these to find your sessions:
- **Session names**: "main", "nixcfg", "worktrees"
- **Window names**: "dev", "build", "logs"
- **Pane titles**: "claude", "editor", "terminal"
- **Commands**: "vim", "git", "npm", "zsh"
- **Paths**: "/home/tim/src", "nixcfg", "dsp"
- **Dates**: "2025-08-30", "15:45"
- **Stats**: "3W" (3 windows), "8P" (8 panes)

### Display Format
```
★ main  2025-08-30 15:45  3W 8P
  nixcfg    : 3p • ~/s/nixcfg (vim)      worktrees : 2p • ~/s/dsp (git)
  logs      : 3p • /v/l/system

  dsp  2025-08-29 12:30  2W 4P
  dev       : 3p • ~/p/dsp (npm)         test      : 1p • ~/p/dsp/tests (pytest)
```

### Adaptive Column Layout
- **<80 cols**: 1 column (narrow terminals)
- **80-120 cols**: 2 columns (standard width)
- **120-160 cols**: 3 columns (wide)
- **160+ cols**: 4 columns (ultra-wide)

### Technical Implementation
- **Direct TSV Processing**: No JSON intermediate format for better performance
- **Single Format Function**: One consistent approach, ~340 lines total
- **Path Abbreviations**: `~/src/` → `~/s/`, `~/projects/` → `~/p/`
- **Hidden Metadata**: `##METADATA:...##FILE:/path` for comprehensive searching
- **✅ Robust Plugin Integration**: Uses proper Nix derivation paths (`${pkgs.tmuxPlugins.resurrect}`) instead of hardcoded paths
- **Build-time Path Resolution**: Plugin script paths resolved during Nix build for maximum reliability

### Updated Key Bindings
| Key | Action | Features | Best For |
|-----|--------|----------|----------|
| `Prefix + t` | Enhanced FZF picker v2 | Full search + preview | Primary interface |
| `Alt + Shift + T` | Basic interactive | Number selection | Fallback/simple |
| `Alt + t` | List sessions | View only | Quick reference |

## Table of Contents
1. [Overview](#overview)
2. [Key Bindings](#key-bindings)
3. [Session Management](#session-management)
4. [Resurrect Session Picker](#resurrect-session-picker)
5. [Status Bar](#status-bar)
6. [Plugins](#plugins)

## Overview

The tmux configuration is defined in `home/common/tmux.nix` and provides:
- Custom prefix key (Ctrl-a)
- Vi-style navigation
- Smart pane switching with Vim awareness
- Session persistence via tmux-resurrect
- Automatic saving via tmux-continuum
- Custom status bar with system monitoring
- Nested session support (F12 toggle)

## Key Bindings

### Prefix Key
- **Prefix**: `Ctrl-a` (not the default Ctrl-b)
- **Send prefix to nested tmux**: `Ctrl-a Ctrl-a`

### Window Management
- `Prefix + l` - Last window
- `Alt + h` - Previous window
- `Alt + l` - Next window  
- `Alt + Ctrl + h` - Move window left
- `Alt + Ctrl + l` - Move window right

### Pane Management
- `Prefix + |` or `Prefix + v` - Split vertically
- `Prefix + -` or `Prefix + s` - Split horizontally
- `Ctrl + h/j/k/l` - Navigate panes (Vim-aware)
- `Prefix + h/j/k/l` - Resize panes (repeatable)

### Session Management
- `Prefix + S` - Save current session (tmux-resurrect)
- `Prefix + R` - Restore saved session (tmux-resurrect)
- `Prefix + T` - Browse saved sessions with FZF (search-enabled)
- `Alt + Shift + T` - Browse saved sessions (basic interactive mode)
- `Alt + t` - List saved sessions (view only)

### Other
- `Prefix + r` - Reload tmux configuration
- `Prefix + s` - Toggle pane synchronization
- `Prefix + m` - Toggle activity monitoring
- `F12` - Toggle nested session mode

## Session Management

Tmux sessions are automatically saved and can be restored across system restarts.

### Automatic Saving
Sessions are automatically saved:
- Every 5 minutes (via tmux-continuum)
- On detach (when you disconnect from tmux)
- On session close

### Manual Operations
- **Save**: Press `Prefix + S` to manually save current session
- **Restore**: Press `Prefix + R` to restore the last saved session
- **Browse**: Press `Prefix + T` to browse all saved sessions

## Resurrect Session Picker

The custom `tmux-resurrect-browse` script provides an easy way to browse and restore different saved sessions.

### Usage

#### From Command Line
```bash
# List all saved sessions (non-interactive)
tmux-resurrect-browse
tmux-resurrect-browse list

# Restore a specific session by number
tmux-resurrect-browse restore 5

# Open interactive session browser
tmux-resurrect-browse interactive
```

#### From Within Tmux (Recommended)

**Quick Access**: Press `Prefix + t` (Ctrl-a then t)

This opens the **Enhanced FZF Session Picker v2** with comprehensive search:

**Key Innovation - Hidden Searchable Metadata**:
- Each session line contains hidden metadata appended as `##METADATA:...##FILE:/path`
- FZF displays only the clean formatted part (using `--with-nth=1`)
- But searches the ENTIRE line including hidden content
- Result: Clean interface with comprehensive search capabilities

**What Happens When You Type**:
- Type "claude" → Finds all sessions with claude command (even if not visible)
- Type "nixcfg" → Finds sessions with that in name, window, or path
- Type "2025-08-30" → Finds sessions from that date
- Type "vim /home" → Finds sessions with vim editing files in /home

**Interface Layout**:
```
┌─── Search Box ──────────────────────────────┬─── Preview ────────────────┐
│ Search> vim                                  │ main, nixcfg │ 3W 8P       │
├─── Session List (40%) ──────────────────────┼─── Details (60%) ──────────│
│ ▶ main, nixcfg │ 2025-08-30 15:45 │ 3W 8P   │ ● Window 1: nixcfg         │
│   worktrees    │ 2025-08-29 12:30 │ 2W 4P   │   ▸ P1: vim editor.txt     │
│   [Hidden: ##METADATA with all searchable]  │     /home/tim/src/nixcfg   │
└──────────────────────────────────────────────┴────────────────────────────┘
```

**Color Coding**:
- **Cyan**: Window information
- **Magenta**: Pane information
- **Blue**: Commands and dates
- **Dim**: Paths
- **Bold**: Session headers
- **★**: Current active session

**Alternative Interfaces**:
- **Basic Interactive Mode**: Press `Alt + Shift + T` for number-based selection
  ```
  Available tmux resurrect sessions:
  ===================================
  
   1) 2025-08-29 19:31 -  8 windows, 24 panes [CURRENT]
   2) 2025-08-27 14:22 -  6 windows, 18 panes
   3) 2025-08-25 09:15 -  4 windows, 12 panes
  
  -----------------------------------
  Enter session number to restore
  Press 'q' or Ctrl-C to quit
  -----------------------------------
  Choice: _
  ```
- **View Only**: Press `Alt + t` to just list sessions without interaction

**After Selection**:
- The selected session is restored immediately
- All windows and panes are recreated with their layouts
- Working directories are restored
- Running programs (if configured) are restarted

### Session Storage
Saved sessions are stored in `~/.local/share/tmux/resurrect/`:
- `tmux_resurrect_*.txt` - Session state files
- `last` - Symlink to the session that will be restored with Prefix+R
- `pane_contents.tar.gz` - Saved pane contents

### What Gets Saved
The following are preserved across saves/restores:
- All windows and their names
- All panes and their layouts
- Working directories for each pane
- Running programs (configured list):
  - SSH/mosh connections
  - Serial connections (tio, picocom, etc.)
  - File viewers (tail, less)
  - Claude Code sessions
  - Custom loops and monitors

## Status Bar

The status bar is configured with responsive design based on terminal width:

### Left Status
- Lock indicator (⮞ when unlocked)
- Hostname (truncated to 10 chars)
- Current date and time

### Right Status  
Dynamic CPU/Memory display that adjusts to terminal width:
- **Narrow** (<60 chars): Minimal display
- **Medium** (60-100 chars): Basic stats
- **Wide** (>100 chars): Full stats with load average

### Window Status
- Centered window list
- Current window highlighted
- Window names truncated based on terminal width

## Plugins

### tmux-resurrect
Saves and restores tmux sessions including:
- Window/pane layouts
- Working directories
- Running programs (configurable)
- Pane contents (optional)

### tmux-continuum
Provides continuous saving of tmux environment:
- Auto-save every 5 minutes
- Auto-restore on tmux start (optional)
- Integration with system boot (optional)

### tmux-sensible
Provides sensible tmux defaults:
- Faster command sequences (escape-time)
- Increased scrollback buffer
- Better mouse support
- UTF-8 handling

### tmux-yank
Enhanced copy mode with system clipboard integration:
- Copy to system clipboard
- Paste from system clipboard
- Works in WSL environments

## Nested Session Support

For SSH sessions with tmux on remote hosts:
1. Press `F12` to toggle nested mode
2. The status bar shows a lock icon when in nested mode
3. All keybindings are passed through to the inner tmux
4. Press `F12` again to return to outer session control

## Troubleshooting

### Session Picker Issues

**✅ MAJOR FIX (2025-08-31): Session Restoration Now Working**

**Problem**: Session picker would exit successfully but fail to restore the selected session
**Root Cause**: Hardcoded plugin paths (`~/.tmux/plugins/tmux-resurrect/scripts/restore.sh`) don't exist in Nix-managed tmux setups
**Solution**: Fixed all hardcoded paths to use proper Nix derivation references

**Technical Details**:
- **Fixed 6 references** across 3 files using `${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/restore.sh`
- **Build-time path substitution** in tmux-session-picker-v2 for robust script generation
- **Future-proof architecture** that survives plugin updates and system rebuilds

**Files Updated**:
- `home/common/tmux.nix`: Hook configurations (lines 188-189, 378)
- `home/modules/validated-scripts/bash.nix`: Build-time substitution for tmux-session-picker-v2
- Generated tmux.conf now uses correct Nix store paths

**Status**: ✅ **RESOLVED** - Session picker now properly restores selected sessions

---

**Problem 1**: Picker closes immediately without allowing selection
**Solution**: Fixed in latest version - picker now waits for input

**Problem 2**: Interface is cluttered or hard to navigate
**Solution**: Use `Prefix + T` for enhanced FZF v2 picker, or `Alt + Shift + T` for simple number selection

**Problem 3**: Rendering errors or garbled output in preview
**Solution**: Fixed in v2 using Miller/jq for proper TSV parsing

**Problem 4**: Not enough space to see session details
**Solution**: v2 uses 95% of terminal space (up from 80%)

**Problem 5**: Corrupted session files cause errors
**Solution**: v2 detects and gracefully handles corrupted files

**To Apply Fixes**: 
1. Run `home-manager switch --flake '.#tim@tblack-t14-nixos'`
2. Reload tmux config with `Prefix + r`
3. Test with `Prefix + T` for the enhanced v2 picker

**Dependencies**: The v2 picker requires:
- `miller` (mlr) - for TSV parsing
- `jq` - for JSON processing
- `fzf` - for interactive selection
All are automatically installed via the Nix configuration

### Session Not Restoring
1. Check if session files exist: `ls ~/.local/share/tmux/resurrect/`
2. Verify the `last` symlink points to a valid file
3. Try manually selecting a session with `tmux-resurrect-browse interactive`
4. Ensure you have write permissions to the resurrect directory

### Keybindings Not Working
1. Ensure you're using the correct prefix (Ctrl-a, not Ctrl-b)
2. Check if you're in nested mode (F12 toggles)
3. Reload config with `Prefix + r`
4. Verify script is installed: `which tmux-resurrect-browse`

### Status Bar Issues
1. Check terminal width with `echo $COLUMNS`
2. Ensure required commands are available: `which tmux-cpu-mem`
3. Verify terminal supports UTF-8 and colors

### WSL-Specific Issues
1. Ensure Windows Terminal is properly configured (see diagnose-emoji-rendering)
2. Check that WSL interop is working for clipboard operations
3. Verify font configuration for proper rendering

## Configuration Files

- `home/common/tmux.nix` - Main tmux configuration with proper Nix plugin derivation references
- `home/files/bin/tmux-cpu-mem` - CPU/memory monitoring script
- `home/files/bin/tmux-session-picker-v2` - Session picker source (with placeholder paths)
- `home/modules/validated-scripts/bash.nix` - Build system with path substitution for robust plugin integration
- `~/.config/tmux/tmux.conf` - Generated tmux config with correct Nix store paths (read-only)
- `~/.local/share/tmux/resurrect/` - Saved session storage

### ✅ Architecture Notes (2025-08-31)
The tmux configuration now uses proper Nix derivation references for all plugin paths:
- **Source files** contain placeholder paths like `~/.tmux/plugins/tmux-resurrect/scripts/restore.sh`  
- **Build process** substitutes these with actual Nix store paths like `${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/restore.sh`
- **Generated configuration** contains robust, future-proof paths that survive plugin updates