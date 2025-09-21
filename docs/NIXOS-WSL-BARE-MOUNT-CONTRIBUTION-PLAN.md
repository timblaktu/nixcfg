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

*Created: 2025-09-20*
*Purpose: Guide upstream contribution of bare mount support to NixOS-WSL*
*Status: Ready for implementation*