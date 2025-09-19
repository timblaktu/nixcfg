# WSL Storage Mount - Validation & Testing Prompt

## Context for Next Session

### What We've Built
We've successfully implemented a robust WSL storage mounting solution for managing multiple NixOS-WSL instances' `/nix` stores on a dedicated 4TB NVMe SSD. The implementation is currently deployed and running on `thinky-nixos` with the storage successfully mounted but NOT yet used for the Nix store (pending data migration).

### Current State (as of 2025-09-19)

**✅ What's Working:**
- NixOS module: `modules/nixos/wsl-storage-mount.nix` 
- Host configuration: `hosts/thinky-nixos/default.nix`
- Mount point: `/mnt/wsl/storage` (ext4 on WD BLACK SN850X 4TB)
- SystemD service: `wsl-storage-mount.service` (active and enabled)
- Directories created: `nixos-wsl-{main,dev,test}` with proper ownership
- Documentation: `docs/WSL-AUTOMOUNT-IMPLEMENTATION.md`

**⏳ What's Pending:**
- Data migration: 46GB from `/nix` to `/mnt/wsl/storage/nixos-wsl-main/`
- Bind mount activation: `bindMountNixStore` currently set to `false`
- Persistence testing: Validate mount survives Windows reboots
- Multi-instance setup: Configure dev and test WSL instances

### Architecture Decisions to Validate

1. **Single Filesystem vs Multiple Partitions**
   - We chose: Single ext4 filesystem with subdirectories
   - Rationale: Flexibility, easier space management, simpler administration
   - Risk: Less isolation between instances
   - Mitigation: Directory permissions and potential quotas

2. **Bind Mount vs Direct Mount**
   - We chose: Bind mount from `/mnt/wsl/storage/nixos-wsl-main` to `/nix`
   - Rationale: Allows multiple instances to share same physical disk
   - Risk: Additional layer of indirection
   - Benefit: Easy to switch between instances or rollback

3. **Mount Persistence Strategy**
   - Primary: SystemD service with 30-retry loop
   - Fallback: PowerShell script via Windows (if needed)
   - Risk: Race conditions during boot
   - Mitigation: Service ordering and dependency management

### Testing Checklist

#### Phase 1: Basic Validation (Current State)
- [ ] Verify mount persists through WSL restart: `wsl --terminate NixOS && wsl -d NixOS`
- [ ] Check mount persists through Windows restart
- [ ] Validate service logs: `journalctl -u wsl-storage-mount -f`
- [ ] Test mount recovery: Unmount manually and check if service recovers
- [ ] Verify permissions: Can write to `/mnt/wsl/storage/nixos-wsl-main` as user

#### Phase 2: Nix Store Migration Testing
- [ ] Create backup of current /nix store
- [ ] Test rsync command with dry-run first
- [ ] Perform actual migration (46GB copy)
- [ ] Enable bind mount (`bindMountNixStore = true`)
- [ ] Verify Nix operations still work
- [ ] Test garbage collection on new mount
- [ ] Benchmark performance difference

#### Phase 3: Multi-Instance Validation
- [ ] Create second WSL instance (nixos-wsl-dev)
- [ ] Configure with different `nixStoreSubdir`
- [ ] Verify isolation between instances
- [ ] Test concurrent Nix operations
- [ ] Check for any lock contention

#### Phase 4: Performance Testing
- [ ] Benchmark Nix build times (before/after)
- [ ] Test large derivation builds
- [ ] Measure garbage collection speed
- [ ] Monitor I/O during concurrent operations
- [ ] Compare with documented expectations (30-60% improvement)

### Critical Questions to Answer

1. **Mount Reliability**: Does the mount survive all restart scenarios?
   - WSL instance restart
   - Windows reboot
   - Windows fast startup
   - Windows update restart

2. **Data Integrity**: Is the bind mount approach safe?
   - File consistency during operations
   - Atomic operations preserved
   - No corruption during unexpected shutdowns

3. **Performance Impact**: Does it meet expectations?
   - Target: 30-60% improvement over VHDX
   - Actual measurements needed
   - Any unexpected bottlenecks?

4. **Multi-Instance Safety**: Can multiple instances coexist?
   - No cross-contamination
   - Proper isolation
   - Resource sharing without conflicts

### Commands for Testing

```bash
# Check mount status
mount | grep storage
systemctl status wsl-storage-mount
ls -la /mnt/wsl/storage/

# Test mount persistence
sudo systemctl stop wsl-storage-mount
sudo umount /mnt/wsl/storage
sudo systemctl start wsl-storage-mount

# Monitor logs
journalctl -u wsl-storage-mount -f
tail -f /var/log/wsl-mount.log

# Performance testing (after migration)
time nix-build '<nixpkgs>' -A hello
time nix-collect-garbage -d

# Disk usage monitoring
df -h /mnt/wsl/storage
du -sh /mnt/wsl/storage/nixos-wsl-*
```

### Risk Assessment

**High Risk Areas:**
1. Data loss during migration - Mitigate with backups
2. Mount not persisting - Have PowerShell fallback ready
3. Performance regression - Test thoroughly before committing

**Medium Risk Areas:**
1. Permission issues - Document proper ownership
2. Space exhaustion - Implement quotas if needed
3. Service ordering problems - Monitor boot logs

**Low Risk Areas:**
1. Bind mount overhead - Negligible in practice
2. Directory isolation - Unix permissions sufficient
3. Configuration complexity - Well documented

### Next Steps Recommendation

1. **Immediate**: Test mount persistence through Windows restart
2. **Today**: Validate recovery mechanisms work
3. **This Week**: Perform Nix store migration with full backup
4. **Next Week**: Set up second WSL instance for multi-instance testing
5. **Future**: Consider ZFS or Btrfs for snapshots/compression

### Support Information

- Documentation: `/home/tim/src/nixcfg/docs/WSL-AUTOMOUNT-IMPLEMENTATION.md`
- Module source: `/home/tim/src/nixcfg/modules/nixos/wsl-storage-mount.nix`
- Configuration: `/home/tim/src/nixcfg/hosts/thinky-nixos/default.nix`
- Original analysis: `/home/tim/src/nixcfg/docs/nixos-wsl-storage-revised.md`
- PowerShell scripts: `/mnt/c/Users/timbl/wsl/`

### Session Goals

For our next conversation, we should:
1. Review test results from the checklist above
2. Troubleshoot any issues discovered
3. Plan and execute the Nix store migration
4. Document any necessary adjustments
5. Prepare configuration for additional WSL instances

---

## Quick Start for New Session

"I need help validating and testing the WSL storage mount implementation we created. The mount is currently working on thinky-nixos at /mnt/wsl/storage but we haven't migrated the Nix store yet. Can you help me:
1. Test mount persistence through Windows restart
2. Plan the safe migration of 46GB from /nix 
3. Review any issues I've encountered
4. Optimize the configuration if needed"

---

*Generated: 2025-09-19*
*Purpose: Provide complete context for validation session*
*Status: Ready for testing phase*