# Team Image Deployment Guide

**Audience**: Development team members and colleagues receiving pre-built NixOS images
**Purpose**: Comprehensive reference for understanding, building, and deploying NixOS images from this configuration

## Table of Contents

1. [Overview](#overview)
2. [Image Types and Use Cases](#image-types-and-use-cases)
3. [Understanding the Build System](#understanding-the-build-system)
4. [Packages and Derivations](#packages-and-derivations)
5. [Building Images](#building-images)
6. [Deploying Images](#deploying-images)
7. [Customization and Extension](#customization-and-extension)
8. [Troubleshooting](#troubleshooting)

---

## Overview

This repository provides automated NixOS image building for consistent development and deployment environments. Images are built declaratively using Nix flakes, ensuring reproducibility across team members.

### What You Get

- **WSL Tarballs**: Pre-configured NixOS for Windows Subsystem for Linux
- **VM Images**: QEMU-compatible qcow2 images for virtual machines
- **Consistency**: Same configuration across all deployment targets
- **Reproducibility**: Bit-for-bit identical builds from the same flake inputs

### Quick Start

```bash
# Clone repository
git clone <repository-url>
cd nixcfg

# Build WSL tarball (two steps)
nix build '.#packages.x86_64-linux.wsl-image'
sudo ./result/bin/nixos-wsl-tarball-builder nixos-wsl-minimal

# Build VM image (single step)
nix build '.#packages.x86_64-linux.vm-image'

# Result: ./nixos-wsl-minimal.wsl and ./result/nixos.qcow2
```

---

## Image Types and Use Cases

### WSL Tarball (`.wsl` format)

**Use Case**: Windows developers needing NixOS development environment

**Advantages**:
- Native Windows integration via WSL2
- Fast filesystem access
- Shared network and process space with Windows
- Easy IDE integration (VS Code Remote-WSL, etc.)

**Target Audience**:
- Windows 11 users
- Colleagues without Linux hardware
- Testing WSL-specific configurations

**Distribution Method**: Share `.wsl` tarball file (1-2GB compressed)

### VM Image (`.qcow2` format)

**Use Case**: Testing, isolated environments, server deployment

**Advantages**:
- Full isolation from host system
- Hardware emulation for testing
- Portable across Linux/macOS hosts
- Snapshot and clone capabilities

**Target Audience**:
- Linux/macOS developers
- CI/CD systems
- Testing environments
- Server deployment scenarios

**Distribution Method**: Share `.qcow2` image file (4-5GB)

---

## Understanding the Build System

### Architecture Overview

```
flake.nix
  └─ nixosConfigurations.nixos-wsl-minimal
      ├─ config.system.build.tarballBuilder  ──→  WSL tarball builder
      └─ [entire system configuration]       ──→  VM image source

flake-modules/images.nix
  ├─ images.wsl-minimal  ──→  packages.x86_64-linux.wsl-image
  └─ images.vm-minimal   ──→  packages.x86_64-linux.vm-image
```

### Key Components

#### 1. NixOS Configuration (`nixosConfigurations.nixos-wsl-minimal`)

**Location**: `flake.nix` (defined in flake-modules/nixos-configurations.nix)
**Purpose**: Base system configuration for all images
**Contains**: User accounts, packages, services, system settings

This is the **source of truth** for what goes into images. Modifying this configuration changes all derived images.

#### 2. Image Building Module (`flake-modules/images.nix`)

**Purpose**: Transforms NixOS configuration into distributable image formats
**Technology**:
- **WSL**: Uses `NixOS-WSL` upstream tarball builder
- **VM**: Uses `nixos-generators` with qcow2 format

#### 3. Flake Packages

**Purpose**: Exposes images as buildable flake outputs
**Usage**: `nix build '.#packages.x86_64-linux.<image-name>'`

---

## Packages and Derivations

### Package Outputs

The flake exposes two primary packages under `packages.x86_64-linux`:

```bash
# List all packages
nix flake show --json | jq -r '.packages."x86_64-linux" | keys[]'
```

#### `packages.x86_64-linux.wsl-image`

**Type**: Derivation → Executable builder script
**Output**: `./result/bin/nixos-wsl-tarball-builder`
**Derivation Path**: `/nix/store/...-nixos-wsl-tarball-builder.drv`

**What it builds**:
1. Full NixOS system closure (all packages, configs, dependencies)
2. Wrapper script that packages closure into WSL-compatible tarball
3. Metadata for WSL integration (systemd, networking, mount points)

**Why not a direct tarball?**
Nix builds run in sandboxes without root access. Creating a WSL tarball requires:
- Root-owned files (`/etc`, `/nix/store`, etc.)
- Special permissions and symlinks
- WSL-specific directory structures

The builder script bridges this gap by running **outside** the Nix sandbox with `sudo`.

#### `packages.x86_64-linux.vm-image`

**Type**: Derivation → qcow2 disk image
**Output**: `./result/nixos.qcow2`
**Derivation Path**: `/nix/store/...-nixos-disk-image.drv`

**What it builds**:
1. Full NixOS system closure
2. Bootloader (GRUB) configuration
3. Disk image with partitions and filesystem
4. qcow2 compression and metadata

**Single-step process**: No sudo required, fully builds within Nix sandbox.

### Derivation Deep Dive

#### Understanding Derivations

A **derivation** is Nix's build recipe. It specifies:
- **Inputs**: Dependencies (other derivations, source files)
- **Build script**: How to transform inputs into output
- **Outputs**: Files produced (binaries, images, scripts)

```bash
# Inspect WSL derivation
nix derivation show '.#packages.x86_64-linux.wsl-image'

# Inspect VM derivation
nix derivation show '.#packages.x86_64-linux.vm-image'

# Show full dependency tree
nix-store --query --tree $(nix path-info --derivation '.#packages.x86_64-linux.vm-image')
```

#### Build Derivation vs Runtime Dependencies

- **Build-time**: Tools needed to create the image (QEMU, tar, compression tools)
- **Runtime**: Software included in the final image (vim, git, systemd services)

Example:
- `qemu-utils` is a **build dependency** (creates qcow2)
- `vim` is a **runtime dependency** (included in image)

### System Build Outputs

The NixOS configuration provides multiple build outputs under `config.system.build`:

```bash
# List all available build outputs
nix eval '.#nixosConfigurations.nixos-wsl-minimal.config.system.build' --apply 'builtins.attrNames'
```

**Key outputs**:
- `tarballBuilder` - WSL tarball creation script (used by images.nix)
- `toplevel` - Full system activation script
- `vm` - VM runner script (for quick testing)
- `etc` - /etc directory contents
- `bootStage2` - Stage 2 boot script

We use `tarballBuilder` for WSL images. For other image formats, we could use `toplevel` as the base.

---

## Building Images

### Prerequisites

**Required**:
- Nix 2.18+ with flakes enabled
- Linux x86_64 or WSL2 environment
- 10GB+ free disk space
- 4GB+ RAM

**For WSL tarball creation**:
- `sudo` access (final step only)

**Verify setup**:
```bash
nix --version  # Should show 2.18+
nix flake --help  # Should not error
df -h /nix/store  # Check disk space
```

### Building WSL Tarball

**Two-step process**:

#### Step 1: Build the Builder Script

```bash
nix build '.#packages.x86_64-linux.wsl-image'
```

**What happens**:
1. Nix evaluates `flake.nix` and `flake-modules/images.nix`
2. Resolves `nixosConfigurations.nixos-wsl-minimal`
3. Extracts `config.system.build.tarballBuilder`
4. Builds all dependencies (NixOS closure, ~1500+ packages)
5. Creates wrapper script at `./result/bin/nixos-wsl-tarball-builder`

**Output**: `./result` symlink → `/nix/store/...-nixos-wsl-tarball-builder/`

**Time**: 5-15 minutes (first build), 1-2 minutes (cached)

**Verify**:
```bash
ls -lh ./result/bin/nixos-wsl-tarball-builder
# Should show executable script

file ./result/bin/nixos-wsl-tarball-builder
# Should show "shell script, ASCII text executable"
```

#### Step 2: Execute the Builder

```bash
sudo ./result/bin/nixos-wsl-tarball-builder nixos-wsl-minimal
```

**What happens**:
1. Script reads NixOS closure from `/nix/store`
2. Creates temporary directory with proper ownership
3. Assembles WSL-specific directory structure
4. Creates `/etc`, `/nix`, `/bin`, `/usr/bin` symlinks
5. Compresses to `.tar.gz` with `.wsl` extension
6. Cleans up temporary files

**Output**: `./nixos-wsl-minimal.wsl` (in current directory)

**Time**: 2-5 minutes

**Why sudo?**:
- Creates files owned by root (uid=0, gid=0)
- Sets proper permissions (755, 644, etc.)
- Creates device nodes if needed

**Custom filename**:
```bash
sudo ./result/bin/nixos-wsl-tarball-builder my-team-nixos
# Output: ./my-team-nixos.wsl
```

**Verify**:
```bash
file nixos-wsl-minimal.wsl
# Should show "gzip compressed data"

tar -tzf nixos-wsl-minimal.wsl | head -20
# Should show tarball contents (./etc, ./nix, etc.)
```

### Building VM Image

**Single-step process**:

```bash
nix build '.#packages.x86_64-linux.vm-image'
```

**What happens**:
1. Nix evaluates flake and resolves `nixos-generators` input
2. Calls `nixosGenerate` with `format = "qcow"`
3. Builds NixOS system closure
4. Installs GRUB bootloader
5. Creates disk image with partitions
6. Converts to qcow2 format with compression
7. Creates `./result/nixos.qcow2`

**Output**: `./result` symlink → `/nix/store/...-nixos-disk-image/nixos.qcow2`

**Time**: 10-20 minutes (first build), 2-5 minutes (cached)

**No sudo required**: Entire build runs in Nix sandbox.

**Verify**:
```bash
qemu-img info ./result/nixos.qcow2
# Should show:
# - format: qcow2
# - virtual size: ~20-30GB (sparse)
# - disk size: ~4-5GB (actual)

file ./result/nixos.qcow2
# Should show "QEMU QCOW2 Image"
```

### Build Commands Reference

| Command | Output | Time (first) | Time (cached) | sudo? |
|---------|--------|--------------|---------------|-------|
| `nix build '.#packages.x86_64-linux.wsl-image'` | Builder script | 5-15 min | 1-2 min | No |
| `sudo result/bin/nixos-wsl-tarball-builder <name>` | `.wsl` tarball | 2-5 min | 2-5 min | **Yes** |
| `nix build '.#packages.x86_64-linux.vm-image'` | `.qcow2` image | 10-20 min | 2-5 min | No |

### Incremental Builds and Caching

**Nix automatically caches**:
- Individual packages
- Intermediate derivations
- System closures

**Cache locations**:
1. `/nix/store` - Local cache
2. `https://cache.nixos.org` - Binary cache (upstream packages)
3. Custom binary caches (if configured)

**Force rebuild**:
```bash
nix build '.#packages.x86_64-linux.vm-image' --rebuild
```

**Clear cache**:
```bash
# Remove old generations and unused packages
nix-collect-garbage -d

# Remove specific build
rm ./result
nix-store --delete /nix/store/...-nixos-disk-image
```

---

## Deploying Images

### Deploying WSL Tarball

#### Prerequisites (Windows)

- Windows 11 (recommended) or Windows 10 version 1903+
- WSL2 enabled
- Administrator access (first-time setup)

**Enable WSL2** (if not already):
```powershell
# From Administrator PowerShell
wsl --install --no-distribution
wsl --set-default-version 2
```

#### Import Steps

**1. Transfer tarball to Windows**

From WSL:
```bash
# Copy to Windows-accessible location
cp nixos-wsl-minimal.wsl /mnt/c/temp/
```

Or use file sharing, USB drive, network share, etc.

**2. Import into WSL**

From PowerShell:
```powershell
# Choose installation directory
$WSL_DIR = "C:\WSL\nixos-minimal"

# Import tarball
wsl --import nixos-minimal $WSL_DIR C:\temp\nixos-wsl-minimal.wsl

# Verify import
wsl --list --verbose
# Should show: nixos-minimal  Running  2
```

**3. Launch**

```powershell
# Start WSL instance
wsl -d nixos-minimal

# Or set as default
wsl --set-default nixos-minimal
wsl
```

#### First Boot Configuration

After launching:

```bash
# Check system info
uname -a
cat /etc/os-release

# Verify Nix works
nix --version
nix-shell -p hello --run hello

# Check user setup
whoami
groups

# Update channels (if needed)
sudo nix-channel --update
```

#### WSL Management

```powershell
# List instances
wsl --list --verbose

# Stop instance
wsl --terminate nixos-minimal

# Unregister (delete)
wsl --unregister nixos-minimal
```

### Deploying VM Image

#### Prerequisites (Linux/macOS)

**Option A - QEMU** (command-line):
- QEMU installed (`qemu-system-x86_64`)
- KVM support (for hardware acceleration)

**Option B - virt-manager** (GUI):
- libvirt + virt-manager installed
- User in `libvirt` group

**Check prerequisites**:
```bash
# Check QEMU
which qemu-system-x86_64

# Check KVM support
ls /dev/kvm
# If exists, you have hardware acceleration

# Check libvirt
systemctl status libvirtd
```

#### Deployment with QEMU

**Basic launch**:
```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cpu host \
  -smp 4 \
  -drive file=./result/nixos.qcow2,format=qcow2 \
  -net nic -net user
```

**With graphics**:
```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cpu host \
  -smp 4 \
  -drive file=./result/nixos.qcow2,format=qcow2 \
  -vga virtio \
  -display gtk \
  -net nic -net user,hostfwd=tcp::2222-:22
```

**SSH access** (with port forwarding):
```bash
# From host
ssh -p 2222 nixos@localhost
```

#### Deployment with virt-manager

**1. Copy image to libvirt storage**:
```bash
sudo cp ./result/nixos.qcow2 /var/lib/libvirt/images/nixos-minimal.qcow2
sudo chown libvirt-qemu:kvm /var/lib/libvirt/images/nixos-minimal.qcow2
```

**2. Create VM via GUI**:
1. Open virt-manager
2. File → New Virtual Machine
3. Choose "Import existing disk image"
4. Browse to `/var/lib/libvirt/images/nixos-minimal.qcow2`
5. OS type: Linux, Version: Generic Linux 2024
6. RAM: 4096 MB, CPUs: 4
7. Finish

**3. Boot and connect**:
- Start the VM
- View console via VNC/SPICE
- Login with configured credentials

#### VM Management

**QEMU snapshots**:
```bash
# Create snapshot
qemu-img snapshot -c initial-state ./result/nixos.qcow2

# List snapshots
qemu-img snapshot -l ./result/nixos.qcow2

# Restore snapshot
qemu-img snapshot -a initial-state ./result/nixos.qcow2
```

**Clone VM**:
```bash
# Create copy-on-write clone
qemu-img create -f qcow2 -b ./result/nixos.qcow2 -F qcow2 nixos-clone.qcow2
```

---

## Customization and Extension

### Modifying Image Contents

**To change what's in the images**:

1. **Edit NixOS configuration**:
   ```nix
   # flake.nix or relevant module
   nixosConfigurations.nixos-wsl-minimal = {
     # Add packages
     environment.systemPackages = with pkgs; [
       vim
       git
       docker
       # Add your tools here
     ];

     # Enable services
     services.docker.enable = true;

     # Create users
     users.users.developer = {
       isNormalUser = true;
       extraGroups = [ "wheel" "docker" ];
       initialPassword = "changeme";
     };
   };
   ```

2. **Rebuild images**:
   ```bash
   # Rebuild both images
   nix build '.#packages.x86_64-linux.wsl-image'
   sudo ./result/bin/nixos-wsl-tarball-builder nixos-wsl-v2
   nix build '.#packages.x86_64-linux.vm-image'
   ```

3. **Test changes**:
   - Import new WSL tarball
   - Boot new VM image
   - Verify packages and services

### Adding New Image Formats

To add more formats (ISO, Docker, VirtualBox, etc.):

**Edit `flake-modules/images.nix`**:
```nix
{
  # Add ISO image
  images.iso = withSystem "x86_64-linux" ({ pkgs, ... }:
    inputs.nixos-generators.nixosGenerate {
      system = "x86_64-linux";
      format = "iso";
      modules = [
        self.nixosConfigurations.nixos-wsl-minimal.config
      ];
    }
  );

  # Expose as package
  packages.x86_64-linux.iso-image = self.images.iso;
}
```

**Supported formats** (via nixos-generators):
- `iso` - Live ISO (USB boot, installation)
- `docker` - Docker image
- `virtualbox` - VirtualBox OVA
- `vmware` - VMware VMDK
- `gce` - Google Compute Engine
- `ami` - Amazon AMI
- Many more...

### Creating Specialized Images

**Example: Development-focused image**:

```nix
# flake-modules/images.nix
images.dev-environment = withSystem "x86_64-linux" ({ pkgs, ... }:
  inputs.nixos-generators.nixosGenerate {
    system = "x86_64-linux";
    format = "qcow";
    modules = [
      self.nixosConfigurations.nixos-wsl-minimal.config
      # Additional dev-specific config
      ({ pkgs, ... }: {
        environment.systemPackages = with pkgs; [
          # Language runtimes
          python3
          nodejs
          rustc
          cargo

          # Development tools
          vscode-fhs
          git
          docker-compose

          # Database
          postgresql
          redis
        ];

        services.docker.enable = true;
        services.postgresql.enable = true;
        services.redis.servers."dev".enable = true;

        # Dev user with all access
        users.users.dev = {
          isNormalUser = true;
          extraGroups = [ "wheel" "docker" ];
          openssh.authorizedKeys.keys = [
            "ssh-rsa AAAA... dev@team"
          ];
        };
      })
    ];
  }
);
```

**Build**:
```bash
nix build '.#packages.x86_64-linux.dev-environment'
```

---

## Troubleshooting

### Build Issues

#### Problem: "experimental feature 'flakes' is disabled"

**Cause**: Nix doesn't have flakes enabled

**Solution**:
```bash
# Enable permanently
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# Or use flag
nix --extra-experimental-features "nix-command flakes" build '.#packages.x86_64-linux.wsl-image'
```

#### Problem: "out of space" during build

**Cause**: Insufficient disk space in `/nix/store`

**Solution**:
```bash
# Check space
df -h /nix/store

# Clean up old builds
nix-collect-garbage -d

# If still insufficient, increase disk allocation
```

#### Problem: WSL builder fails with "Permission denied"

**Cause**: Builder script needs root to create tarball

**Solution**:
```bash
# Use sudo for step 2
sudo ./result/bin/nixos-wsl-tarball-builder nixos-wsl-minimal

# Verify script is executable
chmod +x ./result/bin/nixos-wsl-tarball-builder
```

#### Problem: Build hangs or is very slow

**Possible causes**:
1. No binary cache access
2. Building without substitutes
3. Insufficient RAM

**Solutions**:
```bash
# Check cache connectivity
nix-store --verify

# Use more cores
nix build '.#packages.x86_64-linux.vm-image' --max-jobs auto

# Enable more substituters (if offline)
nix build --option substituters "https://cache.nixos.org https://nix-community.cachix.org"
```

### Deployment Issues

#### WSL Import Fails

**Problem**: "The system cannot find the file specified"

**Solution**:
```bash
# Ensure tarball is on Windows filesystem
cp nixos-wsl-minimal.wsl /mnt/c/temp/

# Use Windows path in PowerShell
wsl --import nixos-minimal C:\WSL\nixos-minimal C:\temp\nixos-wsl-minimal.wsl
```

**Problem**: "The requested operation requires elevation"

**Solution**: Run PowerShell as Administrator

#### VM Won't Boot

**Problem**: GRUB error or boot loop

**Solution**:
```bash
# Verify image integrity
qemu-img check ./result/nixos.qcow2

# Rebuild with verbose output
nix build '.#packages.x86_64-linux.vm-image' --print-build-logs

# Try without KVM
qemu-system-x86_64 -m 4096 -drive file=./result/nixos.qcow2,format=qcow2
```

**Problem**: No KVM access

**Solution**:
```bash
# Check KVM exists
ls /dev/kvm

# Add user to kvm group
sudo usermod -aG kvm $USER
# Log out and back in

# If KVM not available, run without acceleration
# (remove -enable-kvm flag)
```

### Runtime Issues

#### Can't Login to Image

**Problem**: Don't know username/password

**Solution**:
```bash
# Check configuration for user setup
nix eval '.#nixosConfigurations.nixos-wsl-minimal.config.users.users' --json | jq 'keys'

# Default may be:
# Username: nixos
# Password: nixos (or none, use sudo)
```

#### Services Not Starting

**Problem**: Docker/Postgres/etc not running

**Solution**:
```bash
# Check service status
systemctl status docker

# Enable service
sudo systemctl enable --now docker

# Check configuration
nix eval '.#nixosConfigurations.nixos-wsl-minimal.config.services.docker.enable'
```

### Getting Help

**Debug build issues**:
```bash
# Show full build logs
nix build '.#packages.x86_64-linux.vm-image' --print-build-logs

# Show derivation details
nix derivation show '.#packages.x86_64-linux.vm-image'

# Check dependencies
nix-store --query --tree ./result
```

**Community resources**:
- NixOS Discourse: https://discourse.nixos.org
- NixOS Wiki: https://nixos.wiki
- #nixos on IRC/Discord

---

## Appendix: Command Reference

### Build Commands

```bash
# List available packages
nix flake show

# Build WSL builder
nix build '.#packages.x86_64-linux.wsl-image'

# Execute WSL builder
sudo ./result/bin/nixos-wsl-tarball-builder <name>

# Build VM image
nix build '.#packages.x86_64-linux.vm-image'

# Build everything
nix build '.#packages.x86_64-linux.wsl-image' \
          '.#packages.x86_64-linux.vm-image'
```

### Inspection Commands

```bash
# Show flake info
nix flake info
nix flake metadata

# Show package details
nix show '.#packages.x86_64-linux.vm-image'

# Show derivation
nix derivation show '.#packages.x86_64-linux.vm-image'

# Get store path
nix path-info '.#packages.x86_64-linux.vm-image'

# Show dependencies
nix-store --query --tree $(nix path-info '.#packages.x86_64-linux.vm-image')

# Show build logs
nix log '.#packages.x86_64-linux.vm-image'
```

### Maintenance Commands

```bash
# Update flake inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Clean up old builds
nix-collect-garbage -d

# Optimize store
nix-store --optimize

# Verify store integrity
nix-store --verify --check-contents
```

### Deployment Commands

**WSL**:
```powershell
# Import
wsl --import <name> <install-dir> <tarball>

# List
wsl --list --verbose

# Launch
wsl -d <name>

# Terminate
wsl --terminate <name>

# Unregister
wsl --unregister <name>
```

**VM**:
```bash
# Launch with QEMU
qemu-system-x86_64 -enable-kvm -m 4096 -drive file=image.qcow2,format=qcow2

# Info
qemu-img info image.qcow2

# Snapshot
qemu-img snapshot -c <snapshot-name> image.qcow2

# Convert format
qemu-img convert -f qcow2 -O raw image.qcow2 image.raw
```

---

## Version History

- **2025-12-15**: Initial documentation for Phase 3 image building implementation
- Configuration source: `nixos-wsl-minimal` NixOS configuration
- Images tested and verified on x86_64-linux

For updates and contributions, see repository commit history.
