## Context
I've completed fixing the NixOS-WSL bare mount feature implementation on the feature/bare-mount-support branch. All documentation and tests
now correctly use the UUID-based approach (diskUuid field).

The branch is ready for PR submission to upstream NixOS-WSL. I have:
- Issue description template at ~/src/nixcfg/BARE-MOUNT-ISSUE.md
- PR description template at ~/src/nixcfg/BARE-MOUNT-PR.md
- Working implementation at ~/src/NixOS-WSL (branch: feature/bare-mount-support)

Next steps (PR prep):
1. Review if any final adjustments are needed to the issue/PR descriptions
2. Create the GitHub issue on nix-community/NixOS-WSL
3. Create the PR referencing the issue
4. Consider if we should test the feature first in my nixcfg before submitting

The feature provides declarative configuration for WSL bare disk mounts, addressing the performance and workflow issues with manual mount management. It generates Windows-side PowerShell scripts while maintaining Linux-side automation through systemd.

## Current State of active machine thinky-nixos nix configuration (/home/tim/src/nixcfg/hosts/thinky-nixos/default.nix) 
- Bare mount configuration is active (lines 61-85)
- Bind mount is **commented out** (lines 90-102) 
- /nix/* copy (not just store!) exists at: `/mnt/wsl/internal-4tb-nvme/nix-thinky-nixos/`
- Active System still using `/nix` from root filesystem

## Next Steps (USER WILL DO THESE MANUALLY!!)
1. **Uncomment the bind mount**: Edit `/home/tim/src/nixcfg/hosts/thinky-nixos/default.nix` lines 90-102
2. **Rebuild the system**: `sudo nixos-rebuild switch --flake '.#thinky-nixos'`
3. **Reboot WSL instance**: 
4. **Verify the mount**: Check that `/nix` is served from `/mnt/wsl/internal-4tb-nvme/nix-thinky-nixos`

```
# Check mounts
mount | grep -E "(nix|internal-4tb)"
df -h /nix /mnt/wsl/internal-4tb-nvme

# Diagnostic tool
check-bare-mounts
```

5. **Test system operation**: Ensure nix commands work, packages install correctly
6. **Document results**: Update docs with success/failure and any issues encountered

## Important Notes
- The bind mount uses systemd automount for reliability
- Dependencies are properly ordered (bare mount before bind mount before nix-daemon)
- If something fails, comment out bind mount and rebuild to recover
- DO NOT run long sudo commands with timeouts (causes Claude Code crashes)

## File Locations
- Module: `/home/tim/src/NixOS-WSL/modules/wsl-bare-mount.nix`
- Host Nix Config: `/home/tim/src/nixcfg/hosts/thinky-nixos/default.nix`
- Data: `/mnt/wsl/internal-4tb-nvme/nix-thinky-nixos/`
- Docs: `/home/tim/src/nixcfg/docs/NIXOS-WSL-BARE-MOUNT-TESTING.md`

