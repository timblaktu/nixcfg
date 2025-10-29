# Architecture: Standalone-Only Home Manager

## Design Philosophy

This configuration uses **standalone-only** Home Manager for clear separation of concerns:

- **System Configuration**: Managed by NixOS/nix-darwin
- **User Environment**: Managed independently by Home Manager

## Benefits

- ✅ Fast iteration on user environment changes
- ✅ Clear separation of system vs user concerns  
- ✅ Error isolation between system and user environments
- ✅ User autonomy (no root required for user changes)
- ✅ Simplified configuration (no dual-mode complexity)

## Deployment Workflows

### Development (Fast Iteration)
```bash
# Quick user environment updates
home-manager switch --flake '.#tim@thinky-nixos'
```

### System Updates
```bash
# NixOS
sudo nixos-rebuild switch --flake '.#thinky-nixos'

# macOS  
darwin-rebuild switch --flake '.#macbook-air'
```

### Combined Deployment
```bash
# System first, then user environment
sudo nixos-rebuild switch --flake '.#thinky-nixos'
home-manager switch --flake '.#tim@thinky-nixos'
```

## Configuration Structure

### System Configurations
- `hosts/thinky-nixos/` - NixOS system configuration
- `hosts/macbook-air/` - macOS system configuration
- No user environment configuration in system configs

### User Configurations  
- `flake-modules/home-configurations.nix` - All user environments
- `home/modules/` - Shared user modules and configuration
- Independent of system configurations

## Migration Benefits

**Previous integrated approach**: Required `nixos-rebuild switch` for any user environment change.

**Current standalone approach**: Allows independent updates with ~5-15 second overhead vs significant development velocity gains.

## Shared Configuration

Both system and user configurations share:
- Flake inputs (nixpkgs versions, etc.)
- Overlays and package customizations
- Common configuration patterns

This ensures consistency while maintaining independence.