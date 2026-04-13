# nix-guarded: flock-based concurrency guard for nix commands
# Serializes all nix evaluations system-wide to prevent OOM kills
# from concurrent nix evaluations in multi-agent sessions.
#
# At build time, @@NIX_REAL@@ is replaced with the store path to the real nix binary.
# Bypass: NIX_NO_GUARD=1 nix <args>
#
# NOTE: writeShellApplication provides shebang, set -euo pipefail, and shellcheck.

LOCK="/tmp/nix-eval-guard.lock"
NIX_REAL="@@NIX_REAL@@"

if [[ "${NIX_NO_GUARD:-}" == "1" ]]; then
  exec "$NIX_REAL" "$@"
fi

# Open lock file descriptor; degrade gracefully if it fails.
# NOTE: Do NOT use 2>/dev/null on the exec line — bash exec without a command
# applies redirections to the shell itself, permanently sending stderr to /dev/null.
if ! { exec {fd}>"$LOCK"; } 2>/dev/null; then
  exec "$NIX_REAL" "$@"
fi

# Try non-blocking first; if contested, log and block
if ! flock --nonblock "$fd" 2>/dev/null; then
  echo "[nix-guard] Waiting for lock (another nix evaluation is running)..." >&2
  if ! flock --timeout 600 "$fd"; then
    echo "[nix-guard] Lock timeout after 600s, proceeding anyway" >&2
  fi
fi

exec "$NIX_REAL" "$@"
