#!/usr/bin/env bash
# disk-doctor core analyzer - OS-agnostic, strictly READ-ONLY.
# Reports filesystem usage, largest dirs, Nix store + GC-roots audit, and caches.
# Tools are nix-managed via the skill's home.packages (dust/duf), with coreutils
# fallbacks so the script still works if they are absent.
#
# Usage:
#   analyze.sh            Full human-readable triage.
#   analyze.sh --quiet    One line "FREE=<bytes> PCT=<used%> MOUNT=/" for hooks.
set -euo pipefail

quiet=0
[ "${1:-}" = "--quiet" ] && quiet=1

have() { command -v "$1" >/dev/null 2>&1; }

# --- quiet mode: one line for a low-disk warning hook -------------------------
if [ "$quiet" -eq 1 ]; then
  # Portable df: -P for POSIX columns, -k for KiB (GNU and BSD/macOS agree).
  line=$(df -Pk / | awk 'NR==2')
  avail_k=$(echo "$line" | awk '{print $4}')
  pct=$(echo "$line" | awk '{gsub(/%/,"",$5); print $5}')
  printf 'FREE=%s PCT=%s MOUNT=/\n' "$((avail_k * 1024))" "$pct"
  exit 0
fi

section() { printf '\n=== %s ===\n' "$1"; }

section "Filesystem usage"
if have duf; then
  duf --only local 2>/dev/null || duf 2>/dev/null || df -h
else
  df -h | awk 'NR==1 || /^\/dev|^\/$| \/$/'
fi

section "Largest directories under \$HOME (top 15)"
if have dust; then
  dust -d 1 -n 15 -r "$HOME" 2>/dev/null || true
else
  du -xh --max-depth=1 "$HOME" 2>/dev/null | sort -rh | head -15 || true
fi

# --- Nix store (identical across Linux/WSL/macOS) -----------------------------
if have nix && [ -d /nix/store ]; then
  section "Nix store"
  df -h /nix 2>/dev/null | awk 'NR==1 || NR==2'

  section "Nix GC config (live - the min-free emergency-GC hazard)"
  nix config show 2>/dev/null | grep -E 'min-free|max-free|auto-optimise-store|keep-outputs|keep-derivations' || true

  section "Dead store paths (collectable now)"
  dead=$(nix-store --gc --print-dead 2>/dev/null | wc -l | tr -d ' ')
  printf '%s dead paths. Collect with: nix-collect-garbage  (add -d to prune old generations)\n' "$dead"

  section "GC-roots audit (the #1 lever - stale out-links pin whole closures)"
  if [ -d /nix/var/nix/gcroots/auto ]; then
    stale_tmp=0
    printf '%-9s %s\n' 'CLOSURE' 'ROOT -> TARGET'
    for l in /nix/var/nix/gcroots/auto/*; do
      [ -e "$l" ] || continue
      tgt=$(readlink "$l" 2>/dev/null) || continue
      [ -n "$tgt" ] || continue
      store=$tgt
      # Indirect roots point at an out-link symlink; resolve one more hop.
      if [ -L "$tgt" ]; then store=$(readlink "$tgt" 2>/dev/null || echo "$tgt"); fi
      sz=$(nix path-info -Sh "$store" 2>/dev/null | awk '{print $2}' | head -1)
      flag=''
      case "$tgt" in /tmp/*) flag=' [STALE? /tmp out-link]'; stale_tmp=$((stale_tmp + 1)) ;; esac
      printf '%-9s %s%s\n' "${sz:-?}" "$tgt" "$flag"
    done | sort -h | tail -40
    printf '\n%s indirect roots live under /tmp (prime stale candidates; removing the symlink frees its closure).\n' "$stale_tmp"
  fi
else
  section "Nix store"
  echo "nix not found on PATH - skipping store/GC-roots audit."
fi

# --- Generic caches (OS module covers OS-specific cache locations) ------------
section "Caches under \$HOME/.cache (top 12)"
if [ -d "$HOME/.cache" ]; then
  du -xh --max-depth=1 "$HOME/.cache" 2>/dev/null | sort -rh | head -12 || true
else
  echo "no \$HOME/.cache"
fi

section "Next step"
echo "Load the environment module for OS-specific levers:"
echo "  Darwin        -> references/darwin.md + scripts/os/darwin.sh"
echo "  Linux (WSL)   -> references/wsl.md    + scripts/os/wsl.sh"
echo "  Linux (other) -> references/linux.md  + scripts/os/linux.sh"
