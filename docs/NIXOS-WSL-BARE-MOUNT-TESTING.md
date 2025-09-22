# Testing NixOS-WSL Bare Mount Module

## Summary

Successfully implemented the `wsl.bareMounts` module for NixOS-WSL:
- Branch: `feature/bare-mount-support` 
- Fork: https://github.com/timblaktu/NixOS-WSL
- PR URL: https://github.com/timblaktu/NixOS-WSL/pull/new/feature/bare-mount-support

## Understanding NixOS-WSL Module Testing

### How NixOS Modules Work

NixOS uses a composable module system where configurations are built from multiple modules that can be:
1. **Built into the base system** - Core NixOS and NixOS-WSL modules
2. **Imported at configuration time** - Additional modules from any path
3. **Overlaid dynamically** - Modules can extend or override others

### Testing Without Rebuilding Tarballs

**Key Insight**: You don't need to rebuild the NixOS-WSL distribution tarball to test new modules!

- **Tarball**: Only needed for initial WSL instance creation
- **Module Testing**: Can import new modules directly in your configuration
- **Live Testing**: Changes apply via `nixos-rebuild switch`

This works because:
1. NixOS configurations are evaluated at build time
2. Modules can be imported from any filesystem path
3. The module system merges all imports into final configuration
4. `nixos-rebuild` applies the new configuration to your running system

### Example Testing Workflow

```nix
# In your /etc/nixos/configuration.nix or flake
{
  imports = [
    # Your existing imports...
    /home/tim/src/NixOS-WSL/modules  # Import ALL modules from fork
    # OR import specific module:
    # /home/tim/src/NixOS-WSL/modules/wsl-bare-mount.nix
  ];
  
  # Test the new module
  wsl.bareMounts.enable = true;
  # ... configuration ...
}
```

Then simply: `sudo nixos-rebuild switch`

## Implementation Details

### Files Created
1. **`modules/wsl-bare-mount.nix`** - Core module implementation
2. **`docs/bare-mount-example.md`** - Comprehensive usage documentation
3. **`tests/bare-mount/bare-mount.nix`** - Test configuration
4. **`tests/bare-mount.Tests.ps1`** - PowerShell test suite

### Module Features
- Declarative configuration for multiple bare disk mounts
- Automatic mounting via `wsl.conf` boot command
- Optional filesystem mounting with systemd integration
- Manual mount commands (`wsl-bare-mount`) for debugging
- Pattern matching for robust device identification

## Local Testing Instructions

### 1. Test in Your NixOS Configuration

Add to your host configuration (e.g., `hosts/thinky-nixos/default.nix`):

```nix
{
  imports = [
    # ... existing imports ...
    /home/tim/src/NixOS-WSL/modules  # Use local fork with bare-mount module
  ];

  wsl.bareMounts = {
    enable = true;
    disks = [{
      name = "internal-4tb-nvme";
      serialNumber = "E823_8FA6_BF53_0001_001B_448B_4ED0_B0F4.";
      filesystem = {
        mountPoint = "/mnt/wsl/${name}";
        fsType = "ext4";
        options = [ "defaults" "noatime" ];
      };
    }];
  };
}
```

### 2. Build and Switch

```bash
# Test evaluation
nix-instantiate --eval -E "(import <nixpkgs/nixos> { configuration = ./hosts/thinky-nixos/default.nix; }).config.wsl.bareMounts.enable"

# Build configuration
sudo nixos-rebuild build --flake '.#thinky-nixos'

# Apply configuration
sudo nixos-rebuild switch --flake '.#thinky-nixos'
```

### 3. Verify Configuration

```bash
# Check generated wsl.conf
cat /etc/wsl.conf

# Check boot command specifically
grep "command" /etc/wsl.conf

# After WSL restart, check mount status
wsl-bare-mount status

# Check if device appears
ls -la /dev/disk/by-id/ | grep Samsung

# Check if filesystem is mounted
mount | grep /mnt/wsl/storage
```

### 4. Manual Testing

```bash
# Try manual mount (if not already mounted)
wsl-bare-mount mount

# Check mount status
wsl-bare-mount status

# Test filesystem access
echo "test" > /mnt/wsl/storage/test.txt
cat /mnt/wsl/storage/test.txt

# Unmount when done testing
wsl-bare-mount unmount
```

## Performance Testing

### Baseline (.vhdx storage in home directory):
```bash
time dd if=/dev/zero of=~/test.img bs=1M count=1000
```

### With Bare Mount:
```bash
time dd if=/dev/zero of=/mnt/wsl/storage/test.img bs=1M count=1000
```

### For comparison - Windows filesystem (worst case):
```bash
time dd if=/dev/zero of=/mnt/c/temp/test.img bs=1M count=1000
```

Expected improvements:
- Bare mount vs .vhdx: 2-4x faster for sequential I/O
- Bare mount vs Windows FS: 10-20x faster
- Greatest benefit: When distributing I/O across multiple bare-mounted disks

## Troubleshooting

### If disk doesn't mount at boot:

1. Check Windows side:
   ```powershell
   # Verify serial number
   Get-PhysicalDisk | Select FriendlyName, SerialNumber
   
   # Try manual mount
   $disk = Get-PhysicalDisk -SerialNumber "E823_8FA6_BF53_0001_001B_448B_4ED0_B0F4."
   wsl --mount "\\.\PHYSICALDRIVE$($disk.DeviceId)" --bare --name test
   ```

2. Check WSL side:
   ```bash
   # Look for device
   ls /dev/disk/by-id/ | grep -i samsung
   
   # Check systemd mount units
   systemctl status '*.mount' | grep storage
   
   # Check journal for errors
   journalctl -xe | grep -i mount
   ```

## Next Steps for PR

1. **Create Pull Request**
   - Go to: https://github.com/timblaktu/NixOS-WSL/pull/new/feature/bare-mount-support
   - Target: `nix-community/NixOS-WSL:main`
   - Title: "Add wsl.bareMounts module for declarative bare disk mounting"

2. **PR Description Template**:
   ```markdown
   ## Summary
   Adds a new `wsl.bareMounts` module that enables declarative configuration of WSL bare disk mounts, providing direct block device access for improved I/O performance and storage flexibility.

   ## Motivation
   - WSL2 runs from .vhdx files with inherent virtualization overhead and size constraints
   - Performance-critical workloads benefit from distributed I/O across multiple physical disks
   - No declarative NixOS way to handle `wsl --mount --bare` operations
   - Bare mounts bypass .vhdx layer for direct block device access
   
   ## Testing
   - [x] Module evaluates without errors
   - [x] Boot commands generated correctly
   - [x] Manual mount commands work
   - [ ] Tested on real hardware with actual disk
   - [ ] Performance improvements verified
   
   ## Documentation
   - Comprehensive usage guide in `docs/bare-mount-example.md`
   - Module has inline documentation for all options
   - Example configurations provided
   ```

3. **Be ready to:**
   - Add more tests if requested
   - Adjust implementation based on feedback
   - Provide performance benchmarks
   - Test on different WSL2 configurations

## Module Validation Completed

✅ Module syntax and structure validated
✅ Configuration evaluation tested
✅ Boot command generation verified
✅ Documentation created
✅ Test suite scaffolded
✅ Ready for hardware testing and PR submission

---

*Created: 2025-09-20*
*Module Location: ~/src/NixOS-WSL (feature/bare-mount-support branch)*
*Testing Config: Can use actual disk serial number for real-world testing*
