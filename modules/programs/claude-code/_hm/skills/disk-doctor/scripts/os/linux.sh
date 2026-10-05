#!/usr/bin/env bash
# disk-doctor Linux module - READ-ONLY probe of Linux-specific reclaim levers.
set -euo pipefail

[ "$(uname -s)" = "Linux" ] || { echo "linux.sh: not Linux (uname=$(uname -s)); aborting." >&2; exit 2; }

section() { printf '\n=== %s ===\n' "$1"; }

section "/tmp backing and aging"
if findmnt /tmp >/dev/null 2>&1; then
  findmnt -no FSTYPE,SIZE,TARGET /tmp | sed 's/^/tmp mount: /'
else
  echo "/tmp is not a separate mount (on-disk, part of /). Survives reboots."
fi
echo "systemd-tmpfiles aging rules touching /tmp (deletes by age):"
{ cat /etc/tmpfiles.d/*.conf /run/current-system/sw/lib/tmpfiles.d/*.conf /usr/lib/tmpfiles.d/*.conf; } 2>/dev/null \
  | grep -E '^[[:space:]]*[qQeR!]+[[:space:]]+/(tmp|var/tmp)' || echo "  (none found)"
if systemctl is-enabled systemd-tmpfiles-clean.timer >/dev/null 2>&1; then
  echo "systemd-tmpfiles-clean.timer: enabled (the aging cleaner runs)."
fi

section "Local filesystem snapshots (reclaimable)"
if command -v zfs >/dev/null 2>&1; then
  zfs list -t snapshot -o name,used 2>/dev/null | head -20 || echo "  zfs present, no snapshots listed"
else echo "  no zfs"; fi
if command -v btrfs >/dev/null 2>&1; then
  echo "  btrfs present - check: sudo btrfs subvolume list / ; sudo btrfs filesystem usage /"
else echo "  no btrfs"; fi

section "Package-manager caches"
if command -v apt-get >/dev/null 2>&1; then
  du -sh /var/cache/apt/archives 2>/dev/null | sed 's/^/apt archives: /' || true
  echo "  clean with: sudo apt-get clean"
fi
[ -d "$HOME/.cache/apt-cacher-ng" ] && du -sh "$HOME/.cache/apt-cacher-ng" 2>/dev/null | sed 's/^/apt-cacher-ng: /'

section "Yocto/ISAR build state (large, regenerable, slow to rebuild)"
# shellcheck disable=SC2016  # literal glob is intentional guidance
echo 'Scan for build dirs:  fd -I -t d "^build$" ~/src | rg "backends/.*/build$"'
[ -d "$HOME/.cache/yocto" ] && du -sh "$HOME/.cache/yocto"/* 2>/dev/null | sort -rh | sed 's/^/yocto cache: /'

section "Developer caches (XDG)"
for d in go-build nix uv go; do
  [ -d "$HOME/.cache/$d" ] && du -sh "$HOME/.cache/$d" 2>/dev/null | sed 's/^/  /'
done
echo "Note: ISAR/Yocto build dirs are often root-owned (container user-ns). Deletion needs 'sudo rm -rf' - hand it to the user."
