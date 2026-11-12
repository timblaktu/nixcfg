# Quick Reference: Old vs New Approach

This repository once kept every flake output in a single large `flake.nix`. It now splits those outputs across focused modules under [`modules/flake-parts/`](../modules/flake-parts), each owning one concern. This reference contrasts the old monolithic style ("Before") with the current [flake-parts](https://flake.parts) style ("After") so a reader coming from a classic `flake.nix` can map familiar tasks onto the new layout. For the full architecture, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Where each output lives now

| Flake output | Module |
|--------------|--------|
| Custom packages | [`packages.nix`](../modules/flake-parts/packages.nix) |
| Development shells and `nix run` apps | [`dev-shells.nix`](../modules/flake-parts/dev-shells.nix) |
| NixOS systems | [`nixos-configurations.nix`](../modules/flake-parts/nixos-configurations.nix) |
| macOS (Darwin) systems | [`darwin-configurations.nix`](../modules/flake-parts/darwin-configurations.nix) |
| Home Manager configs | [`home-configurations.nix`](../modules/flake-parts/home-configurations.nix) |
| Nixpkgs overlays | [`overlays.nix`](../modules/flake-parts/overlays.nix) |
| Supported architectures | [`systems.nix`](../modules/flake-parts/systems.nix) |
| Exported module catalog | [`shared-modules.nix`](../modules/flake-parts/shared-modules.nix) |

## Adding a New Package

### ❌ Before (Monolithic)
```nix
# In one massive flake.nix
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
# In focused modules/flake-parts/packages.nix
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
# In focused modules/flake-parts/dev-shells.nix
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
# In focused modules/flake-parts/nixos-configurations.nix
flake.nixosConfigurations = {
  new-host = withSystem "x86_64-linux" ({ pkgs, ... }:
    inputs.nixpkgs.lib.nixosSystem {
      # Clean, flake-parts standard approach
      system = "x86_64-linux";
      modules = [ inputs.self.modules.nixos.new-host /* ... */ ];
    }
  );
};
```

## Common Tasks Comparison

| Task | Before | After |
|------|--------|-------|
| **Find package definitions** | Search through one huge `flake.nix` | Open `modules/flake-parts/packages.nix` |
| **Add development shell** | Navigate massive file | Edit `modules/flake-parts/dev-shells.nix` |
| **Modify NixOS config** | Find among mixed concerns | Edit `modules/flake-parts/nixos-configurations.nix` |
| **Update overlay** | Search through monolith | Edit `modules/flake-parts/overlays.nix` |
| **Add new system support** | Modify helper functions | Built-in `perSystem` handles it |
| **Debug configuration** | Hard to isolate issues | Focused modules, clear errors |
| **Git diff readability** | Huge diffs in one file | Small, focused diffs |
| **Onboard new contributor** | Explain 19k line file | Point to relevant module |

## Usage Commands (Unchanged)

All your existing commands work exactly the same:

```bash
# NixOS deployments (same as before)
sudo nixos-rebuild switch --flake '.#thinky-nixos'

# Home Manager (same as before)
nix run home-manager -- switch --flake '.#tim@thinky-nixos'

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
- One large file holding every output
- Mixed concerns
- Hard to navigate
- Difficult to modify safely

### After: Logical separation
- `systems.nix` (~120 lines) - Supported architectures
- `overlays.nix` (~15 lines) - Package overlays
- `packages.nix` (~60 lines) - Custom packages
- `dev-shells.nix` (~130 lines) - Development environments and `nix run` apps
- `nixos-configurations.nix` (~160 lines) - NixOS systems
- `darwin-configurations.nix` (~90 lines) - macOS systems
- `home-configurations.nix` (~150 lines) - Home Manager configs

Each module owns one concern, so a change touches one small file instead of a monolith. [`flake.nix`](../flake.nix) itself shrinks to roughly fifty lines that just hand the `modules/` tree to [import-tree](https://github.com/vic/import-tree).
