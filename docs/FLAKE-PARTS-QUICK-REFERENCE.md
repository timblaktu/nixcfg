# Quick Reference: Old vs New Approach

## Adding a New Package

### ❌ Before (Monolithic)
```nix
# In massive flake.nix (19,923 bytes)
packages = forAllSystems (system:
  let
    pkgs = nixpkgsFor.${system};
    customPkgs = import ./pkgs { inherit pkgs; };
  in {
    # Add your package here among 50+ other lines
    my-new-package = pkgs.writeShellScript "my-new-package" "echo hello";
    # ... existing packages
  });
```

### ✅ After (Flake-Parts)
```nix
# In focused flake-modules/packages.nix
perSystem = { pkgs, ... }: {
  packages = {
    # Clean, focused file just for packages
    my-new-package = pkgs.writeShellScript "my-new-package" "echo hello";
  };
};
```

## Adding a New Development Shell

### ❌ Before (Monolithic)
```nix
# Buried in the massive flake.nix file
devShells = forAllSystems (system:
  let pkgs = nixpkgsFor.${system}; in {
    # Add among other system logic
    my-shell = pkgs.mkShell { ... };
  }
);
```

### ✅ After (Flake-Parts)
```nix
# In focused flake-modules/dev-shells.nix  
perSystem = { pkgs, ... }: {
  devShells = {
    # Clean, dedicated file for development environments
    my-shell = pkgs.mkShell { ... };
  };
};
```

## Adding a New NixOS Host

### ❌ Before (Monolithic)
```nix
# In the giant flake.nix, find the right spot among hundreds of lines
nixosConfigurations = {
  # ... existing hosts
  new-host = mkNixosSystem {  # Using custom helper function
    hostname = "new-host";
    system = "x86_64-linux";
    # Repeat boilerplate...
  };
};
```

### ✅ After (Flake-Parts)
```nix
# In focused flake-modules/nixos-configurations.nix
flake.nixosConfigurations = {
  new-host = withSystem "x86_64-linux" ({ pkgs, ... }:
    inputs.nixpkgs.lib.nixosSystem {
      # Clean, flake-parts standard approach
      system = "x86_64-linux";
      modules = [ ../hosts/new-host /* ... */ ];
    }
  );
};
```

## Common Tasks Comparison

| Task | Before | After |
|------|--------|-------|
| **Find package definitions** | Search through 19,923 line file | Open `flake-modules/packages.nix` |
| **Add development shell** | Navigate massive file | Edit `flake-modules/dev-shells.nix` |
| **Modify NixOS config** | Find among mixed concerns | Edit `flake-modules/nixos-configurations.nix` |
| **Update overlay** | Search through monolith | Edit `flake-modules/overlays.nix` |
| **Add new system support** | Modify helper functions | Built-in `perSystem` handles it |
| **Debug configuration** | Hard to isolate issues | Focused modules, clear errors |
| **Git diff readability** | Huge diffs in one file | Small, focused diffs |
| **Onboard new contributor** | Explain 19k line file | Point to relevant module |

## Usage Commands (Unchanged)

All your existing commands work exactly the same:

```bash
# NixOS deployments (same as before)
sudo nixos-rebuild switch --flake .\#tblack-t14-nixos

# Home Manager (same as before)  
nix run home-manager -- switch --flake .\#tim@tblack-t14-nixos

# Package builds (same as before)
nix build .\#nixvim-anywhere

# Development shells (same as before)
nix develop
```

## New Features Available

```bash
# Quick validation
nix run .\#check

# Easy updates
nix run .\#update

# Enhanced development shell with helpful info
nix develop  # Now shows available commands and usage tips
```

## File Organization Benefits

### Before: Everything in flake.nix
- 19,923 bytes in one file
- Mixed concerns
- Hard to navigate
- Difficult to modify safely

### After: Logical separation
- `systems.nix` (125 lines) - System utilities
- `overlays.nix` (50 lines) - Package overlays  
- `packages.nix` (150 lines) - Custom packages
- `dev-shells.nix` (200 lines) - Development environments
- `nixos-configurations.nix` (400 lines) - NixOS systems
- `darwin-configurations.nix` (100 lines) - macOS systems
- `home-configurations.nix` (500 lines) - Home Manager configs

**Total: Much more maintainable and extensible!**
