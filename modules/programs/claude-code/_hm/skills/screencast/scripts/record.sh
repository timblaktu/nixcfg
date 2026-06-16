#!/usr/bin/env bash
# record.sh - thin, opinionated wrapper around `asciinema rec`.
#
# Records a terminal session to an asciicast-v2 file (v2 chosen for the widest
# downstream support: asciinema-player, agg, and the annotate.py engine all read
# it natively). Sets sane defaults for presentation capture.
#
# Usage:
#   record.sh OUTPUT.cast [--title "Text"] [--idle SECS] [--size COLSxROWS] \
#             [-- COMMAND ARG...]
#
# Modes:
#   - Interactive (no `-- COMMAND`): drops you into a recorded shell. Type your
#     demo, then `exit` or Ctrl-D to stop. Ctrl-\ pauses/resumes capture.
#   - Scripted   (`-- COMMAND ...`): runs COMMAND headless and captures only its
#     output. Deterministic and re-runnable; ideal for slow build segments that
#     you want to record once and replay. NOTE: a scripted run executes COMMAND
#     for real every time - capture slow builds ONCE, then annotate the .cast.
#
# After recording, post-process with annotate.py (compress idle, add title cards
# + markers), then export with embed.sh (into an HTML deck) or agg (gif/mp4).
set -euo pipefail

die() { printf 'record.sh: %s\n' "$*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: record.sh OUTPUT.cast [--title T] [--idle N] [--size CxR] [-- CMD...]"

OUT="$1"; shift
TITLE=""
IDLE="2.0"          # cap idle gaps during capture; annotate.py compresses further
SIZE=""             # e.g. 100x30 for a consistent recording geometry
CMD=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) TITLE="$2"; shift 2 ;;
    --idle)  IDLE="$2";  shift 2 ;;
    --size)  SIZE="$2";  shift 2 ;;
    --)      shift; CMD=("$@"); break ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v asciinema >/dev/null 2>&1 || die "asciinema not found on PATH (home-manager switch with the screencast skill enabled)"

args=(rec --overwrite -f asciicast-v2 --idle-time-limit "$IDLE")
[[ -n "$TITLE" ]] && args+=(--title "$TITLE")
[[ -n "$SIZE"  ]] && args+=(--window-size "$SIZE")

if [[ ${#CMD[@]} -gt 0 ]]; then
  # Scripted capture: run the command headless so it never touches the live TTY.
  # asciinema's -c takes ONE string that it re-parses through a shell, so the
  # original argv must be shell-quoted to survive that round-trip (a plain
  # "${CMD[*]}" join silently drops nested quoting).
  printf -v CMD_STR '%q ' "${CMD[@]}"
  args+=(--headless -c "$CMD_STR")
fi

args+=("$OUT")

printf 'record.sh: capturing -> %s\n' "$OUT" >&2
asciinema "${args[@]}"
printf 'record.sh: done. Next: annotate.py %s steps.toml -o %s.annotated.cast\n' "$OUT" "${OUT%.cast}" >&2
