# NixOS-WSL Tiger Team Quickstart

This guide covers importing and setting up the pre-built NixOS-WSL image on your
Windows 11 laptop.

## Prerequisites

- **Windows 11** with WSL enabled. If not already set up, run from PowerShell (admin):
  ```powershell
  wsl --install --no-distribution
  ```
  Then reboot.
- **Windows Terminal** installed (comes with Windows 11; update from Microsoft Store if needed).
- You received two files from your team lead:
  - `nixos.wsl` — the NixOS-WSL tarball
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
   .\Import-NixOSWSL.ps1 -TarballPath .\nixos.wsl
   ```

   The script will:
   - Detect where your existing WSL distros are stored and create the new one alongside them
   - Import the tarball via `wsl --import`
   - Create the Windows Terminal profile so it appears as a tab option
   - Verify the instance is responsive

5. **Close and reopen Windows Terminal.** The new "NixOS Tiger Team" profile should
   appear in the tab dropdown.

> **Replacing an existing install?** The script detects an existing distro with the
> same name and offers to replace it. Just re-run the same command.

## First Login

1. Open the **NixOS Tiger Team** tab in Windows Terminal.

2. You are logged in as the default `dev` user. Personalize your username:
   ```bash
   setup-username yourname
   ```
   Use lowercase letters, numbers, hyphens, or underscores (e.g. `jsmith`, `alice`).
   Confirm with `y` when prompted.

3. After the rename completes, shut down the distro. In PowerShell:
   ```powershell
   wsl --shutdown
   ```

4. Reopen the NixOS Tiger Team tab. Verify your new identity:
   ```bash
   whoami      # should show your chosen username
   hostname    # nixos-wsl-tiger
   ```

## What's Included

**Development tools**: git, neovim, tmux, direnv, shellcheck, jq, fzf, and modern
CLI replacements (eza, bat, delta, dust, zoxide).

**AI coding assistants**: Claude Code and OpenCode, pre-configured for the Code
Companion enterprise proxy.

**Containers**: Podman with `docker` alias — run containers without Docker Desktop.

**Cross-compilation**: aarch64 (ARM64) builds via QEMU binfmt, for embedded targets.

**Network tools**: curl, httpie, nmap, tcpdump, iperf3, dig, traceroute.

**GitLab integration**: `glab` CLI pre-configured for `git.panasonic.aero`.

**Passwordless sudo** for the dev workflow (you are in the `wheel` group).

## Updating to a New Version

When a new tarball is distributed:

1. Save the new `nixos.wsl` file.
2. Run the same import command — the script will offer to replace the existing install:
   ```powershell
   .\Import-NixOSWSL.ps1 -TarballPath .\nixos.wsl
   ```
3. After import, run `setup-username` again to personalize.

> Your home directory is reset on reimport. Back up any local work (committed git repos
> are safe if pushed to a remote).

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
The tarball is approximately 1.5 GB and expands on disk. Free up space on the drive where
your WSL distros are stored (usually `%LOCALAPPDATA%\WSL`).

**Import failed with "WSL is not installed"**
Run `wsl --install --no-distribution` from an admin PowerShell and reboot.

**`setup-username` says "can only be run by the 'dev' user"**
The username has already been changed from the default. You can verify with `whoami`.

**Distro starts as `root` instead of your user**
The `wsl.conf` default user may not have been updated. Fix it manually:
```bash
sudo sed -i 's/^default=.*/default=yourname/' /etc/wsl.conf
```
Then `wsl --shutdown` and reopen.

## Removing / Reinstalling

To remove the distro completely:
```powershell
wsl --unregister nixos-wsl-tiger-team
```

Then re-import with the steps above.

## Advanced: Setting as Default Distro

If you want this to be the distro that opens when you type `wsl` in PowerShell:
```powershell
.\Import-NixOSWSL.ps1 -TarballPath .\nixos.wsl -SetDefault
```
Or after import:
```powershell
wsl --set-default nixos-wsl-tiger-team
```
