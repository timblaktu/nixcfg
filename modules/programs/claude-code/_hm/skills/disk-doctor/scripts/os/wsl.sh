#!/usr/bin/env bash
# disk-doctor WSL module - READ-ONLY probe of WSL-specific reclaim levers.
# Inherits all Linux levers (run linux.sh too); adds WSL-only concerns.
set -euo pipefail

is_wsl=0
[ -n "${WSL_DISTRO:-}${WSL_DISTRO_NAME:-}" ] && is_wsl=1
grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && is_wsl=1
[ "$is_wsl" = "1" ] || { echo "wsl.sh: not WSL; use scripts/os/linux.sh instead." >&2; exit 2; }

section() { printf '\n=== %s ===\n' "$1"; }

echo "WSL detected (${WSL_DISTRO:-${WSL_DISTRO_NAME:-unknown}}). All Linux levers apply - also run scripts/os/linux.sh."

section ".vhdx sparse growth (the WSL-specific trap)"
cat <<'EOF'
WSL stores this distro on a virtual disk (.vhdx) on the Windows host. The .vhdx
GROWS as you use space but does NOT shrink when you delete files - so reclaiming
space inside WSL frees the Linux filesystem but the Windows-side .vhdx stays large.
To shrink it back (Windows-side, user action, after freeing space inside WSL):
  1. wsl --shutdown                     (from PowerShell/cmd)
  2. Optimize-VHD -Path <distro.vhdx> -Mode Full     (Hyper-V hosts), or
     diskpart> select vdisk file="<distro.vhdx>"; compact vdisk
Find the .vhdx: it is under %LOCALAPPDATA%\Packages\...\LocalState\ on Windows.
EOF

section "Windows %TEMP% visible via /mnt/c (do NOT delete blindly)"
for u in /mnt/c/Users/*; do
  t="$u/AppData/Local/Temp"
  [ -d "$t" ] && du -sh "$t" 2>/dev/null | sed 's/^/win temp: /'
done 2>/dev/null || echo "  (no /mnt/c user temp visible)"
echo "These are Windows-owned; clean from Windows (Disk Cleanup), not from WSL."

section "9p mounts (not reclaimable; noted for context)"
mount 2>/dev/null | grep -E '9p|drvfs' | sed 's/^/  /' | head -5 || echo "  (none)"
