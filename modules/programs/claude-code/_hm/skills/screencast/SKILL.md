---
name: screencast
description: Record terminal sessions and post-process them into standalone, narration-free screencasts. Use when asked to record a terminal demo, capture a CLI session for a presentation, compress/annotate a recording, turn a session into a GIF/MP4, or embed a terminal recording in an HTML deck. Built on asciinema + agg + ffmpeg.
---

# Screencast Skill

**Version**: 1.0.0
**Last Updated**: 2026-06-16

Record a terminal session once, then post-process the text-based `.cast` so it is
watchable with **zero audio narration**: idle/build gaps are collapsed with honest
"skipped Nm Ns" frames, step boundaries get on-screen title cards, and chapter
markers land on the player scrubber. Primary output target is an **embedded player
inside a self-contained HTML deck**; GIF/MP4 export is available via agg/ffmpeg.

## When to use

- "Record this terminal demo / CLI session for the presentation."
- "Compress this recording - skip the slow build part."
- "Annotate the recording so it explains itself without me talking."
- "Embed the recording in the deck" / "turn it into a GIF or MP4."

## Toolchain (provided by the skill's home-manager deps)

| Tool | Role |
|------|------|
| `asciinema` 3.x | record / convert / play (`.cast`, asciicast format) |
| `agg` | `.cast` -> animated GIF (and PNG frames for video) |
| `ffmpeg` | frames -> MP4/WebM, burned-in captions if wanted |
| `vhs` | optional: fully-scripted deterministic recordings from a `.tape` |

Scripts live beside this file in `scripts/`. Resolve them relative to the skill
dir (`SKILL_DIR=$(dirname "$0")`-style) - they are deployed read-only with the skill.

## The pipeline: record -> annotate -> embed

### 1. Record (`scripts/record.sh`)

Writes **asciicast-v2** (widest player/agg/engine support).

```bash
# Interactive: drops into a recorded shell; type the demo, then exit / Ctrl-D.
record.sh demo.cast --title "Consume packages from acme-validated" --size 100x30

# Scripted: capture one command headless (no TTY needed, re-runnable).
record.sh build.cast -- nix run '.' -- --variant base
```

**Critical for slow segments:** a scripted run executes the command *for real every
time*. Capture a slow ISAR/pipeline run **ONCE**, keep the `.cast`, and do all
further iteration in annotate.py - never re-record to tweak pacing.

### 2. Annotate + compress (`scripts/annotate.py`)

The engine. Operates purely on the text `.cast`; the source is never mutated.

```bash
annotate.py demo.cast steps.toml -o demo.annotated.cast
# or, gap-compression only (no steps file):
annotate.py demo.cast --gap 6 --skip-dwell 1.0 -o demo.annotated.cast
```

Sidecar `steps.toml` (a `.json` sidecar with the same keys also works). `at` is the
timestamp **in the original recording**; find them with `asciinema play demo.cast`
or by reading the cast's event times.

```toml
gap_threshold = 8.0     # collapse idle longer than this (seconds)
skip_dwell    = 1.2     # replacement dwell for a collapsed gap
card_dwell    = 2.5     # how long a title card stays on screen
width         = 72      # banner width in columns

[[step]]
at    = 0.0
label = "List all 16 image variants"

[[step]]
at    = 42.0
label = "Consume 15 packages from acme-validated"
```

What it produces: a boxed blue title card at each `at`, a dim `⏩ skipped Nm Ns`
frame at every collapsed gap, and an asciicast `m` marker per step for the scrubber.

### Choosing the embed: `file://` (double-click) vs HTTP-served

**DECIDE THIS FIRST - it dictates 3a vs 3c.** How will the deck be OPENED at show time?

- **Double-clicked / opened as a `file://` path** (incl. `file://wsl.localhost/...` from a
  Windows browser), emailed as a file, or handed off to someone who won't run a server
  => **use the MP4 `<video>` embed (3c), NOT the asciinema player.** The vendored
  asciinema-player v3 runs its terminal emulator as **WebAssembly**, and browsers REFUSE
  to instantiate that WASM from a `file://` origin - the player mounts but renders a
  **blank black box**. This is independent of how the cast is supplied (relative fetch,
  base64 `data:` URI, or fully-inlined `{data: atob(...)}` all fail the same way), so no
  amount of inlining fixes it. Symptom: deck text/diagrams render, the cast pane is empty.
- **Served over `http(s)://`** (localhost `python3 -m http.server`, or a real web host)
  => the asciinema player works (3a), giving a scrubber, chapter markers, and copyable text.

When unsure, prefer 3c (MP4): a `<video>` plays over BOTH `file://` and HTTP with zero JS,
so it is the durable, no-surprises default for a presentation deck.

### 3a. Embed the asciinema player in an HTML deck (`scripts/embed.sh`) - HTTP-served decks only

```bash
embed.sh demo.annotated.cast docs/hsw-showcase.html consume-packages --cols 100 --rows 30
```

Copies the cast to `<deckdir>/hsw-demo-assets/<name>.cast`, vendors a pinned
asciinema-player (offline-capable) into `hsw-demo-assets/asciinema-player/`, and
replaces the placeholder `<!-- SCREENCAST:<name> -->` in the deck with the player
markup. If the placeholder is absent it prints the markup to paste. The deck stays
one portable HTML file + a sibling assets dir - no CDN at show time. **But it only
plays when the deck is SERVED over http(s)** (see the decision note above): the WASM
player will not run from a double-clicked `file://` deck. "No network" here means
"no CDN", NOT "works from disk".

### 3c. Embed an MP4 `<video>` in an HTML deck - the `file://`/double-click-safe path

The robust default for a deck someone opens by double-clicking. Render the cast to MP4
(see 3b) and drop a plain `<video>` in place of the `<!-- SCREENCAST:<name> -->`
placeholder - it plays over `file://` AND HTTP with zero JS, no WASM, no fetch:

```html
<video controls muted playsinline loop preload="metadata"
       style="width:100%;height:100%;object-fit:contain;background:#121212">
  <source src="assets/<name>/demo.mp4" type="video/mp4">
  <a href="assets/<name>/demo.mp4">Download the demo video</a>
</video>
```

Relative `<source src>` loads fine over `file://` (unlike `fetch()`/WASM). Keep the
`.cast` beside the `.mp4` for future re-annotation. Trade-off vs 3a: no scrubber
chapter markers and no selectable text - acceptable for a linear video on a slide.

### 3b. Export GIF / MP4 (fallback)

```bash
# GIF (markers are player-only; a GIF is linear). agg needs an explicit monospace
# font family - "Cascadia Mono" ships in the home profile:
agg --font-family "Cascadia Mono" --theme monokai demo.annotated.cast demo.gif

# Trim by injected markers, then GIF:
agg --font-family "Cascadia Mono" --select marker:0..marker:2 demo.annotated.cast clip.gif

# MP4 via the GIF (when you need a real video file, e.g. for the 3c <video> embed).
# The pad filter forces EVEN width/height - yuv420p (needed for broad browser playback)
# rejects odd dimensions, and agg's terminal-derived size is often odd:
ffmpeg -y -i demo.gif -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2:color=black" \
  -movflags +faststart -pix_fmt yuv420p demo.mp4
```

> agg resolves fonts through fontconfig. If it errors with "no faces matching font
> family options", pass `--font-family "Cascadia Mono"` (or any installed monospace).
> The exact installed family may be `"Cascadia Mono PL"` - check `fc-list | grep -i cascadia`.

> Use the `agg` on PATH (home-manager profile), NOT `nix run 'nixpkgs#agg'` - the
> nixpkgs `agg` build has failed to execute here ("No such file or directory" on an
> existing binary). `command -v agg` should resolve to `~/.nix-profile/bin/agg`.

> WebM (`-c:v libvpx-vp9`) may fail if this ffmpeg lacks libvpx ("Conversion failed",
> 0-byte output). MP4 (h264) alone plays everywhere modern; don't block on WebM.

## Deterministic scripted recordings (VHS) - when to prefer it

Use `vhs` instead of record.sh **only** when the demo is fast and you want a
fully-reproducible, source-controlled recording (a `.tape` script of keystrokes).
Do **not** use VHS for slow builds - it re-runs the command on every render. For
this project's slow ISAR/pipeline segments, always use `record.sh` (capture once)
+ annotate.py.

## Gotchas

- **asciicast version**: asciinema 3.x records **v3** by default; record.sh forces
  **v2**. annotate.py reads v2 only and prints the exact `asciinema convert` command
  if handed a v3 cast.
- **Idle vs compression**: `record.sh --idle` only caps idle in metadata at capture
  time; the real temporal compression (with skip frames) is annotate.py's job.
- **Find `at` timestamps** against the **original** cast, not the annotated one.
- **Offline shows**: run embed.sh once while online so the player assets vendor in;
  after that the deck plays with no network.
- **Banner width**: set `width` to match the recording's `--size` columns for a
  clean full-width bar.
- **Blank player pane = `file://` + WASM**: if an embedded asciinema player shows an
  empty box, the deck is almost certainly opened from disk (`file://`), where the v3
  WASM terminal emulator will not run. Fix = MP4 `<video>` embed (3c) or serve over
  http(s). Do NOT waste cycles trying more cast-inlining variants - they all fail the
  same way. Proven reference: `~/src/raft-l2-oracle/docs/hackathon-presentation.html`
  (a `<video>` deck that plays on double-click).
