# nix-guarded: systemd cgroup memory guard for nix commands
# Wraps nix invocations in a systemd --user --scope with percentage-based
# memory limits under a shared nix-eval.slice. Prevents OOM from runaway
# evaluations without the fd-leak problems of the previous flock approach.
#
# Two-level memory control:
#
#   Per-scope (this wrapper) — limits each individual nix invocation:
#     MemoryHigh  Soft ceiling (% of total RAM). When RSS exceeds this, the
#                 kernel aggressively reclaims pages (swapping). The process is
#                 NOT killed but slows down. Set above expected peak RSS to
#                 avoid throttle-induced swap pressure.
#     MemoryMax   Hard ceiling. The kernel OOM-kills the process immediately
#                 if RSS reaches this. Acts as a safety net for truly runaway
#                 evaluations — should be comfortably above MemoryHigh.
#
#   Slice (nix-eval.slice, deployed via HM) — aggregate ceiling for ALL
#   concurrent nix scopes combined. Ensures two simultaneous evals can't
#   starve the rest of the system. Also enables systemd-oomd monitoring:
#     ManagedOOMMemoryPressure=kill  Tells oomd to watch this slice.
#     ManagedOOMMemoryPressureDurationSec  How long sustained pressure must
#                 exceed the threshold before oomd kills a process (default 60s).
#
# Baseline (2026-04-18, 27.4G RAM):
#   nix flake check --no-build peaks at ~16.6G RSS. Defaults are tuned so a
#   single eval fits within MemoryHigh without throttling. Two concurrent evals
#   will exceed the slice ceiling and trigger oomd (correct behavior).
#
# At build time, @@NIX_REAL@@ is replaced with the store path to the real nix binary.
# Bypass: NIX_NO_GUARD=1 nix <args>
#
# Environment variable overrides (accepts any value systemd accepts):
#   NIX_GUARD_MEM_HIGH  - per-scope MemoryHigh (default: 65%)
#   NIX_GUARD_MEM_MAX   - per-scope MemoryMax  (default: 75%)
#
# NOTE: writeShellApplication provides shebang, set -euo pipefail, and shellcheck.

NIX_REAL="@@NIX_REAL@@"

if [[ "${NIX_NO_GUARD:-}" == "1" ]]; then
  exec "$NIX_REAL" "$@"
fi

# Short description for systemd journal
desc="nix${1:+ $1}"

# Try systemd-run with cgroup memory limits.
# Degrade gracefully if unavailable (containers, CI, no user session).
if command -v systemd-run >/dev/null 2>&1 && \
   systemd-run --user --scope --quiet -- true 2>/dev/null; then
  exec systemd-run --user --scope --quiet \
    --slice=nix-eval.slice \
    -p MemoryHigh="${NIX_GUARD_MEM_HIGH:-65%}" \
    -p MemoryMax="${NIX_GUARD_MEM_MAX:-75%}" \
    --description="$desc" \
    -- "$NIX_REAL" "$@"
fi

# Fallback: run unguarded
exec "$NIX_REAL" "$@"
