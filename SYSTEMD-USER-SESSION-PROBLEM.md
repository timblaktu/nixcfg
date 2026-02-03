# Systemd User Session Failure on NixOS-WSL Boot

**Date:** 2026-02-02
**Host:** pa161878-nixos (thinky-nixos WSL instance)
**Status:** Root cause identified, workaround implemented, permanent fix proposed

## Problem Summary

After WSL boots, the systemd user session (`user@1000.service`) fails to start, causing:
- `systemctl --user` commands fail with "No such file or directory"
- Podman rootless containers fail (requires systemd cgroup management)
- No user D-Bus session available

## Symptoms Observed

```
$ systemctl --user status
Failed to connect to user scope bus via local transport: No such file or directory

$ systemctl status user@1000.service
× user@1000.service - User Manager for UID 1000
     Active: failed (Result: exit-code)
     Error: pam_systemd(systemd-user:session): Runtime directory '/run/user/1000' is not owned by UID 1000
```

## Root Cause Analysis

### The Ownership Problem

The `/run/user/1000` directory is created with `root:root` ownership instead of `tim:users`:

```bash
$ ls -ld /run/user/1000
drwxrwxrwt 11 root root 260 Feb  2 08:25 /run/user/1000
```

When `pam_systemd` checks ownership before starting `systemd --user`, the check fails and the user session never starts.

### Boot Sequence Analysis

From `journalctl -b`, the relevant events occur in this order:

1. **07:24:00** - WSLg tmpfs mount created at `/mnt/wslg/run/user/1000`
2. **07:24:00** - `User Runtime Directory /run/user/1000` service starts and finishes
3. **07:24:00** - `User Manager for UID 1000` starts
4. **07:24:00** - `pam_systemd` ownership check FAILS
5. **07:24:00** - `systemd --user` fails: "Runtime directory not owned by UID 1000"

### Why Root Ownership?

The issue stems from WSL's fstab-based filesystem setup. In `/etc/fstab` (generated from NixOS hardware-config.nix):

```
tmpfs /mnt/wslg/run/user/1000 tmpfs defaults 0 0
```

This creates `/mnt/wslg/run/user/1000` early in boot with `root:root` ownership.

**However**, the actual `/run/user/1000` directory is created by `systemd-user-runtime-dir`, which SHOULD create it with proper ownership. The problem appears to be:

1. Something creates `/run/user/1000` before `systemd-user-runtime-dir` runs
2. OR `systemd-user-runtime-dir` creates it with wrong ownership in WSL context
3. OR there's a race condition where the directory is created by multiple sources

### Key Files Examined

| File | Purpose | Relevant Content |
|------|---------|-----------------|
| `/etc/fstab` | WSL mounts | `/mnt/wslg/run/user/1000` as tmpfs |
| `hosts/pa161878-nixos/hardware-config.nix` | NixOS mount config | Defines the WSLg tmpfs mount |
| `hosts/common/default.nix` | Common NixOS config | Contains `linger = true` and an activation script fix |
| `user-runtime-dir@.service` | Systemd unit | Creates `/run/user/UID` directories |

### Existing Fix Attempt (Not Deployed)

There's an activation script in `hosts/common/default.nix` that was intended to fix this:

```nix
system.activationScripts.fixUserRuntimeDir = lib.stringAfter [ "users" ] ''
  echo "fixing /run/user/1000 ownership..."
  if [ -d /run/user/1000 ]; then
    chown tim:users /run/user/1000
    chmod 0700 /run/user/1000
  fi
'';
```

**Problem:** Activation scripts only run during `nixos-rebuild switch`, NOT at boot time. The ownership is reset on every boot when the tmpfs is recreated.

## Manual Workaround (Current Session)

To fix the issue for the current session:

```bash
# Fix ownership recursively
sudo chown -R tim:users /run/user/1000/

# Restart the user service
sudo systemctl restart user@1000.service

# Verify
systemctl --user status  # Should show "running"
```

This was successfully applied on 2026-02-02 at 08:26:17 PST.

## Proposed Permanent Solutions

### Option 1: Systemd Oneshot Service (Recommended)

Create a systemd service that runs at boot BEFORE `user@.service`:

```nix
# In hosts/common/default.nix or modules/wsl-common.nix
systemd.services.fix-user-runtime-dir = {
  description = "Fix /run/user/1000 ownership for WSL";
  wantedBy = [ "user@1000.service" ];
  before = [ "user@1000.service" ];
  after = [ "user-runtime-dir@1000.service" ];
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.coreutils}/bin/chown -R tim:users /run/user/1000";
    RemainAfterExit = true;
  };
};
```

**Pros:**
- Runs at the right time in the boot sequence
- Integrates properly with systemd dependencies
- Declarative NixOS configuration

**Cons:**
- Hardcodes UID 1000 and username "tim"

### Option 2: Systemd tmpfiles.d Rule

Use systemd-tmpfiles to ensure correct ownership:

```nix
systemd.tmpfiles.rules = [
  "d /run/user/1000 0700 tim users -"
];
```

**Note:** This might conflict with `systemd-user-runtime-dir` which also manages this directory. Needs testing.

### Option 3: ExecStartPre in user-runtime-dir Service

Add a drop-in for `user-runtime-dir@.service`:

```nix
systemd.services."user-runtime-dir@".serviceConfig.ExecStartPost = [
  "${pkgs.coreutils}/bin/chown %i:users /run/user/%i"
];
```

**Pros:**
- Uses the template variable `%i` for UID, more generic
- Runs immediately after directory creation

### Option 4: Override WSLg Mount Options

Modify the fstab entry to include uid/gid options:

```nix
fileSystems."/mnt/wslg/run/user/1000" = {
  device = "tmpfs";
  fsType = "tmpfs";
  options = [ "uid=1000" "gid=100" "mode=0700" ];
};
```

**Note:** This fixes `/mnt/wslg/run/user/1000` but not `/run/user/1000` which is a separate mount.

### Option 5: Investigate nixos-wsl Module

The nixos-wsl module might have a proper solution or be the source of the issue. Check:
- `inputs.nixos-wsl.nixosModules.default`
- Whether there's a WSL-specific user runtime directory handling

## Related Configuration

### User Linger Enabled

```nix
users.users.tim = {
  linger = true;  # Enable systemd user session persistence
};
```

This is correctly configured - `loginctl show-user tim` shows `Linger=yes`.

### WSL Configuration

```nix
wsl = {
  enable = true;
  defaultUser = "tim";
};
```

## Testing the Fix

After implementing the permanent fix:

1. Rebuild: `sudo nixos-rebuild switch --flake '.#thinky-nixos'`
2. Restart WSL: `wsl --shutdown` from PowerShell, then restart
3. Verify: `systemctl --user status` should show "running"
4. Verify Podman: `podman info | grep cgroupManager` should show "systemd"

## References

- [systemd user session documentation](https://www.freedesktop.org/software/systemd/man/user@.service.html)
- [pam_systemd runtime directory requirements](https://www.freedesktop.org/software/systemd/man/pam_systemd.html)
- [NixOS-WSL issues](https://github.com/nix-community/NixOS-WSL/issues)

## Appendix: Journal Excerpts

### Boot Failure (Jan 25, 2026)

```
Jan 25 07:24:00 pa161878-nixos systemd[1]: Starting User Runtime Directory /run/user/1000...
Jan 25 07:24:00 pa161878-nixos systemd[1]: Finished User Runtime Directory /run/user/1000.
Jan 25 07:24:00 pa161878-nixos systemd[1]: Starting User Manager for UID 1000...
Jan 25 07:24:00 pa161878-nixos (systemd)[385]: pam_systemd(systemd-user:session): Runtime directory '/run/user/1000' is not owned by UID 1000, as it should.
Jan 25 07:24:00 pa161878-nixos (systemd)[385]: pam_systemd(systemd-user:session): Not setting $XDG_RUNTIME_DIR, as the directory is not in order.
Jan 25 07:24:00 pa161878-nixos systemd[385]: Trying to run as user instance, but $XDG_RUNTIME_DIR is not set.
```

### Successful Manual Fix (Feb 2, 2026)

```
Feb 02 08:26:17 pa161878-nixos sudo[620413]: tim : COMMAND=/nix/store/.../chown -R tim:users /run/user/1000/
Feb 02 08:26:17 pa161878-nixos systemd[620419]: Queued start job for default target Main User Target.
Feb 02 08:26:17 pa161878-nixos systemd[620419]: Startup finished in 302ms.
```
