# Files Module Testing Guide

This guide provides comprehensive testing for the `home/modules/files` module across multiple platforms.

## Overview

The files module automatically deploys files from `home/files/` to the user's home directory:

- `home/files/bin/` → `~/bin/` (executable files)
- `home/files/claude/` → `~/claude/` (directory tree)
- `home/files/config/` → `~/.config/` (configuration files)

## Test Scripts

### 1. Pre-deployment Testing: `test-files-module.sh`

Tests configuration building and evaluation across all platforms without applying changes.

**Usage:**
```bash
cd /home/tim/src/nixcfg
chmod +x test-files-module.sh
./test-files-module.sh
```

**What it tests:**
- Configuration builds successfully
- Nix evaluation works without errors  
- Expected files are included in home.file
- Bin files are marked executable
- Source paths are valid

**Platforms tested:**
- `tim@thinky-ubuntu` (Home Manager on Ubuntu WSL)
- `tim@thinky-nixos` (NixOS WSL)
- `tim@tblack-t14-nixos` (NixOS WSL - work machine)
- `tim@mbp` (Linux system)
- `tim@potato` (ARM Linux system)

### 2. Post-deployment Verification: `verify-files-deployment.sh`

Verifies actual file deployment after applying home-manager configuration.

**Usage:**
```bash
# After applying home-manager configuration
cd /home/tim/src/nixcfg
chmod +x verify-files-deployment.sh
./verify-files-deployment.sh
```

**What it verifies:**
- All expected files exist in home directory
- Files are properly symlinked to nix store
- Bin files have executable permissions
- Directory structure is correct

## Testing Workflow

### Phase 1: Pre-deployment Testing
```bash
cd /home/tim/src/nixcfg

# Run comprehensive tests across all platforms
./test-files-module.sh
```

### Phase 2: Platform-specific Testing

Test on current platform (thinky-ubuntu):
```bash
# Build only (no activation)
nix build .#homeConfigurations."tim@thinky-ubuntu".activationPackage --no-link

# Preview what would be installed
nix run home-manager -- build --flake .#"tim@thinky-ubuntu" --show-trace

# Check specific file deployments
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq 'keys[]' | grep -E "(bin/|claude/)"
```

### Phase 3: Safe Deployment Testing

Apply with backup on current platform:
```bash
# Apply with backup (safe)
nix run home-manager -- switch --flake .#"tim@thinky-ubuntu" -b backup

# Verify deployment
./verify-files-deployment.sh
```

### Phase 4: Cross-platform Validation

For other platforms, you can test builds without deployment:
```bash
# Test other platforms (build only)
nix build .#homeConfigurations."tim@thinky-nixos".activationPackage --no-link
nix build .#homeConfigurations."tim@mbp".activationPackage --no-link
nix build .#homeConfigurations."tim@potato".activationPackage --no-link
```

## Expected File Deployments

### Bin Files (executable)
- `~/bin/.env`
- `~/bin/bootstrap-secrets.sh`
- `~/bin/claudevloop`
- `~/bin/colorfuncs.sh`
- `~/bin/functions.sh`
- `~/bin/mkclaude_desktop_config`
- `~/bin/restart_claude`

### Claude Files
- `~/claude/prompt/static-prompt.md`

### Config Files
Currently empty (`home/files/config/` exists but is empty)

## Troubleshooting

### Common Issues

1. **Build failures**: Check flake.nix syntax and module imports
2. **Missing files**: Verify files exist in `home/files/` directory
3. **Permission issues**: Ensure bin files are marked executable in module
4. **Path problems**: Verify relative paths in module configuration

### Debugging Commands

```bash
# Check what's in home.file configuration
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq 'keys[]'

# Check specific file configuration
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file.\"bin/restart_claude\" --json

# Test module evaluation in isolation
nix eval --impure --expr 'let pkgs = import <nixpkgs> {}; in (import ./home/modules/files/default.nix { inherit (pkgs) lib; config = { homeBase = {}; }; pkgs = pkgs; })'

# Check file sources
ls -la ~/bin/ | head -5
ls -la ~/claude/
```

### Recovery

If deployment causes issues:
```bash
# Restore from backup (if used -b backup)
cp ~/.zshrc.backup ~/.zshrc  # example

# Or rebuild previous generation
nix run home-manager -- list-generations
nix run home-manager -- switch --switch-generation 1  # previous generation
```

## Integration Testing

After successful deployment, test integration:

```bash
# Test bin files are in PATH
which restart_claude
which claudevloop

# Test claude directory structure
ls ~/claude/prompt/

# Test file content
head ~/bin/restart_claude
cat ~/claude/prompt/static-prompt.md | head -10
```

## Success Criteria

The files module is working correctly when:

1. ✅ All test scripts pass without errors
2. ✅ Expected files are deployed to correct locations
3. ✅ Bin files are executable
4. ✅ Files are symlinked to nix store
5. ✅ No conflicts with existing files
6. ✅ Directory structure is preserved
7. ✅ Configuration builds on all target platforms

Run both test scripts to validate these criteria.
