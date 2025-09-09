# Flake-Parts Migration Documentation

This repository has been migrated from a monolithic flake.nix to a modular flake-parts structure for improved maintainability, readability, and extensibility.

## What is flake-parts?

[flake-parts](https://flake.parts) is a framework that brings the NixOS module system to Nix flakes, enabling:

- **Modular configuration**: Split large flake.nix into focused, reusable modules
- **System abstraction**: `perSystem` automatically handles multi-platform outputs
- **Code reuse**: Modules can be shared between projects and flakes
- **Ecosystem integration**: Many projects provide flake-parts modules (devenv, rust-flake, etc.)
- **Reduced boilerplate**: Eliminates repetitive helper functions and system handling

## New Structure

### Before (monolithic)
```
flake.nix (19,923 bytes - everything in one file)
├── Complex helper functions (forAllSystems, nixpkgsFor, mkNixosSystem, etc.)
├── All NixOS configurations
├── All home-manager configurations  
├── All Darwin configurations
├── Package definitions
├── Development shells
└── Repetitive system handling logic
```

### After (modular with flake-parts)
```
flake.nix (much smaller - just imports and basic config)
flake-modules/
├── systems.nix           # System configuration and utilities
├── overlays.nix          # Package overlays
├── packages.nix          # Custom packages 
├── dev-shells.nix        # Development environments
├── nixos-configurations.nix    # NixOS system configs
├── darwin-configurations.nix   # macOS system configs  
└── home-configurations.nix     # Home Manager configs
```

## Key Benefits

### 1. **Eliminated Boilerplate**
- No more `forAllSystems` helper function
- No more `nixpkgsFor` repetition  
- `perSystem` automatically handles system-specific outputs
- `withSystem` provides clean cross-system access

### 2. **Better Organization**
- Each concern has its own focused file
- Related functionality is grouped together
- Easier to find and modify specific configurations
- Clear separation between system-level and user-level configs

### 3. **Improved Maintainability**
- Smaller, focused files are easier to understand
- Changes are isolated to relevant modules
- Less risk of breaking unrelated functionality
- Better git diff readability

### 4. **Enhanced Extensibility**
- Easy to add new modules for new functionality
- Can import flake-parts ecosystem modules
- Modular structure supports future growth
- Clean interfaces between components

### 5. **Code Reuse**
- Modules can be shared between different flakes
- Common patterns can be extracted into reusable modules
- Less duplication across configurations

## Usage Examples

### Building packages (same as before)
```bash
nix build .#nixvim-anywhere
nix build .#<package-name>
```

### Using development shells (same as before)  
```bash
nix develop                    # Default development shell
nix develop .#esp32c5         # ESP32-C5 development shell
```

### Applying configurations (same as before)
```bash
# NixOS systems
sudo nixos-rebuild switch --flake .#tblack-t14-nixos

# Home Manager (standalone)
nix run home-manager -- switch --flake .#tim@tblack-t14-nixos
```

### Running apps (new convenience commands)
```bash
nix run .#check               # Run flake checks
nix run .#update              # Update flake inputs
```

## Migration Benefits Summary

1. **19,923 byte monolithic flake.nix** → **Small focused modules**
2. **Complex helper functions** → **Built-in flake-parts abstractions**  
3. **Repetitive system handling** → **Automatic `perSystem` management**
4. **Mixed concerns** → **Clear separation of functionality**
5. **Hard to extend** → **Modular, extensible architecture**

## Future Enhancements

The modular structure enables easy integration of:
- [devenv](https://devenv.sh/) for enhanced development environments
- [rust-flake](https://github.com/juspay/rust-flake) for Rust projects  
- [haskell-flake](https://community.flake.parts/haskell-flake) for Haskell projects
- Custom flake modules for specific workflows
- Third-party ecosystem modules

## Adding New Modules

To add a new flake module:

1. Create `flake-modules/your-module.nix`
2. Add `./flake-modules/your-module.nix` to imports in `flake.nix`
3. Use `perSystem` for system-specific outputs
4. Use `flake` for system-agnostic outputs

Example:
```nix
# flake-modules/your-module.nix
{ inputs, ... }: {
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    # System-specific outputs (packages, devShells, apps, etc.)
    packages.your-package = pkgs.hello;
  };
  
  flake = {
    # System-agnostic outputs (nixosModules, overlays, etc.)
    nixosModules.your-module = ./your-nixos-module.nix;
  };
}
```

This migration significantly improves the maintainability and extensibility of your nixcfg repository while preserving all existing functionality.
