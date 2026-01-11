# Termux NixOS Bootstrap System

A reproducible, declarative Termux environment designed specifically for running NixOS in proot-distro, enabling full provisioning through NixOS and home-manager configurations.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Quick Start](#quick-start)
4. [Main Bootstrap Script](#main-bootstrap-script)
5. [Custom NixOS Rootfs Integration](#custom-nixos-rootfs-integration)
6. [NixOS Configuration Module](#nixos-configuration-module)
7. [Helper Scripts](#helper-scripts)
8. [Directory Structure](#directory-structure)
9. [PRoot Compatibility Considerations](#proot-compatibility-considerations)
10. [Environment Variables](#environment-variables)
11. [Troubleshooting](#troubleshooting)

## Overview

This bootstrap system provides a minimal, reproducible Termux setup specifically designed for running NixOS through proot-distro. Unlike generic Termux setups, this focuses solely on providing the foundation for a full NixOS environment.

### Key Features

- **NixOS-First**: Designed exclusively for NixOS deployment
- **Custom Rootfs Support**: Ability to import pre-built NixOS tarballs
- **Idempotent**: Safe to run multiple times
- **Minimal**: Only essential packages for NixOS hosting
- **Declarative**: Tracks configuration state
- **Integration Ready**: Seamless integration with existing nixcfg flakes

## Architecture

```
┌─────────────────────────────────────────┐
│           Android System                 │
├─────────────────────────────────────────┤
│             Termux                       │
│  (Minimal Bootstrap Environment)         │
├─────────────────────────────────────────┤
│            PRoot Layer                   │
│  (User-space filesystem virtualization)  │
├─────────────────────────────────────────┤
│         NixOS Root Filesystem            │
│  (Custom or pre-built tarball)           │
├─────────────────────────────────────────┤
│    Nix Package Manager + Home Manager    │
│  (Full declarative configuration)        │
└─────────────────────────────────────────┘
```

## Quick Start

Bootstrap your Termux environment for NixOS:

```bash
# One-line installation
curl -L https://raw.githubusercontent.com/YOUR-USERNAME/termux-nixos-bootstrap/main/bootstrap.sh | bash

# Or clone and run locally
git clone https://github.com/YOUR-USERNAME/termux-nixos-bootstrap
cd termux-nixos-bootstrap
./bootstrap.sh
```

## Main Bootstrap Script

```bash
#!/data/data/com.termux/files/usr/bin/bash
# Termux NixOS Bootstrap Script v2.0
# Minimal environment setup for NixOS in proot-distro

set -euo pipefail

# Configuration
BOOTSTRAP_VERSION="2.0.0"
BOOTSTRAP_DIR="$HOME/.termux-bootstrap"
CONFIG_FILE="$BOOTSTRAP_DIR/config.json"
LOG_FILE="$BOOTSTRAP_DIR/bootstrap.log"
NIXOS_ROOTFS_DIR="$BOOTSTRAP_DIR/nixos-rootfs"
PROOT_DISTRO_DIR="$PREFIX/etc/proot-distro"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Create bootstrap directory
init_bootstrap() {
    if [[ ! -d "$BOOTSTRAP_DIR" ]]; then
        mkdir -p "$BOOTSTRAP_DIR"
        log "Created bootstrap directory: $BOOTSTRAP_DIR"
    fi
    
    if [[ ! -d "$NIXOS_ROOTFS_DIR" ]]; then
        mkdir -p "$NIXOS_ROOTFS_DIR"
        log "Created NixOS rootfs directory: $NIXOS_ROOTFS_DIR"
    fi
}

# Check if already bootstrapped
check_existing() {
    if [[ -f "$CONFIG_FILE" ]]; then
        existing_version=$(grep -oP '"version":\s*"\K[^"]+' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
        warn "System already bootstrapped (version: $existing_version)"
        read -p "Do you want to re-run bootstrap? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Bootstrap cancelled by user"
            exit 0
        fi
    fi
}

# Setup storage permissions
setup_storage() {
    if [[ ! -d "$HOME/storage" ]]; then
        log "Setting up storage access..."
        termux-setup-storage
        sleep 3  # Wait for permission dialog
        
        # Wait for user to grant permission
        while [[ ! -d "$HOME/storage" ]]; do
            warn "Please grant storage permission in the Android dialog"
            sleep 2
        done
        log "Storage access configured"
    else
        log "Storage access already configured"
    fi
}

# Update and upgrade base packages
update_system() {
    log "Updating package repositories..."
    pkg update -y || error "Failed to update packages"
    
    log "Upgrading installed packages..."
    pkg upgrade -y || error "Failed to upgrade packages"
}

# Install minimal packages for NixOS hosting
install_packages() {
    local ESSENTIAL_PACKAGES=(
        # Core PRoot requirements
        "proot"
        "proot-distro"
        
        # Network and download utilities
        "curl"
        "wget"
        "git"
        
        # SSH for remote access
        "openssh"
        
        # Terminal essentials
        "termux-api"
        "termux-tools"
        
        # Minimal editor (for emergency config edits)
        "nano"
        
        # Archive tools (for rootfs manipulation)
        "tar"
        "gzip"
        "xz-utils"
        
        # Process monitoring
        "htop"
        
        # JSON processing (for config management)
        "jq"
    )
    
    log "Installing essential packages..."
    for package in "${ESSENTIAL_PACKAGES[@]}"; do
        info "Installing $package..."
        pkg install -y "$package" || warn "Failed to install $package"
    done
}

# Configure shell environment for NixOS
setup_shell() {
    log "Configuring shell environment..."
    
    # Create .bashrc if it doesn't exist
    if [[ ! -f "$HOME/.bashrc" ]]; then
        cat > "$HOME/.bashrc" << 'EOF'
# Termux NixOS Bootstrap Shell Configuration
export TERM=xterm-256color
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# NixOS-specific aliases
alias nixos='proot-distro login nixos --shared-tmp --bind /dev --bind /proc --bind /sys'
alias nixos-shell='proot-distro login nixos --shared-tmp --bind /dev --bind /proc --bind /sys -- /run/current-system/sw/bin/bash --login'
alias nixos-rebuild='nixos -- nixos-rebuild'
alias nixos-clean='nixos -- nix-collect-garbage -d'

# Quick NixOS operations
nixos-run() {
    if [ -z "$1" ]; then
        echo "Usage: nixos-run <command>"
        return 1
    fi
    proot-distro login nixos --shared-tmp --bind /dev --bind /proc --bind /sys -- "$@"
}

# Check NixOS status
nixos-status() {
    if proot-distro list | grep -q "nixos.*Installed"; then
        echo -e "\033[0;32m✓ NixOS is installed\033[0m"
        echo "Enter with: nixos"
    else
        echo -e "\033[0;31m✗ NixOS is not installed\033[0m"
        echo "Install with: install-nixos-rootfs.sh"
    fi
}

# Custom prompt showing NixOS availability
PS1='\[\033[01;32m\]termux\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$(nixos-status 2>/dev/null | grep -q "✓" && echo "[\[\033[0;36m\]nix\[\033[0m\]]")\$ '

# Bootstrap version info
export TERMUX_BOOTSTRAP_VERSION="2.0.0"
export TERMUX_BOOTSTRAP_TYPE="nixos"

# Source Nix profile if it exists (for nix-on-droid compatibility)
if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi
EOF
        log "Created .bashrc configuration"
    else
        log ".bashrc already exists, skipping"
    fi
    
    # Source the bashrc
    source "$HOME/.bashrc"
}

# Create proot-distro plugin for NixOS
setup_nixos_plugin() {
    log "Creating proot-distro plugin for NixOS..."
    
    mkdir -p "$PROOT_DISTRO_DIR"
    
    cat > "$PROOT_DISTRO_DIR/nixos.sh" << 'EOF'
# NixOS proot-distro plugin
DISTRO_NAME="NixOS"
DISTRO_COMMENT="NixOS - The Purely Functional Linux Distribution"

# Architecture mapping
TARBALL_ARCH=$(uname -m)
case "$TARBALL_ARCH" in
    aarch64) DISTRO_ARCH="aarch64" ;;
    armv7l|armv8l) DISTRO_ARCH="arm" ;;
    x86_64) DISTRO_ARCH="x86_64" ;;
    i686) DISTRO_ARCH="i686" ;;
    *) echo "Unsupported architecture: $TARBALL_ARCH"; exit 1 ;;
esac

# Default to local tarball if it exists
NIXOS_TARBALL="$HOME/.termux-bootstrap/nixos-rootfs/nixos-rootfs-${DISTRO_ARCH}.tar.xz"

if [ -f "$NIXOS_TARBALL" ]; then
    TARBALL_URL["$DISTRO_ARCH"]="file://$NIXOS_TARBALL"
    TARBALL_SHA256["$DISTRO_ARCH"]="SKIP"
else
    # Fallback to a minimal NixOS tarball URL (you'll need to provide this)
    TARBALL_URL["$DISTRO_ARCH"]="https://your-domain.com/nixos-rootfs-${DISTRO_ARCH}.tar.xz"
    TARBALL_SHA256["$DISTRO_ARCH"]="YOUR_SHA256_HERE"
fi

# How many leading path components to strip when extracting
TARBALL_STRIP_OPT=0

distro_setup() {
    # Create necessary directories
    run_proot_cmd mkdir -p /etc/nixos
    run_proot_cmd mkdir -p /nix/var/nix/profiles
    
    # Create a basic configuration.nix if it doesn't exist
    if [ ! -f "${DISTRO_DIR}/etc/nixos/configuration.nix" ]; then
        cat > "${DISTRO_DIR}/etc/nixos/configuration.nix" << 'NIX_EOF'
{ config, pkgs, ... }:
{
  imports = [ ];
  
  # Basic system configuration
  boot.isContainer = true;
  
  # Enable nix flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Basic packages
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
  ];
  
  # System state version (don't change this after initial install)
  system.stateVersion = "24.05";
}
NIX_EOF
    fi
    
    # Set up initial channels (if not using flakes)
    run_proot_cmd sh -c "nix-channel --add https://nixos.org/channels/nixos-24.05 nixos"
    run_proot_cmd sh -c "nix-channel --update"
}
EOF
    
    chmod +x "$PROOT_DISTRO_DIR/nixos.sh"
    log "NixOS proot-distro plugin created"
}

# Create helper scripts
create_helper_scripts() {
    log "Creating helper scripts..."
    
    # Script to build NixOS rootfs from flake
    cat > "$BOOTSTRAP_DIR/build-nixos-rootfs.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Build NixOS rootfs tarball from a flake configuration

set -euo pipefail

FLAKE_URL="${1:-}"
OUTPUT_DIR="$HOME/.termux-bootstrap/nixos-rootfs"
ARCH=$(uname -m)

if [ -z "$FLAKE_URL" ]; then
    echo "Usage: $0 <flake-url> [configuration-name]"
    echo "Example: $0 github:timblaktu/nixcfg#termux-nixos"
    exit 1
fi

CONFIG_NAME="${2:-termux-nixos}"

echo "Building NixOS rootfs from flake..."
echo "Flake: $FLAKE_URL"
echo "Configuration: $CONFIG_NAME"
echo "Architecture: $ARCH"

# This would typically be run on a NixOS host to build the tarball
# The actual build command would be something like:
cat << 'BUILD_INSTRUCTIONS'

To build a NixOS rootfs tarball, run this on a NixOS host:

nix build "${FLAKE_URL}#nixosConfigurations.${CONFIG_NAME}.config.system.build.tarball"

Or add this to your flake configuration:

{
  nixosConfigurations.termux-nixos = nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";  # or your target architecture
    modules = [
      ({ config, pkgs, ... }: {
        # Container/PRoot specific configuration
        boot.isContainer = true;
        boot.loader.grub.enable = false;
        
        # Build tarball output
        system.build.tarball = pkgs.callPackage <nixpkgs/nixos/lib/make-system-tarball.nix> {
          inherit (config.system.build) toplevel;
          contents = [];
          compressCommand = "xz -z -T0 -9";
          compressionExtension = ".xz";
          storeContents = [ config.system.build.toplevel ];
        };
        
        # Your other NixOS configuration here
        # ...
      })
    ];
  };
}

BUILD_INSTRUCTIONS

echo "Once built, copy the tarball to: $OUTPUT_DIR/nixos-rootfs-${ARCH}.tar.xz"
EOF
    chmod +x "$BOOTSTRAP_DIR/build-nixos-rootfs.sh"
    
    # Script to install custom NixOS rootfs
    cat > "$BOOTSTRAP_DIR/install-nixos-rootfs.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Install NixOS from a custom rootfs tarball

set -euo pipefail

ROOTFS_DIR="$HOME/.termux-bootstrap/nixos-rootfs"
ARCH=$(uname -m)
TARBALL_PATH="${1:-$ROOTFS_DIR/nixos-rootfs-${ARCH}.tar.xz}"

if [ ! -f "$TARBALL_PATH" ]; then
    echo "Error: Rootfs tarball not found at $TARBALL_PATH"
    echo ""
    echo "Usage: $0 [path-to-tarball]"
    echo ""
    echo "To create a NixOS rootfs tarball:"
    echo "1. Build it on a NixOS host using your flake configuration"
    echo "2. Copy it to: $ROOTFS_DIR/nixos-rootfs-${ARCH}.tar.xz"
    echo "3. Run this script again"
    exit 1
fi

echo "Installing NixOS from: $TARBALL_PATH"

# Update the proot-distro plugin to use this tarball
sed -i "s|NIXOS_TARBALL=.*|NIXOS_TARBALL=\"$TARBALL_PATH\"|" "$PREFIX/etc/proot-distro/nixos.sh"

# Install using proot-distro
echo "Installing NixOS via proot-distro..."
proot-distro install nixos

echo "NixOS installation complete!"
echo "Enter NixOS with: nixos"
echo "Or use: proot-distro login nixos --shared-tmp"
EOF
    chmod +x "$BOOTSTRAP_DIR/install-nixos-rootfs.sh"
    
    # Script to backup Termux+NixOS configuration
    cat > "$BOOTSTRAP_DIR/backup-termux-nixos.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Backup Termux and NixOS configuration

BACKUP_DIR="$HOME/storage/shared/termux-nixos-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="termux-nixos-backup-$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "Creating backup..."
tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
    --exclude="$HOME/storage" \
    --exclude="$HOME/.cache" \
    --exclude="*.log" \
    "$HOME/.termux" \
    "$HOME/.bashrc" \
    "$HOME/.termux-bootstrap" \
    "$PREFIX/etc/proot-distro" \
    "$PREFIX/var/lib/proot-distro/installed-rootfs/nixos" \
    2>/dev/null || true

echo "Backup saved to: $BACKUP_DIR/$BACKUP_FILE"

# Save installed package list
pkg list-installed > "$BACKUP_DIR/packages-$TIMESTAMP.txt"
proot-distro list > "$BACKUP_DIR/distros-$TIMESTAMP.txt"

# If NixOS is installed, save its configuration
if [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/nixos" ]; then
    echo "Backing up NixOS configuration..."
    proot-distro login nixos -- tar -czf "/tmp/nixos-config-$TIMESTAMP.tar.gz" \
        /etc/nixos \
        /home \
        2>/dev/null || true
    
    mv "$PREFIX/var/lib/proot-distro/installed-rootfs/nixos/tmp/nixos-config-$TIMESTAMP.tar.gz" \
       "$BACKUP_DIR/" 2>/dev/null || true
fi

echo "Backup complete!"
EOF
    chmod +x "$BOOTSTRAP_DIR/backup-termux-nixos.sh"
    
    log "Helper scripts created"
}

# Save bootstrap configuration
save_config() {
    log "Saving bootstrap configuration..."
    
    cat > "$CONFIG_FILE" << EOF
{
    "version": "$BOOTSTRAP_VERSION",
    "type": "nixos",
    "timestamp": "$(date -Iseconds)",
    "packages": [
        "proot",
        "proot-distro",
        "curl",
        "wget",
        "git",
        "openssh",
        "termux-api",
        "termux-tools",
        "nano",
        "tar",
        "gzip",
        "xz-utils",
        "htop",
        "jq"
    ],
    "android_version": "$(getprop ro.build.version.release)",
    "device": "$(getprop ro.product.model)",
    "arch": "$(uname -m)"
}
EOF
    log "Configuration saved to $CONFIG_FILE"
}

# Verification step
verify_installation() {
    log "Verifying installation..."
    
    local VERIFY_COMMANDS=(
        "proot --version"
        "proot-distro list"
        "git --version"
        "curl --version | head -n1"
    )
    
    local failed=0
    for cmd in "${VERIFY_COMMANDS[@]}"; do
        if eval "$cmd" &>/dev/null; then
            info "✓ $cmd"
        else
            error "✗ $cmd failed"
            ((failed++))
        fi
    done
    
    # Check if NixOS plugin is properly installed
    if [ -f "$PROOT_DISTRO_DIR/nixos.sh" ]; then
        info "✓ NixOS proot-distro plugin installed"
    else
        warn "✗ NixOS plugin not found"
        ((failed++))
    fi
    
    if [[ $failed -eq 0 ]]; then
        log "All verification checks passed!"
    else
        warn "$failed verification checks failed"
    fi
}

# Display next steps
show_next_steps() {
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   NixOS Bootstrap Installation Complete!${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo
    echo "1. ${CYAN}Build NixOS rootfs on a NixOS host:${NC}"
    echo "   nix build 'github:YOUR/nixcfg#nixosConfigurations.termux-nixos.config.system.build.tarball'"
    echo
    echo "2. ${CYAN}Copy the tarball to this device:${NC}"
    echo "   Place it in: ~/.termux-bootstrap/nixos-rootfs/nixos-rootfs-$(uname -m).tar.xz"
    echo
    echo "3. ${CYAN}Install NixOS:${NC}"
    echo "   ./install-nixos-rootfs.sh"
    echo
    echo "4. ${CYAN}Enter NixOS:${NC}"
    echo "   nixos"
    echo
    echo -e "${GREEN}Helper Scripts Available:${NC}"
    echo "  • build-nixos-rootfs.sh   - Instructions for building rootfs"
    echo "  • install-nixos-rootfs.sh - Install NixOS from tarball"
    echo "  • backup-termux-nixos.sh  - Backup your configuration"
    echo
    echo -e "${BLUE}Configuration saved to: $CONFIG_FILE${NC}"
    echo -e "${BLUE}Log file: $LOG_FILE${NC}"
    echo
}

# Main execution
main() {
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   Termux NixOS Bootstrap System v2.0   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo
    
    init_bootstrap
    check_existing
    
    log "Starting NixOS bootstrap process..."
    
    setup_storage
    update_system
    install_packages
    setup_shell
    setup_nixos_plugin
    create_helper_scripts
    save_config
    verify_installation
    
    show_next_steps
}

# Run main function
main "$@"
```

## Custom NixOS Rootfs Integration

PRoot-distro supports custom rootfs tarballs through local file URLs. This allows you to build a NixOS system tarball with your exact configuration and import it directly.

### Building NixOS Rootfs Tarball

Add this to your `flake.nix`:

```nix
{
  nixosConfigurations.termux-nixos = nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";  # Match your Android device architecture
    modules = [
      ({ config, pkgs, lib, ... }: {
        # Essential PRoot/container configuration
        boot.isContainer = true;
        boot.loader.grub.enable = false;
        boot.tmpOnTmpfs = true;
        
        # Disable systemd services that don't work in PRoot
        systemd.services.systemd-udevd.enable = false;
        systemd.services.systemd-timesyncd.enable = false;
        systemd.services.auditd.enable = false;
        
        # Network configuration for container
        networking.useDHCP = false;
        networking.useHostResolvConf = true;
        
        # Enable Nix flakes
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
        
        # Trust the build user
        nix.settings.trusted-users = [ "root" "@wheel" ];
        
        # Optimize storage
        nix.settings.auto-optimise-store = true;
        nix.gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 7d";
        };
        
        # Build tarball output
        system.build.tarball = pkgs.callPackage <nixpkgs/nixos/lib/make-system-tarball.nix> {
          inherit (config.system.build) toplevel;
          
          contents = [
            {
              source = config.system.build.toplevel + "/init";
              target = "/sbin/init";
            }
          ];
          
          storeContents = [ config.system.build.toplevel ];
          
          compressCommand = "xz -z -T0 -9";
          compressionExtension = ".xz";
        };
        
        # Your custom configuration here
        # Import from your existing nixcfg
        # ...
        
        system.stateVersion = "24.05";
      })
    ];
  };
}
```

### Building the Tarball

On a NixOS host or with Nix installed:

```bash
# Build the tarball
nix build '.#nixosConfigurations.termux-nixos.config.system.build.tarball'

# The tarball will be in ./result/tarball/nixos-system-*.tar.xz
# Copy it to your Android device
```

### Installing Custom Rootfs

1. Transfer the tarball to your Android device
2. Place it in `~/.termux-bootstrap/nixos-rootfs/`
3. Run the installation script:

```bash
./install-nixos-rootfs.sh /path/to/your/nixos-rootfs.tar.xz
```

## NixOS Configuration Module

For integration with your existing nixcfg repository, create a specialized module:

```nix
# modules/termux-proot.nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.termux.proot;
in
{
  options.termux.proot = {
    enable = mkEnableOption "Termux PRoot environment optimizations";
    
    bindMounts = mkOption {
      type = types.listOf types.str;
      default = [ "/dev" "/proc" "/sys" ];
      description = "Directories to bind mount from host";
    };
    
    disabledServices = mkOption {
      type = types.listOf types.str;
      default = [
        "systemd-udevd"
        "systemd-timesyncd"
        "auditd"
        "systemd-journald-audit"
        "systemd-modules-load"
      ];
      description = "Systemd services to disable in PRoot";
    };
  };
  
  config = mkIf cfg.enable {
    # Container-specific settings
    boot.isContainer = true;
    boot.loader.grub.enable = false;
    boot.tmpOnTmpfs = true;
    
    # Disable incompatible services
    systemd.services = lib.genAttrs cfg.disabledServices (_: {
      enable = false;
    });
    
    # Network configuration for container
    networking.useDHCP = false;
    networking.useHostResolvConf = true;
    
    # File system optimizations
    fileSystems."/" = {
      device = "/dev/root";
      fsType = "fakeroot";
      options = [ "defaults" ];
    };
    
    # Android-specific environment variables
    environment.sessionVariables = {
      ANDROID_ROOT = "/system";
      ANDROID_DATA = "/data";
      TMPDIR = "/tmp";
    };
    
    # Termux integration scripts
    environment.systemPackages = with pkgs; [
      (writeScriptBin "termux-open" ''
        #!${stdenv.shell}
        # Bridge to Termux's termux-open command
        exec /data/data/com.termux/files/usr/bin/termux-open "$@"
      '')
    ];
  };
}
```

## Helper Scripts

### Update Bootstrap Components

```bash
#!/data/data/com.termux/files/usr/bin/bash
# update-bootstrap.sh - Update all bootstrap components

set -euo pipefail

echo "Updating Termux packages..."
pkg update -y && pkg upgrade -y

echo "Updating proot-distro..."
pkg install -y proot-distro

if proot-distro list | grep -q "nixos.*Installed"; then
    echo "Updating NixOS channels..."
    proot-distro login nixos -- sh -c "
        nix-channel --update
        nixos-rebuild switch || true
    "
fi

echo "Update complete!"
```

### NixOS Flake Integration

```bash
#!/data/data/com.termux/files/usr/bin/bash
# setup-flake.sh - Configure NixOS to use your flake

FLAKE_URL="${1:-github:timblaktu/nixcfg}"
CONFIG_NAME="${2:-termux-nixos}"

proot-distro login nixos -- sh -c "
    # Clone or update the flake repository
    if [ ! -d /etc/nixos/.git ]; then
        git clone $FLAKE_URL /etc/nixos
    else
        cd /etc/nixos && git pull
    fi
    
    # Switch to the flake configuration
    nixos-rebuild switch --flake '/etc/nixos#$CONFIG_NAME'
"
```

## Directory Structure

After complete setup:

```
$HOME/
├── .termux-bootstrap/
│   ├── config.json              # Bootstrap configuration
│   ├── bootstrap.log            # Installation log
│   ├── nixos-rootfs/           # NixOS tarball storage
│   │   └── nixos-rootfs-*.tar.xz
│   ├── build-nixos-rootfs.sh   # Build instructions
│   ├── install-nixos-rootfs.sh # Installation script
│   └── backup-termux-nixos.sh  # Backup script
├── .bashrc                      # Shell configuration
└── storage/                     # Android storage access
    └── shared/                  # Maps to /sdcard

$PREFIX/
├── etc/
│   └── proot-distro/
│       └── nixos.sh            # NixOS plugin definition
└── var/
    └── lib/
        └── proot-distro/
            └── installed-rootfs/
                └── nixos/       # NixOS root filesystem
                    ├── etc/
                    │   └── nixos/
                    │       └── configuration.nix
                    ├── nix/
                    └── home/
```

## PRoot Compatibility Considerations

Based on analysis of your nixcfg repository and PRoot limitations:

### Compatible Features
- ✅ Nix package management
- ✅ Home-manager configurations
- ✅ Most development tools
- ✅ Text-based applications
- ✅ Network services (on high ports)
- ✅ Git operations
- ✅ Shell customizations

### Incompatible/Limited Features
- ❌ Hardware access (USB, Bluetooth)
- ❌ Kernel modules
- ❌ Docker/Podman containers
- ❌ System services requiring real root
- ❌ Port binding below 1024 (redirect to 2000+)
- ❌ FUSE filesystems
- ⚠️ Systemd services (limited functionality)
- ⚠️ Performance-critical applications

### Recommended Adaptations for Your nixcfg

1. **Create a termux-specific host configuration**:
   ```nix
   # hosts/termux/default.nix
   { config, pkgs, ... }:
   {
     imports = [ 
       ../../modules/termux-proot.nix
       # Your common modules
     ];
     
     termux.proot.enable = true;
     
     # Disable incompatible features
     virtualisation.docker.enable = false;
     virtualisation.podman.enable = false;
   }
   ```

2. **Adapt home-manager for Termux**:
   ```nix
   # home/termux.nix
   { config, pkgs, ... }:
   {
     # Use programs that work well in PRoot
     programs.git.enable = true;
     programs.neovim.enable = true;
     programs.tmux.enable = true;
     
     # Avoid GUI applications
     services.gpg-agent.enable = false;
   }
   ```

## Environment Variables

The bootstrap sets up these environment variables:

```bash
# Termux Bootstrap
TERMUX_BOOTSTRAP_VERSION="2.0.0"
TERMUX_BOOTSTRAP_TYPE="nixos"

# Terminal
TERM=xterm-256color
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8

# Android paths (accessible from NixOS)
ANDROID_ROOT=/system
ANDROID_DATA=/data
ANDROID_STORAGE=/sdcard
```

## Troubleshooting

### Common Issues and Solutions

#### 1. "No space left on device" during NixOS operations
```bash
# Clean Nix store
nixos-run nix-collect-garbage -d

# Check available space
df -h /data
```

#### 2. Systemd services failing
```bash
# Check service status
nixos-run systemctl status service-name

# Disable incompatible service
nixos-run systemctl disable service-name
```

#### 3. Network issues in NixOS
```bash
# Use Termux's DNS
echo "nameserver 8.8.8.8" | nixos-run tee /etc/resolv.conf
```

#### 4. Permission denied errors
```bash
# Ensure proper bind mounts
proot-distro login nixos --bind /dev --bind /proc --bind /sys
```

### Debug Mode

Enable verbose logging:
```bash
PROOT_VERBOSE=9 proot-distro login nixos
```

## Advanced Configuration

### Using Nix-on-Droid Features

While this setup uses vanilla NixOS in PRoot, you can borrow optimizations from nix-on-droid:

```nix
# Borrow optimizations from nix-on-droid
{
  nix.extraOptions = ''
    keep-outputs = true
    keep-derivations = true
    fallback = true
    sandbox = false  # Required for PRoot
  '';
}
```

### Cross-Compilation Setup

For building packages on a more powerful machine:

```nix
# On your build host
{
  nixpkgs.crossSystem = {
    system = "aarch64-linux";
  };
}
```

## Security Considerations

1. **PRoot Limitations**: PRoot doesn't provide real isolation - it's a user-space solution
2. **File Permissions**: Android's SELinux may interfere with some operations
3. **Network Security**: Use SSH keys, not passwords, for remote access
4. **Backup Strategy**: Regular backups to external storage are essential

## Performance Optimization

1. **Storage**: Use adopted storage or external SD card for /nix/store
2. **Compilation**: Avoid building from source; use binary caches
3. **Memory**: Monitor RAM usage; Android may kill processes
4. **CPU**: Limit concurrent builds with `nix.settings.max-jobs = 2`

## Future Enhancements

- [ ] Automated rootfs building via GitHub Actions
- [ ] Integration with cachix for binary caching
- [ ] Systemd-nspawn alternative exploration
- [ ] GUI application support via VNC
- [ ] Integration with Termux:X11

## Contributing

Contributions are welcome! Please consider:
- Testing on different Android versions
- Optimizing for specific architectures
- Improving systemd compatibility
- Adding device-specific configurations

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Termux team for the amazing terminal emulator
- NixOS community for the powerful package manager
- PRoot developers for user-space virtualization
- nix-on-droid project for Android-specific insights
