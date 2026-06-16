#!/usr/bin/env python3
"""annotate.py - post-process an asciicast-v2 recording for standalone (no-audio) playback.

Three transforms, all driven from the source .cast plus a tiny sidecar:

  1. Temporal compression - any idle/build gap longer than `gap_threshold` seconds
     is collapsed to `skip_dwell`, and an honest "skipped Nm Ns" frame is spliced
     in at the cut. This is the "jump forward in time" the recording needs so a
     5-minute build does not bore the audience.

  2. Title cards - at each step boundary a boxed banner is injected, dwelling
     `card_dwell` seconds, so a viewer follows the demo with zero narration.

  3. Chapter markers - an asciicast "m" event is emitted at each step boundary.
     asciinema-player renders these on the scrubber; `agg --select marker:a..b`
     can also cut the export by them.

The source .cast is never mutated; output is a fresh v2 file.

Usage:
  annotate.py INPUT.cast [STEPS.(toml|json)] [-o OUTPUT.cast]
              [--gap SECS] [--skip-dwell SECS] [--card-dwell SECS] [--width COLS]

Sidecar schema (TOML shown; JSON with the same keys also works):

    gap_threshold = 8.0     # collapse idle longer than this (seconds)
    skip_dwell    = 1.2     # replacement dwell for a collapsed gap
    card_dwell    = 2.5     # how long a title card stays on screen
    width         = 72      # banner width in columns

    [[step]]
    at    = 0.0             # ORIGINAL recording timestamp (seconds) to insert at
    label = "List all 16 image variants"

    [[step]]
    at    = 42.0
    label = "Consume 15 packages from converix-validated"

CLI flags override sidecar values; sidecar values override the built-in defaults.
With no sidecar, only gap compression runs (using defaults / CLI flags).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# ---- ANSI title-card / skip-frame rendering -------------------------------------------------

RESET = "[0m"
CARD = "[1;97;44m"   # bold white on blue
SKIP = "[2;37m"      # dim grey


def banner(label: str, width: int) -> str:
    """A boxed title card as one output frame (CR/LF separated, blank-line padded)."""
    text = f" ▸ {label} "          # ▸ label
    bar = text.ljust(width)
    return f"\r\n{CARD}{bar}{RESET}\r\n\r\n"


def skip_frame(seconds: float, width: int) -> str:
    m, s = divmod(int(round(seconds)), 60)
    human = f"{m}m{s:02d}s" if m else f"{s}s"
    text = f" ⏩ skipped {human} of output ".ljust(width)
    return f"\r\n{SKIP}{text}{RESET}\r\n"


# ---- cast IO --------------------------------------------------------------------------------

def load_cast(path: Path):
    lines = path.read_text().splitlines()
    if not lines:
        sys.exit(f"annotate.py: empty cast file: {path}")
    header = json.loads(lines[0])
    version = header.get("version")
    if version == 3:
        sys.exit(
            "annotate.py: input is asciicast-v3; convert to v2 first:\n"
            f"  asciinema convert -f asciicast-v2 {path} {path.with_suffix('.v2.cast')}\n"
            "(record.sh already writes v2; this only happens for externally-made casts.)"
        )
    if version != 2:
        sys.exit(f"annotate.py: unsupported asciicast version {version!r} (expected 2)")
    events = []  # (abs_time, code, data)
    for ln in lines[1:]:
        ln = ln.strip()
        if not ln:
            continue
        t, code, data = json.loads(ln)
        events.append((float(t), code, data))
    return header, events


def load_steps(path: Path | None, args) -> dict:
    cfg = {"gap_threshold": 8.0, "skip_dwell": 1.2, "card_dwell": 2.5, "width": 72, "step": []}
    if path is not None:
        raw = path.read_text()
        if path.suffix == ".json":
            data = json.loads(raw)
        else:
            try:
                import tomllib
            except ModuleNotFoundError:
                sys.exit("annotate.py: TOML sidecar needs Python 3.11+ (tomllib); use a .json sidecar instead")
            data = tomllib.loads(raw)
        cfg.update({k: v for k, v in data.items() if k != "step"})
        cfg["step"] = data.get("step", data.get("steps", []))
    # CLI overrides
    if args.gap is not None:
        cfg["gap_threshold"] = args.gap
    if args.skip_dwell is not None:
        cfg["skip_dwell"] = args.skip_dwell
    if args.card_dwell is not None:
        cfg["card_dwell"] = args.card_dwell
    if args.width is not None:
        cfg["width"] = args.width
    return cfg


# ---- transform ------------------------------------------------------------------------------

def transform(events, cfg):
    """Walk events in interval form, injecting cards/markers and collapsing gaps.

    Returns a new list of (interval, code, data); caller re-accumulates to absolute.
    """
    steps = sorted(cfg["step"], key=lambda s: s["at"])
    gap = cfg["gap_threshold"]
    skip_dwell = cfg["skip_dwell"]
    card_dwell = cfg["card_dwell"]
    width = cfg["width"]

    out = []  # [interval, code, data]
    prev_abs = 0.0
    si = 0

    for abs_t, code, data in events:
        interval = abs_t - prev_abs
        card_here = False

        # Inject any step boundaries we cross on the way to this event.
        while si < len(steps) and steps[si]["at"] <= abs_t:
            label = steps[si]["label"]
            lead = min(interval, 0.4)          # tiny lead-in before the card
            out.append([lead, "m", label])      # marker on the scrubber
            out.append([0.0, "o", banner(label, width)])
            interval = card_dwell               # banner dwells before real output
            card_here = True
            si += 1

        # Collapse long idle/build gaps (skip the compression if we just showed a card).
        if not card_here and interval > gap:
            out.append([min(skip_dwell * 0.4, interval), "o", skip_frame(interval, width)])
            interval = skip_dwell

        out.append([interval, code, data])
        prev_abs = abs_t

    # Any trailing steps past the last event (e.g. a closing card).
    while si < len(steps):
        out.append([0.4, "m", steps[si]["label"]])
        out.append([0.0, "o", banner(steps[si]["label"], width)])
        out.append([card_dwell, "o", ""])
        si += 1

    return out


def main():
    ap = argparse.ArgumentParser(description="Annotate + compress an asciicast-v2 recording.")
    ap.add_argument("input", type=Path)
    ap.add_argument("steps", type=Path, nargs="?", default=None)
    ap.add_argument("-o", "--output", type=Path, default=None)
    ap.add_argument("--gap", type=float, default=None)
    ap.add_argument("--skip-dwell", type=float, default=None)
    ap.add_argument("--card-dwell", type=float, default=None)
    ap.add_argument("--width", type=int, default=None)
    args = ap.parse_args()

    header, events = load_cast(args.input)
    cfg = load_steps(args.steps, args)
    new_intervals = transform(events, cfg)

    # Re-accumulate intervals to absolute timestamps.
    out_events = []
    t = 0.0
    for interval, code, data in new_intervals:
        t += max(0.0, interval)
        out_events.append([round(t, 6), code, data])

    out_header = dict(header)
    out_header["version"] = 2
    out_header.pop("idle_time_limit", None)  # compression is now baked in

    out_path = args.output or args.input.with_suffix(".annotated.cast")
    with out_path.open("w") as fh:
        fh.write(json.dumps(out_header) + "\n")
        for ev in out_events:
            fh.write(json.dumps(ev) + "\n")

    n_cards = len(cfg["step"])
    print(f"annotate.py: wrote {out_path} ({len(out_events)} events, {n_cards} title cards, "
          f"gap>{cfg['gap_threshold']}s collapsed)", file=sys.stderr)


if __name__ == "__main__":
    main()
