# NixOS-WSL Distribution Guide

This guide documents how to build and distribute a minimal NixOS-WSL tarball to colleagues.

## Overview

The `nixos-wsl-minimal` configuration provides a lightweight, shareable NixOS installation for WSL2 that includes:

- Basic NixOS system with flakes enabled
- Essential development tools (git, vim, curl, etc.)
- WSL integration utilities
- Simple user setup with default credentials
- Clean base for customization

## Building the Tarball

### Prerequisites

- A system with Nix installed (Linux, macOS, or existing WSL)
- Sudo access (required by the tarball builder)

### Build Command

```bash
# After applying your home-manager configuration with development enabled:
build-wsl-tarball                           # Build default nixos-wsl-minimal
build-wsl-tarball tblack-t14-nixos          # Build personal configuration (runs security checks)
build-wsl-tarball nixos-wsl-minimal timestamp  # Build with timestamped filename
build-wsl-tarball --help                    # Show usage and available configs

# Run security checks only (without building):
nix run '.#nixosConfigurations.tblack-t14-nixos.config.system.build.tarballSecurityCheck' -- tblack-t14-nixos

# Bypass security checks if needed (NOT RECOMMENDED):
WSL_TARBALL_SKIP_CHECKS=1 build-wsl-tarball tblack-t14-nixos

# Or directly without installing:
sudo nix run '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballBuilder'
sudo nix run '.#nixosConfigurations.tblack-t14-nixos.config.system.build.tarballBuilder'
```

This creates a `nixos.wsl` file (approximately 500-600MB) in the current directory.

### Optional: Version with Timestamp

```bash
# Build and rename with timestamp
sudo nix run '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballBuilder' && \
  mv nixos.wsl nixos-wsl-$(date +%Y%m%d-%H%M%S).tar.gz
```

## Distribution to Colleagues

### For Recipients - Installation Instructions

1. **Import the tarball** (in Windows PowerShell/CMD):
   ```powershell
   wsl --import nixos-wsl C:\WSL\nixos nixos.wsl
   ```

2. **Start the distribution**:
   ```powershell
   wsl -d nixos-wsl
   ```

3. **First login tasks**:
   - Change the default password: `passwd`
   - Update the system: `sudo nixos-rebuild switch`

4. **Optional - Set as default**:
   ```powershell
   wsl --set-default nixos-wsl
   ```

### Default Credentials

- **Username**: `nixos`
- **Password**: `nixos` (should be changed immediately)
- **Sudo**: Enabled for wheel group without password (initially)

## Customization Options

### For Distribution Maintainers

To customize the minimal configuration before building:

1. **Edit the configuration**:
   ```bash
   vim hosts/nixos-wsl-minimal/default.nix
   ```

2. **Key customization points**:
   - Default username (line 12)
   - Pre-installed packages (lines 53-64)
   - Shell aliases (lines 67-75)
   - Time zone (line 117)
   - SSH configuration (lines 103-109)

3. **Test locally** before distribution:
   ```bash
   nix build '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.toplevel'
   ```

### For End Users

After installation, users can customize their instance:

1. **Create a flake configuration**:
   ```bash
   sudo mkdir -p /etc/nixos
   sudo vim /etc/nixos/flake.nix
   ```

2. **Example user flake**:
   ```nix
   {
     description = "My NixOS-WSL Config";
     
     inputs = {
       nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
       nixos-wsl.url = "github:nix-community/NixOS-WSL";
     };
     
     outputs = { self, nixpkgs, nixos-wsl }: {
       nixosConfigurations.nixos-wsl = nixpkgs.lib.nixosSystem {
         system = "x86_64-linux";
         modules = [
           nixos-wsl.nixosModules.default
           {
             wsl.enable = true;
             wsl.defaultUser = "myusername";
             
             # Add your customizations here
             environment.systemPackages = with pkgs; [
               nodejs
               python3
               docker
             ];
           }
         ];
       };
     };
   }
   ```

3. **Apply changes**:
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl
   ```

## Advanced Features

The minimal configuration has several features disabled by default that users can enable:

### Enable SSH Server
```nix
services.openssh.enable = true;
services.openssh.ports = [ 2222 ];  # Use non-standard port if multiple WSL instances
```

### Enable USB/IP Support
```nix
wsl.usbip.enable = true;
wsl.usbip.autoAttach = [ "1-1" ];  # Specify bus IDs
```

### Enable Cross-Instance Mounting
```nix
wsl.crossInstanceMount.enable = true;
```

### Add Development Tools
```nix
environment.systemPackages = with pkgs; [
  # Languages
  nodejs
  python3
  rustc
  go
  
  # Tools
  docker
  kubectl
  terraform
  
  # Editors
  vscode
  neovim
];
```

## Comparison with Full Configuration

| Feature | Minimal | Full (tblack-t14-nixos) |
|---------|---------|-------------------------|
| Base System | ✅ | ✅ |
| Flakes | ✅ | ✅ |
| WSL Integration | ✅ Basic | ✅ Advanced |
| Default Shell | Bash | Zsh |
| Development Tools | Basic | Comprehensive |
| ESP-IDF | ❌ | ✅ |
| USB/IP | ❌ | ✅ |
| Home Manager | ❌ | ✅ |
| Custom Scripts | ❌ | ✅ |
| Size | ~400MB | ~2GB+ |

## Troubleshooting

### Build Fails

1. **Check Nix version**:
   ```bash
   nix --version
   ```
   Ensure you have Nix 2.4+ with flakes enabled.

2. **Update flake inputs**:
   ```bash
   nix flake update
   ```

3. **Verify configuration**:
   ```bash
   nix flake check
   ```

### Import Fails in Windows

1. **Check WSL version**:
   ```powershell
   wsl --version
   ```
   Ensure WSL2 is installed and updated.

2. **Check disk space**:
   - Need at least 2GB free space for import
   - Default location: `%LOCALAPPDATA%\Packages\`

3. **Try different location**:
   ```powershell
   wsl --import nixos-wsl D:\WSL\nixos nixos-wsl.tar.gz
   ```

### Performance Issues

1. **Move to faster disk**:
   ```powershell
   wsl --export nixos-wsl nixos-backup.tar.gz
   wsl --unregister nixos-wsl
   wsl --import nixos-wsl D:\WSL\nixos nixos-backup.tar.gz
   ```

2. **Adjust WSL memory**:
   Create/edit `%USERPROFILE%\.wslconfig`:
   ```ini
   [wsl2]
   memory=4GB
   processors=2
   ```

## Automated Security Checks

The build system includes automated security and privacy checks that run before building tarballs. These checks help ensure you don't accidentally include personal information in distributed images.

### What Gets Checked

The security check module (`modules/wsl-tarball-checks.nix`) automatically scans for:

1. **Personal Identifiers**: Usernames like "tim", "tblack", etc. in:
   - `wsl.defaultUser`
   - `users.users` (normal users only)
   - `networking.hostName`

2. **SSH Keys**: Warns if any users have SSH authorized keys configured

3. **Sensitive Environment Variables**: Blocks build if it detects:
   - API tokens (TOKEN, API_KEY, GITHUB_TOKEN, etc.)
   - Passwords and secrets
   - Cloud credentials (AWS_*, etc.)

4. **Git Configuration**: Warns about GIT_AUTHOR_NAME/EMAIL in environment

### Check Results

- **✓ Green**: No issues found, safe for distribution
- **⚠ Yellow Warnings**: Personal information detected but build continues
- **✗ Red Errors**: Critical security issues, build blocked

### Customizing Checks

You can customize the checks in your configuration:

```nix
{
  wsl.tarballChecks = {
    enable = true;  # Enable/disable checks
    personalIdentifiers = [ "tim" "tblack" "myname" ];  # Names to check
    sensitivePatterns = [ "MY_SECRET" "COMPANY_TOKEN" ];  # Env patterns
  };
}
```

## Anonymization for Personal Configurations

When building a personal configuration (like `tblack-t14-nixos`) for distribution, the automated checks will warn you about items that need anonymization:

### Items Automatically Handled by WSL
- **Hostname**: WSL sets this to the Windows computer name on import
- **Network configuration**: WSL manages all networking
- **Hardware settings**: WSL provides virtualized hardware

### Items You Should Review
1. **Username**: Set in `wsl.defaultUser` (e.g., "tim" → generic username)
2. **Git configuration**: Any hardcoded git user.name/user.email
3. **SSH keys**: Remove any private keys from the configuration
4. **API tokens/keys**: Check environment variables and configuration files
5. **Custom paths**: References to specific user directories
6. **Shell history**: Not included in tarball, but check shell rc files

### No Home-Manager Configuration Needed
NixOS configurations don't require a separate homeConfiguration name. The user's home directory is created based on the `wsl.defaultUser` setting in the NixOS configuration.

### Quick Anonymization Checklist
```bash
# Check for usernames
rg "tim|tblack" hosts/YOUR-CONFIG/

# Check for sensitive environment variables
rg "TOKEN|KEY|SECRET|PASSWORD" hosts/YOUR-CONFIG/

# Check for hardcoded paths
rg "/home/tim" hosts/YOUR-CONFIG/
```

## Security Considerations

⚠️ **Important Security Notes**:

1. The default configuration has:
   - Known default password (`nixos`)
   - Sudo without password for wheel group
   - These should be changed immediately after installation

2. For production use:
   - Change default passwords
   - Configure proper sudo rules
   - Enable and configure firewall if needed
   - Review and restrict installed packages

3. The tarball contains no sensitive data or credentials specific to your environment

## Maintenance

### Updating the Base Image

To create an updated tarball with latest packages:

1. Update flake inputs:
   ```bash
   nix flake update
   ```

2. Rebuild tarball:
   ```bash
   ./build-wsl-tarball.sh
   ```

3. Test the new image before distribution

### Version Management

Consider versioning your tarballs:
- Use timestamps: `nixos-wsl-minimal-20240315.tar.gz` (the build script can do this automatically)
- Tag releases in git
- Document changes in a CHANGELOG

## Support Resources

- [NixOS-WSL Documentation](https://nix-community.github.io/NixOS-WSL/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Flakes Guide](https://nixos.wiki/wiki/Flakes)
- [WSL Documentation](https://docs.microsoft.com/en-us/windows/wsl/)

# Appendices

## Why do both build methods require root privileges?

The root privileges are required because the NixOS-WSL tarball builder needs to:

  1. Create system files with proper ownership - The tarball contains files that must be owned by
  root (like /etc, /nix/store entries)
  2. Set special permissions - Some system files need specific permission bits that only root can set
  3. Create device nodes - WSL system initialization requires certain device files

### Can We Avoid This?

Unfortunately, no - not for a proper WSL distribution tarball. The tarball needs to contain a complete root filesystem with correct permissions. NixOS-WSL's builder uses fakeroot internally but still needs real root to set up certain aspects correctly.

### Alternative: Docker-style Build

If you really wanted to avoid sudo, you could theoretically:
  1. Build a derivation with all the files
  2. Use fakeroot to create a tarball with correct permissions
  3. But this would be complex and might not work correctly with WSL's expectations

### Security Note

The sudo requirement is actually a good thing - it makes it explicit that you're building a system image. This isn't just packaging files; it's creating a complete OS distribution.

### For Comparison

Similar operations that require root:

  - docker build (when not in rootless mode)
  - debootstrap (Debian base system)
  - nixos-install (installing NixOS)

The requirement for root is standard when creating system images or distributions. It's not a limitation of our configuration but a fundamental requirement of creating a proper WSL root filesystem.
