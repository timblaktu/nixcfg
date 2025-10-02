# Request: Declarative Configuration for WSL Bare Disk Mounts

## Problem Description

NixOS-WSL users currently have no declarative way to configure bare disk mounts, forcing manual operations that break NixOS's configuration-as-code philosophy and causing significant performance issues when working with large repositories or databases.

## Current Pain Points

### 1. Performance Impact
The default 9P filesystem used for Windows drives (`/mnt/c`, `/mnt/d`) has [documented performance penalties of 10x or more](https://github.com/microsoft/WSL/issues/4197). This makes common operations painful:
- Building large projects takes 5-10x longer
- Nix store operations on `/mnt/c` are extremely slow  
- Database operations suffer from excessive I/O latency
- Git operations on large repos become unbearable

### 2. Manual Process Required Every Session
Users must manually run these commands before each WSL session:
```powershell
# In Windows Terminal as Administrator
wsl --mount \\.\PHYSICALDRIVE2 --bare

# Then start WSL and manually mount
mkdir -p /mnt/wsl/data-disk
sudo mount -t ext4 /dev/sdc1 /mnt/wsl/data-disk
```

If you forget, your mounts are missing and services fail.

### 3. No Persistence Across Restarts  
Unlike traditional Linux systems where `/etc/fstab` handles everything, WSL requires:
- Windows-side: Manual `wsl --mount` command (requires Admin)
- Linux-side: Manual mount configuration
- No coordination between the two sides
- Everything lost on WSL restart

### 4. Common Use Cases Blocked

**Nix Store on Dedicated Disk**: Users want to keep the Nix store on a fast NVMe drive without the 9P penalty, but must manually set up bind mounts every time.

**ZFS Pools**: ZFS users need persistent pool access across WSL restarts, currently requiring manual import commands.

**Shared Development Drives**: Teams sharing ext4/btrfs drives between multiple WSL instances must coordinate manual mount procedures.

**Database Storage**: PostgreSQL/MySQL on dedicated drives for performance requires complex manual setup.

## Current Workarounds and Why They're Insufficient

### PowerShell Scripts
Users write custom scripts but:
- No standard location or format
- No integration with NixOS configuration
- Scripts get out of sync with Linux-side config
- No validation or error handling

### Task Scheduler
Some try Windows Task Scheduler but:
- Requires Administrator configuration
- Runs at system startup (not WSL start)
- No feedback if mount fails
- Still needs manual Linux configuration

### Manual Documentation
Teams document mount procedures but:
- Developers forget steps
- Documentation gets outdated
- No automation possible
- Onboarding new developers is painful

## Proposed Solution

A NixOS module that declaratively configures the Linux side and generates the required Windows-side helper scripts:

```nix
# Desired configuration experience
{
  wsl.bareMounts = {
    enable = true;
    mounts = [
      {
        diskUuid = "e030a5d0-fd70-4823-8f51-e6ea8c145fe6";
        mountPoint = "/mnt/wsl/nvme-storage";
        fsType = "ext4";
        options = [ "defaults" "noatime" ];
      }
    ];
  };
  
  # Bind mount Nix store for 10x performance improvement
  fileSystems."/nix" = {
    device = "/mnt/wsl/nvme-storage/nix";
    fsType = "none";
    options = [ "bind" ];
  };
}
```

After configuration:
1. NixOS generates systemd mount units automatically
2. PowerShell script is generated at known location
3. Clear instructions provided for Windows-side setup
4. Validation on boot shows if Windows steps were missed

## Expected Benefits

1. **Declarative Configuration**: Single source of truth in `configuration.nix`
2. **Performance**: Native ext4/btrfs/ZFS speeds instead of 9P overhead
3. **Reliability**: Automated mount units with proper dependencies
4. **Documentation**: Self-documenting configuration
5. **Team Workflow**: Consistent setup across developer machines

## Technical Context

This requires Windows-side operations because WSL instances cannot call `wsl --mount` on themselves - it's a hypervisor-level operation that must happen before the Linux VM starts. The proposed module would:
- Handle everything possible on the Linux side declaratively
- Generate helper scripts for unavoidable Windows operations
- Provide clear feedback when manual steps are needed
- Maintain NixOS philosophy where architecturally possible

## Related Issues
- microsoft/WSL#4197 - 9P filesystem performance
- microsoft/WSL#5298 - Mount configuration persistence
- microsoft/WSL#6675 - Declarative mount configuration request

## Priority
High - This impacts daily developer productivity for anyone using NixOS-WSL with large repositories, databases, or the Nix store on dedicated storage.