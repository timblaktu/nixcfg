# Image Building Guide

This document explains how to build deployment images from this NixOS configuration for colleague onboarding and testing.

## Overview

This flake provides two types of deployment images:

1. **WSL Tarball** (`.wsl` format) - For Windows Subsystem for Linux import
2. **VM Image** (`.qcow2` format) - For QEMU/KVM virtual machines

Both images are built from the same `nixos-wsl-minimal` configuration, ensuring consistency between deployment targets.

## Prerequisites

### System Requirements

- **Operating System**: Linux (x86_64) or WSL2
- **Nix**: Version 2.18+ with flakes enabled
- **Disk Space**:
  - WSL tarball builder: ~2GB
  - Final WSL tarball: ~1-2GB
  - VM qcow2 image: ~4-5GB
- **Memory**: Minimum 4GB RAM recommended
- **Permissions**: `sudo` access required for WSL tarball creation (final step only)

### Nix Configuration

Ensure experimental features are enabled:

```bash
# Check if flakes are enabled
nix --version
nix flake --help

# If not enabled, add to ~/.config/nix/nix.conf or /etc/nix/nix.conf:
experimental-features = nix-command flakes
```

## Building Images

### WSL Tarball (Two-Step Process)

The WSL tarball build is a **two-step process** due to NixOS-WSL's architecture:

#### Step 1: Build the Tarball Builder Script

```bash
# Build the tarball builder executable
nix build '.#packages.x86_64-linux.wsl-image'

# This produces: ./result/bin/nixos-wsl-tarball-builder
```

**What happens**:
- Nix builds the entire NixOS system closure
- Creates an executable script that packages the closure into WSL format
- Output: `./result` symlink pointing to the builder script in `/nix/store`

**Build time**: 5-15 minutes (first build), 1-2 minutes (cached)

#### Step 2: Execute the Builder (Requires sudo)

```bash
# Run the builder to create the final .wsl tarball
sudo ./result/bin/nixos-wsl-tarball-builder nixos-wsl-minimal

# This produces: ./nixos-wsl-minimal.wsl (in current directory)
```

**What happens**:
- Builder script packages the system closure into WSL tarball format
- Creates filesystem with proper permissions (requires root)
- Compresses to `.wsl` format (~1-2GB)

**Why sudo?**: The builder must create filesystem structures with root-owned files and proper permissions for WSL import.

**Build time**: 2-5 minutes

**Optional**: Customize the output filename:
```bash
sudo ./result/bin/nixos-wsl-tarball-builder my-custom-name
# Produces: ./my-custom-name.wsl
```

### VM Image (Single-Step Process)

The VM image build is a **single-step process** using nixos-generators:

```bash
# Build the qcow2 VM image
nix build '.#packages.x86_64-linux.vm-image'

# This produces: ./result/nixos.qcow2
```

**What happens**:
- Nix builds the entire NixOS system
- nixos-generators packages it as qcow2 format
- Output: `./result/nixos.qcow2` (~4-5GB, ready to use)

**Build time**: 10-20 minutes (first build), 2-5 minutes (cached)

**No sudo required**: VM image building runs entirely in user space.

## Using Built Images

### WSL Import

After building the WSL tarball (both steps complete):

```powershell
# From PowerShell on Windows:
wsl --import nixos-minimal C:\WSL\nixos-minimal \\wsl$\Ubuntu\home\tim\src\nixcfg\nixos-wsl-minimal.wsl

# Launch the imported instance:
wsl -d nixos-minimal
```

**First boot**:
1. WSL will extract and configure the filesystem
2. NixOS will complete initial setup
3. Login as the configured user (check configuration for username)

### VM Boot

After building the VM image:

```bash
# Start with QEMU (adjust memory/CPU as needed)
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cpu host \
  -smp 4 \
  -drive file=./result/nixos.qcow2,format=qcow2 \
  -net nic -net user

# Or with virt-manager/libvirt:
# 1. Copy result/nixos.qcow2 to /var/lib/libvirt/images/
# 2. Create new VM pointing to the qcow2 image
# 3. Boot normally
```

**Graphics**: Add `-vga virtio` or `-display gtk` for graphical output if needed.

## Build Targets Reference

| Target | Command | Output | Requires sudo? |
|--------|---------|--------|----------------|
| WSL Builder | `nix build '.#packages.x86_64-linux.wsl-image'` | `./result/bin/nixos-wsl-tarball-builder` | No |
| WSL Tarball | `sudo ./result/bin/nixos-wsl-tarball-builder [name]` | `./<name>.wsl` | **Yes** |
| VM Image | `nix build '.#packages.x86_64-linux.vm-image'` | `./result/nixos.qcow2` | No |

## Troubleshooting

### WSL Tarball Issues

**Problem**: Builder script fails with "Permission denied"
```bash
# Solution: Ensure you're using sudo
sudo ./result/bin/nixos-wsl-tarball-builder nixos-wsl-minimal
```

**Problem**: "No space left on device"
```bash
# Check disk space
df -h /nix/store

# Clean up old build artifacts
nix-collect-garbage -d
```

**Problem**: WSL import fails with "The system cannot find the file specified"
```powershell
# Ensure WSL path is correct - use WSL-accessible path
# From within WSL, copy to /mnt/c/temp first:
cp nixos-wsl-minimal.wsl /mnt/c/temp/

# Then from PowerShell:
wsl --import nixos-minimal C:\WSL\nixos-minimal C:\temp\nixos-wsl-minimal.wsl
```

### VM Image Issues

**Problem**: Build fails with "out of memory"
```bash
# Increase Nix build memory limits in /etc/nix/nix.conf:
max-jobs = 2
cores = 2
```

**Problem**: qcow2 image doesn't boot
```bash
# Verify image integrity
qemu-img check ./result/nixos.qcow2

# Try rebuilding with verbose output
nix build '.#packages.x86_64-linux.vm-image' --print-build-logs
```

**Problem**: KVM not available
```bash
# Check KVM support
ls /dev/kvm

# If missing, run without -enable-kvm (slower):
qemu-system-x86_64 -m 4096 -drive file=./result/nixos.qcow2,format=qcow2
```

### General Build Issues

**Problem**: "error: experimental Nix feature 'nix-command' is disabled"
```bash
# Enable flakes in ~/.config/nix/nix.conf:
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# Or use --extra-experimental-features:
nix --extra-experimental-features "nix-command flakes" build '.#packages.x86_64-linux.wsl-image'
```

**Problem**: Builds are slow
```bash
# Enable binary caching (should be default)
nix-channel --list
# Ensure https://cache.nixos.org is present

# Check if you're rebuilding unnecessarily
nix-store --verify-path ./result  # Should not rebuild if valid

# Use --max-jobs for parallel builds
nix build '.#packages.x86_64-linux.vm-image' --max-jobs auto
```

## Implementation Details

### Architecture

Images are defined in `flake-modules/images.nix`:

- **WSL**: Uses `nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballBuilder`
  - Provided by NixOS-WSL upstream
  - Two-step process is by design for proper permission handling

- **VM**: Uses `nixos-generators.nixosGenerate` with `format = "qcow"`
  - Single derivation produces ready-to-use image
  - Supports multiple formats (iso, docker, etc.) - currently only qcow2 enabled

### Configuration Source

Both images use the same base configuration:
- **nixosConfiguration**: `nixos-wsl-minimal` (defined in `flake.nix`)
- **System**: `x86_64-linux`
- **Consistency**: Same package set, services, and user configuration

To customize images, modify:
1. `flake.nix` - adjust `nixos-wsl-minimal` configuration
2. `flake-modules/images.nix` - change image build parameters
3. Rebuild images with new configuration

### Why Two Steps for WSL?

The two-step WSL process exists because:

1. **Nix sandbox constraints**: Nix builds run in isolated sandboxes without root access
2. **Filesystem requirements**: WSL tarballs need root-owned files with specific permissions
3. **NixOS-WSL design**: Upstream separates "build closure" (pure) from "create tarball" (impure)

The builder script is the bridge between Nix's pure world and WSL's permission requirements.

## Next Steps

After building images:

1. **Test the images**: Import WSL tarball or boot VM to verify functionality
2. **Document for colleagues**: Create onboarding guide with installation steps
3. **Automate with CI/CD**: Set up GitHub Actions to build images on releases
4. **Distribute**: Upload to GitHub Releases or internal file server

See `docs/ci-cd-integration.md` for automation setup (planned).

## References

- [NixOS-WSL Documentation](https://github.com/nix-community/NixOS-WSL)
- [nixos-generators](https://github.com/nix-community/nixos-generators)
- [Nix Flakes Manual](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html)
- [WSL Import Documentation](https://docs.microsoft.com/en-us/windows/wsl/use-custom-distro)
