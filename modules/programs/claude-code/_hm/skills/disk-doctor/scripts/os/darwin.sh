#!/usr/bin/env bash
# disk-doctor macOS module - READ-ONLY probe of macOS-specific reclaim levers.
# NOTE: authored on Linux; runtime-verify on a real macOS host before trusting output.
set -euo pipefail

[ "$(uname -s)" = "Darwin" ] || { echo "darwin.sh: not macOS (uname=$(uname -s)); aborting." >&2; exit 2; }

section() { printf '\n=== %s ===\n' "$1"; }

section "Disk usage and purgeable space"
df -h / 2>/dev/null
if command -v diskutil >/dev/null 2>&1; then
  diskutil info / 2>/dev/null | grep -iE 'Container Free Space|Free Space|Volume Free Space' | sed 's/^/  /' || true
  echo "  'Free' includes purgeable (APFS). Purgeable is mostly local snapshots + caches."
fi

section "APFS local Time Machine snapshots (often GBs; reclaimable)"
if command -v tmutil >/dev/null 2>&1; then
  tmutil listlocalsnapshots / 2>/dev/null | sed 's/^/  /' || echo "  (none)"
  echo "  Thin them (user action): tmutil thinlocalsnapshots / <bytes> 4"
  echo "  Or disable local snapshots while low: sudo tmutil disablelocal (older macOS)"
else
  echo "  tmutil not found (unexpected on macOS)"
fi

section "User and developer caches (macOS paths)"
for d in "Library/Caches" "Library/Developer/Xcode/DerivedData" "Library/Developer/CoreSimulator/Caches" "Library/Developer/Xcode/iOS DeviceSupport"; do
  [ -d "$HOME/$d" ] && du -sh "$HOME/$d" 2>/dev/null | sed 's/^/  /'
done
echo "  Xcode DerivedData is safe to delete (rebuilds). CoreSimulator can be huge."

section "Homebrew cache"
if command -v brew >/dev/null 2>&1; then
  brew --cache 2>/dev/null | xargs -I{} du -sh {} 2>/dev/null | sed 's/^/  brew cache: /' || true
  echo "  Reclaim with: brew cleanup -s   (and: brew autoremove)"
else
  echo "  brew not installed"
fi

section "Nix store"
echo "Nix store levers are OS-agnostic - see SKILL.md 'The Nix store' and analyze.sh output."
echo "On nix-darwin the scheduled GC is a launchd job (not systemd); query it with: launchctl list | grep nix"
