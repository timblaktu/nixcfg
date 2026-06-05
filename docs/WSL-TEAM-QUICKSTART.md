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

3. Generate an SSH key for connecting to remote git hosts:
   ```bash
   ssh-keygen -t ed25519 -C "you@company.com"
   cat ~/.ssh/id_ed25519.pub   # Add this to GitHub/GitLab
   ```

## What's Included

**Development tools**: git, neovim, tmux, direnv, shellcheck, jq, fzf, and modern
CLI replacements (eza, bat, delta, dust, zoxide).

**AI coding assistants**: Claude Code and OpenCode, pre-configured with multi-account
wrapper scripts.

**Containers**: Podman with `docker` alias — run containers without Docker Desktop.

**Cross-compilation**: aarch64 (ARM64) builds via QEMU binfmt, for embedded targets.

**Hardware development**: USB debug probes (ST-LINK, CMSIS-DAP, J-Link) and programmers (Dediprog) auto-attach from Windows via usbipd-win with non-root access. See [Hardware Development](#hardware-development-usb-device-passthrough) below.

**Network tools**: curl, httpie, nmap, tcpdump, iperf3, dig, traceroute.

**GitLab integration**: `glab` CLI with credential helpers.

**Passwordless sudo** for the dev workflow (you are in the `wheel` group).

**CrowdStrike Falcon**: Module is included but disabled by default. If your
organization requires it, see the
[CrowdStrike WSL2 Security Brief](CROWDSTRIKE-WSL2-SECURITY-BRIEF.md) for
enablement and WSL2 behavior details.

For the full contents inventory, layer architecture, and alternative
consumption options, see [DISTRIBUTION.md](DISTRIBUTION.md).

## Hardware Development (USB Device Passthrough)

The dev-team image includes udev rules and auto-attach configuration for common embedded development hardware. When you plug a supported device into your Windows host, it is automatically forwarded to the NixOS-WSL instance via [usbipd-win](https://github.com/dorssel/usbipd-win).

### Supported devices (auto-attached)

| Device | VID:PID | Use case |
|--------|---------|----------|
| FTDI USB-UART | `0403:6001` | Serial console |
| ST-LINK/V2-1 | `0483:374b` | STM32 Nucleo/Discovery flash+debug |
| Dediprog SF100/600/700 | `0483:dada` | SPI flash programming |
| NVIDIA Jetson (APX) | `0955:7523` | Recovery mode flashing |
| Linux USB Mass Storage | `1d6b:0104` | Jetson initrd-flash gadget |

### Windows prerequisites

1. Install usbipd-win (v4.x or later):
   ```powershell
   winget install -e --id dorssel.usbipd-win
   ```

2. Verify the driver is running:
   ```powershell
   usbipd.exe list
   ```
   You should see your USB devices listed. Devices with state "Shared" are available for WSL attachment.

> **IT-managed laptops:** usbipd-win requires the WinUSB driver and a kernel-mode service. Some organizations block unsigned driver installation or restrict kernel services. If `winget install` succeeds but `usbipd.exe list` shows no devices or errors, contact your IT team about allowing the usbipd-win service. There is no workaround - USB/IP is a kernel-level feature.

### How it works

The NixOS-WSL module creates a systemd service for each configured hardware ID. On boot, each service polls `usbipd.exe list` until the device appears on the Windows USB bus, then runs:

```
usbipd.exe attach --wsl --hardware-id VID:PID --auto-attach
```

The `--auto-attach` flag re-attaches the device if it is disconnected and reconnected (e.g., power-cycling a Nucleo board).

### Verifying a device is attached

From inside WSL:
```bash
lsusb                              # should show the device
ls /dev/ttyACM*                    # ST-LINK VCP appears as ttyACM0
openocd -f board/st_nucleo_f2.cfg  # test ST-LINK connectivity
```

If the device does not appear, check the service status:
```bash
systemctl status usbipd-auto-attach-hwid-0483-374b.service
```

### Adding a new device

Add the VID:PID to `wsl-settings.usbip.autoAttachByHardwareId` in either the team config (`wsl-dev-team.nix`) or your host config:

```nix
wsl-settings.usbip.autoAttachByHardwareId = [
  { hardwareId = "1234:5678"; description = "My new device"; }
];
```

If the device needs non-root access (most debug probes do), add a udev rules package to `services.udev.packages` in the appropriate NixOS module. OpenOCD already ships rules for most JTAG/SWD probes - adding `pkgs.openocd` to udev packages covers ST-LINK, CMSIS-DAP, J-Link, and others.

### macOS

USB passthrough is a WSL-specific concern. On macOS, USB devices are natively accessible - no forwarding needed. Install OpenOCD via `nix profile install nixpkgs#openocd` (or `brew install openocd`) and plug in the device directly.

> **IT-managed Macs:** macOS kernel extensions (kexts) for USB debug probes are increasingly blocked by MDM profiles. If System Settings > Privacy & Security shows a blocked extension for a debug probe driver, this requires IT approval. OpenOCD's libusb backend typically works without kexts on Apple Silicon, but older Intel Macs with some probes may hit this restriction.

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
