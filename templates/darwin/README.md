# macOS Configuration Template (nix-darwin + home-manager)

This template provides a minimal macOS configuration using [nix-darwin](https://github.com/LnL7/nix-darwin) and home-manager.

## Requirements

- macOS (Intel or Apple Silicon)
- Nix package manager installed
- Nix flakes enabled

## Quick Start

1. **Install Nix** (if not already installed):
   ```bash
   sh <(curl -L https://nixos.org/nix/install)
   ```

2. **Enable flakes** by creating `~/.config/nix/nix.conf`:
   ```
   experimental-features = nix-command flakes
   ```

3. **Install nix-darwin** (first time only):
   ```bash
   nix run nix-darwin -- switch --flake .#my-mac
   ```

4. **Edit `flake.nix`** and customize:
   - Change `myuser` to your actual username
   - Update `system` to `aarch64-darwin` if using Apple Silicon
   - Customize system defaults, packages, and user configuration
   - Update Git name and email

5. **Build and activate**:
   ```bash
   darwin-rebuild switch --flake .#my-mac
   ```

## What You Get

- ✅ Declarative macOS system configuration
- ✅ Home Manager for user-level packages and dotfiles
- ✅ Sensible macOS defaults (Dock, Finder, keyboard settings)
- ✅ Nix daemon enabled
- ✅ Common development tools (git, vim, curl, etc.)

## Next Steps

1. **Customize system defaults**:
   - Add more macOS preferences in `system.defaults`
   - See [nix-darwin options](https://daiderd.com/nix-darwin/manual/index.html)

2. **Add more packages**:
   ```nix
   environment.systemPackages = with pkgs; [
     neovim
     tmux
     nodejs
   ];
   ```

3. **Configure home-manager**:
   ```nix
   home-manager.users.myuser = { pkgs, ... }: {
     programs.neovim = {
       enable = true;
       viAlias = true;
       vimAlias = true;
     };
   };
   ```

4. **Learn more**:
   - [nix-darwin Documentation](https://github.com/LnL7/nix-darwin)
   - [Home Manager Manual](https://nix-community.github.io/home-manager/)

## Platform Compatibility

- ✅ macOS Intel (x86_64-darwin)
- ✅ macOS Apple Silicon (aarch64-darwin)

Make sure to update the `system` field in `flake.nix` to match your hardware.

## Troubleshooting

### "activation would overwrite existing files"
Some dotfiles may conflict with existing files. Either:
- Back up and remove existing files
- Use `home-manager.backupFileExtension = "backup"` in your config

### "permission denied" when running darwin-rebuild
Try with sudo: `sudo darwin-rebuild switch --flake .#my-mac`

### Changes not taking effect
After switching, you may need to:
- Log out and back in for some system defaults
- Restart the application for app-specific settings
