# WSL NixOS Configuration Template

This template provides a minimal NixOS-WSL configuration using shared modules from [timblaktu/nixcfg](https://github.com/timblaktu/nixcfg).

## Requirements

- NixOS-WSL distribution installed
- Nix with flakes enabled

## Quick Start

1. Clone or copy this template to your desired location
2. Edit `flake.nix` and customize:
   - `wslCommon.hostname` - Your WSL instance hostname
   - `wslCommon.defaultUser` - Your username
   - `wslCommon.sshPort` - SSH port (default 2222)
   - `wslCommon.authorizedKeys` - Your SSH public keys

3. Generate hardware configuration (if not already present):
   ```bash
   sudo nixos-generate-config --show-hardware-config > hardware-config.nix
   ```

4. Build and activate:
   ```bash
   sudo nixos-rebuild switch --flake .#my-wsl
   ```

## What You Get

This template uses `nixcfg.nixosModules.wsl-base` which provides:

- ✅ System-level WSL integration (wsl.conf, systemd services)
- ✅ User and group management
- ✅ SSH daemon with WSL-specific settings
- ✅ SOPS-nix secrets management integration
- ✅ USB/IP support for hardware passthrough
- ✅ Standard shell aliases (explorer, code, etc.)

## Next Steps

1. **Add Home Manager** (optional but recommended):
   - See the `wsl-home` template for user-level configuration
   - Use standalone home-manager for faster iteration

2. **Customize your system**:
   - Add packages to `environment.systemPackages`
   - Configure services in your flake.nix
   - Override any `wslCommon` defaults

3. **Learn more**:
   - [NixOS-WSL Documentation](https://github.com/nix-community/NixOS-WSL)
   - [nixcfg Shared Modules](https://github.com/timblaktu/nixcfg/blob/main/docs/SHARED-MODULES.md)

## Platform Requirements

**IMPORTANT**: This template requires a full NixOS-WSL distribution. It will NOT work on:
- Vanilla Ubuntu WSL
- Debian WSL
- Alpine WSL
- Other non-NixOS WSL distributions

For portable home-manager configuration that works on ANY WSL distro, see the `wsl-home` template instead.
