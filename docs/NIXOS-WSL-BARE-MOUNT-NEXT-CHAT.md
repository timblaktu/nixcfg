# Continue NixOS-WSL Bare Mount Feature Development

## Current Status

I have implemented a `wsl.bareMounts` module for NixOS-WSL that enables declarative configuration of WSL bare disk mounts. The feature is complete and ready for testing and PR submission.

**Branch**: `feature/bare-mount-support` at https://github.com/timblaktu/NixOS-WSL
**Files Created**:
- `modules/wsl-bare-mount.nix` - Core module implementation
- `docs/bare-mount-example.md` - Usage documentation  
- `tests/bare-mount/` - Test configurations
- `tests/bare-mount.Tests.ps1` - PowerShell test suite

## Key Understanding

**Bare Mount Purpose**: Not about escaping Windows filesystem penalties (which only apply to /mnt/c), but about:
1. Bypassing .vhdx virtualization overhead for direct block device access
2. Distributing I/O across multiple physical disks for better throughput
3. Avoiding .vhdx size limitations and growth issues
4. Providing dedicated storage for performance-critical workloads

**Module Testing**: No need to rebuild NixOS-WSL tarballs - can test by importing modules directly from local fork path in configuration.

## Next Steps

1. **Test the module with real hardware**:
   - Import module from `/home/tim/src/NixOS-WSL/modules` in thinky-nixos config
   - Configure with actual disk serial number: `E823_8FA6_BF53_0001_001B_448B_4ED0_B0F4.`
   - Apply with `nixos-rebuild switch` and restart WSL
   - Verify mount with `wsl-bare-mount status`

2. **Create Pull Request**:
   - Go to https://github.com/timblaktu/NixOS-WSL/pull/new/feature/bare-mount-support
   - Use PR template emphasizing I/O distribution benefits, not Windows FS avoidance
   - Be prepared to provide performance benchmarks (.vhdx vs bare mount)

3. **Potential Improvements to Consider**:
   - Add option for encrypted bare mounts
   - Support for dynamic disk discovery (by label/UUID instead of serial)
   - Integration with existing `wsl.mount` options
   - Prometheus metrics for monitoring I/O distribution

## Testing Configuration

```nix
# For hosts/thinky-nixos/default.nix
{
  imports = [
    # Test local fork with bare mount module
    /home/tim/src/NixOS-WSL/modules
  ];

  wsl.bareMounts = {
    enable = true;
    disks = [{
      name = "internal-4tb-nvme";
      serialNumber = "E823_8FA6_BF53_0001_001B_448B_4ED0_B0F4.";
      devicePattern = "nvme-Samsung_SSD_990_PRO_4TB_*";
      filesystem = {
        mountPoint = "/mnt/wsl/storage";
        fsType = "ext4";
        options = [ "defaults" "noatime" "nodiratime" ];
      };
    }];
  };
}
```

## References

- Module implementation: `~/src/NixOS-WSL/modules/wsl-bare-mount.nix`
- Testing docs: `~/src/nixcfg/docs/NIXOS-WSL-BARE-MOUNT-TESTING.md`
- Original plan: `~/src/nixcfg/docs/NIXOS-WSL-BARE-MOUNT-CONTRIBUTION-PLAN.md`

## Task

Please help me:
1. Test the bare mount module with my actual hardware configuration
2. Verify it works correctly with the Samsung 990 PRO 4TB NVMe
3. Gather performance benchmarks comparing .vhdx vs bare mount storage
4. Create and submit the pull request to upstream NixOS-WSL
5. Address any feedback from maintainers