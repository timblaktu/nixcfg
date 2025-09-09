# nixvim-anywhere

**Make nixvim accessible on any system by converting traditional environments to use Nix + home-manager**

## Philosophy

Instead of extracting nixvim configurations for manual deployment, `nixvim-anywhere` converts traditional systems (Type 3) to Nix-managed systems (Type 2) by safely installing Nix and home-manager. This approach provides:

- **Complete dependency management**: Nix handles all LSP servers, tools, and runtimes
- **Perfect isolation**: home-manager prevents conflicts with system packages  
- **Atomic operations**: Can rollback entire environment changes
- **Single source of truth**: One nixvim configuration for all platforms
- **Reproducible environments**: Identical setups across all systems

## Problem Solved

The core challenge: maintaining nixvim configurations across different system types while handling complex dependency management (LSP servers, Node.js, formatters, etc.) that tools like Mason would normally handle.

**nixvim-anywhere approach:**
- **System conversion**: Install minimal Nix + home-manager on any system
- **Declarative management**: All dependencies handled automatically by Nix
- **Conflict avoidance**: Proper isolation prevents system package interference

## System Types

### Type 1: NixOS Systems ✅
- **Source**: Native nixvim configuration
- **Management**: Direct NixOS rebuilds
- **Status**: Already supported

### Type 2: Non-NixOS with Nix ✅  
- **Source**: Same nixvim configuration via home-manager
- **Management**: `home-manager switch`
- **Status**: Already supported

### Type 3 → Type 2: Traditional Systems 🎯
- **Source**: Same nixvim configuration via home-manager  
- **Migration**: `nixvim-anywhere` converts system to Type 2
- **Management**: `home-manager switch` (after conversion)
- **Status**: **This project's focus**

## Features

### 🛡️ **Safe Installation**
- **Single-user Nix**: No system-wide changes, no root daemon
- **Backup strategy**: Comprehensive backup of existing configurations
- **Conflict detection**: Identifies potential PATH and binary conflicts
- **Rollback capability**: Easy reversion to original system state

### 🔧 **Automated Setup**
- **Nix installation**: Automated single-user installation
- **home-manager setup**: Minimal configuration for nixvim only
- **Dependency resolution**: All LSP servers and tools via Nix packages
- **Validation testing**: Ensures setup works correctly

### 🎯 **Minimal Footprint**
- **Isolated management**: Only manages Neovim, leaves other tools alone
- **Selective overrides**: Can choose which system tools to replace
- **Easy removal**: Complete uninstall removes all Nix components

### 📋 **Platform Support**
- **Ubuntu/Debian**: Full support with apt integration
- **macOS**: Homebrew coexistence and conflict resolution
- **Arch Linux**: pacman integration and AUR compatibility
- **Generic Linux**: POSIX-compliant for other distributions

## Quick Start

### One-Command Conversion
```bash
# Convert current system to use nixvim via home-manager
curl -L https://github.com/tim/nixcfg/raw/main/install-nixvim-anywhere.sh | bash
```

### Manual Installation
```bash
# Clone and run
git clone https://github.com/tim/nixcfg.git
cd nixcfg
./nixvim-anywhere install --backup --validate
```

### Custom Configuration
```bash
# Use specific nixvim configuration
./nixvim-anywhere install --config tim@tblack-t14-nixos --backup
```

## Workflow

### 1. **Pre-Installation Assessment**
- Detect existing Neovim installations and configurations
- Identify potential conflicts (system packages, PATH issues)
- Check system requirements and compatibility
- Create comprehensive backup plan

### 2. **Safe Nix Installation**
- Install Nix in single-user mode (no daemon)
- Configure minimal PATH integration
- Verify installation without affecting system tools

### 3. **home-manager Setup**
- Install home-manager in standalone mode
- Create minimal configuration focused only on nixvim
- Explicitly avoid managing other system tools

### 4. **nixvim Deployment**
- Deploy identical nixvim configuration as Type 1/2 systems
- All dependencies (LSP servers, formatters) installed via Nix
- Validate complete functionality

### 5. **Validation & Testing**
- Verify nixvim takes precedence over system neovim
- Test all plugins, LSP servers, and features
- Ensure no conflicts with existing system tools
- Provide rollback option if issues detected

## Commands

### Installation Commands
```bash
# Basic installation with backup
./nixvim-anywhere install --backup

# Installation with conflict detection
./nixvim-anywhere install --backup --detect-conflicts

# Dry run to see what would be changed
./nixvim-anywhere install --dry-run

# Install specific configuration target
./nixvim-anywhere install --target nixvim-config-mbp
```

### Management Commands
```bash
# Update nixvim configuration
./nixvim-anywhere update

# Validate installation health
./nixvim-anywhere validate

# Show system status
./nixvim-anywhere status

# Backup current state
./nixvim-anywhere backup
```

### Recovery Commands
```bash
# Rollback to pre-Nix state
./nixvim-anywhere rollback

# Remove Nix completely
./nixvim-anywhere uninstall

# Restore from backup
./nixvim-anywhere restore --backup-id 20250616_143022
```

## Architecture

### Core Components

**`nixvim-anywhere`** - Main deployment script
- System detection and compatibility checking
- Automated Nix installation with safety checks
- home-manager setup and configuration deployment
- Conflict resolution and rollback capabilities

**`home-manager-templates/`** - Minimal configurations
- Template configurations for different use cases
- Nixvim-only setups that avoid system tool conflicts
- Host-specific configuration variants

**`validation-suite/`** - Testing and validation
- Pre-installation compatibility checks
- Post-installation functionality validation
- Conflict detection and resolution guidance

**`backup-restore/`** - Safety and recovery
- Comprehensive backup of existing configurations
- Rollback scripts for complete system restoration
- Migration history and state tracking

### Integration with nixcfg

The tool integrates with your existing nixcfg repository by:

1. **Using existing nixvim configurations**: Same `home/common/nixvim.nix` as source
2. **Generating home-manager configs**: Creates Type 2 compatible configurations
3. **Providing flake outputs**: `packages.nixvim-anywhere-installer`
4. **Maintaining consistency**: Ensures Type 2 systems match Type 1 functionality

## Benefits Over Manual Configuration

### Dependency Management
- **Manual approach**: Install Node.js, npm, 9 LSP servers, formatters individually
- **nixvim-anywhere**: All dependencies declared and installed automatically

### System Conflicts  
- **Manual approach**: PATH conflicts, version mismatches, manual resolution
- **nixvim-anywhere**: home-manager isolation prevents conflicts entirely

### Updates
- **Manual approach**: Update system packages and Neovim configuration separately
- **nixvim-anywhere**: `home-manager switch` updates everything atomically

### Reproducibility
- **Manual approach**: Hard to reproduce exact environment on new systems
- **nixvim-anywhere**: Identical environment guaranteed via Nix expressions

### Maintenance
- **Manual approach**: Document installation steps for each platform
- **nixvim-anywhere**: Automated installation with built-in safety checks

## Development Status

- [ ] **Phase 1**: Core installation automation (Nix + home-manager)
- [ ] **Phase 2**: Conflict detection and resolution system  
- [ ] **Phase 3**: Comprehensive backup and rollback capabilities
- [ ] **Phase 4**: Multi-platform support and testing
- [ ] **Phase 5**: Integration with nixcfg repository and flake outputs

## Strategic Value

**For Users:**
- Access to nixvim's powerful configuration system on any platform
- No manual dependency management complexity
- Safe installation with easy rollback
- Automatic updates via home-manager

**For Teams:**  
- Consistent development environments across different platforms
- Easy onboarding of developers regardless of their system
- Reproducible setups for CI/CD and development containers
- Single nixvim configuration maintained for all team members

**For nixvim Community:**
- Extends nixvim reach to traditional Linux distributions
- Demonstrates safe Nix adoption patterns
- Provides template for other cross-platform Nix deployments
- Potential upstream contribution to home-manager or nixvim projects

## Related Projects

- **home-manager**: Provides the foundation for user-space package management
- **nixvim**: The configuration system being deployed
- **nix-portable**: Alternative approach for systems where Nix installation is restricted
- **devenv**: Similar cross-platform development environment management

---

*nixvim-anywhere: Making nixvim accessible everywhere through the power of Nix*
