# NixOS-WSL Dev Team Quickstart

This guide covers importing and setting up the pre-built NixOS-WSL image on your
Windows 11 laptop.

## Prerequisites

- **Windows 11** with WSL enabled. If not already set up, run from PowerShell (admin):
  ```powershell
  wsl --install --no-distribution
  ```
  Then reboot.
- **Windows Terminal** installed (comes with Windows 11; update from Microsoft Store if needed).

## Download the Image

1. Go to the [latest release](https://github.com/timblaktu/nixcfg/releases/latest).
2. Download both files:
   - `nixcfg-wsl-dev-team-<version>.wsl` — the NixOS-WSL tarball
   - `Import-NixOSWSL.ps1` — the import script

## Import the Image

1. Open **PowerShell** (regular user, not admin).

2. If you haven't run PowerShell scripts before, allow local scripts for this session:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
   ```

3. Navigate to the folder containing both files:
   ```powershell
   cd C:\Users\$env:USERNAME\Downloads    # or wherever you saved them
   ```

4. Run the import script:
   ```powershell
   .\Import-NixOSWSL.ps1 -TarballPath .\nixcfg-wsl-dev-team-*.wsl
   ```

   The script will:
   - Detect where your existing WSL distros are stored and create the new one alongside them
   - Import the tarball via `wsl --import`
   - Create the Windows Terminal profile so it appears as a tab option
   - Verify the instance is responsive

5. **Close and reopen Windows Terminal.** The new "NixOS Dev Team" profile should
   appear in the tab dropdown.

> **Replacing an existing install?** The script detects an existing distro with the
> same name and offers to replace it. Just re-run the same command.

## First Login

1. Open the **NixOS Dev Team** tab in Windows Terminal.

2. You are logged in as user `dev`. Configure your git identity:
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "you@company.com"
   ```

> **Optional**: To rename the `dev` user, run `setup-username <yourname>`, then
> `wsl --shutdown` and reopen. This is cosmetic — all tooling works as `dev`.

## What's Included

**Development tools**: git, neovim, tmux, direnv, shellcheck, jq, fzf, and modern
CLI replacements (eza, bat, delta, dust, zoxide).

**AI coding assistants**: Claude Code and OpenCode, pre-configured with multi-account
wrapper scripts.

**Containers**: Podman with `docker` alias — run containers without Docker Desktop.

**Cross-compilation**: aarch64 (ARM64) builds via QEMU binfmt, for embedded targets.

**Network tools**: curl, httpie, nmap, tcpdump, iperf3, dig, traceroute.

**GitLab integration**: `glab` CLI with credential helpers.

**Passwordless sudo** for the dev workflow (you are in the `wheel` group).

## Updating to a New Version

When a new release is published:

1. Download the new `.wsl` and `Import-NixOSWSL.ps1` files from the
   [releases page](https://github.com/timblaktu/nixcfg/releases/latest).
2. Run the same import command — the script will offer to replace the existing install:
   ```powershell
   .\Import-NixOSWSL.ps1 -TarballPath .\nixcfg-wsl-dev-team-*.wsl
   ```

> Your home directory is reset on reimport. Back up any local work (committed git repos
> are safe if pushed to a remote).

## Alternative: Build from Source

If you prefer to build the tarball yourself (requires Nix):

```bash
# Clone the repo
git clone https://github.com/timblaktu/nixcfg.git
cd nixcfg

# Build the tarball builder
nix build '.#nixosConfigurations.nixos-wsl-dev-team.config.system.build.tarballBuilder'

# Build the tarball (requires sudo for chroot)
sudo ./result/bin/nixos-wsl-tarball-builder nixos.wsl

# Import on Windows
wsl --import nixos-wsl-dev-team <install-location> nixos.wsl
```

## Alternative: Consume as Flake Input

For advanced users who want to customize the image or cherry-pick modules, see
[SHARED-MODULES.md](SHARED-MODULES.md) for the full module catalog and usage examples.

## Troubleshooting

**Distro not appearing in Terminal**
Close and reopen Windows Terminal. The profile is created as a Terminal fragment file
which is picked up on launch.

**"Running scripts is disabled on this system"**
Set the execution policy for the current session:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

**Import failed with "not enough disk space"**
The tarball is approximately 1.8 GB and expands on disk. Free up space on the drive where
your WSL distros are stored (usually `%LOCALAPPDATA%\WSL`).

**Import failed with "WSL is not installed"**
Run `wsl --install --no-distribution` from an admin PowerShell and reboot.

**Distro starts as `root` instead of `dev`**
Check `/etc/wsl.conf` has `default=dev` under `[user]`. Fix if needed:
```bash
sudo sed -i 's/^default=.*/default=dev/' /etc/wsl.conf
```
Then `wsl --shutdown` and reopen.

## Removing / Reinstalling

To remove the distro completely:
```powershell
wsl --unregister nixos-wsl-dev-team
```

Then re-import with the steps above.

## Advanced: Setting as Default Distro

If you want this to be the distro that opens when you type `wsl` in PowerShell:
```powershell
.\Import-NixOSWSL.ps1 -TarballPath .\nixcfg-wsl-dev-team-*.wsl -SetDefault
```
Or after import:
```powershell
wsl --set-default nixos-wsl-dev-team
```
