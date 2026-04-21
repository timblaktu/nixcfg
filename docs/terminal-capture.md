# Terminal Capture Toolkit

Headless-compatible tools for recording and screenshotting terminal sessions.
No WSLg/X11 required -- works purely with terminal I/O.

**Packages**: `asciinema_3`, `asciinema-agg`, `termshot`, `svg-term`
**Location**: `modules/system/types/3-cli/cli.nix` (home-cli cliPackages)

## Quick Reference

| Want | Tool | Output |
|------|------|--------|
| Static screenshot | `termshot` | PNG |
| Record a session | `asciinema` | .cast |
| Recording to GIF | `agg` | GIF |
| Recording to SVG | `svg-term` | SVG |

## Static Screenshots (PNG)

```bash
# Capture output of a command directly
termshot -- htop
termshot -- cat /etc/os-release
termshot -- git log --oneline -20

# Specify output path
termshot -f /tmp/my-screenshot.png -- ls -la

# Capture current tmux pane content
tmux capture-pane -p -e -t . | termshot -f /tmp/pane.png
```

## Recording Sessions (.cast)

```bash
# Start recording (Ctrl-D or 'exit' to stop)
asciinema rec demo.cast

# Record with a title
asciinema rec -t "My Demo" demo.cast

# Record with idle time limit (cap pauses to 2s)
asciinema rec -i 2 demo.cast

# Play back a recording in terminal
asciinema play demo.cast
```

## Convert to GIF

```bash
# Basic conversion
agg demo.cast demo.gif

# With a theme
agg --theme monokai demo.cast demo.gif
agg --theme solarized-dark demo.cast demo.gif

# Custom font size
agg --font-size 14 demo.cast demo.gif

# Speed up 2x
agg --speed 2 demo.cast demo.gif
```

## Convert to Animated SVG

SVGs are razor-sharp at any zoom, tiny file size, and render natively in
browsers and GitHub READMEs.

```bash
# Basic conversion
svg-term --in demo.cast --out demo.svg

# With window chrome
svg-term --in demo.cast --out demo.svg --window

# Custom dimensions
svg-term --in demo.cast --out demo.svg --width 80 --height 24
```

## Typical Workflows

### Quick screenshot for Slack/Teams

```bash
termshot -f /tmp/shot.png -- <command>
# Then drag-and-drop the PNG
```

### Demo recording for a PR or doc

```bash
asciinema rec -i 2 -t "Feature Demo" demo.cast
agg --theme monokai demo.cast demo.gif          # GIF for Slack/email
svg-term --in demo.cast --out demo.svg --window  # SVG for GitHub/docs
```

### Capture full tmux layout

Set up your tmux panes/windows as desired, then record:

```bash
# From inside tmux, this records everything you see
asciinema rec -i 2 tmux-session.cast
# Navigate panes, run commands, then exit
```

### Dump terminal buffer as text (no extra tools needed)

```bash
# Current pane
tmux capture-pane -p > buffer.txt

# With ANSI colors preserved
tmux capture-pane -p -e > buffer-ansi.txt

# Full scrollback history
tmux capture-pane -p -S - > full-history.txt
```
