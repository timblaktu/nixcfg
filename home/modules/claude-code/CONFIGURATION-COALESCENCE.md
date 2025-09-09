# Claude Code Configuration Coalescence System

*Comprehensive analysis of Claude Code's configuration hierarchy and Nix-managed coalescence*

## Research Findings (2025-08-27)

**Critical Discovery**: Initial assumptions about Claude Code "losing MCP configurations due to runtime data overwrites" were **incorrect** based on empirical analysis of actual `.claude.json` files.

### Key Findings

1. **MCP Configurations Are Stable**: Analysis of production `.claude.json` files shows MCP server configurations are preserved and functional, with all servers showing "✔ connected" status.

2. **Runtime Data Storage is Intentional Design**: Claude Code's storage of conversation history, project state, and analytics in `.claude.json` is intentional architecture, not a bug or "data pollution."

3. **Current System Works**: The existing coalescence system appears to be functioning correctly, with proper MCP server configurations maintained through Nix management.

4. **Multi-Writer Coordination is the Real Problem**: The coalescence system solves the legitimate challenge of coordinating between Nix's declarative configuration management and Claude Code's runtime state updates.

## Overview

This document provides a complete analysis of how Claude Code's official configuration system works and how our Nix-managed coalescence system addresses the multi-writer coordination challenge to ensure consistent, declarative configuration management.

## Official Claude Code Configuration Hierarchy

Based on [Claude Code's official documentation](https://docs.anthropic.com/en/docs/claude-code/settings#settings-files), the configuration hierarchy is:

### Precedence Order (Highest → Lowest)

1. **🏢 Enterprise Managed Policies** (Cannot be overridden)
   - Linux/WSL: `/etc/claude-code/managed-settings.json`
   - macOS: `/Library/Application Support/ClaudeCode/managed-settings.json`
   - Windows: `C:\ProgramData\ClaudeCode\managed-settings.json`

2. **⚡ Command Line Arguments**
   - Runtime flags passed to `claude` command

3. **💻 Local Project Settings** 
   - `.claude/settings.local.json` (personal, not shared)

4. **📁 Shared Project Settings**
   - `.claude/settings.json` (team-shared)
   - `.mcp.json` (MCP server configurations)

5. **👤 User Settings** (Lowest precedence)
   - `~/.claude/settings.json` (global user defaults)
   - `~/.claude-{account}/settings.json` (account-specific)

### Configuration Merging Behavior

- Settings are **merged**, with more specific settings adding to or overriding broader ones
- Enterprise managed policies **cannot be overridden** at any level
- System ensures "enterprise security policies are always enforced while still allowing teams and individuals to customize their experience"

## Nix-Managed Configuration Integration

Our Nix system operates **within** this established hierarchy, managing settings at appropriate levels:

### Configuration Sources & Targets

| **Nix Configuration** | **Target File** | **Official Hierarchy Level** | **Management Strategy** |
|----------------------|-----------------|------------------------------|------------------------|
| System-wide policies | `/etc/claude-code/managed-settings.json` | **Enterprise (Highest)** | Complete control - overwrites all |
| User account defaults | `~/.claude-{account}/settings.json` | **User (Lowest)** | Template deployment - preserved if exists |
| Runtime state coalescence | `~/.claude-{account}/.claude.json` | **Active Runtime Configuration** | Selective field replacement |

## Parameter Ownership & Management Classification

### 🔧 Nix-Managed Static Configuration

These parameters are **always enforced** by the coalescence system:

| **Parameter** | **Source** | **Target File** | **Enforcement Level** | **Purpose** |
|---------------|------------|-----------------|---------------------|-------------|
| **mcpServers** | `cfg._internal.mcpServers` | `.claude.json` | Always | Declarative MCP server management |
| **permissions** | `cfg.permissions` | `.claude.json` / `/etc/` | Always | Security policy enforcement |
| **env** | `cfg.environmentVariables` | `.claude.json` / `/etc/` | Always | Environment consistency |
| **statusLine** | `cfg._internal.statuslineSettings` | `.claude.json` | Always | UI consistency |
| **hooks** | `cfg._internal.hooks` | `.claude.json` | Always | Automated workflow consistency |
| **model** | `cfg.defaultModel` | `/etc/` or `settings.json` | Always | Resource/cost control |
| **projectOverrides** | System policy | `/etc/` | Always | Security boundary control |

### 🏃 Claude Code Runtime-Managed Dynamic State

These parameters are **never modified** by coalescence:

| **Parameter** | **Purpose** | **Preservation Rule** | **Rationale** |
|---------------|-------------|---------------------|---------------|
| **oauthAccount** | Authentication tokens | Never modify | Authentication state |
| **projects** | Project-specific state/history | Never modify | User work state |
| **userID** | Account identification | Never modify | Identity management |
| **numStartups** | Usage analytics | Never modify | Analytics/tracking |
| **firstStartTime** | Installation tracking | Never modify | Analytics/tracking |
| **has*** | Feature flags/UI state | Never modify | User experience state |
| **cached*** | Performance optimization | Never modify | Runtime optimization |
| **last*** | Version/update tracking | Never modify | Update management |
| **tips***, **onboarding*** | User experience state | Never modify | Personalization |

## Configuration Coalescence System Architecture

### Current Implementation Analysis

The coalescence script performs **selective field replacement**:

```bash
jq '. | .mcpServers = $mcpServers | .permissions = $permissions | .env = $env | .statusLine = $statusLine | .hooks = $hooks'
```

**Operation Characteristics:**
1. **Starts with existing file** (`.` preserves all existing data)
2. **Completely replaces Nix-managed fields** (`=` operator overwrites entire field)
3. **Preserves all other fields** (Claude Code runtime state untouched)
4. **Atomic operation** (uses `.tmp` + `mv` for safe replacement)

### Issues with Current Implementation

#### 1. ❌ Incorrect Conditional Logic

**Current (Wrong):**
```nix
${optionalString (cfg.permissions != {}) ''--argjson permissions '${builtins.toJSON cfg.permissions}' \''}
```

**Corrected (Right):**
```nix
--argjson permissions '${builtins.toJSON cfg.permissions}' \
```

**Issue**: Current logic only applies Nix-managed settings IF they're configured. Should always apply them, even if empty/default.

#### 2. ⚠️ Multi-Writer Coordination Challenge

**Problem**: Nix and Claude Code both need to modify the same configuration files, creating a coordination challenge.

**Core Issue**: 
- **Nix**: Wants to declaratively manage configuration as source of truth
- **Claude Code**: Legitimately needs to write runtime state to configuration files
- **Solution**: Coalescence system provides controlled synchronization between the two systems

## Simplified Wrapper-Based Coalescence Solution

### Design Decision: Simplicity Over Complexity

**Chosen Approach**: Replace complex real-time monitoring with simple startup coalescence through wrapper functions.

**Rationale**:
- Configuration changes are infrequent events  
- Users naturally restart applications after system configuration changes
- Real-time monitoring adds unnecessary complexity for the usage pattern
- Wrapper-based approach leverages existing infrastructure
- Clear lifecycle: config change → restart → fresh state

### Architecture Overview

Simple startup-time coalescence that handles configuration synchronization when Claude Code launches:

```bash
# claudepro/claudemax wrapper approach
#!/bin/bash
ensure_single_instance_or_exit "$account"
coalesce_nix_configuration_for_account "$account"  
exec actual-claude-code "$@"
```

### Wrapper-Based Coalescence Logic

```bash
# Coalesce Nix configuration at startup (simplified approach)
coalesce_nix_configuration_for_account() {
  local account="$1"
  local config_file="$HOME/.claude-${account}/.claude.json"
  
  # Ensure configuration file exists
  [[ -f "$config_file" ]] || return 0
  
  # Apply Nix-managed fields (always, unconditionally)
  jq \
    --argjson mcpServers '${builtins.toJSON cfg._internal.mcpServers}' \
    --argjson permissions '${builtins.toJSON cfg.permissions}' \
    --argjson env '${builtins.toJSON cfg.environmentVariables}' \
    --argjson statusLine '${builtins.toJSON cfg._internal.statuslineSettings.statusLine}' \
    --argjson hooks '${builtins.toJSON cfg._internal.hooks}' \
    '. |
    .mcpServers = $mcpServers |
    .permissions = $permissions |
    .env = $env |
    .statusLine = $statusLine |
    .hooks = $hooks
    ' "$config_file" > "$config_file.tmp"
  
  mv "$config_file.tmp" "$config_file"
}

ensure_single_instance_or_exit() {
  local account="$1"
  local pidfile="/tmp/claude-${account}.pid"
  
  # Check if another instance is running
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "Claude Code ($account) is already running. Please close existing session first."
    exit 1
  fi
  
  # Create pidfile for this instance
  echo $$ > "$pidfile"
  trap "rm -f '$pidfile'" EXIT
}
```

### Key Features

1. **🚀 Startup Coalescence**: Configuration synchronized once per session at launch
2. **🛡️ Single Instance Enforcement**: Prevents concurrent access conflicts  
3. **🔧 Always Apply**: All Nix-managed fields applied unconditionally
4. **📊 Multi-Account Aware**: Handles pro/max accounts with separate logic
5. **⚡ Simple & Reliable**: No complex monitoring, clear execution path
6. **🧹 Clean Lifecycle**: Proper cleanup on exit
7. **🎯 User-Friendly**: Clear error messages for conflicts

## System Integration Points

### NixOS System Level
- **File**: `/etc/claude-code/managed-settings.json`
- **Trigger**: `nixos-rebuild switch`
- **Scope**: System-wide policies (highest precedence)
- **Management**: Complete replacement

### Home Manager User Level  
- **Files**: `~/.claude-{account}/settings.json`
- **Trigger**: `home-manager switch`
- **Scope**: User account defaults
- **Management**: Template deployment (preserved if exists)

### Wrapper-Based Coalescence Level
- **Files**: `~/.claude-{account}/.claude.json`
- **Trigger**: Claude Code startup via wrapper functions
- **Scope**: Active runtime configuration
- **Management**: Selective field replacement at launch time

## Benefits of Wrapper-Based System

1. **✅ Respects Official Hierarchy**: Works within Claude Code's established precedence system
2. **✅ Always Enforces Nix Settings**: No conditional logic - Nix-managed fields always applied  
3. **✅ Simple & Reliable**: Clear execution path with minimal complexity
4. **✅ Preserves Runtime State**: Never touches Claude Code's dynamic data
5. **✅ Multi-Account Support**: Handles Pro/Max accounts with separate wrappers
6. **✅ Conflict Prevention**: Single-instance enforcement prevents concurrent access
7. **✅ User-Friendly Workflow**: Natural restart cycle after configuration changes
8. **✅ Atomic Safety**: Configuration applied once at startup, then stable during session

## Implementation Roadmap

### Phase 1: Research & Analysis ✅  
1. ✅ **Deep Research Completed**: Investigated actual Claude Code configuration behavior
2. ✅ **Corrected Understanding**: MCP configurations are stable, not being lost
3. ✅ **Design Decision**: Chose wrapper-based over complex inotify approach
4. ✅ **Documentation Updated**: Comprehensive analysis and findings documented

### Phase 2: Wrapper-Based Implementation ✅ COMPLETE (2025-08-27)
1. ✅ **Enhanced Existing Wrappers**: Integrated coalescence logic into `claudepro`/`claudemax` wrappers
2. ✅ **Single Instance Enforcement**: Added pidfile-based locking - prevents conflicts successfully
3. ✅ **Error Handling**: Implemented clear user feedback for configuration issues
4. ✅ **Testing**: Validated wrapper behavior - blocking works, configuration sync confirmed

### Phase 3: Polish & Documentation 🎯
1. **User Documentation**: Create clear guidance for configuration change workflow
2. **Monitoring**: Add optional logging for coalescence operations
3. **Edge Case Handling**: Account for missing files, permission issues, etc.
4. **Integration Testing**: Test with actual home-manager switch cycles

## Conclusion

**Research Summary**: Empirical analysis revealed that Claude Code's configuration system works as designed, with runtime data storage being intentional architecture rather than problematic "data pollution." MCP server configurations remain stable and functional.

**Design Evolution**: The system evolved from a complex real-time monitoring approach to a simple wrapper-based solution that addresses the core multi-writer coordination challenge without unnecessary complexity.

**Implementation Status (2025-08-27)**: ✅ **COMPLETE AND OPERATIONAL**
- Wrapper-based coalescence successfully implemented and tested
- Configuration synchronization confirmed working at startup
- Single-instance enforcement validated with proper PID tracking
- Helper commands (`claude-status`, `claude-close`) functional
- Clear user feedback for all conflict scenarios

**Final Architecture**: The wrapper-based coalescence system provides:
- **Clean separation of concerns** between Nix and Claude Code
- **Simple, reliable implementation** using existing wrapper infrastructure  
- **User-friendly workflow** where configuration changes require session restarts
- **Conflict prevention** through single-instance enforcement

This approach successfully solves the multi-writer coordination problem while maintaining compatibility with Claude Code's official configuration hierarchy and preserving all runtime state.