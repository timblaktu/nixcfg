#!/usr/bin/env bash
# embed.sh - drop an annotated asciicast into a self-contained HTML deck via asciinema-player.
#
# Usage:
#   embed.sh CAST.cast DECK.html NAME [--cols N] [--rows N] [--poster SECS]
#
# What it does:
#   1. Copies CAST next to DECK as <deckdir>/hsw-demo-assets/<NAME>.cast.
#   2. Vendors a pinned asciinema-player (CSS+JS) into <deckdir>/hsw-demo-assets/
#      asciinema-player/ so the deck plays offline (downloads once if missing).
#   3. If DECK contains the placeholder  <!-- SCREENCAST:NAME -->  it is replaced
#      in place with the player markup. Otherwise the markup is printed to stdout
#      for manual paste.
#
# The deck stays portable: one HTML file + a sibling assets dir, no network at
# show time. Markers injected by annotate.py appear on the player scrubber.
set -euo pipefail

die() { printf 'embed.sh: %s\n' "$*" >&2; exit 1; }

[[ $# -ge 3 ]] || die "usage: embed.sh CAST.cast DECK.html NAME [--cols N] [--rows N] [--poster SECS]"

CAST="$1"; DECK="$2"; NAME="$3"; shift 3
COLS=100; ROWS=30; POSTER="npt:0:01"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cols)   COLS="$2"; shift 2 ;;
    --rows)   ROWS="$2"; shift 2 ;;
    --poster) POSTER="npt:$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -f "$CAST" ]] || die "cast not found: $CAST"
[[ -f "$DECK" ]] || die "deck not found: $DECK"

PLAYER_VERSION="3.8.0"
DECK_DIR="$(cd "$(dirname "$DECK")" && pwd)"
ASSETS="$DECK_DIR/hsw-demo-assets"
PLAYER_DIR="$ASSETS/asciinema-player"
mkdir -p "$PLAYER_DIR"

cp -f "$CAST" "$ASSETS/${NAME}.cast"

# Vendor the player (pinned) once.
js="$PLAYER_DIR/asciinema-player.min.js"
css="$PLAYER_DIR/asciinema-player.css"
base="https://cdn.jsdelivr.net/npm/asciinema-player@${PLAYER_VERSION}/dist/bundle"
if [[ ! -s "$js" || ! -s "$css" ]]; then
  printf 'embed.sh: fetching asciinema-player %s ...\n' "$PLAYER_VERSION" >&2
  curl -fsSL "$base/asciinema-player.min.js" -o "$js" \
    || die "could not download player JS (offline?). Place asciinema-player@${PLAYER_VERSION} dist files in $PLAYER_DIR manually."
  curl -fsSL "$base/asciinema-player.css" -o "$css" \
    || die "could not download player CSS (offline?)."
fi

# Player markup. Relative paths keep the deck portable.
read -r -d '' MARKUP <<HTML || true
<!-- SCREENCAST:${NAME} -->
<link rel="stylesheet" href="hsw-demo-assets/asciinema-player/asciinema-player.css" />
<div id="screencast-${NAME}"></div>
<script src="hsw-demo-assets/asciinema-player/asciinema-player.min.js"></script>
<script>
  AsciinemaPlayer.create(
    'hsw-demo-assets/${NAME}.cast',
    document.getElementById('screencast-${NAME}'),
    { cols: ${COLS}, rows: ${ROWS}, poster: '${POSTER}', fit: 'width', markers: true }
  );
</script>
HTML

placeholder="<!-- SCREENCAST:${NAME} -->"
if grep -qF "$placeholder" "$DECK"; then
  python3 - "$DECK" "$placeholder" <<'PY' "$MARKUP"
import sys, pathlib
deck, placeholder, markup = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(deck)
p.write_text(p.read_text().replace(placeholder, markup))
print(f"embed.sh: injected player for screencast into {deck}", file=sys.stderr)
PY
else
  printf 'embed.sh: no placeholder %s found in deck.\n' "$placeholder" >&2
  printf 'embed.sh: paste this where the recording should appear:\n\n' >&2
  printf '%s\n' "$MARKUP"
fi
