# Plan 060 T6 - proactive low-disk SessionStart warning.
# Runs the disk-doctor analyzer in --quiet mode and, when free space on the
# root filesystem is below a configurable threshold, surfaces a one-shot
# warning as SessionStart hookSpecificOutput.additionalContext (the same
# injection convention the resume hook uses). Silent when healthy; never blocks
# (continueOnError=true at the group), so it can only ever ADD a line of
# session-start context, never gate startup.
#
# The Nix writeShellScript wrapper injects, before this body:
#   PATH            bash/jq/coreutils/gawk
#   ANALYZE_SH      store path to the disk-doctor analyze.sh (reused verbatim)
#   DISK_WARN_PCT   used-percent threshold (warn when used% >= this)
#   DISK_WARN_GIB   free-GiB threshold   (warn when free < this many GiB)
#
# This file is builtins.readFile'd verbatim into the wrapper, so its ${...}
# parameter expansions need NO Nix escaping.
set -u

pct_threshold="${DISK_WARN_PCT:-90}"
gib_threshold="${DISK_WARN_GIB:-20}"

# analyze.sh --quiet prints one line: FREE=<bytes> PCT=<used%> MOUNT=<mount>.
# Any failure (missing df, odd host) degrades to silence, never an error.
out="$(bash "$ANALYZE_SH" --quiet 2>/dev/null)" || exit 0

free_bytes=""
pct=""
mount="/"
# shellcheck disable=SC2086  # deliberate word-splitting of the fixed KEY=VAL line
set -- $out
for tok in "$@"; do
  case "$tok" in
    FREE=*) free_bytes="${tok#FREE=}" ;;
    PCT=*) pct="${tok#PCT=}" ;;
    MOUNT=*) mount="${tok#MOUNT=}" ;;
  esac
done

# Need numeric values to decide; otherwise stay silent.
case "$free_bytes" in '' | *[!0-9]*) exit 0 ;; esac
case "$pct" in '' | *[!0-9]*) exit 0 ;; esac

gib_threshold_bytes=$((gib_threshold * 1024 * 1024 * 1024))
free_gib=$((free_bytes / 1024 / 1024 / 1024))

low=0
reason=""
if [ "$pct" -ge "$pct_threshold" ]; then
  low=1
  reason="${pct}% used (>= ${pct_threshold}% threshold)"
fi
if [ "$free_bytes" -lt "$gib_threshold_bytes" ]; then
  low=1
  if [ -n "$reason" ]; then
    reason="${reason}; only ${free_gib} GiB free (< ${gib_threshold} GiB threshold)"
  else
    reason="only ${free_gib} GiB free (< ${gib_threshold} GiB threshold)"
  fi
fi

[ "$low" -eq 1 ] || exit 0

msg="Low disk on ${mount}: ${reason}. Run the disk-doctor skill (/disk-doctor) to audit the Nix store, GC-roots, caches, temp, and large directories and get a ranked, safe reclaim plan."

jq -n --arg ctx "$msg" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
