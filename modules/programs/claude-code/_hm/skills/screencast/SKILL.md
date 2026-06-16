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
record.sh demo.cast --title "Consume packages from converix-validated" --size 100x30

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
label = "Consume 15 packages from converix-validated"
```

What it produces: a boxed blue title card at each `at`, a dim `⏩ skipped Nm Ns`
frame at every collapsed gap, and an asciicast `m` marker per step for the scrubber.

### 3a. Embed in an HTML deck (`scripts/embed.sh`) - primary target

```bash
embed.sh demo.annotated.cast docs/hsw-showcase.html consume-packages --cols 100 --rows 30
```

Copies the cast to `<deckdir>/hsw-demo-assets/<name>.cast`, vendors a pinned
asciinema-player (offline-capable) into `hsw-demo-assets/asciinema-player/`, and
replaces the placeholder `<!-- SCREENCAST:<name> -->` in the deck with the player
markup. If the placeholder is absent it prints the markup to paste. The deck stays
one portable HTML file + a sibling assets dir - no network at show time.

### 3b. Export GIF / MP4 (fallback)

```bash
# GIF (markers are player-only; a GIF is linear). agg needs an explicit monospace
# font family - "Cascadia Mono" ships in the home profile:
agg --font-family "Cascadia Mono" --theme monokai demo.annotated.cast demo.gif

# Trim by injected markers, then GIF:
agg --font-family "Cascadia Mono" --select marker:0..marker:2 demo.annotated.cast clip.gif

# MP4 via the GIF (when you need a real video file):
ffmpeg -i demo.gif -movflags +faststart -pix_fmt yuv420p demo.mp4
```

> agg resolves fonts through fontconfig. If it errors with "no faces matching font
> family options", pass `--font-family "Cascadia Mono"` (or any installed monospace).

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
