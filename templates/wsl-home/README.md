# WSL Home Manager Configuration Template

This template provides a portable home-manager configuration for ANY WSL distribution using shared modules from [timblaktu/nixcfg](https://github.com/timblaktu/nixcfg).

## Requirements

- **ANY WSL distribution** (Ubuntu, Debian, Alpine, NixOS-WSL, etc.)
- Nix package manager installed
- Nix flakes enabled

## Quick Start

1. **Install Nix** (if not already installed):
   ```bash
   sh <(curl -L https://nixos.org/nix/install) --daemon
   ```

2. **Enable flakes** by adding to `~/.config/nix/nix.conf`:
   ```
   experimental-features = nix-command flakes
   ```

3. **Clone or copy this template** to `~/.config/home-manager/`

4. **Edit `flake.nix`** and customize:
   - Change `myuser` to your actual username (in both the configuration name and homeBase)
   - Update `homeDirectory` to match your home directory
   - Customize fonts, keybindings, and other settings

5. **Build and activate**:
   ```bash
   home-manager switch --flake ~/.config/home-manager#myuser@my-wsl
   ```

## What You Get

This template uses `nixcfg.homeManagerModules.wsl-home-base` which provides:

- ✅ User-level WSL tweaks (shell wrappers, environment variables)
- ✅ Windows Terminal settings management (non-destructive merge)
- ✅ WSL utilities (wslu)
- ✅ Home Manager `targets.wsl` configuration
- ✅ Git, Tmux, Neovim, Zsh with sensible defaults
- ✅ Yazi file manager with Windows integration
- ✅ Claude Code configuration with MCP servers

## Platform Compatibility

**WORKS ON**:
- ✅ Ubuntu WSL
- ✅ Debian WSL
- ✅ Alpine WSL
- ✅ NixOS-WSL
- ✅ Any other WSL distribution with Nix installed

This is a **user-level** configuration that doesn't require NixOS.

## Next Steps

1. **Add more packages**:
   ```nix
   homeBase.additionalPackages = with pkgs; [
     ripgrep
     fd
     fzf
   ];
   ```

2. **Enable development tools**:
   ```nix
   homeBase.enableDevelopment = true;
   ```

3. **Configure secrets management** (optional):
   ```nix
   secretsManagement = {
     enable = true;
     rbw.email = "your-email@example.com";
   };
   ```

4. **Learn more**:
   - [Home Manager Manual](https://nix-community.github.io/home-manager/)
   - [nixcfg Shared Modules](https://github.com/timblaktu/nixcfg/blob/main/docs/SHARED-MODULES.md)

## Troubleshooting

### "assertion failed: homeBase.username must be explicitly set"
Make sure you've changed both occurrences of `myuser` in `flake.nix` to your actual username.

### Windows Terminal settings not applying
Ensure Windows Terminal is closed when running `home-manager switch`, then reopen it.

### Command not found after activation
Run `exec $SHELL` to reload your shell environment.
