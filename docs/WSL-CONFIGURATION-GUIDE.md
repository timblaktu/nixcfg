# WSL Configuration Guide

## Overview

This guide documents the comprehensive WSL-specific configuration in this NixOS setup, covering:
- Current WSL configuration architecture
- Microsoft Terminal settings.json management
- Font configuration and installation
- Home Manager WSL target module integration
- Recommendations for managing Terminal settings declaratively

**Last Updated**: 2025-11-21
**Target Audience**: WSL NixOS system administrators
**Status**: Research Complete - Ready for Implementation

---

## Quick Reference: Task Status

### Current State Summary

| Feature | Status | Location |
|---------|--------|----------|
| Font management | ✅ Working | `home/modules/terminal-verification.nix` |
| Font verification | ✅ Working | PowerShell interop via activation |
| PowerShell activation access | ✅ Working | home-manager fork `wsl-target-module` |
| Keybinding management | ❌ Missing | N/A |
| Color scheme management | ❌ Missing | N/A |
| Declarative settings.json | ❌ Missing | N/A |

### Implementation Tasks (Self-Contained Checklist)

**Phase 1: Foundation** (Priority: High)
- [ ] Create `modules/nixos/windows-terminal.nix` skeleton
- [ ] Implement options for profiles.defaults, keybindings, colorSchemes
- [ ] Create PowerShell script for settings.json merge/update
- [ ] Add NixOS activation script
- [ ] Test on current WSL instance
- [ ] Add host configuration to `hosts/thinky-nixos/default.nix`

**Phase 2: Enhancement** (Priority: Medium)
- [ ] Implement WSL instance detection for profile auto-generation
- [ ] Add settings merge modes (overlay/replace/backup)
- [ ] Improve backup and recovery mechanisms
- [ ] Test on multiple WSL instances

**Phase 3: Integration** (Priority: Low)
- [ ] Extend `targets.wsl` in home-manager fork with Terminal options
- [ ] Create user override mechanism
- [ ] Prepare for upstream contribution

**Phase 4: Polish** (Priority: Future)
- [ ] Theme import/export functionality
- [ ] Advanced keybinding presets
- [ ] Community testing and upstream PR

### Next Session Prompt

```
Continue implementing WSL Terminal settings management. Review
docs/WSL-CONFIGURATION-GUIDE.md for context and task list.
Start with Phase 1: Create modules/nixos/windows-terminal.nix
with basic keybinding and color scheme support.
```

---

## Table of Contents

1. [Current WSL Configuration Architecture](#current-wsl-configuration-architecture)
2. [Microsoft Terminal Settings Management](#microsoft-terminal-settings-management)
3. [Font Configuration System](#font-configuration-system)
4. [Home Manager WSL Target Module](#home-manager-wsl-target-module)
5. [Scope Analysis: NixOS vs Home Manager](#scope-analysis-nixos-vs-home-manager)
6. [Recommendations and Action Plan](#recommendations-and-action-plan)
7. [Implementation Roadmap](#implementation-roadmap)

---

## Current WSL Configuration Architecture

### Module Hierarchy

```
NixOS Layer (System-wide):
├── modules/wsl-common.nix           # Base WSL configuration
├── modules/nixos/wsl-storage-mount.nix  # Bare mount support
└── modules/wsl-tarball-checks.nix   # Distribution validation

Home Manager Layer (User-specific):
├── home/common/terminal.nix         # Terminal utilities
├── home/modules/terminal-verification.nix  # Font verification
└── home/migration/wsl-home-files.nix  # WSL-specific files

Home Manager Fork:
└── modules/targets/wsl/default.nix  # PowerShell activation access
```

### Key Configuration Files

#### 1. `modules/wsl-common.nix`
**Scope**: NixOS system-level
**Purpose**: Common WSL configuration across all instances

**Features**:
- Hostname and user configuration
- Windows interop settings
- SSH configuration
- Windows PATH integration
- Shell aliases for Windows tools

**Configuration Options**:
```nix
wslCommon = {
  enable = true;
  hostname = "hostname";
  defaultUser = "username";
  sshPort = 2223;
  interopRegister = true;
  interopIncludePath = true;
  appendWindowsPath = true;
  enableWindowsTools = true;
};
```

#### 2. `home/modules/terminal-verification.nix`
**Scope**: Home Manager (user-level)
**Purpose**: Terminal font verification and Windows Terminal alignment

**Features**:
- Automatic font installation (CaskaydiaMono Nerd Font, Noto Color Emoji)
- Windows Terminal settings.json verification
- Activation-time checks for font configuration
- WSL tools verification (wslpath, clip.exe, powershell.exe)

**Configuration Options**:
```nix
terminalVerification = {
  enable = true;
  verbose = false;
  warnOnMisconfiguration = true;
  terminalFont = "CaskaydiaMono Nerd Font";
};
```

**Current Limitations**:
- ⚠️ **Read-only**: Only *verifies* Terminal settings, doesn't *manage* them
- ⚠️ Manual intervention required for Terminal configuration changes
- ⚠️ No keybinding or color scheme management
- ⚠️ Settings only applied via PowerShell scripts

#### 3. `modules/nixos/wsl-storage-mount.nix`
**Scope**: NixOS system-level
**Purpose**: Bare disk mounting for Nix store on external storage

**Features**:
- PowerShell-based disk mounting via WSL interop
- Automatic retry logic
- Systemd integration
- Per-instance directory management

---

## Microsoft Terminal Settings Management

### Current State: Font Configuration Only

**What Currently Works**:
1. **Font Verification** (`terminal-verification.nix:76-134`)
   - Detects Windows Terminal settings.json location
   - Reads current font configuration via PowerShell
   - Compares against expected font face
   - Warns if configuration doesn't match

2. **Font Installation** (`install-terminal-fonts.ps1`)
   - Downloads and installs fonts (CaskaydiaMono NF, Noto Color Emoji)
   - Updates `profiles.defaults.font.face` in settings.json
   - Sets `profiles.defaults.intenseTextStyle = "all"`
   - Creates backup before modification

**What's Missing** (User's Request):
- ❌ Keybinding management (e.g., tab navigation)
- ❌ Color scheme management (e.g., NixOS profile colors)
- ❌ Profile-specific settings (per-distro configuration)
- ❌ Declarative full settings.json management

### Windows Terminal Settings.json Structure

**Location**:
```
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json
```

**WSL Access Path**:
```bash
/mnt/c/Users/$USERNAME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json
```

**Key Settings Structure**:
```json
{
  "profiles": {
    "defaults": {
      "font": {
        "face": "CaskaydiaMono Nerd Font Mono, Noto Color Emoji"
      },
      "intenseTextStyle": "all"
    },
    "list": [
      {
        "guid": "{...}",
        "name": "NixOS",
        "source": "Windows.Terminal.Wsl",
        "colorScheme": "CustomScheme",
        "font": { "face": "..." }
      }
    ]
  },
  "schemes": [
    {
      "name": "CustomScheme",
      "foreground": "#...",
      "background": "#..."
    }
  ],
  "keybindings": [
    { "command": "nextTab", "keys": "ctrl+tab" },
    { "command": "prevTab", "keys": "ctrl+shift+tab" }
  ]
}
```

### Current Font Management Workflow

```
┌─────────────────────────────────────────────────────────────┐
│ home-manager activation                                      │
│ ├─ terminal-verification.nix activation script             │
│ │  ├─ Detect Windows Terminal                              │
│ │  ├─ Read settings.json via PowerShell                    │
│ │  ├─ Compare fonts                                         │
│ │  └─ Warn if mismatch                                      │
│ └─ User runs setup-terminal-fonts                           │
│    └─ install-terminal-fonts.ps1                            │
│       ├─ Install fonts to Windows                           │
│       ├─ Update settings.json                               │
│       └─ Backup original                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Font Configuration System

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Font Configuration Flow                                      │
├─────────────────────────────────────────────────────────────┤
│ NixOS/WSL (Linux side):                                     │
│ ├─ home/modules/terminal-verification.nix                   │
│ │  ├─ Installs Nerd Fonts via home.packages                │
│ │  ├─ Configures fontconfig                                │
│ │  └─ Provides verification scripts                         │
│ └─ home/common/terminal.nix                                 │
│    └─ Provides font setup utilities                         │
│                                                              │
│ Windows (Windows side):                                     │
│ ├─ install-terminal-fonts.ps1                               │
│ │  ├─ Downloads fonts from GitHub                           │
│ │  ├─ Installs to Windows fonts directory                   │
│ │  └─ Registers in Windows Registry                         │
│ └─ fix-terminal-fonts.ps1                                   │
│    └─ Updates Terminal settings.json                        │
└─────────────────────────────────────────────────────────────┘
```

### Font Detection Functions

**Robust Font Detection** (`font-detection-functions.ps1`):
- `Find-InstalledFonts`: Searches all installed fonts
- `Get-BestCascadiaFont`: Prioritizes Nerd Font variants
- `Get-BestEmojiFont`: Detects emoji font availability
- `Get-OptimalTerminalFontConfig`: Generates optimal font stack

**Font Stack Priority**:
1. CaskaydiaMono Nerd Font Mono (preferred)
2. CaskaydiaMono NF / CaskaydiaMono NFM (aliases)
3. Cascadia Mono (fallback)
4. Noto Color Emoji (emoji support)
5. Segoe UI Emoji (Windows fallback)

### Scripts

#### 1. `setup-terminal-fonts` (Bash wrapper)
**Location**: `home/files/bin/setup-terminal-fonts`
**Purpose**: Interactive font installation from WSL

**Workflow**:
1. Analyzes current configuration (Windows + NixOS fonts)
2. Checks Windows Terminal settings
3. Shows what will be changed
4. Prompts for confirmation
5. Runs PowerShell installer
6. Optionally restarts Terminal

#### 2. `install-terminal-fonts.ps1` (PowerShell)
**Location**: `home/files/bin/install-terminal-fonts.ps1`
**Purpose**: Automated font download, installation, and Terminal configuration

**Features**:
- Detects existing fonts (avoids re-download)
- Searches Downloads folder first
- Falls back to online download
- Installs system-wide (admin) or per-user
- Updates settings.json with backup
- Dynamic font detection for optimal configuration

#### 3. `check-windows-terminal` (Verification)
**Location**: Generated by `terminal-verification.nix`
**Purpose**: Verify Terminal configuration matches expectations

---

## Home Manager WSL Target Module

### Overview

**Repository**: `/home/tim/src/home-manager` (fork)
**Branch**: `wsl-target-module`
**Status**: Implemented, pending upstream contribution

**Documentation**: `/home/tim/src/home-manager/WSL-TARGETS-IMPLEMENTATION.md`

### Purpose

Solves the **PowerShell activation environment access problem**:
- Home Manager activation runs in minimal environment
- Windows mount paths (`/mnt/c`) not in PATH during activation
- Windows tools (PowerShell, cmd.exe) not accessible
- Prevents Windows integration during home-manager activation

### Implementation

**Module**: `modules/targets/wsl/default.nix`

**Configuration**:
```nix
targets.wsl = {
  enable = true;  # Auto-detected in WSL environments

  windowsTools = {
    enablePowerShell = true;
    powerShellPath = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe";

    enableCmd = false;
    cmdPath = "/mnt/c/Windows/System32/cmd.exe";

    enableWslPath = false;
    wslPathPath = "/usr/bin/wslpath";
  };
};
```

**How It Works**:
1. Creates Nix wrapper packages with symlinks to Windows executables
2. Adds wrappers to `home.extraActivationPath`
3. Makes Windows tools available during activation via standard command detection
4. Validates tools at activation time

**Benefits**:
- Enables Windows interop during home-manager activation
- Required for any feature that needs PowerShell during activation
- Foundation for advanced WSL integration features

**Upstream Status**:
- Ready for contribution to home-manager
- Fills gap (home-manager has `targets.darwin` but no `targets.wsl`)
- Benefits entire Nix community

---

## Scope Analysis: NixOS vs Home Manager

### The Question

**Should Microsoft Terminal settings management live in NixOS or Home Manager?**

User's observation:
> "at least the Microsoft Terminal settings related features, are really WSL machine specific and not linux user-specific, so as such should reside at the NixOS level/layer"

### Analysis

| Aspect | NixOS System Layer | Home Manager User Layer |
|--------|-------------------|------------------------|
| **Scope** | Machine-wide, all users | Per-user configuration |
| **Files** | System files (`/etc`, `/nix/store`) | User files (`~/.config`, `~/.local`) |
| **Privileges** | Root required | User-level only |
| **Activation** | System rebuild | User home-manager switch |
| **Target** | Windows host environment | WSL user environment |

### Windows Terminal Settings Reality

**Key Insight**: Windows Terminal settings.json is **per-Windows-user**, not per-WSL-instance!

**Location**:
```
C:\Users\{WINDOWS_USER}\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

**Implications**:
1. ✅ One settings.json serves **all WSL distributions** for that Windows user
2. ✅ Multiple NixOS-WSL instances share the same Terminal settings
3. ✅ Different Windows users have separate Terminal configurations
4. ⚠️ But: Multiple Linux users in one WSL instance would share Terminal settings

### Recommendation: Hybrid Approach

**For Terminal settings.json management**:

#### Option A: NixOS Module (Recommended for your use case)
**Reasoning**:
- You typically run one primary WSL instance (thinky-nixos) per Windows user
- Terminal settings affect the Windows host environment, not just one Linux user
- Centralized management at system level makes sense
- Can be reused across multiple WSL instances with same needs

**Implementation Location**: `modules/nixos/windows-terminal.nix`

**Benefits**:
- ✅ One source of truth per WSL machine
- ✅ Works for single or multiple Linux users
- ✅ Consistent with other Windows host integration (mounts, etc.)
- ✅ Natural location for Windows-side configuration

**Drawbacks**:
- ⚠️ Requires root for system rebuild
- ⚠️ Harder to share config across multiple machines
- ⚠️ Not portable to other NixOS-WSL setups

#### Option B: Home Manager Module (Traditional Nix approach)
**Reasoning**:
- Most Terminal configuration is user preference (colors, fonts, keybindings)
- Home Manager configs are more portable
- User-level activation is faster
- Aligns with home-manager's terminal emulator configuration patterns

**Implementation Location**: Home manager fork `modules/targets/wsl/windows-terminal.nix`

**Benefits**:
- ✅ User-level control
- ✅ Portable across machines
- ✅ Fast activation (no sudo)
- ✅ Consistent with alacritty/kitty module patterns in home-manager

**Drawbacks**:
- ⚠️ Multiple users would fight over same settings.json
- ⚠️ Complexity in multi-user scenarios

#### Option C: Hybrid (Most Flexible)
**Recommended for this project**:

1. **NixOS module** (`modules/nixos/windows-terminal.nix`):
   - Machine-specific settings (default profile, auto-generated profiles)
   - Windows host integration
   - System-wide defaults

2. **Home Manager integration** (via `targets.wsl`):
   - User font preferences
   - User color schemes
   - User keybindings
   - PowerShell activation access for updates

**Configuration Flow**:
```nix
# NixOS system level (hosts/thinky-nixos/default.nix)
windowsTerminal = {
  enable = true;
  manageSettings = true;
  profiles = {
    defaults = {
      # System-wide defaults
    };
    # Auto-generate profiles for all WSL instances
  };
};

# Home Manager user level (home/wsl.nix)
targets.wsl = {
  enable = true;
  windowsTerminal = {
    font = "CaskaydiaMono Nerd Font";
    colorScheme = "Dracula";
    keybindings = [ ... ];
  };
};
```

**Implementation**: NixOS module generates base configuration, Home Manager adds user preferences.

---

## Recommendations and Action Plan

### Immediate Improvements (Phase 1)

#### 1. Create NixOS Windows Terminal Module
**Priority**: High
**Complexity**: Medium
**Benefit**: Solves user's immediate problem

**Implementation**:
```nix
# modules/nixos/windows-terminal.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.windowsTerminal;

  # Generate settings.json from NixOS options
  settingsJson = pkgs.writeText "windows-terminal-settings.json" (builtins.toJSON {
    profiles = {
      defaults = cfg.profiles.defaults;
      list = cfg.profiles.list;
    };
    schemes = cfg.colorSchemes;
    keybindings = cfg.keybindings;
    # ... other settings
  });

  # PowerShell script to update settings.json
  updateScript = pkgs.writeScript "update-windows-terminal.ps1" ''
    # Backup, merge, and apply settings
    # ...
  '';

in {
  options.windowsTerminal = {
    enable = mkEnableOption "Windows Terminal settings management";

    manageSettings = mkOption {
      type = types.bool;
      default = true;
      description = "Manage settings.json from NixOS";
    };

    profiles = {
      defaults = mkOption {
        type = types.attrs;
        description = "Default profile settings";
      };
      list = mkOption {
        type = types.listOf types.attrs;
        description = "Profile definitions";
      };
    };

    colorSchemes = mkOption {
      type = types.listOf types.attrs;
      description = "Color scheme definitions";
    };

    keybindings = mkOption {
      type = types.listOf types.attrs;
      description = "Keybinding definitions";
    };
  };

  config = mkIf cfg.enable {
    # System activation script
    system.activationScripts.windowsTerminalSettings = {
      text = ''
        # Run PowerShell script to update settings
        if [[ -n "''${WSL_DISTRO_NAME:-}" ]]; then
          # Copy generated settings to temp location
          # Run PowerShell script to merge
          ${pkgs.powershell}/bin/pwsh ${updateScript}
        fi
      '';
    };
  };
}
```

**Usage**:
```nix
# hosts/thinky-nixos/default.nix
windowsTerminal = {
  enable = true;

  profiles.defaults = {
    font.face = "CaskaydiaMono Nerd Font Mono, Noto Color Emoji";
    intenseTextStyle = "all";
  };

  keybindings = [
    { command = "nextTab"; keys = "ctrl+tab"; }
    { command = "prevTab"; keys = "ctrl+shift+tab"; }
  ];

  colorSchemes = [
    {
      name = "NixOS Dark";
      foreground = "#839496";
      background = "#002b36";
      # ... other colors
    }
  ];
};
```

#### 2. Integrate with targets.wsl
**Priority**: Medium
**Complexity**: Low
**Benefit**: Ensures PowerShell access during activation

**Change**: Merge Windows Terminal functionality into `targets.wsl` module in home-manager fork.

#### 3. Enhance Font Management
**Priority**: Low
**Complexity**: Low
**Benefit**: More robust font detection and installation

**Improvements**:
- Detect and preserve user customizations
- Support font fallback chains
- Better error handling for font installation

### Future Enhancements (Phase 2)

#### 1. Profile Auto-Generation
**Feature**: Automatically generate Terminal profiles for all WSL instances

**Implementation**:
```nix
# Detect all WSL instances and generate profiles
profiles.list = map (instance: {
  name = instance.name;
  source = "Windows.Terminal.Wsl";
  hidden = false;
  guid = generateGuid instance.name;
}) config.wsl.instances;
```

#### 2. Settings Merging Strategy
**Feature**: Intelligent merge of NixOS-managed and user-customized settings

**Strategies**:
- Overlay mode: NixOS provides base, user additions preserved
- Replace mode: NixOS fully manages specific sections
- Backup mode: Always preserve user settings before modification

#### 3. Integration with Windows Terminal Themes
**Feature**: Import and manage Windows Terminal theme collections

**Sources**:
- Windows Terminal Themes website
- Custom theme definitions
- Per-profile theme selection

#### 4. Advanced Keybinding Management
**Feature**: Comprehensive keybinding configuration

**Capabilities**:
- Conditional keybindings (per-profile)
- Keybinding conflicts detection
- Common preset bundles (vim-style, emacs-style)

### Testing Strategy

#### 1. Multi-Instance Testing
**Test**: Multiple WSL instances (thinky-nixos, nixos-wsl-minimal)
**Verify**: Settings correctly shared across instances
**Edge Cases**: Different NixOS configurations generating conflicting settings

#### 2. Multi-User Testing
**Test**: Multiple Linux users in same WSL instance
**Verify**: Last writer wins, no corruption
**Edge Cases**: Concurrent home-manager activation

#### 3. Upgrade Testing
**Test**: Windows Terminal version upgrades
**Verify**: Settings schema compatibility
**Edge Cases**: Deprecated settings fields

#### 4. Rollback Testing
**Test**: NixOS rollback
**Verify**: Terminal settings rollback possible
**Edge Cases**: Windows-side changes not captured in generation

---

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)

**Goals**:
- Basic NixOS module for Terminal settings
- Integration with existing font management
- Keybindings and color schemes support

**Tasks**:
1. Create `modules/nixos/windows-terminal.nix`
2. Implement settings.json generation
3. Create PowerShell update script with merging logic
4. Add activation script
5. Test on thinky-nixos

**Deliverables**:
- Working module with example configuration
- Documentation for usage
- Test results

### Phase 2: Enhancement (Weeks 3-4)

**Goals**:
- Profile auto-generation
- Settings merging strategies
- Enhanced error handling

**Tasks**:
1. Implement WSL instance detection
2. Create profile generation logic
3. Add settings merge modes
4. Improve backup and recovery
5. Test on multiple instances

**Deliverables**:
- Auto-generation feature
- Merge strategies documentation
- Multi-instance test results

### Phase 3: Integration (Weeks 5-6)

**Goals**:
- Home Manager integration via targets.wsl
- User-level overrides
- Complete documentation

**Tasks**:
1. Extend targets.wsl with Terminal options
2. Create user override mechanism
3. Write comprehensive guide
4. Prepare for upstream contribution

**Deliverables**:
- Complete hybrid implementation
- User guide with examples
- Upstream contribution plan

### Phase 4: Polish (Weeks 7-8)

**Goals**:
- Advanced features
- Community feedback
- Upstream submission

**Tasks**:
1. Theme import/export
2. Advanced keybinding management
3. Community testing
4. Submit to nixpkgs/home-manager

**Deliverables**:
- Feature-complete implementation
- Community-tested configuration
- Upstream PR

---

## Appendices

### A. File Locations Reference

**NixOS Configuration**:
```
modules/
├── wsl-common.nix                    # Base WSL configuration
├── nixos/
│   ├── windows-terminal.nix         # [TO BE CREATED] Terminal management
│   └── wsl-storage-mount.nix        # Bare mount support
└── wsl-tarball-checks.nix           # Distribution validation
```

**Home Manager Configuration**:
```
home/
├── common/
│   └── terminal.nix                  # Terminal utilities
├── modules/
│   └── terminal-verification.nix    # Font verification
└── files/bin/
    ├── setup-terminal-fonts          # Interactive font setup (Bash)
    ├── install-terminal-fonts.ps1   # Font installer (PowerShell)
    ├── fix-terminal-fonts.ps1       # Settings updater (PowerShell)
    └── font-detection-functions.ps1 # Font detection library
```

**Home Manager Fork**:
```
/home/tim/src/home-manager/
├── modules/targets/wsl/
│   ├── default.nix                   # WSL target module
│   └── tests.nix                     # Test cases
└── WSL-TARGETS-IMPLEMENTATION.md     # Documentation
```

### B. PowerShell Script Locations

All PowerShell scripts are deployed to Windows-accessible locations:

**Deployment Path**:
```
$HOME/bin/  →  /home/tim/bin/  →  /mnt/c/Users/$WINDOWS_USER/.../bin/
```

**Windows Path**:
```
C:\Users\{WINDOWS_USER}\...\bin\*.ps1
```

**Execution from WSL**:
```bash
powershell.exe -ExecutionPolicy Bypass -File "$HOME/bin/install-terminal-fonts.ps1"
```

### C. Windows Terminal Settings.json Schema

**Official Schema**:
```
https://aka.ms/terminal-profiles-schema
```

**Key Sections**:
- `profiles.defaults`: Default settings for all profiles
- `profiles.list`: Array of profile definitions
- `schemes`: Color scheme definitions
- `keybindings`: Keyboard shortcut definitions
- `actions`: Custom actions
- `themes`: UI theme definitions (Terminal v1.12+)

**Example Profile**:
```json
{
  "guid": "{...}",
  "name": "NixOS",
  "source": "Windows.Terminal.Wsl",
  "hidden": false,
  "icon": "ms-appx:///ProfileIcons/{...}.png",
  "colorScheme": "Campbell",
  "font": {
    "face": "CaskaydiaMono Nerd Font Mono",
    "size": 11
  },
  "padding": "8, 8, 8, 8",
  "scrollbarState": "visible",
  "snapOnInput": true,
  "historySize": 9001,
  "intenseTextStyle": "all"
}
```

### D. Related Documentation

**NixOS-WSL**:
- Official: https://nix-community.github.io/NixOS-WSL/
- Local fork: /home/tim/src/NixOS-WSL

**Home Manager**:
- Official: https://nix-community.github.io/home-manager/
- Local fork: /home/tim/src/home-manager (branch: wsl-target-module)

**Windows Terminal**:
- Official docs: https://learn.microsoft.com/en-us/windows/terminal/
- Settings reference: https://learn.microsoft.com/en-us/windows/terminal/customize-settings/
- Color schemes: https://windowsterminalthemes.dev/

**Related Docs in This Repo**:
- `docs/NIXOS-WSL-BARE-MOUNT-CONTRIBUTION-PLAN.md`
- `docs/NIXOS-WSL-BARE-MOUNT-TESTING.md`
- `/home/tim/src/home-manager/WSL-TARGETS-IMPLEMENTATION.md`

---

## Conclusion

This guide provides a comprehensive overview of WSL configuration in this NixOS setup, with specific focus on Microsoft Terminal settings management. The recommended hybrid approach (NixOS module + Home Manager integration) provides the best balance of flexibility, usability, and alignment with NixOS/home-manager architecture patterns.

**Next Steps**:
1. Review this guide and approve the recommended approach
2. Begin Phase 1 implementation of `windows-terminal.nix` module
3. Test on current machine (nixos-wsl instance "nixos")
4. Extend to other WSL instances (thinky-nixos)
5. Contribute improvements back to NixOS-WSL and home-manager communities

**Questions or Feedback**:
- Review the Scope Analysis section for architectural decisions
- Consult the Implementation Roadmap for timeline
- Refer to Appendices for technical details
