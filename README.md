# Unified Nix Configuration

This repository contains my unified Nix configurations for multiple systems, built with [flake-parts](https://flake.parts) for modular, maintainable configuration management.

- **NixOS** (x86_64, ARM, WSL)
- **macOS** with nix-darwin  
- **Linux** with Home Manager
- **Cross-platform** development environments

## 🚀 Key Features

- **Modular Architecture**: Built with flake-parts for clean, maintainable configuration
- **Multi-System Support**: Seamlessly manage different architectures and platforms
- **WSL Integration**: Advanced WSL support with cross-instance mounting
- **Development Ready**: Comprehensive development environments and tools
- **Secrets Management**: Integrated sops-nix for secure secret handling

## 📁 Repository Structure

```
nixcfg/
├── flake.nix                    # Main flake entry point (modular with flake-parts)
├── flake.lock                   # Lock file
├── FLAKE-PARTS-MIGRATION.md     # Migration documentation
├── flake-modules/               # 🆕 Modular flake components
│   ├── systems.nix              # System configuration and utilities
│   ├── overlays.nix             # Package overlays
│   ├── packages.nix             # Custom packages
│   ├── dev-shells.nix           # Development environments  
│   ├── nixos-configurations.nix # NixOS system configs
│   ├── darwin-configurations.nix# macOS system configs
│   └── home-configurations.nix  # Home Manager configs
├── hosts/                       # Host-specific configurations
│   ├── common/                  # Common configuration shared across hosts
│   ├── mbp/                     # MacBook Pro configuration
│   ├── potato/                  # ARM device configuration
│   ├── thinky-nixos/           # WSL NixOS configuration
│   ├── tblack-t14-nixos/       # Work laptop WSL configuration
│   ├── thinky-ubuntu/          # Ubuntu WSL configuration
│   └── macbook-air/            # macOS configuration
├── home/                        # Home-manager configurations
│   ├── common/                  # Common home-manager modules
│   ├── modules/                 # Structured home modules
│   ├── files/                   # Static files and scripts
│   └── nixvim-minimal.nix      # Minimal nixvim configuration
├── modules/                     # Custom NixOS and Home-manager modules
├── pkgs/                        # Custom packages (nixvim-anywhere, etc.)
├── overlays/                    # Nixpkgs overlays
├── profiles/                    # Configuration profiles
└── secrets/                     # Encrypted secrets (sops-nix)
```

## 🛠️ Usage

**⚠️ Important for zsh users**: All command examples use `\#` to escape the hash character for zsh compatibility. If you're using bash or other shells, you can use just `#`.

### NixOS Systems

**Note**: No new switching commands were added. Use the same commands as before:

```bash
# Apply full system configuration (same as before)
sudo nixos-rebuild switch --flake '.\\#hostname'

# Examples:
sudo nixos-rebuild switch --flake '.\\#tblack-t14-nixos'
sudo nixos-rebuild switch --flake '.\\#thinky-nixos'  
sudo nixos-rebuild switch --flake '.\\#potato'

# Dry run to test changes (recommended)
sudo nixos-rebuild switch --flake '.\\#tblack-t14-nixos' --dry-run
```

### Home Manager (Standalone)

```bash
# Apply user configuration (same as before)
nix run home-manager -- switch --flake '.\\#username@hostname'

# Examples:
nix run home-manager -- switch --flake '.\\#tim@tblack-t14-nixos'
nix run home-manager -- switch --flake '.\\#tim@thinky-ubuntu' 
nix run home-manager -- switch --flake '.\\#tim@nixvim-minimal'

# Dry run to test changes (recommended)
nix run home-manager -- switch --flake '.\\#tim@tblack-t14-nixos' --dry-run
```

### macOS (Darwin)

```bash
# Apply macOS system configuration (same as before)
darwin-rebuild switch --flake '.\\#hostname'

# Example:
darwin-rebuild switch --flake '.\\#macbook-air'
```

### Development Environment

```bash
# Enter development shell with all tools
nix develop

# Or use specific development environments
nix develop '.\\#esp32c5'  # ESP32-C5 development (when available)
```

### 🆕 New Convenience Commands

These are **new additions** provided by the flake-parts migration:

```bash
# Quick flake validation
nix run '.\\#check'

# Update all flake inputs  
nix run '.\\#update'

# Build custom packages (same as before)
nix build '.\\#nixvim-anywhere'
```

## 🎯 Available Configurations

### NixOS Systems
- **mbp**: MacBook Pro running NixOS
- **potato**: ARM device (Raspberry Pi, etc.)
- **thinky-nixos**: WSL NixOS instance
- **tblack-t14-nixos**: Work laptop WSL NixOS

### Home Manager Configurations  
- **tim@mbp**: Full development environment
- **tim@thinky-ubuntu**: Ubuntu WSL with full tools
- **tim@thinky-nixos**: NixOS WSL home config
- **tim@tblack-t14-nixos**: Work environment with ESP-IDF
- **tim@nixvim-minimal**: Minimal Neovim-only configuration
- **tim@tblack-t14-ubuntu**: Minimal Ubuntu WSL setup
- **tim@potato**: ARM device home configuration

### Darwin Systems
- **macbook-air**: macOS configuration with homebrew integration

## ⚡ Benefits of Flake-Parts Migration

This repository was migrated from a monolithic 19,923-byte flake.nix to a modular flake-parts structure:

### Before ❌
- Single massive flake.nix file
- Repetitive helper functions 
- Complex system handling logic
- Mixed concerns in one file
- Hard to maintain and extend

### After ✅  
- **Modular structure** with focused files
- **Eliminated boilerplate** through flake-parts abstractions
- **Automatic system handling** via `perSystem`
- **Clear separation** of concerns
- **Easy to extend** and maintain
- **Future-ready** for ecosystem modules

See [FLAKE-PARTS-MIGRATION.md](./FLAKE-PARTS-MIGRATION.md) for detailed migration documentation.

## 🔧 Custom Packages

- **nixvim-anywhere**: Portable Neovim configuration deployment tool
- **Custom overlays**: Package customizations and patches

## 🔐 Secrets Management

Secrets are managed using [sops-nix](https://github.com/Mic92/sops-nix) with age encryption:

```bash
# Edit secrets
sops secrets/common/example.yaml

# Secrets are automatically decrypted and available to configurations
```

## 🌍 Multi-Platform Support

This configuration supports:
- **x86_64-linux**: Intel/AMD Linux systems
- **aarch64-linux**: ARM Linux systems (Raspberry Pi, etc.)  
- **x86_64-darwin**: Intel macOS systems
- **aarch64-darwin**: Apple Silicon macOS systems

System-specific outputs are automatically generated using flake-parts `perSystem`.

## 🆕 New Features Since Migration

### Enhanced Development Shell
```bash
nix develop
# Now shows helpful information about available commands
```

### Quick Commands
```bash
nix run '.\#check'     # Validate flake quickly
nix run '.\#update'    # Update all inputs
```

### Better Organization
- Each configuration type has its own file
- Easier to find and modify settings
- Better git diff readability
- Reduced risk of breaking changes

## ℹ️ Switching Commands: No Changes

**The flake-parts migration did not change any switching commands.** All your existing workflows remain exactly the same:

| System Type | Command Pattern | Example |
|-------------|----------------|----------|
| **NixOS** | `sudo nixos-rebuild switch --flake '.\#hostname'` | `sudo nixos-rebuild switch --flake '.\#tblack-t14-nixos'` |
| **Home Manager** | `nix run home-manager -- switch --flake '.\#user@host'` | `nix run home-manager -- switch --flake '.\#tim@tblack-t14-nixos'` |
| **macOS** | `darwin-rebuild switch --flake '.\#hostname'` | `darwin-rebuild switch --flake '.\#macbook-air'` |

## 🤔 Potential Future Switching Improvements

While no new switching commands were added in this migration, here are some potential improvements for the future:

```bash
# Potential convenience scripts (not implemented yet)
./scripts/switch-nixos tblack-t14-nixos
./scripts/switch-home tim@tblack-t14-nixos  
./scripts/update-and-switch tblack-t14-nixos

# Or using nix apps (could be added)
nix run '.\#switch-nixos' -- tblack-t14-nixos
nix run '.\#switch-home' -- tim@tblack-t14-nixos
```

## 📚 Documentation

- [Flake-Parts Migration Guide](./FLAKE-PARTS-MIGRATION.md)
- [Implementation Summary](./IMPLEMENTATION-SUMMARY.md) 
- [Migration Checklist](./MIGRATION-CHECKLIST.md)
- [Quick Reference](./QUICK-REFERENCE.md)
- [Detailed Configuration Documentation](./DOCUMENTATION.md)
- [Files Module Testing](./FILES-MODULE-TESTING.md)

## 🤝 Contributing

When adding new functionality:

1. Create focused modules in `flake-modules/`
2. Add system-specific outputs to `perSystem`  
3. Add system-agnostic outputs to `flake`
4. Update documentation

The modular flake-parts structure makes contributions easier and safer by isolating changes to relevant modules.

## 🛠️ Troubleshooting

### Validation
```bash
# Check flake validity
nix flake check

# Show all outputs  
nix flake show

# Run verification script
bash verify-migration.sh  # or chmod +x first, then ./verify-migration.sh
```

### Common Issues
- **Git tracking**: New files must be `git add`ed before Nix can see them
- **System mismatch**: Verify system strings match your actual systems
- **Path issues**: Ensure relative paths in modules are correct (`../`)

### Debug Commands
```bash
# Test specific configurations
nix eval '.\#nixosConfigurations.tblack-t14-nixos.config.system.build.toplevel'
nix eval '.\#homeConfigurations."tim@tblack-t14-nixos".config.home.homeDirectory'
```

### Shell Compatibility
**zsh users**: Must escape hash with `\#` (as shown in all examples)  
**bash/fish users**: Can use either `#` or `\#`  
**Trouble with commands?** Try single quotes: `'.\#hostname'` instead of double quotes

## 🔍 Performance Profiling

For optimizing build and evaluation performance, see **[NIX-PROFILING.md](NIX-PROFILING.md)**.

Quick profiling:
```bash
./nix-profile-proper.sh  # Profile current config
# Make changes, then profile again to compare
```
