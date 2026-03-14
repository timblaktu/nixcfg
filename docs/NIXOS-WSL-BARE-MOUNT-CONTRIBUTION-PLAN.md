# NixOS-WSL Bare Mount Feature - Upstream Contribution Plan

## Executive Summary

Contributing a new `wsl.bareMounts` module to NixOS-WSL that enables declarative mounting of bare disks in WSL2, providing direct block device access for improved I/O distribution and performance optimization beyond the limitations of .vhdx-based storage.

## Problem Statement

### Current Situation
- WSL2 instances run from .vhdx files with inherent virtualization overhead and size constraints
- Performance-critical workloads benefit from distributed I/O across multiple physical disks
- Current bare mount solutions require complex Windows Task Scheduler scripts and manual PowerShell commands
- No declarative NixOS way to handle `wsl --mount --bare` operations
- Bare mounts provide direct block device access, bypassing .vhdx virtualization layer

### Research Findings
- NixOS-WSL has **no existing bare mount support**
- No open issues or PRs addressing this need
- Project has elegant patterns for Windows interop (see `usbip.nix`)
- `wsl.wslConf.boot.command` exists but is underutilized for this purpose

## Proposed Solution

### New Module: `modules/wsl-bare-mount.nix`

Key features:
- Declarative configuration for multiple bare disk mounts
- Automatic mounting via `wsl.conf` boot command
- Optional filesystem mounting with systemd integration
- Manual mount commands for debugging
- Following NixOS-WSL's established patterns

### Module Interface

```nix
wsl.bareMounts = {
  enable = true;
  disks = [{
    name = "internal-4tb-nvme";
    serialNumber = "E823_8FA6_BF53_0001_001B_448B_4ED0_B0F4.";
    devicePattern = "scsi-*internal-4tb-nvme*";
    filesystem = {
      mountPoint = "/mnt/wsl/storage";
      fsType = "ext4";
      options = [ "defaults" "noatime" ];
    };
  }];
};
```

## Development Plan

### Phase 1: Setup and Initial Development

1. **Repository Setup**
   ```bash
   cd ~/src/NixOS-WSL
   git remote add fork https://github.com/timblaktu/NixOS-WSL
   git fetch fork
   git checkout -b feature/bare-mount-support
   ```

2. **Module Implementation**
   - Create `modules/wsl-bare-mount.nix` with core functionality
   - Add module to `modules/default.nix` imports
   - Implement mount script generation
   - Add systemd mount unit generation for filesystems

3. **Documentation**
   - Add module documentation comments
   - Create example configuration in `docs/`
   - Update README with bare mount feature

### Phase 2: Testing Infrastructure

1. **Unit Tests**
   - Create `tests/bare-mount.nix` for module evaluation tests
   - Test multiple disk configurations
   - Verify systemd unit generation
   - Test with/without filesystem mounting

2. **Integration Tests**
   - Mock PowerShell commands for CI environment
   - Test boot command generation
   - Verify mount unit ordering

### Phase 3: Local Testing

1. **Test Configuration**
   ```nix
   # hosts/thinky-nixos/test-bare-mount.nix
   {
     imports = [ /home/tim/src/NixOS-WSL/modules/wsl-bare-mount.nix ];
     
     wsl.bareMounts = {
       enable = true;
       disks = [{
         name = "internal-4tb-nvme";
         serialNumber = "E823_8FA6_BF53_0001_001B_448B_4ED0_B0F4.";
         devicePattern = "scsi-*internal-4tb-nvme*";
         filesystem = {
           mountPoint = "/mnt/wsl/storage";
           fsType = "ext4";
         };
       }];
     };
   }
   ```

2. **Testing Steps**
   - Build configuration with new module
   - Verify wsl.conf generation
   - Test boot-time mounting
   - Verify filesystem mounting
   - Test manual mount commands
   - Measure performance improvement

### Phase 4: PR Preparation

1. **Code Quality**
   - Run nixpkgs-fmt on new code
   - Ensure all options have descriptions
   - Add assertions for invalid configurations

2. **PR Content**
   - Clear problem statement
   - Implementation overview
   - Usage examples
   - Testing results (performance metrics)
   - Documentation updates

## Technical Implementation Details

### Key Design Decisions

1. **Use `wsl.wslConf.boot.command`**
   - Simpler than systemd service coordination
   - Runs before systemd starts
   - Avoids timing issues

2. **Direct PowerShell Execution**
   - No intermediate scripts needed
   - Uses `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe`
   - Always available in WSL

3. **Optional Filesystem Mounting**
   - Not all bare mounts need filesystem mounting
   - Systemd mount units only created when needed
   - Uses `nofail` to prevent boot failures

4. **Pattern Matching for Devices**
   - Handles device name variations
   - Uses glob patterns in `/dev/disk/by-id/`
   - Robust against device enumeration changes

### Error Handling

- Silent failures for PowerShell commands (won't break boot)
- `nofail` option on all mount units
- Manual mount commands for debugging
- Logging to systemd journal

## Testing Checklist

- [ ] Module evaluates without errors
- [ ] wsl.conf contains correct boot commands
- [ ] Bare mount succeeds on first boot
- [ ] Filesystem mounts correctly
- [ ] Survives WSL restart
- [ ] Survives Windows reboot
- [ ] Multiple disks work correctly
- [ ] Manual mount commands work
- [ ] Performance improvement verified
- [ ] No interference with existing WSL features

## Success Criteria

1. **Functionality**
   - Bare disks mount automatically at boot
   - Filesystems mount when configured
   - No manual intervention required

2. **Performance**
   - Improved I/O throughput by distributing load across multiple physical disks
   - Bypasses .vhdx virtualization overhead
   - Direct block device access for latency-sensitive operations

3. **Code Quality**
   - Follows NixOS-WSL patterns
   - Well documented
   - Includes tests
   - No regressions

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| PowerShell interop fails | Provide manual mount commands |
| Device names change | Use pattern matching |
| Mount timing issues | Use boot.command instead of systemd |
| Breaking existing setups | Feature is opt-in via enable flag |

## Timeline

- **Day 1**: Module implementation and local testing
- **Day 2**: Test suite development
- **Day 3**: Documentation and PR preparation
- **Day 4**: Submit PR and address feedback

## Next Chat Instructions

In the next chat session, proceed with:

1. Set up the repository remotes
2. Create the feature branch
3. Implement the `wsl-bare-mount.nix` module
4. Add it to the module imports
5. Create basic tests
6. Build and verify the changes
7. Provide testing instructions

Start with: "I'm ready to implement the NixOS-WSL bare mount feature. I'll begin by setting up the repository and creating the module."

## References

- Current implementation attempt: `/home/tim/src/nixcfg/modules/nixos/wsl-storage-mount.nix`
- Windows mount script: `C:\Users\timbl\wsl\wsl-mount-bare-disks.ps1`
- NixOS-WSL repo: `~/src/NixOS-WSL`
- Fork: https://github.com/timblaktu/NixOS-WSL

---

## Other Upstream Contribution Opportunities

### usbip.nix: Add `usbipd-win` prerequisite warning

**Status**: Deferred (local activation check implemented in `modules/system/settings/wsl/wsl.nix`)
**Date identified**: 2026-03-08
**Upstream context**:
- `modules/usbip.nix` has no validation that `usbipd-win` is installed on Windows
- [Issue #662](https://github.com/nix-community/NixOS-WSL/issues/662) and [Issue #111](https://github.com/nix-community/NixOS-WSL/issues/111) show users repeatedly hitting this
- [PR #524](https://github.com/nix-community/NixOS-WSL/pull/524) (open, by @terlar) addresses related `vhci-hcd` module loading — coordinate with this
- NixOS-WSL uses `warnings` (not assertions) for this class of problem (see `wsl-distro.nix`, `interop.nix`, `wsl-conf.nix`)

**Proposed change**: Add a static `warnings` entry to `usbip.nix` when `wsl.usbip.enable = true`:
```nix
warnings = [
  "wsl.usbip is enabled. Requires usbipd-win on Windows: winget install -e --id dorssel.usbipd-win"
];
```

**Note**: A NixOS `warnings` entry fires at evaluation time (every build), so it's informational rather than a runtime check. A runtime `system.activationScripts` check would be more precise but NixOS-WSL doesn't use that pattern for validation. Consider proposing both options in the issue/PR discussion.

### usbip.nix: Modernize for usbipd-win v5.x + hardware-ID auto-attach

**Status**: Research complete, ready for upstream PR
**Date identified**: 2026-03-14
**Priority**: HIGH — current NixOS-WSL module will break when users update usbipd-win

**Current upstream state** (`modules/usbip.nix` on main as of 2026-03-14):
- Fetches `auto-attach.sh` from dorssel/usbipd-win **v4.2.0** (June 2023)
- Creates templated systemd services (`usbip-auto-attach@<busid>.service`) that run
  the bash script inside WSL, polling every 1s with Linux-side `usbip attach`
- Identifies devices by **bus ID** only (port-dependent, e.g., "3-1")
- `wsl.extraBin` provides cat/ls/modprobe to `/bin` for `usbipd.exe` to invoke from Windows

**What changed in usbipd-win v5.x**:
- **v5.0.0**: `auto-attach.sh` still present, ARM64 support added
- **v5.1.0**: `auto-attach.sh` replaced by **native binary** `usbip-auto-attach` (C project
  by @andrewleech: https://github.com/andrewleech/usbip-auto-attach). Added `--host-ip`
  and `--unplugged` options
- **v5.2.0**: **Non-FHS distribution support** (NixOS!) — uses `shell-type standard` instead
  of `--exec`, honoring root's `$PATH`. This may eliminate the need for `wsl.extraBin`
  workarounds (cat, ls, usbip symlinks)
- **v5.3.0**: `auto-attach.sh` **removed entirely** (HTTP 404 on GitHub). Only native binary
  `usbip-auto-attach` + `usbip` shipped per architecture (x64/arm64)

**Impact**: NixOS-WSL's `usbip.nix` fetches from v4.2.0 via hash-pinned URL, so it won't
break immediately. But:
1. It's stale (2+ years behind, missing `--host-ip`, `--unplugged`, non-FHS support)
2. Users who manually follow usbipd-win docs find outdated NixOS-WSL behavior
3. The Linux-side polling approach is inferior to Windows-side `usbipd.exe attach --auto-attach`

**Two auto-attach mechanisms** (important architectural distinction):
| Aspect | Mechanism A (current) | Mechanism B (proposed) |
|---|---|---|
| Where it runs | Linux systemd service | Windows-side usbipd.exe |
| Invocation | `usbip attach --remote=HOST --busid=BID` | `usbipd.exe attach --wsl --hardware-id VID:PID --auto-attach` |
| Device ID | Bus ID (port-dependent) | Hardware ID VID:PID (port-independent) |
| Reconnect | Polls /sys every 1s | Native OS event-driven |
| Script | Bash (auto-attach.sh, removed in v5.3) | None (compiled into usbipd.exe) |
| Dependencies | usbip package, iproute2, IP discovery | Windows interop PATH |
| Networking | Requires knowing host IP (shell snippet) | Automatic (same as manual attach) |

**Proposed upstream changes** (single PR with 3 parts):

1. **Update auto-attach mechanism**: Either use shipped native `usbip-auto-attach` binary
   from usbipd-win installation, or switch to Windows-side `usbipd.exe attach --auto-attach`.
   The Windows-side approach is simpler (no IP discovery needed, event-driven) but requires
   Windows interop PATH. The native binary approach keeps current architecture but needs
   path to `C:\Program Files\usbipd-win\WSL\<arch>\usbip-auto-attach`.

2. **Add `autoAttachByHardwareId` option**: New option complementing existing bus-ID
   mechanism. Creates systemd services that run `usbipd.exe attach --wsl --hardware-id VID:PID
   --auto-attach` from WSL via Windows interop:
   ```nix
   autoAttachByHardwareId = lib.mkOption {
     type = with lib.types; listOf (submodule {
       options = {
         hardwareId = lib.mkOption { type = str; example = "0403:6001"; };
         description = lib.mkOption { type = str; default = ""; };
       };
     });
     default = [ ];
     description = "Auto-attach USB devices by hardware ID (VID:PID) via usbipd.exe";
   };
   ```
   Advantages: port-independent, survives replug to different USB port, matches
   usbipd-win's recommended workflow.

3. **Test v5.2.0+ non-FHS support**: Verify whether `wsl.extraBin` entries for cat/ls/usbip
   are still needed with usbipd-win v5.2.0+. If not, gate them behind a version check or
   remove them.

**Coordinate with**:
- [PR #524](https://github.com/nix-community/NixOS-WSL/pull/524) (open, by @terlar):
  kernel module loading for `vhci-hcd`. Rebased Jan 2026, WSL 2.5.7+ ships 6.6 kernel
  where modules are loadable. This PR is prerequisite for usbip on newer kernels.
- [Issue #662](https://github.com/nix-community/NixOS-WSL/issues/662): User unable to use
  usbipd — closed by #665 (extraBin fix) but underlying architecture still outdated.
- [Issue #594](https://github.com/nix-community/NixOS-WSL/issues/594): auto-attach broken
  by v4.2.0's `./usbip` relative path — fixed by patching, but moot with native binary.
- [Issue #111](https://github.com/nix-community/NixOS-WSL/issues/111): Long-running thread
  showing users struggling with usbip setup. Every workaround eventually broke.

**Maintainer context**:
- **nzbr** (main maintainer): Responsive, merged original usbip module
- **SuperSandro2000**: Active reviewer, approved usbip PRs, pragmatic about fixes
- **terlar**: Original usbip module author, still active (Jan 2026 rebase on PR #524)
- **K900**: Technical reviewer, asks probing questions about correctness
- PRs with tests and clean implementation get merged within weeks
- Project actively maintained (pushed today)

**User's confirmed working workflow** (2026-03-14):
```powershell
# From PowerShell (non-admin, with usbipd policy configured):
Start-Process -WindowStyle Hidden usbipd.exe -ArgumentList "attach --wsl --hardware-id 0403:6001 --auto-attach"
Start-Process -WindowStyle Hidden usbipd.exe -ArgumentList "attach --wsl --hardware-id 0955:7523 --auto-attach"
```
Devices: FTDI USB-UART adapter (0403:6001), NVIDIA Jetson Recovery Mode APX (0955:7523).

**Local implementation** (interim, in `wsl-settings.usbip` / tiger-team module):
Will implement hardware-ID auto-attach locally first, then extract as upstream PR.
The local version creates systemd services that call `usbipd.exe` via Windows interop.
Tiger-team module sets the two team device hardware IDs.

### wsl-env-capture: Boot-time environment capture for systemd-spawned shells

**Status**: Implemented locally (`modules/system/settings/wsl/wsl.nix`, `wsl-settings.envCapture`)
**Date identified**: 2026-03-08
**Upstream context**:
- [Issue #171](https://github.com/nix-community/NixOS-WSL/issues/171) (assigned K900): Environment/PAM problems, references microsoft/WSL#9213
- [Issue #375](https://github.com/nix-community/NixOS-WSL/issues/375) (wontfix): Maintainer nzbr acknowledges workarounds possible
- microsoft/WSL#8842, #9213, #10205: Upstream WSL bugs, unresolved
- Shell-wrapper PRs (#452, #464, #561) fix login shells only, not systemd-spawned sessions

**Problem**: WSL injects environment variables (Windows PATH, WSLg display vars, WSL_INTEROP)
into Relay-spawned login shells only. Processes spawned by systemd (tmux, SSH, user services)
never receive these. NixOS-WSL's `split-path` is a classifier, not a provider.

**Proposed change**: Two components:
1. `wsl-env-capture.service` — oneshot boot service that queries Windows PATH via `cmd.exe`,
   probes filesystem for WSLg state, writes sourceable cache to `/run/wsl-env`
2. `environment.extraInit` (mkAfter) — sources cache when WSLPATH is empty (systemd-spawned shells)

**Note**: Novel approach not proposed upstream. Boot-time capture fills the gap between
WSL's per-session injection and systemd's early boot context. Enabled by default, <1KB cache,
~100ms service, single `[ -z ]` shell init check.

---

*Created: 2025-09-20*
*Purpose: Guide upstream contribution of bare mount support to NixOS-WSL*
*Status: Ready for implementation*