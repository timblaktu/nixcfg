# Plan 022: WSL Systemd User Session Fix — Declarative /run/user Ownership

**Branch**: `refactor/dendritic-pattern`
**Status**: IMPLEMENTED — awaiting deployment validation
**Created**: 2026-02-12
**Host affected**: pa161878-nixos (confirmed), thinky-nixos (unconfirmed — may differ)

## Problem Statement

On NixOS-WSL (pa161878-nixos), the systemd user session fails at boot because `/run/user/1000` is owned by `root:root` instead of `tim:users`. This causes:

1. `user@1000.service` fails (exit status 1)
2. No `$XDG_RUNTIME_DIR` set
3. No user dbus session bus
4. `nixos-rebuild switch` reports: "Error: Failed to open dbus connection / Unable to autolaunch a dbus-daemon without a $DISPLAY for X11"

## Root Cause Analysis

### Mount Hierarchy (findmnt output on pa161878-nixos)

```
/run/user          none            tmpfs  rw,nosuid,nodev,noexec,noatime,mode=755  <- systemd
└─/run/user        none[/run/user] tmpfs  rw,relatime                              <- WSL OVERLAY
  └─/run/user/1000 tmpfs           tmpfs  rw,relatime                              <- on WSL overlay
```

WSL's init process overlays its own tmpfs on `/run/user` **after** systemd creates it. This overlay is owned by root. When `user-runtime-dir@1000.service` runs, it creates `/run/user/1000` on top of the WSL overlay, inheriting root ownership.

### Boot Sequence (from journal)

```
09:01:56 Mounting /mnt/wslg/run/user/1000...
09:01:56 Mounted /mnt/wslg/run/user/1000.
09:01:57 Starting User Runtime Directory /run/user/1000...
09:01:57 Finished User Runtime Directory /run/user/1000.
09:01:57 pam_systemd: Runtime directory '/run/user/1000' is not owned by UID 1000
09:01:57 pam_systemd: Not setting $XDG_RUNTIME_DIR
09:01:57 systemd: Trying to run as user instance, but $XDG_RUNTIME_DIR is not set.
```

### Key Differentiator: hardware-config.nix

**pa161878-nixos** (`modules/hosts/pa161878-nixos [N]/_hardware-config.nix`):
- Full auto-generated config from `nixos-generate-config`
- Declares ALL WSLg mounts including:
  - `/mnt/wslg` (tmpfs)
  - `/mnt/wslg/distro` (bind /)
  - `/mnt/wslg/doc` (overlay)
  - `/mnt/wslg/run/user/1000` (tmpfs) ← LINE 76-80
  - `/tmp/.X11-unix` (bind from WSLg)
  - `/usr/lib/wsl/drivers` (9p)
  - `/usr/lib/wsl/lib` (overlay)

**thinky-nixos** (`modules/hosts/thinky-nixos/_hardware-config.nix`):
- Custom config with ONLY Google Drive mounts (drvfs)
- Does NOT declare ANY WSLg mounts
- WSLg mounts still happen (WSL init creates them) but NixOS doesn't manage them

**Hypothesis**: The presence of NixOS-managed WSLg mounts in hardware-config changes the mount ordering/behavior, potentially causing the WSL overlay on `/run/user` to persist after systemd's user-runtime-dir runs.

### Current State on pa161878-nixos

```
$ ls -ld /run/user/1000
drwxrwxrwt 3 root root 60 Feb 12 09:02 /run/user/1000
# Should be: drwx------ N tim users

$ systemctl status user@1000.service
Active: inactive (dead) - exit status 1/FAILURE

$ echo $DBUS_SESSION_BUS_ADDRESS  # empty
$ echo $XDG_RUNTIME_DIR           # empty
$ ls /run/user/1000/bus            # No such file
```

### Systemd Version

systemd 258.3 — this version has stricter `pam_systemd` ownership checks than earlier versions. The check CANNOT be disabled (security requirement).

### WSL Version

WSL 2.6.3.0, Kernel 6.6.87.2, WSLg 1.0.71

## Upstream References

- [microsoft/WSL#13143](https://github.com/microsoft/WSL/issues/13143) — systemctl --user failing due to /run/user setup
- [nix-community/NixOS-WSL#346](https://github.com/nix-community/NixOS-WSL/issues/346) — /run/user/$UID permissions 0755 instead of 0700
- [microsoft/WSL#10205](https://github.com/microsoft/WSL/issues/10205) — WSL login nukes systemd/dbus user session
- [microsoft/WSL#8842](https://github.com/microsoft/WSL/issues/8842) — systemd doesn't create user dbus

## Solution Requirements

1. **Declarative** — must be in NixOS/Nix configuration, not manual workarounds
2. **Idempotent** — safe to run multiple times, across rebuilds
3. **Per-host-configurable** — option in wsl-settings to enable/disable
4. **Homogeneous** — should normalize all WSL/systemd user session inconsistencies
5. **Boot-order-aware** — must run AFTER mounts, BEFORE user@.service

## Proposed Solution: Multi-Layer Fix

### Layer 1: Systemd oneshot service (ownership fix)

Add to `modules/system/settings/wsl/wsl.nix`:

```nix
systemd.services."fix-wsl-user-runtime-dir@" = {
  description = "Fix /run/user/%i ownership for WSL systemd user sessions";
  documentation = [ "man:systemd-user-runtime-dir(8)" ];
  before = [ "user@%i.service" ];
  after = [ "user-runtime-dir@%i.service" ];
  wants = [ "user-runtime-dir@%i.service" ];
  wantedBy = [ "multi-user.target" ];
  unitConfig = {
    StopWhenUnneeded = true;
  };
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = pkgs.writeShellScript "fix-wsl-user-runtime-dir" ''
      UID_NUM=%i
      RUNDIR="/run/user/$UID_NUM"
      USERNAME=$(id -un "$UID_NUM" 2>/dev/null)
      if [ -d "$RUNDIR" ] && [ "$(stat -c %u "$RUNDIR")" != "$UID_NUM" ]; then
        chown "$UID_NUM" "$RUNDIR"
        chmod 0700 "$RUNDIR"
        echo "Fixed ownership of $RUNDIR for $USERNAME (UID $UID_NUM)"
      fi
    '';
  };
};
```

### Layer 2: User linger (persistent user session)

```nix
users.users.${cfg.defaultUser}.linger = true;
```

### Layer 3: Tmpfiles safety net

```nix
systemd.tmpfiles.rules = [
  "d /run/user/1000 0700 ${cfg.defaultUser} users -"
];
```

### Layer 4: Option grouping

```nix
options.wsl-settings.systemdUserSession = {
  fixRuntimeDir = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Fix /run/user ownership for WSL systemd user sessions at boot";
  };
  enableLinger = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable user linger for persistent systemd user session";
  };
};
```

## Implementation Notes (2026-02-12)

**Approach changed from plan**: Used a non-template (non-`@`) service targeting the specific UID
rather than a template service. This avoids complexity around NixOS systemd template service
instantiation while still being correct — the UID is resolved at evaluation time from
`config.users.users.${cfg.defaultUser}.uid`.

**Commits**:
- `0c14942` — Add homeDefault.enableLocalAI flag, disable CUDA on pa161878-nixos
- `f31c8b1` — Add WSL systemd user session fix (Plan 022)

**What was implemented**:
- `wsl-settings.systemdUserSession.fixRuntimeDir` (default: true) — oneshot service
- `wsl-settings.systemdUserSession.enableLinger` (default: true) — user linger
- Tmpfiles safety net rule for `/run/user/<UID>`
- Both options default to true, so all WSL hosts get the fix automatically

**Also done (related)**:
- Added `homeDefault.enableLocalAI` option to gate marker-pdf
- Disabled CUDA + marker-pdf on pa161878-nixos

## Investigation TODO for Next Session

- [ ] Verify whether thinky-nixos actually has the same underlying issue (check ownership there)
- [x] ~~Determine if the template service (@) approach works~~ — Used non-template approach instead
- [ ] Check if `users.users.tim.linger = true` interacts correctly with NixOS-WSL (deploy to verify)
- [ ] Validate the fix doesn't break the WSLg socket paths (Wayland, PulseAudio, X11)

## Validation Checklist

After implementation, verify:

```bash
# 1. Directory ownership correct
ls -ld /run/user/1000
# Expected: drwx------ ... tim users (or tim root)

# 2. User session running
systemctl --user status
# Expected: active (running)

# 3. D-Bus session available
echo $DBUS_SESSION_BUS_ADDRESS
# Expected: not empty

# 4. XDG_RUNTIME_DIR set
echo $XDG_RUNTIME_DIR
# Expected: /run/user/1000

# 5. nixos-rebuild switch clean
sudo nixos-rebuild switch --flake '.#pa161878-nixos'
# Expected: no dbus error during "reloading user units for tim..."

# 6. User linger enabled
loginctl show-user tim | grep Linger
# Expected: Linger=yes
```

## Files to Modify

| File | Change |
|------|--------|
| `modules/system/settings/wsl/wsl.nix` | Add `systemdUserSession` options + service + tmpfiles |
| `modules/hosts/pa161878-nixos [N]/pa161878-nixos.nix` | Enable if not default |

## Definition of Done

- [ ] `nixos-rebuild switch` on pa161878-nixos produces no dbus error
- [ ] `/run/user/1000` owned by tim after reboot
- [ ] `systemctl --user status` works
- [ ] `$XDG_RUNTIME_DIR` and `$DBUS_SESSION_BUS_ADDRESS` set in new shells
- [x] Solution is declarative (no manual chown needed)
- [x] `nix flake check --no-build` passes
