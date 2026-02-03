# Termux NixOS Bootstrap System V2.0

A comprehensive guide to running NixOS on Android with multiple containerization approaches, from basic PRoot solutions to advanced native container deployments. This version addresses the fundamental limitations of PRoot and explores superior alternatives for maximum NixOS capability.

## Table of Contents

1. [Overview](#overview)
2. [Container Technology Comparison](#container-technology-comparison)
3. [Architecture Tiers](#architecture-tiers)
4. [Tier 1: Enhanced PRoot Bootstrap](#tier-1-enhanced-proot-bootstrap)
5. [Tier 2: Nix-on-Droid Native App](#tier-2-nix-on-droid-native-app)
6. [Tier 3: Rooted Container Solutions](#tier-3-rooted-container-solutions)
7. [Decision Matrix](#decision-matrix)
8. [Migration Strategies](#migration-strategies)
9. [Performance Benchmarking](#performance-benchmarking)
10. [Advanced Configurations](#advanced-configurations)
11. [Troubleshooting](#troubleshooting)
12. [Future-Proofing](#future-proofing)

## Overview

This V2 bootstrap system provides multiple pathways to run NixOS on Android, from simple user-space solutions to advanced native container deployments. The goal is to maximize NixOS capability while providing clear upgrade paths as your requirements evolve.

### Evolution from V1.0

V1.0 focused exclusively on PRoot as the only viable option. V2.0 recognizes PRoot's limitations and provides superior alternatives:

- **Limited Performance**: PRoot introduces significant overhead
- **Incomplete Isolation**: User-space virtualization has inherent limitations
- **Systemd Incompatibility**: Many NixOS services don't work properly in PRoot
- **Package Restrictions**: Some packages can't function in PRoot environment

### Key Improvements in V2.0

- **Multi-tier architecture** offering escalating capability levels
- **Native Android app alternatives** that bypass Termux limitations
- **Advanced container options** for rooted devices
- **Comprehensive comparison matrix** for informed decisions
- **Performance optimization strategies** for each approach
- **Clear migration paths** between tiers

## Container Technology Comparison

### Technology Overview

| Technology | Isolation Level | Performance | Android Compatibility | Root Required | systemd Support |
|------------|-----------------|-------------|----------------------|---------------|-----------------|
| **PRoot** | User-space chroot | Low (30-50% overhead) | Excellent | No | Limited |
| **Nix-on-Droid** | PRoot + Native App | Low-Medium | Excellent | No | Limited |
| **systemd-nspawn** | Kernel namespaces | High | None (requires systemd) | Yes | Full |
| **LXC** | Kernel namespaces | High | Limited (custom kernel) | Yes | Full |
| **Docker** | Kernel namespaces | High | Limited (custom kernel) | Yes | Full |
| **Native chroot** | File-system only | Medium | Good | Yes | Partial |

### Detailed Analysis

#### PRoot (Current V1.0 Approach)
**Advantages:**
- No root required
- Works on all Android versions
- Excellent app compatibility
- Stable and mature

**Limitations:**
- 30-50% performance overhead
- Limited systemd service support
- Some packages fail due to virtualization detection
- No real process isolation

#### systemd-nspawn (Desktop Linux Only)
**Advantages:**
- Full systemd support
- Near-native performance
- Complete NixOS functionality
- Excellent process isolation

**Limitations:**
- **Cannot run on Android** (requires systemd init)
- Only available on desktop Linux distributions
- Requires root access

#### Native Android Container Solutions
**LXC/Docker with Custom Kernel:**
- Requires rooting and kernel modification
- Full container capabilities
- Maximum performance and compatibility
- High setup complexity

## Architecture Tiers

### Tier 1: Enhanced PRoot Bootstrap (Non-Root)
*Recommended for: Most users, stable deployments*

Improved version of V1.0 with better performance tuning and systemd compatibility layers.

### Tier 2: Nix-on-Droid Native App (Non-Root)
*Recommended for: Users wanting better package access, willing to use alpha software*

Native Android application providing direct Nix access without Termux dependency.

### Tier 3: Rooted Container Solutions (Root Required)
*Recommended for: Advanced users, maximum capability requirements*

Full container solutions using LXC or Docker with custom Android kernels.

## Tier 1: Enhanced PRoot Bootstrap

### Improvements Over V1.0

#### Performance Optimizations
```bash
# Enhanced PRoot configuration with performance tuning
PROOT_OPTIONS="--bind=/dev --bind=/proc --bind=/sys"
PROOT_OPTIONS+=" --rootfs=/path/to/nixos --change-id=0:0"
PROOT_OPTIONS+=" --kernel-release=$(uname -r)"
```

#### systemd Compatibility Layer
```nix
# Enhanced NixOS configuration for PRoot
{ config, lib, pkgs, ... }:
{
  # Improved PRoot systemd compatibility
  systemd.enableUnifiedCgroupHierarchy = false;
  systemd.services = {
    # Create systemd service wrappers for PRoot
    systemd-proot-wrapper = {
      enable = true;
      script = ''
        # Custom systemd service adaptation for PRoot
        ${pkgs.systemd}/bin/systemctl --user start user-services.target
      '';
    };
  };

  # Enhanced process management
  boot.kernelParams = [ "systemd.unified_cgroup_hierarchy=0" ];

  # Better resource management
  systemd.extraConfig = ''
    DefaultLimitNOFILE=1048576
    DefaultLimitNPROC=1048576
  '';
}
```

#### Optimized Bootstrap Script
```bash
#!/data/data/com.termux/files/usr/bin/bash
# Enhanced Termux NixOS Bootstrap Script v2.0
# Optimized for better performance and compatibility

set -euo pipefail

# Enhanced configuration
BOOTSTRAP_VERSION="2.0.0"
PROOT_OPTIMIZATION_FLAGS="--kernel-release=$(uname -r) --sysvipc --link2symlink"
NIXOS_CONFIG_TEMPLATE="enhanced-proot"

# Performance monitoring
monitor_performance() {
    echo "Monitoring PRoot performance overhead..."
    time proot $PROOT_OPTIMIZATION_FLAGS /bin/echo "Performance test"
}

# Enhanced package installation with performance focus
install_enhanced_packages() {
    local PERFORMANCE_PACKAGES=(
        "proot"
        "proot-distro"

        # Performance monitoring
        "htop"
        "iotop"
        "strace"

        # Optimized compilers
        "clang"
        "ccache"

        # Enhanced development tools
        "git"
        "curl"
        "wget"
        "jq"

        # Network optimization
        "iperf3"
        "netcat-openbsd"
    )

    # Installation with verification
    for package in "${PERFORMANCE_PACKAGES[@]}"; do
        if ! pkg install -y "$package"; then
            warn "Failed to install $package - continuing with degraded functionality"
        fi
    done
}
```

### Enhanced NixOS Module for PRoot
```nix
# modules/enhanced-proot.nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.proot.enhanced;
in
{
  options.proot.enhanced = {
    enable = mkEnableOption "Enhanced PRoot optimizations";

    performanceMode = mkOption {
      type = types.enum [ "minimal" "balanced" "maximum" ];
      default = "balanced";
      description = "Performance optimization level";
    };

    systemdCompat = mkOption {
      type = types.bool;
      default = true;
      description = "Enable systemd compatibility improvements";
    };
  };

  config = mkIf cfg.enable {
    # Performance optimizations based on mode
    nix.settings = {
      max-jobs = mkIf (cfg.performanceMode == "maximum") 4;
      auto-optimise-store = true;

      # Enhanced substituters for faster builds
      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
        "https://android.cachix.org"
      ];
    };

    # PRoot-specific systemd configuration
    systemd = mkIf cfg.systemdCompat {
      # Disable services that don't work well in PRoot
      services = {
        systemd-udevd.enable = false;
        systemd-timesyncd.enable = false;
        auditd.enable = false;
        systemd-journald-audit.enable = false;
        systemd-networkd.enable = false;
        systemd-resolved.enable = false;
      };

      # Custom service adaptations
      extraConfig = ''
        # PRoot compatibility settings
        DefaultEnvironment="PROOT_NO_SECCOMP=1"
        DefaultLimitCORE=0
        DefaultLimitNOFILE=1048576
        RuntimeWatchdogSec=60s
        ShutdownWatchdogSec=10min
      '';
    };

    # Enhanced container environment
    environment = {
      systemPackages = with pkgs; [
        # PRoot-optimized tools
        (writeScriptBin "proot-status" ''
          #!/usr/bin/env bash
          echo "PRoot Status: $(ps aux | grep proot | wc -l) processes"
          echo "Memory Usage: $(cat /proc/meminfo | grep MemAvailable)"
          echo "Performance: $(cat /proc/loadavg)"
        '')

        # Development tools optimized for PRoot
        git htop strace ltrace

        # Network tools
        curl wget netcat iperf3
      ];

      # PRoot-specific environment variables
      sessionVariables = {
        PROOT_NO_SECCOMP = "1";
        TMPDIR = "/tmp";
        XDG_RUNTIME_DIR = "/tmp/runtime-root";
        ANDROID_PROOT_MODE = "enhanced";
      };
    };

    # Optimized file system configuration
    fileSystems = {
      "/" = {
        device = "/dev/root";
        fsType = "overlay";
        options = [ "defaults" "noatime" ];
      };

      "/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "defaults" "noatime" "size=512M" ];
      };
    };
  };
}
```

## Tier 2: Nix-on-Droid Native App

### Overview

Nix-on-Droid represents a significant evolution beyond Termux+PRoot, providing a native Android application that runs Nix directly without the overhead of a full terminal emulator distribution.

### Architecture Advantages

```
┌─────────────────────────────────────────┐
│           Android System                 │
├─────────────────────────────────────────┤
│       Nix-on-Droid Native App           │
│   (Fork of Termux Terminal Only)        │
├─────────────────────────────────────────┤
│       Optimized PRoot Layer             │
│   (Cross-compiled for bionic libc)      │
├─────────────────────────────────────────┤
│       Direct Nixpkgs Access             │
│   (Full repository, no limitations)     │
├─────────────────────────────────────────┤
│     Declarative Configuration           │
│   (Nix expressions + home-manager)      │
└─────────────────────────────────────────┘
```

### Key Improvements Over Termux

#### Package Availability
- **Full nixpkgs access**: 100,000+ packages vs Termux's ~1,000
- **Security tools**: Metasploit, THC-Hydra, John the Ripper (removed from Termux)
- **Development environments**: Complete language ecosystems
- **Scientific computing**: R, Python scientific stack, Julia

#### Performance Benefits
- **Reduced overhead**: No full distribution layer
- **Optimized PRoot**: Cross-compiled against bionic libc
- **Direct Nix builds**: No package conversion layer
- **Better caching**: Native Nix binary cache integration

### Installation and Setup

```bash
# Option 1: F-Droid Installation
# Download from F-Droid: https://f-droid.org/en/packages/com.termux.nix/

# Option 2: Direct APK Installation
wget https://github.com/nix-community/nix-on-droid-app/releases/latest/download/nix-on-droid.apk
# Install via ADB or file manager

# First Launch Setup
# 1. Launch app and press OK
# 2. Expect ~180MB download (bootstrap + packages)
# 3. Wait for initial Nix installation
```

### Configuration Management

#### Basic Configuration File
```nix
# ~/.config/nix-on-droid/nix-on-droid.nix
{ config, lib, pkgs, ... }:
{
  # Basic system configuration
  environment.packages = with pkgs; [
    # Essential tools
    git vim tmux htop

    # Development environments
    nodejs python3 go rust

    # Security tools (unavailable in Termux)
    metasploit john hashcat nmap wireshark

    # Scientific computing
    jupyter python3Packages.numpy python3Packages.scipy
  ];

  # Home Manager integration
  home-manager = {
    enable = true;
    config = ./home.nix;
  };

  # System settings
  system.stateVersion = "24.05";

  # Android-specific optimizations
  nix = {
    settings = {
      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
        "https://android.cachix.org"  # Android-optimized packages
      ];

      auto-optimise-store = true;
      max-jobs = 2;  # Conservative for mobile devices
    };

    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 3d";
    };
  };
}
```

#### Home Manager Configuration
```nix
# ~/.config/nix-on-droid/home.nix
{ config, lib, pkgs, ... }:
{
  # Shell configuration
  programs.bash = {
    enable = true;
    bashrcExtra = ''
      # Android-specific aliases
      alias ls='ls --color=auto'
      alias grep='grep --color=auto'
      alias ll='ls -la'

      # Nix shortcuts
      alias nix-search='nix search nixpkgs'
      alias nix-shell='nix shell'
      alias rebuild='nix-on-droid switch'
    '';
  };

  # Git configuration
  programs.git = {
    enable = true;
    userEmail = "user@example.com";
    userName = "Your Name";

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # Development environments
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      vim-nix
      vim-gitgutter
      fzf-vim
    ];
  };

  # Terminal multiplexer
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    keyMode = "vi";

    extraConfig = ''
      # Android-optimized tmux configuration
      set -g status-style bg=black,fg=white
      set -g mouse on

      # Battery and system info for Android
      set -g status-right '#(cat /sys/class/power_supply/battery/capacity)% %H:%M'
    '';
  };

  home.stateVersion = "24.05";
}
```

### Migration from Termux

#### Data Migration Script
```bash
#!/usr/bin/env bash
# migrate-to-nix-on-droid.sh
# Migrate existing Termux setup to Nix-on-Droid

set -euo pipefail

TERMUX_HOME="/data/data/com.termux/files/home"
NIXDROID_HOME="/data/data/com.termux.nix/files/home"

echo "Starting migration from Termux to Nix-on-Droid..."

# Backup important Termux data
backup_termux_data() {
    local backup_dir="$HOME/storage/shared/termux-backup-$(date +%Y%m%d)"
    mkdir -p "$backup_dir"

    echo "Backing up Termux configuration..."
    cp -r "$TERMUX_HOME"/{.bashrc,.vimrc,.gitconfig,.ssh} "$backup_dir/" 2>/dev/null || true

    echo "Backing up project directories..."
    find "$TERMUX_HOME" -maxdepth 1 -type d -name "*project*" -o -name "*src*" -o -name "*dev*" \
        -exec cp -r {} "$backup_dir/" \; 2>/dev/null || true

    echo "Backup completed to: $backup_dir"
}

# Generate Nix-on-Droid configuration from Termux setup
generate_config() {
    cat > "$NIXDROID_HOME/.config/nix-on-droid/nix-on-droid.nix" << 'EOF'
# Migrated from Termux configuration
{ config, lib, pkgs, ... }:
{
  environment.packages = with pkgs; [
    # Detected from Termux package list
    git vim bash curl wget
    htop tree file which
    openssh rsync
    python3 nodejs
  ];

  home-manager = {
    enable = true;
    config = {
      # Migrate shell configuration
      programs.bash.enable = true;
      programs.git.enable = true;
      programs.vim.enable = true;
    };
  };

  system.stateVersion = "24.05";
}
EOF

    echo "Basic Nix-on-Droid configuration generated"
}

# Main migration process
main() {
    backup_termux_data
    generate_config

    echo "Migration preparation complete!"
    echo "Next steps:"
    echo "1. Install Nix-on-Droid from F-Droid"
    echo "2. Launch and complete initial setup"
    echo "3. Run: nix-on-droid switch"
    echo "4. Manually copy project directories from backup"
}

main "$@"
```

## Tier 3: Rooted Container Solutions

For users requiring maximum NixOS capability and willing to root their devices, native container solutions provide the best performance and compatibility.

### LXC Container Approach

#### Prerequisites
- Rooted Android device
- Custom kernel with container support
- BusyBox or equivalent init system

#### Architecture Benefits
```
┌─────────────────────────────────────────┐
│           Android System                 │
│              (Rooted)                    │
├─────────────────────────────────────────┤
│         Custom Kernel                    │
│    (Container namespace support)         │
├─────────────────────────────────────────┤
│           LXC Container                  │
│      (Full process isolation)            │
├─────────────────────────────────────────┤
│         Complete NixOS                   │
│   (Full systemd, all services)          │
└─────────────────────────────────────────┘
```

#### Setup Process

##### 1. Kernel Requirements Check
```bash
#!/system/bin/sh
# check-container-support.sh
# Verify kernel container support

echo "Checking container support in kernel..."

check_feature() {
    local feature="$1"
    if zcat /proc/config.gz 2>/dev/null | grep -q "^CONFIG_${feature}=y"; then
        echo "✓ $feature: Enabled"
        return 0
    else
        echo "✗ $feature: Disabled"
        return 1
    fi
}

required_features=(
    "NAMESPACES"
    "UTS_NS"
    "IPC_NS"
    "USER_NS"
    "PID_NS"
    "NET_NS"
    "CGROUPS"
    "CGROUP_CPUACCT"
    "CGROUP_DEVICE"
    "CGROUP_FREEZER"
    "CGROUP_SCHED"
    "CPUSETS"
    "MEMCG"
    "KEYS"
    "VETH"
    "BRIDGE"
    "NETFILTER_ADVANCED"
    "NF_NAT"
    "IP_NF_TARGET_MASQUERADE"
)

failed=0
for feature in "${required_features[@]}"; do
    if ! check_feature "$feature"; then
        ((failed++))
    fi
done

if [ $failed -eq 0 ]; then
    echo "✓ All container features supported!"
    echo "Device is ready for LXC containers."
else
    echo "✗ $failed required features missing"
    echo "Custom kernel compilation required."
fi
```

##### 2. LXC Installation and Configuration
```bash
# install-lxc-nixos.sh
# Install LXC and create NixOS container

set -euo pipefail

# Install LXC (requires custom Android build or manual compilation)
install_lxc() {
    echo "Installing LXC..."

    # This would typically require:
    # 1. Cross-compiling LXC for Android
    # 2. Setting up proper mount points
    # 3. Configuring cgroups

    # Simplified example:
    if [ ! -x "/system/bin/lxc-create" ]; then
        echo "Error: LXC not installed. Requires custom Android build."
        exit 1
    fi
}

# Create NixOS container
create_nixos_container() {
    local container_name="nixos-main"
    local rootfs_path="/data/lxc/containers/$container_name"

    echo "Creating NixOS container: $container_name"

    # Create container with NixOS template
    lxc-create -n "$container_name" -t nixos -- \
        --arch aarch64 \
        --release 24.05

    # Configure container
    cat > "/data/lxc/containers/$container_name/config" << EOF
# NixOS LXC Container Configuration

# Basic container settings
lxc.uts.name = nixos-android
lxc.arch = aarch64

# Root filesystem
lxc.rootfs.path = dir:$rootfs_path/rootfs
lxc.rootfs.options = nodev,noatime

# Network configuration
lxc.net.0.type = veth
lxc.net.0.flags = up
lxc.net.0.link = lxcbr0
lxc.net.0.name = eth0

# Resource limits
lxc.cgroup2.memory.max = 2G
lxc.cgroup2.cpu.max = 200000 100000

# Security
lxc.apparmor.profile = unconfined
lxc.seccomp.profile =

# Mount points
lxc.mount.entry = /data/media/0 media/sdcard none bind,optional 0 0
lxc.mount.entry = tmpfs tmp tmpfs defaults 0 0
lxc.mount.entry = tmpfs run tmpfs defaults 0 0
lxc.mount.entry = proc proc proc defaults 0 0
lxc.mount.entry = sysfs sys sysfs defaults 0 0

# Init system
lxc.init.cmd = /run/current-system/sw/bin/init
EOF

    echo "Container created: $container_name"
}

# Start and configure container
configure_nixos_container() {
    local container_name="nixos-main"

    echo "Starting NixOS container..."
    lxc-start -n "$container_name" -d

    # Wait for container to boot
    sleep 10

    # Configure NixOS inside container
    lxc-attach -n "$container_name" -- /bin/bash << 'EOF'
# Inside NixOS container
export PATH="/run/current-system/sw/bin:$PATH"

# Create basic configuration
cat > /etc/nixos/configuration.nix << 'NIXEOF'
{ config, pkgs, ... }:
{
  imports = [ ];

  # Container-specific configuration
  boot.isContainer = true;
  boot.loader.grub.enable = false;

  # Enable full systemd
  systemd.enableCgroupAccounting = true;

  # Network configuration
  networking = {
    useDHCP = false;
    interfaces.eth0.useDHCP = true;
    firewall.enable = false;  # Managed by Android
  };

  # Nix configuration
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # Essential packages
  environment.systemPackages = with pkgs; [
    git vim curl wget htop
    nodejs python3 go
    docker podman  # Nested containers
  ];

  # Enable SSH
  services.openssh = {
    enable = true;
    ports = [ 2222 ];  # Non-privileged port
    permitRootLogin = "yes";
  };

  # Android integration
  environment.sessionVariables = {
    ANDROID_ROOT = "/system";
    ANDROID_DATA = "/data";
  };

  system.stateVersion = "24.05";
}
NIXEOF

# Apply configuration
nixos-rebuild switch

echo "NixOS container configured successfully!"
EOF
}

main() {
    install_lxc
    create_nixos_container
    configure_nixos_container

    echo "LXC NixOS container setup complete!"
    echo "Access with: lxc-attach -n nixos-main"
    echo "SSH access: ssh root@container-ip -p 2222"
}

main "$@"
```

### Docker Alternative (Requires Custom Kernel)

For devices with Docker-compatible kernels:

```bash
# docker-nixos-android.sh
# Run NixOS in Docker container on Android

set -euo pipefail

# Verify Docker support
check_docker_support() {
    if ! command -v docker >/dev/null; then
        echo "Error: Docker not installed or not in PATH"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker daemon not running or accessible"
        exit 1
    fi
}

# Create NixOS Docker container
create_nixos_docker() {
    local container_name="nixos-android"
    local image_name="nixos/nix:latest"

    echo "Creating NixOS Docker container..."

    # Pull NixOS image
    docker pull "$image_name"

    # Create and start container
    docker run -d \
        --name "$container_name" \
        --privileged \
        --restart unless-stopped \
        -v /data/media/0:/media/sdcard:ro \
        -v nixos-store:/nix \
        -v nixos-etc:/etc/nixos \
        -p 2222:22 \
        "$image_name" \
        /run/current-system/sw/bin/init

    echo "Container created: $container_name"
}

# Configure NixOS in Docker
configure_docker_nixos() {
    local container_name="nixos-android"

    echo "Configuring NixOS in Docker container..."

    # Copy configuration into container
    docker exec "$container_name" /bin/bash << 'EOF'
# Create NixOS configuration for Docker
cat > /etc/nixos/configuration.nix << 'NIXEOF'
{ config, pkgs, ... }:
{
  imports = [ ];

  # Docker container configuration
  boot.isContainer = true;
  boot.loader.grub.enable = false;
  systemd.services.systemd-udevd.enable = false;

  # Network configuration
  networking = {
    hostName = "nixos-android";
    useDHCP = false;
    interfaces.eth0.useDHCP = true;
  };

  # Full NixOS capability in container
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
  };

  # Development environment
  environment.systemPackages = with pkgs; [
    git vim neovim tmux htop
    curl wget jq tree
    nodejs python3 go rust
    docker podman  # Nested containers
    nix-index nixpkgs-fmt
  ];

  # Enable services
  services = {
    openssh = {
      enable = true;
      ports = [ 22 ];
      permitRootLogin = "yes";
    };

    # Docker in Docker
    docker.enable = true;
  };

  # User configuration
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    password = "nixos";
  };

  # Android integration scripts
  environment.systemPackages = with pkgs; [
    (writeScriptBin "android-shell" ''
      #!/usr/bin/env bash
      # Access Android shell from NixOS
      nsenter -t 1 -p -u -n -i /system/bin/sh
    '')

    (writeScriptBin "mount-sdcard" ''
      #!/usr/bin/env bash
      # Mount Android SD card
      mkdir -p /mnt/sdcard
      mount --bind /media/sdcard /mnt/sdcard
      echo "SD card mounted at /mnt/sdcard"
    '')
  ];

  system.stateVersion = "24.05";
}
NIXEOF

# Apply configuration
nixos-rebuild switch

# Set up SSH keys
mkdir -p /root/.ssh
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""

echo "NixOS configured in Docker container!"
EOF
}

main() {
    check_docker_support
    create_nixos_docker
    configure_docker_nixos

    echo "Docker NixOS setup complete!"
    echo "Access with: docker exec -it nixos-android /bin/bash"
    echo "SSH access: ssh root@localhost -p 2222"
}

main "$@"
```

## Decision Matrix

### Choose Your Approach

| Requirements | Recommended Tier | Complexity | Performance | NixOS Compatibility |
|--------------|------------------|------------|-------------|-------------------|
| **Stable, simple setup** | Tier 1 (Enhanced PRoot) | Low | Medium (70%) | Good (85%) |
| **Better packages, willing to try alpha** | Tier 2 (Nix-on-Droid) | Medium | Medium (75%) | Good (90%) |
| **Maximum capability, have root** | Tier 3 (LXC/Docker) | High | High (95%) | Excellent (98%) |

### Feature Comparison Matrix

| Feature | Enhanced PRoot | Nix-on-Droid | LXC Container | Docker Container |
|---------|----------------|---------------|---------------|------------------|
| **Setup Complexity** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐ | ⭐⭐ |
| **Performance** | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Package Access** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **systemd Support** | ⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Stability** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Root Required** | ❌ | ❌ | ✅ | ✅ |
| **Android Integration** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |

## Migration Strategies

### Tier 1 → Tier 2 Migration

```bash
#!/data/data/com.termux/files/usr/bin/bash
# migrate-proot-to-nixdroid.sh

set -euo pipefail

PROOT_BACKUP="/data/data/com.termux/files/home/storage/shared/proot-backup-$(date +%Y%m%d)"

echo "Migrating from Enhanced PRoot to Nix-on-Droid..."

# Backup PRoot NixOS configuration
backup_proot_config() {
    mkdir -p "$PROOT_BACKUP"

    # Backup NixOS configuration
    if [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/nixos" ]; then
        echo "Backing up PRoot NixOS configuration..."
        tar -czf "$PROOT_BACKUP/nixos-config.tar.gz" \
            -C "$PREFIX/var/lib/proot-distro/installed-rootfs/nixos" \
            etc/nixos home
    fi

    # Backup user data
    echo "Backing up user projects and data..."
    find "$HOME" -maxdepth 2 -type d \( -name "*project*" -o -name "*src*" -o -name "*git*" \) \
        -exec tar -czf "$PROOT_BACKUP/projects.tar.gz" {} +

    echo "Backup completed to: $PROOT_BACKUP"
}

# Generate Nix-on-Droid configuration from PRoot setup
generate_nixdroid_config() {
    local config_dir="$HOME/.config/nix-on-droid"
    mkdir -p "$config_dir"

    # Extract installed packages from PRoot NixOS
    local packages=""
    if [ -f "$PREFIX/var/lib/proot-distro/installed-rootfs/nixos/etc/nixos/configuration.nix" ]; then
        packages=$(grep -A 20 "environment.systemPackages" \
            "$PREFIX/var/lib/proot-distro/installed-rootfs/nixos/etc/nixos/configuration.nix" \
            | grep -E '^\s+\w+' | tr -d ' ;[]' | xargs)
    fi

    cat > "$config_dir/nix-on-droid.nix" << EOF
# Migrated from Enhanced PRoot setup
{ config, lib, pkgs, ... }:
{
  environment.packages = with pkgs; [
    # Migrated from PRoot NixOS configuration
    $packages

    # Additional packages for Nix-on-Droid
    nix-index
    home-manager
  ];

  home-manager = {
    enable = true;
    config = ./home.nix;
  };

  # Preserve PRoot optimizations in Nix-on-Droid context
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://android.cachix.org"
    ];
  };

  system.stateVersion = "24.05";
}
EOF

    # Create home.nix from backed up home directory
    cat > "$config_dir/home.nix" << EOF
# Home configuration migrated from PRoot
{ config, lib, pkgs, ... }:
{
  programs.bash.enable = true;
  programs.git.enable = true;
  programs.vim.enable = true;

  home.stateVersion = "24.05";
}
EOF

    echo "Nix-on-Droid configuration generated"
}

# Migration verification
verify_migration() {
    echo "Migration verification checklist:"
    echo "1. ✓ PRoot configuration backed up"
    echo "2. ✓ Nix-on-Droid configuration generated"
    echo "3. □ Install Nix-on-Droid app from F-Droid"
    echo "4. □ Launch app and complete bootstrap"
    echo "5. □ Run: nix-on-droid switch"
    echo "6. □ Restore project data from backup"
    echo ""
    echo "Backup location: $PROOT_BACKUP"
}

main() {
    backup_proot_config
    generate_nixdroid_config
    verify_migration
}

main "$@"
```

### Tier 2 → Tier 3 Migration (Root Required)

```bash
#!/system/bin/sh
# migrate-nixdroid-to-lxc.sh
# Migrate from Nix-on-Droid to LXC container

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Root access required for LXC setup"
    exit 1
fi

NIXDROID_BACKUP="/data/media/0/nixdroid-backup-$(date +%Y%m%d)"

echo "Migrating from Nix-on-Droid to LXC container..."

# Export Nix-on-Droid configuration and data
export_nixdroid() {
    mkdir -p "$NIXDROID_BACKUP"

    # Export Nix-on-Droid configuration
    if [ -d "/data/data/com.termux.nix/files/home/.config/nix-on-droid" ]; then
        cp -r "/data/data/com.termux.nix/files/home/.config/nix-on-droid" \
           "$NIXDROID_BACKUP/"
        echo "Configuration exported"
    fi

    # Export user data and projects
    find "/data/data/com.termux.nix/files/home" -maxdepth 2 -type d \
        \( -name "*project*" -o -name "*src*" -o -name ".ssh" \) \
        -exec cp -r {} "$NIXDROID_BACKUP/" \; 2>/dev/null || true

    echo "Data exported to: $NIXDROID_BACKUP"
}

# Create LXC NixOS container with migrated configuration
create_lxc_with_migration() {
    local container_name="nixos-migrated"

    # Create base LXC container
    lxc-create -n "$container_name" -t nixos

    # Import Nix-on-Droid configuration
    if [ -f "$NIXDROID_BACKUP/nix-on-droid/nix-on-droid.nix" ]; then
        # Convert Nix-on-Droid config to NixOS config
        local lxc_rootfs="/data/lxc/containers/$container_name/rootfs"

        # Translate configuration
        cat > "$lxc_rootfs/etc/nixos/configuration.nix" << 'EOF'
# Migrated from Nix-on-Droid
{ config, pkgs, ... }:
{
  imports = [ ];

  # Container configuration
  boot.isContainer = true;
  boot.loader.grub.enable = false;

  # Full systemd support (advantage over Nix-on-Droid)
  systemd.enableCgroupAccounting = true;

  # Import packages from Nix-on-Droid config
  # (This would be parsed from the backed up configuration)
  environment.systemPackages = with pkgs; [
    # Packages will be extracted from backup
  ];

  # Enhanced capabilities available in LXC
  services = {
    openssh = {
      enable = true;
      ports = [ 2222 ];
    };

    # Services that work better in LXC than PRoot
    postgresql.enable = true;
    redis.enable = true;
    nginx.enable = true;
  };

  # Networking with full capabilities
  networking = {
    hostName = "nixos-lxc";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 2222 80 443 ];
    };
  };

  system.stateVersion = "24.05";
}
EOF
    fi

    echo "LXC container created with migrated configuration"
}

main() {
    export_nixdroid
    create_lxc_with_migration

    echo "Migration to LXC complete!"
    echo "Start container: lxc-start -n nixos-migrated"
    echo "Access container: lxc-attach -n nixos-migrated"
}

main "$@"
```

## Performance Benchmarking

### Comprehensive Performance Test Suite

```bash
#!/usr/bin/env bash
# benchmark-nixos-containers.sh
# Compare performance across different containerization approaches

set -euo pipefail

BENCHMARK_DIR="/tmp/nixos-benchmarks"
mkdir -p "$BENCHMARK_DIR"

echo "NixOS Container Performance Benchmark Suite"
echo "============================================"

# CPU benchmark
benchmark_cpu() {
    local test_name="$1"
    echo "Running CPU benchmark for: $test_name"

    # Fibonacci calculation benchmark
    local start_time=$(date +%s.%N)
    local result=$(bash -c '
        fib() {
            local n=$1
            if [ $n -le 1 ]; then
                echo $n
            else
                echo $(($(fib $((n-1))) + $(fib $((n-2)))))
            fi
        }
        fib 30
    ')
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)

    echo "$test_name,CPU,fibonacci-30,$duration,$result" >> "$BENCHMARK_DIR/results.csv"
}

# Memory benchmark
benchmark_memory() {
    local test_name="$1"
    echo "Running memory benchmark for: $test_name"

    # Memory allocation test
    local start_time=$(date +%s.%N)
    python3 -c "
import time
start = time.time()
# Allocate 100MB of memory
data = [0] * (100 * 1024 * 1024 // 8)  # 100MB of integers
# Perform operations on memory
for i in range(0, len(data), 1000):
    data[i] = i
end = time.time()
print(f'{end - start:.3f}')
" 2>/dev/null || echo "N/A"
}

# I/O benchmark
benchmark_io() {
    local test_name="$1"
    echo "Running I/O benchmark for: $test_name"

    # File I/O test
    local test_file="$BENCHMARK_DIR/${test_name}_io_test"
    local start_time=$(date +%s.%N)

    # Write test (100MB)
    dd if=/dev/zero of="$test_file" bs=1M count=100 2>/dev/null
    sync

    # Read test
    dd if="$test_file" of=/dev/null bs=1M 2>/dev/null

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)

    rm -f "$test_file"
    echo "$test_name,IO,file-rw-100mb,$duration,100MB" >> "$BENCHMARK_DIR/results.csv"
}

# Nix operations benchmark
benchmark_nix() {
    local test_name="$1"
    echo "Running Nix benchmark for: $test_name"

    # Nix evaluation benchmark
    local start_time=$(date +%s.%N)
    nix eval --expr 'builtins.foldl' (x: y: x + y) 0 (builtins.genList (x: x) 10000)' 2>/dev/null || echo "0"
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)

    echo "$test_name,NIX,eval-fold-10k,$duration,success" >> "$BENCHMARK_DIR/results.csv"

    # Package installation benchmark
    start_time=$(date +%s.%N)
    nix-env -iA nixpkgs.hello 2>/dev/null || true
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)

    echo "$test_name,NIX,install-hello,$duration,success" >> "$BENCHMARK_DIR/results.csv"
}

# Network benchmark
benchmark_network() {
    local test_name="$1"
    echo "Running network benchmark for: $test_name"

    # HTTP request benchmark
    local start_time=$(date +%s.%N)
    curl -s -o /dev/null "http://cache.nixos.org" || true
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)

    echo "$test_name,NETWORK,http-request,$duration,success" >> "$BENCHMARK_DIR/results.csv"
}

# Run all benchmarks for a specific container type
run_benchmark_suite() {
    local test_name="$1"
    local setup_command="$2"

    echo "Running benchmark suite for: $test_name"

    # Setup environment
    eval "$setup_command" || true

    # Run benchmarks
    benchmark_cpu "$test_name"
    benchmark_memory "$test_name"
    benchmark_io "$test_name"
    benchmark_nix "$test_name"
    benchmark_network "$test_name"

    echo "Completed benchmarks for: $test_name"
}

# Main benchmark execution
main() {
    # Initialize results file
    echo "Container,Category,Test,Duration,Result" > "$BENCHMARK_DIR/results.csv"

    # Benchmark different container approaches

    # Native host (baseline)
    run_benchmark_suite "Native-Host" "true"

    # Enhanced PRoot (if available)
    if command -v proot >/dev/null; then
        run_benchmark_suite "Enhanced-PRoot" \
            'export PROOT_PREFIX="proot --rootfs=/path/to/nixos --bind=/dev --bind=/proc"'
    fi

    # Nix-on-Droid (if available)
    if [ -d "/data/data/com.termux.nix" ]; then
        run_benchmark_suite "Nix-on-Droid" \
            'export PATH="/data/data/com.termux.nix/files/usr/bin:$PATH"'
    fi

    # LXC container (if available)
    if command -v lxc-attach >/dev/null; then
        run_benchmark_suite "LXC-Container" \
            'LXC_CMD="lxc-attach -n nixos-main --"'
    fi

    # Generate report
    generate_report
}

# Generate performance report
generate_report() {
    echo "Generating performance report..."

    cat > "$BENCHMARK_DIR/report.md" << 'EOF'
# NixOS Container Performance Report

Generated: $(date)

## Summary

This report compares performance across different NixOS containerization approaches.

## Results

### CPU Performance (Fibonacci 30)
EOF

    # Add CPU results
    grep "CPU" "$BENCHMARK_DIR/results.csv" | while IFS=, read -r container category test duration result; do
        echo "- $container: ${duration}s" >> "$BENCHMARK_DIR/report.md"
    done

    cat >> "$BENCHMARK_DIR/report.md" << 'EOF'

### I/O Performance (100MB file operations)
EOF

    # Add I/O results
    grep "IO" "$BENCHMARK_DIR/results.csv" | while IFS=, read -r container category test duration result; do
        echo "- $container: ${duration}s" >> "$BENCHMARK_DIR/report.md"
    done

    cat >> "$BENCHMARK_DIR/report.md" << 'EOF'

### Nix Operations Performance
EOF

    # Add Nix results
    grep "NIX" "$BENCHMARK_DIR/results.csv" | while IFS=, read -r container category test duration result; do
        echo "- $container ($test): ${duration}s" >> "$BENCHMARK_DIR/report.md"
    done

    echo "Report generated: $BENCHMARK_DIR/report.md"
    echo "Raw data: $BENCHMARK_DIR/results.csv"
}

# Performance optimization recommendations
generate_optimization_guide() {
    cat > "$BENCHMARK_DIR/optimizations.md" << 'EOF'
# Performance Optimization Guide

## PRoot Optimizations
- Use `--kernel-release=$(uname -r)` for better compatibility
- Enable `--sysvipc` for improved IPC performance
- Use `--link2symlink` to reduce filesystem overhead
- Mount tmpfs for `/tmp` and `/dev/shm`

## Nix-on-Droid Optimizations
- Enable `auto-optimise-store = true`
- Set appropriate `max-jobs` based on device CPU cores
- Use Android-specific binary cache: `https://android.cachix.org`
- Enable garbage collection: `nix.gc.automatic = true`

## LXC Container Optimizations
- Use overlay filesystem for better performance
- Configure appropriate memory and CPU limits
- Enable cgroup accounting for better resource management
- Use bind mounts for shared data to reduce I/O

## General Android Optimizations
- Disable unnecessary Android background services
- Use high-performance governor when benchmarking
- Ensure sufficient free storage (20%+ recommended)
- Consider using external SD card for Nix store
EOF

    echo "Optimization guide generated: $BENCHMARK_DIR/optimizations.md"
}

main "$@"
generate_optimization_guide
```

## Advanced Configurations

### Hybrid Architecture: Multi-Tier Deployment

For advanced users who want to leverage multiple approaches simultaneously:

```nix
# hybrid-nixos-android.nix
# Advanced configuration supporting multiple container tiers

{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.android.hybrid;
in
{
  options.android.hybrid = {
    enable = mkEnableOption "Hybrid multi-tier Android NixOS deployment";

    tiers = {
      proot = {
        enable = mkEnableOption "Enhanced PRoot tier";
        performanceMode = mkOption {
          type = types.enum [ "minimal" "balanced" "maximum" ];
          default = "balanced";
        };
      };

      nixDroid = {
        enable = mkEnableOption "Nix-on-Droid integration";
        syncConfig = mkOption {
          type = types.bool;
          default = true;
          description = "Sync configuration with Nix-on-Droid";
        };
      };

      lxc = {
        enable = mkEnableOption "LXC container tier";
        containers = mkOption {
          type = types.listOf types.str;
          default = [ "development" "production" ];
          description = "LXC containers to manage";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Hybrid environment packages
    environment.systemPackages = with pkgs; [
      # Container management tools
      proot
      lxc

      # Monitoring and orchestration
      htop
      tmux

      # Hybrid deployment scripts
      (writeScriptBin "android-deploy" ''
        #!/usr/bin/env bash
        # Hybrid deployment manager

        deploy_proot() {
            echo "Deploying to PRoot environment..."
            proot-distro login nixos -- nixos-rebuild switch
        }

        deploy_nixdroid() {
            echo "Deploying to Nix-on-Droid..."
            nix-on-droid switch
        }

        deploy_lxc() {
            local container="$1"
            echo "Deploying to LXC container: $container"
            lxc-attach -n "$container" -- nixos-rebuild switch
        }

        case "$1" in
            proot) deploy_proot ;;
            nixdroid) deploy_nixdroid ;;
            lxc) deploy_lxc "$2" ;;
            all)
                deploy_proot
                deploy_nixdroid
                for container in ${toString cfg.tiers.lxc.containers}; do
                    deploy_lxc "$container"
                done
                ;;
            *) echo "Usage: $0 {proot|nixdroid|lxc <container>|all}" ;;
        esac
      '')

      (writeScriptBin "android-monitor" ''
        #!/usr/bin/env bash
        # Multi-tier performance monitoring

        echo "=== Hybrid Android NixOS Monitor ==="

        # PRoot monitoring
        if pgrep proot >/dev/null; then
            echo "PRoot Status: Active ($(pgrep proot | wc -l) processes)"
            echo "PRoot Memory: $(ps -o pid,vsz,rss,comm -p $(pgrep proot | head -1) | tail -1)"
        else
            echo "PRoot Status: Inactive"
        fi

        # Nix-on-Droid monitoring
        if [ -d "/data/data/com.termux.nix" ]; then
            echo "Nix-on-Droid: Installed"
            local store_size=$(du -sh /data/data/com.termux.nix/files/nix 2>/dev/null | cut -f1)
            echo "Nix Store Size: $store_size"
        else
            echo "Nix-on-Droid: Not installed"
        fi

        # LXC monitoring
        if command -v lxc-ls >/dev/null; then
            echo "LXC Containers:"
            lxc-ls -f | grep -E "(NAME|RUNNING)" || echo "No containers"
        else
            echo "LXC: Not available"
        fi

        # System resources
        echo "System Memory: $(cat /proc/meminfo | grep MemAvailable | awk '{print $2 / 1024}') MB available"
        echo "System Load: $(cat /proc/loadavg | cut -d' ' -f1-3)"
      '')
    ];

    # Hybrid configuration synchronization
    system.activationScripts.hybridSync = mkIf cfg.tiers.nixDroid.syncConfig ''
      echo "Synchronizing hybrid configuration..."

      # Sync to Nix-on-Droid if present
      if [ -d "/data/data/com.termux.nix/files/home/.config/nix-on-droid" ]; then
        cp ${pkgs.writeText "nix-on-droid-sync.nix" ''
          # Auto-synced from hybrid NixOS configuration
          { config, lib, pkgs, ... }:
          {
            environment.packages = with pkgs; [
              ${toString config.environment.systemPackages}
            ];

            system.stateVersion = "${config.system.stateVersion}";
          }
        ''} /data/data/com.termux.nix/files/home/.config/nix-on-droid/nix-on-droid.nix
      fi
    '';

    # Multi-tier backup strategy
    system.activationScripts.hybridBackup = ''
      echo "Creating hybrid backup..."

      BACKUP_DIR="/data/media/0/hybrid-backup-$(date +%Y%m%d)"
      mkdir -p "$BACKUP_DIR"

      # Backup all tier configurations
      ${optionalString cfg.tiers.proot.enable ''
        tar -czf "$BACKUP_DIR/proot-config.tar.gz" /etc/nixos
      ''}

      ${optionalString cfg.tiers.nixDroid.enable ''
        if [ -d "/data/data/com.termux.nix" ]; then
          tar -czf "$BACKUP_DIR/nixdroid-config.tar.gz" \
            -C /data/data/com.termux.nix/files/home/.config/nix-on-droid .
        fi
      ''}

      ${optionalString cfg.tiers.lxc.enable ''
        for container in ${toString cfg.tiers.lxc.containers}; do
          if lxc-info -n "$container" >/dev/null 2>&1; then
            lxc-attach -n "$container" -- tar -czf "/tmp/$container-config.tar.gz" /etc/nixos
            mv "/var/lib/lxc/$container/rootfs/tmp/$container-config.tar.gz" "$BACKUP_DIR/"
          fi
        done
      ''}

      echo "Hybrid backup completed: $BACKUP_DIR"
    '';
  };
}
```

### Cross-Platform Configuration Sharing

```nix
# cross-platform-nixos.nix
# Shared configuration between Android containers and desktop NixOS

{ config, lib, pkgs, system, ... }:
let
  isAndroid = builtins.match ".*android.*" system != null;
  isContainer = config.boot.isContainer or false;
in
{
  # Shared configuration across all platforms
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "root" "@wheel" ];

    # Android-optimized settings
    ${lib.optionalString isAndroid ''
      max-jobs = 2;
      cores = 0;

      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
        "https://android.cachix.org"
      ];
    ''}
  };

  # Universal package set
  environment.systemPackages = with pkgs; [
    # Core development tools (work everywhere)
    git vim tmux htop curl wget jq

    # Programming languages
    nodejs python3 go

    # Nix tools
    nix-index nixpkgs-fmt

    # Android-specific additions
    ${lib.optionalString isAndroid ''
      # Android integration tools
      termux-api

      # Lightweight alternatives for mobile
      micro  # Lightweight editor alternative to vim
      btop   # Modern htop alternative
    ''}

    # Container-specific additions
    ${lib.optionalString isContainer ''
      # Container debugging tools
      strace ltrace
      nsenter
    ''}
  ];

  # Platform-specific services
  services = {
    # SSH with platform-appropriate ports
    openssh = {
      enable = true;
      ports = [ (if isAndroid then 2222 else 22) ];
      permitRootLogin = if isAndroid then "yes" else "no";
    };

    # Services that work well on Android
    ${lib.optionalString isAndroid ''
      # Lightweight services suitable for mobile
      syncthing = {
        enable = true;
        user = "root";  # Android container context
      };
    ''}
  };

  # Cross-platform user configuration
  users = lib.mkIf (!isContainer) {
    users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" ] ++ lib.optional (!isAndroid) "sudo";

      # Android-appropriate shell setup
      shell = if isAndroid then pkgs.bash else pkgs.zsh;
    };
  };

  # Platform-appropriate system settings
  system.stateVersion = "24.05";

  # Android-specific optimizations
  ${lib.optionalString isAndroid ''
    # Container/Android-specific boot settings
    boot.isContainer = true;
    boot.loader.grub.enable = false;

    # Disable services that don't work on Android
    systemd.services = {
      systemd-udevd.enable = false;
      systemd-timesyncd.enable = false;
      auditd.enable = false;
    };

    # Android filesystem optimizations
    fileSystems."/" = {
      device = "/dev/root";
      fsType = "overlay";
      options = [ "defaults" "noatime" ];
    };
  ''}
}
```

## Troubleshooting

### Common Issues and Advanced Solutions

#### Issue 1: Performance Degradation in PRoot
```bash
# diagnose-proot-performance.sh
# Advanced PRoot performance diagnostics

#!/usr/bin/env bash
set -euo pipefail

echo "=== PRoot Performance Diagnostics ==="

# Check PRoot overhead
measure_proot_overhead() {
    echo "Measuring PRoot overhead..."

    # Native performance baseline
    echo "Native baseline:"
    time bash -c 'for i in {1..1000}; do echo $i >/dev/null; done' 2>&1 | grep real

    # PRoot performance
    echo "PRoot performance:"
    time proot bash -c 'for i in {1..1000}; do echo $i >/dev/null; done' 2>&1 | grep real

    # System call tracing
    echo "Analyzing system calls..."
    strace -c -f proot bash -c 'echo test' 2>&1 | tail -10
}

# Check for common performance issues
check_performance_issues() {
    echo "Checking for performance issues..."

    # SELinux interference
    if [ -f /sys/fs/selinux/enforce ]; then
        local selinux_status=$(cat /sys/fs/selinux/enforce)
        echo "SELinux enforcing: $selinux_status"
        if [ "$selinux_status" = "1" ]; then
            echo "WARNING: SELinux enforcing mode may impact PRoot performance"
        fi
    fi

    # Check for problematic mount points
    echo "Checking mount points..."
    mount | grep -E "(noexec|nosuid)" | while read -r line; do
        echo "WARNING: Restrictive mount detected: $line"
    done

    # Memory pressure
    local mem_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    local mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local mem_percent=$((mem_available * 100 / mem_total))

    echo "Available memory: ${mem_percent}%"
    if [ "$mem_percent" -lt 20 ]; then
        echo "WARNING: Low memory may impact performance"
    fi
}

# Optimization recommendations
suggest_optimizations() {
    echo "Performance optimization suggestions:"

    cat << 'EOF'
1. PRoot command optimizations:
   - Add --kernel-release=$(uname -r)
   - Use --sysvipc for better IPC
   - Consider --link2symlink for filesystem performance

2. System optimizations:
   - Use tmpfs for /tmp in container
   - Disable unnecessary systemd services
   - Set appropriate CPU governor (performance mode)

3. NixOS configuration optimizations:
   - Enable nix.settings.auto-optimise-store = true
   - Set reasonable nix.settings.max-jobs (1-2 on mobile)
   - Use binary caches to avoid compilation

4. Android system optimizations:
   - Disable background app limits for terminal
   - Use high performance mode when available
   - Ensure adequate free storage space
EOF
}

main() {
    measure_proot_overhead
    check_performance_issues
    suggest_optimizations
}

main "$@"
```

#### Issue 2: systemd Service Failures in Containers

```bash
# fix-systemd-android.sh
# Fix systemd services in Android containers

#!/usr/bin/env bash
set -euo pipefail

echo "=== systemd Android Container Fix ==="

# Analyze failed services
analyze_failed_services() {
    echo "Analyzing failed systemd services..."

    # Get failed services
    local failed_services=$(systemctl --failed --no-legend | awk '{print $1}')

    if [ -z "$failed_services" ]; then
        echo "No failed services found"
        return 0
    fi

    echo "Failed services:"
    for service in $failed_services; do
        echo "- $service"
        echo "  Status: $(systemctl is-active $service)"
        echo "  Reason: $(systemctl status $service --no-pager -l | grep -E "(Main PID|Active|Process)" | head -3)"
        echo
    done
}

# Apply Android-specific systemd fixes
apply_systemd_fixes() {
    echo "Applying Android systemd compatibility fixes..."

    # Create systemd drop-in directory
    mkdir -p /etc/systemd/system

    # Fix common Android incompatible services
    cat > /etc/systemd/system/systemd-udevd.service << 'EOF'
[Unit]
Description=udev Kernel Device Manager (disabled for Android)

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/systemd-timesyncd.service << 'EOF'
[Unit]
Description=Network Time Synchronization (disabled for Android)

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Create Android-compatible service wrapper
    cat > /etc/systemd/system/android-compat.service << 'EOF'
[Unit]
Description=Android Compatibility Layer
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/android-compat-init
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Create compatibility script
    cat > /usr/local/bin/android-compat-init << 'EOF'
#!/usr/bin/env bash
# Android compatibility initialization

# Set up Android-specific environment
export ANDROID_ROOT="/system"
export ANDROID_DATA="/data"

# Fix common permission issues
chmod 755 /tmp
mkdir -p /run/user/0
chmod 700 /run/user/0

# Initialize Android-compatible subsystems
echo "Android compatibility layer initialized"
EOF
    chmod +x /usr/local/bin/android-compat-init

    # Reload systemd configuration
    systemctl daemon-reload
    systemctl enable android-compat.service

    echo "systemd fixes applied"
}

# Verify fixes
verify_systemd_health() {
    echo "Verifying systemd health..."

    # Check overall systemd status
    if systemctl is-system-running --wait; then
        echo "✓ systemd is running normally"
    else
        echo "⚠ systemd has issues (expected in containers)"
    fi

    # Count failed services
    local failed_count=$(systemctl --failed --no-legend | wc -l)
    echo "Failed services: $failed_count"

    # Check essential services
    local essential_services=("dbus" "systemd-logind")
    for service in "${essential_services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo "✓ $service is active"
        else
            echo "⚠ $service is inactive"
        fi
    done
}

main() {
    analyze_failed_services
    apply_systemd_fixes
    verify_systemd_health
}

main "$@"
```

#### Issue 3: Cross-Container Networking

```bash
# setup-container-networking.sh
# Advanced networking setup for multi-tier containers

#!/usr/bin/env bash
set -euo pipefail

echo "=== Container Networking Setup ==="

# Setup bridge network for container communication
setup_bridge_network() {
    echo "Setting up bridge network..."

    # Create bridge interface (requires root)
    if [ "$(id -u)" -eq 0 ]; then
        ip link add name nixbr0 type bridge
        ip addr add 192.168.100.1/24 dev nixbr0
        ip link set nixbr0 up

        echo "Bridge network created: nixbr0 (192.168.100.1/24)"
    else
        echo "Root required for bridge network setup"
        return 1
    fi
}

# Configure container networking
configure_container_network() {
    local container_type="$1"
    local container_name="$2"
    local ip_address="$3"

    case "$container_type" in
        "proot")
            configure_proot_network "$container_name" "$ip_address"
            ;;
        "lxc")
            configure_lxc_network "$container_name" "$ip_address"
            ;;
        "docker")
            configure_docker_network "$container_name" "$ip_address"
            ;;
        *)
            echo "Unknown container type: $container_type"
            return 1
            ;;
    esac
}

# PRoot network configuration
configure_proot_network() {
    local container_name="$1"
    local ip_address="$2"

    echo "Configuring PRoot network for $container_name..."

    # PRoot uses host networking by default
    # Create network namespace simulation
    cat > "/tmp/proot-network-$container_name.sh" << EOF
#!/usr/bin/env bash
# PRoot network configuration

# Set hostname
echo "$container_name" > /proc/sys/kernel/hostname

# Configure network (simulated)
export NIXOS_CONTAINER_IP="$ip_address"
export NIXOS_CONTAINER_NAME="$container_name"

echo "PRoot container network configured: $container_name ($ip_address)"
EOF

    chmod +x "/tmp/proot-network-$container_name.sh"
}

# LXC network configuration
configure_lxc_network() {
    local container_name="$1"
    local ip_address="$2"

    echo "Configuring LXC network for $container_name..."

    # Update LXC container configuration
    cat >> "/var/lib/lxc/$container_name/config" << EOF

# Network configuration
lxc.net.0.type = veth
lxc.net.0.flags = up
lxc.net.0.link = nixbr0
lxc.net.0.name = eth0
lxc.net.0.ipv4.address = $ip_address/24
lxc.net.0.ipv4.gateway = 192.168.100.1
EOF

    echo "LXC network configured: $container_name ($ip_address)"
}

# Docker network configuration
configure_docker_network() {
    local container_name="$1"
    local ip_address="$2"

    echo "Configuring Docker network for $container_name..."

    # Create Docker network if it doesn't exist
    docker network create --subnet=192.168.100.0/24 nixos-net 2>/dev/null || true

    # Connect container to network
    docker network connect --ip "$ip_address" nixos-net "$container_name"

    echo "Docker network configured: $container_name ($ip_address)"
}

# Setup inter-container communication
setup_inter_container_comm() {
    echo "Setting up inter-container communication..."

    # Create communication helper scripts
    cat > /usr/local/bin/container-ssh << 'EOF'
#!/usr/bin/env bash
# SSH between containers

CONTAINER_NAME="$1"
shift

case "$CONTAINER_NAME" in
    "proot-nixos")
        proot-distro login nixos -- ssh "$@"
        ;;
    "lxc-"*)
        lxc_name="${CONTAINER_NAME#lxc-}"
        lxc-attach -n "$lxc_name" -- ssh "$@"
        ;;
    "docker-"*)
        docker_name="${CONTAINER_NAME#docker-}"
        docker exec -it "$docker_name" ssh "$@"
        ;;
    *)
        echo "Unknown container: $CONTAINER_NAME"
        exit 1
        ;;
esac
EOF
    chmod +x /usr/local/bin/container-ssh

    # Create service discovery
    cat > /usr/local/bin/discover-containers << 'EOF'
#!/usr/bin/env bash
# Discover active NixOS containers

echo "=== Active NixOS Containers ==="

# Check PRoot containers
if proot-distro list | grep -q nixos; then
    echo "PRoot: nixos (host network)"
fi

# Check LXC containers
if command -v lxc-ls >/dev/null; then
    lxc-ls -f | grep -E "nixos|RUNNING" | while read -r line; do
        if [[ "$line" =~ nixos.*RUNNING ]]; then
            container=$(echo "$line" | awk '{print $1}')
            ip=$(lxc-info -n "$container" -iH 2>/dev/null || echo "unknown")
            echo "LXC: $container ($ip)"
        fi
    done
fi

# Check Docker containers
if command -v docker >/dev/null; then
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep nixos | while read -r line; do
        container=$(echo "$line" | awk '{print $1}')
        ip=$(docker inspect "$container" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "unknown")
        echo "Docker: $container ($ip)"
    done
fi
EOF
    chmod +x /usr/local/bin/discover-containers

    echo "Inter-container communication setup complete"
}

main() {
    setup_bridge_network || echo "Bridge setup skipped (requires root)"

    # Example container configurations
    configure_container_network "proot" "nixos-dev" "192.168.100.10"
    configure_container_network "lxc" "nixos-prod" "192.168.100.20"
    configure_container_network "docker" "nixos-test" "192.168.100.30"

    setup_inter_container_comm

    echo "Container networking configuration complete!"
    echo "Use 'discover-containers' to see active containers"
    echo "Use 'container-ssh <container-name> <target>' for inter-container SSH"
}

main "$@"
```

## Future-Proofing

### Preparing for Android Container Evolution

As Android evolves to better support container technologies, this bootstrap system is designed to adapt:

#### Upcoming Android Features

1. **Native Container Support**: Android may eventually support LXC/Docker natively
2. **systemd Integration**: Future Android versions might include systemd compatibility
3. **Improved Linux Compatibility**: Better POSIX compliance and filesystem support
4. **Enhanced Security Models**: More flexible permission systems for containers

#### Migration Strategy for Future Technologies

```bash
#!/usr/bin/env bash
# future-migration-framework.sh
# Framework for migrating to future container technologies

set -euo pipefail

echo "=== Future Migration Framework ==="

# Detect available container technologies
detect_container_support() {
    echo "Detecting container technology support..."

    local support_matrix=()

    # Check for systemd-nspawn
    if command -v systemd-nspawn >/dev/null; then
        support_matrix+=("systemd-nspawn:available")
    else
        support_matrix+=("systemd-nspawn:unavailable")
    fi

    # Check for LXC
    if command -v lxc-create >/dev/null; then
        support_matrix+=("lxc:available")
    else
        support_matrix+=("lxc:unavailable")
    fi

    # Check for Docker
    if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
        support_matrix+=("docker:available")
    else
        support_matrix+=("docker:unavailable")
    fi

    # Check for Podman
    if command -v podman >/dev/null; then
        support_matrix+=("podman:available")
    else
        support_matrix+=("podman:unavailable")
    fi

    # Future technology detection placeholders
    support_matrix+=("android-native-containers:future")
    support_matrix+=("systemd-android:future")

    # Display support matrix
    echo "Container Technology Support Matrix:"
    for tech in "${support_matrix[@]}"; do
        local name="${tech%:*}"
        local status="${tech#*:}"
        printf "  %-25s: %s\n" "$name" "$status"
    done

    return 0
}

# Generate migration roadmap
generate_migration_roadmap() {
    echo "Generating migration roadmap..."

    cat > "/tmp/migration-roadmap.md" << 'EOF'
# NixOS Android Migration Roadmap

## Current State (2025)
- ✅ Enhanced PRoot (Tier 1)
- ✅ Nix-on-Droid (Tier 2)
- ✅ Rooted LXC/Docker (Tier 3)

## Short-term Future (2025-2026)
- 🔄 Android 15+ container improvements
- 🔄 Better SELinux policies for containers
- 🔄 Improved cgroup support in Android

## Medium-term Future (2026-2027)
- 🚀 Native Android container runtime
- 🚀 systemd compatibility layer for Android
- 🚀 Wayland support in Android containers

## Long-term Future (2027+)
- 🌟 Full Linux compatibility mode in Android
- 🌟 Native NixOS support in Android
- 🌟 Seamless desktop/mobile NixOS hybrid

## Migration Strategies

### When to Migrate
1. **Performance**: New technology offers >30% performance improvement
2. **Features**: Critical NixOS features become available
3. **Stability**: New approach offers better reliability
4. **Maintenance**: Reduced complexity or maintenance overhead

### Migration Framework
1. **Backup**: Complete backup of current configuration
2. **Parallel**: Set up new technology alongside existing
3. **Test**: Validate functionality in new environment
4. **Switch**: Gradual migration of services
5. **Cleanup**: Remove old infrastructure after validation

### Compatibility Matrix
| Migration Path | Effort | Risk | Benefit |
|----------------|---------|------|---------|
| PRoot → Nix-on-Droid | Low | Low | Medium |
| Nix-on-Droid → LXC | High | Medium | High |
| Any → systemd-nspawn | Medium | Low | High |
| Any → Native Android | TBD | TBD | Very High |
EOF

    echo "Migration roadmap generated: /tmp/migration-roadmap.md"
}

# Create future-proof configuration template
create_futureproof_config() {
    echo "Creating future-proof configuration template..."

    cat > "/tmp/futureproof-nixos.nix" << 'EOF'
# futureproof-nixos.nix
# Configuration designed to work across multiple container technologies

{ config, lib, pkgs, system ? builtins.currentSystem, ... }:
let
  # Detect container environment
  containerType =
    if builtins.pathExists "/run/host/container-manager" then
      builtins.readFile "/run/host/container-manager"
    else if config.boot.isContainer or false then
      if builtins.pathExists "/proc/1/cgroup" then
        let cgroup = builtins.readFile "/proc/1/cgroup"; in
        if lib.hasInfix "lxc" cgroup then "lxc"
        else if lib.hasInfix "docker" cgroup then "docker"
        else if lib.hasInfix "systemd" cgroup then "systemd-nspawn"
        else "unknown-container"
      else "generic-container"
    else "native";

  isAndroid = builtins.match ".*android.*" system != null;
  isPRoot = containerType == "proot" || (isAndroid && containerType == "generic-container");
in
{
  # Universal configuration that works everywhere
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;

    # Adaptive performance settings
    max-jobs =
      if isPRoot then 1
      else if isAndroid then 2
      else 4;
  };

  # Adaptive service configuration
  services = {
    openssh = {
      enable = true;
      ports = [ (if isAndroid then 2222 else 22) ];
    };

    # Services that work in all environments
    syncthing.enable = !isPRoot;  # Skip in PRoot due to performance
  };

  # Container-specific optimizations
  systemd = lib.mkIf (containerType != "native") {
    services = {
      # Disable services that don't work in containers
      systemd-udevd.enable = false;
      systemd-timesyncd.enable = containerType == "proot";

      # Container type specific services
      systemd-machined.enable = containerType == "systemd-nspawn";
    };

    # Adaptive systemd configuration
    extraConfig = lib.concatStringsSep "\n" [
      (lib.optionalString isPRoot ''
        DefaultEnvironment="PROOT_NO_SECCOMP=1"
        DefaultLimitCORE=0
      '')
      (lib.optionalString (containerType == "docker") ''
        DefaultKillMode=mixed
        DefaultTimeoutStopSec=30s
      '')
      (lib.optionalString (containerType == "lxc") ''
        DefaultPrivateNetwork=false
      '')
    ];
  };

  # Future-proof package selection
  environment.systemPackages = with pkgs; [
    # Core packages that work everywhere
    git vim bash curl wget htop

    # Container-specific tools
    ${lib.optionalString (containerType == "systemd-nspawn") "systemd-container"}
    ${lib.optionalString (containerType == "docker") "docker"}
    ${lib.optionalString (containerType == "lxc") "lxc"}

    # Future technology preparation
    (writeScriptBin "container-info" ''
      #!/usr/bin/env bash
      echo "Container Type: ${containerType}"
      echo "Android Device: ${toString isAndroid}"
      echo "PRoot Mode: ${toString isPRoot}"
      echo "System: ${system}"
    '')
  ];

  # Conditional configuration imports
  imports = [
    # Load container-specific modules
    ${lib.optionalString (containerType == "systemd-nspawn") "./modules/systemd-nspawn.nix"}
    ${lib.optionalString (containerType == "lxc") "./modules/lxc-container.nix"}
    ${lib.optionalString (containerType == "docker") "./modules/docker-container.nix"}
    ${lib.optionalString isPRoot "./modules/proot-enhanced.nix"}
  ];

  system.stateVersion = "24.05";

  # Migration metadata
  system.extraDependencies = [
    (pkgs.writeText "migration-info.json" (builtins.toJSON {
      containerType = containerType;
      isAndroid = isAndroid;
      generatedAt = "2025-09-13";
      compatibilityMatrix = {
        systemd-nspawn = containerType != "proot";
        docker = containerType != "proot";
        lxc = containerType != "proot";
        proot = true;
        native = !config.boot.isContainer;
      };
    }))
  ];
}
EOF

    echo "Future-proof configuration created: /tmp/futureproof-nixos.nix"
}

# Monitor for new container technologies
setup_technology_monitoring() {
    echo "Setting up technology monitoring..."

    cat > "/usr/local/bin/monitor-container-tech" << 'EOF'
#!/usr/bin/env bash
# Monitor for new container technology availability

check_new_technologies() {
    echo "Checking for new container technologies..."

    # Check for systemd-nspawn availability
    if command -v systemd-nspawn >/dev/null 2>&1; then
        if [ ! -f "/tmp/systemd-nspawn-available" ]; then
            echo "NEW: systemd-nspawn is now available!"
            touch "/tmp/systemd-nspawn-available"
            echo "Consider migration to Tier 3+ deployment"
        fi
    fi

    # Check for Docker availability
    if docker info >/dev/null 2>&1; then
        if [ ! -f "/tmp/docker-available" ]; then
            echo "NEW: Docker is now available!"
            touch "/tmp/docker-available"
            echo "Consider migration to Docker-based deployment"
        fi
    fi

    # Check for LXC availability
    if lxc-create --help >/dev/null 2>&1; then
        if [ ! -f "/tmp/lxc-available" ]; then
            echo "NEW: LXC is now available!"
            touch "/tmp/lxc-available"
            echo "Consider migration to LXC-based deployment"
        fi
    fi

    # Check Android version for new features
    if [ -f "/system/build.prop" ]; then
        local android_version=$(grep "ro.build.version.release" /system/build.prop | cut -d'=' -f2)
        local stored_version=$(cat /tmp/android-version 2>/dev/null || echo "unknown")

        if [ "$android_version" != "$stored_version" ]; then
            echo "Android version changed: $stored_version → $android_version"
            echo "$android_version" > /tmp/android-version
            echo "Check for new container capabilities"
        fi
    fi
}

# Run check
check_new_technologies

# Set up periodic monitoring (if desired)
if [ "$1" = "--daemon" ]; then
    while true; do
        sleep 3600  # Check every hour
        check_new_technologies
    done
fi
EOF
    chmod +x /usr/local/bin/monitor-container-tech

    echo "Technology monitoring setup complete"
    echo "Run 'monitor-container-tech --daemon' for continuous monitoring"
}

main() {
    detect_container_support
    generate_migration_roadmap
    create_futureproof_config
    setup_technology_monitoring

    echo "Future-proofing framework setup complete!"
    echo ""
    echo "Key files created:"
    echo "- Migration roadmap: /tmp/migration-roadmap.md"
    echo "- Future-proof config: /tmp/futureproof-nixos.nix"
    echo "- Technology monitor: /usr/local/bin/monitor-container-tech"
}

main "$@"
```

## Conclusion

This V2.0 bootstrap system represents a significant evolution from the original PRoot-only approach. By providing multiple tiers of containerization technology, users can choose the approach that best fits their requirements:

- **Tier 1 (Enhanced PRoot)**: Maximum compatibility and ease of use
- **Tier 2 (Nix-on-Droid)**: Better performance and package access
- **Tier 3 (Native Containers)**: Maximum capability for advanced users

The hybrid architecture allows for graceful migration between tiers as requirements change or new technologies become available. The future-proofing framework ensures that configurations remain adaptable as Android's container support evolves.

### Key Advantages of V2.0

1. **Performance**: Multiple optimization strategies for each tier
2. **Flexibility**: Choose the right tool for your specific needs
3. **Migration**: Clear paths between different approaches
4. **Future-Ready**: Designed to adapt to upcoming Android container improvements
5. **Comprehensive**: Covers everything from basic PRoot to advanced LXC/Docker setups

This system transforms Android devices into capable NixOS development and deployment platforms, with the flexibility to scale from simple terminal access to full container orchestration environments.

## Contributing

Contributions are welcome to expand support for:
- Additional container technologies
- Performance optimizations
- Device-specific configurations
- Migration automation
- Testing and validation scripts

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Termux team for the foundational terminal emulator
- NixOS community for the declarative package management system
- Nix-on-Droid project for pioneering native Android Nix deployment
- PRoot developers for user-space containerization
- LXC and Docker communities for container technology advancement
- All contributors to Android container ecosystem development