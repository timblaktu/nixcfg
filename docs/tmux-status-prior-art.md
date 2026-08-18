# tmux command/process status indicator — prior-art research (Plan 050 T1)

Research date: 2026-08-17. Branch `feat/tmux-command-status-indicator`.
Method: four parallel research lanes (subagents), then synthesis; plus a second
round on **multi-pane scoping & aggregation** (see that section).
Local tmux at time of research: **3.6a**.

## Purpose

Before refactoring the ad-hoc per-window tmux "command running / done /
attention" indicator into a DRY, Nix-declarative abstraction (Plan 050), decide
per lane whether to **adopt** an existing standard/plugin or **keep** the custom
implementation — and derive the API shape that decision implies for T2.

## TL;DR — the verdict

**Re-scope state to the PANE, aggregate to the window with the native `#{P:}`
pane-loop, and lean on tmux-native mechanisms as far as they reach. Keep a thin
custom producer only for what tmux genuinely cannot derive (agent "attention",
and the running/done lifecycle on pre-3.8 tmux). Do not adopt an external
framework/plugin as the mechanism — borrow design *shapes*.**

The biggest finding from round two: **the current design is under-modeled.** It
stores state in a per-**window** user option (`@cmd_state`), so multiple panes
running independent commands in one window stomp a single shared value. Correct
granularity is **per-pane**, rendered into the one-entry-per-window status via a
native aggregation. tmux already provides the primitives for this; we were not
using them.

What tmux gives natively (no custom scripts):
- **Per-pane state** — pane user-options (`set -p @cmd_state X`, read as
  `#{@cmd_state}` inside a pane context) and, on **tmux 3.8**, per-pane OSC 133
  lifecycle vars (`#{pane_command_running}`, `#{pane_command_status}`).
- **Pane->window aggregation** — the `#{P:...}` pane-loop folds every pane of a
  window into its single `window-status-format` entry (priority pick:
  attention/error > running > idle). Pure native format expression, no `#()`.
- **Free coarse fallback** — `monitor-activity/bell/silence` auto-aggregate any
  pane's event into `window_{activity,bell,silence}_flag`, scoped by
  `*-action other` (excludes the pane you're viewing), styled by
  `window-status-activity-style`. Best native fit: **bell = attention**.

What still needs a custom producer (irreducible):
- **A true running/done lifecycle** — native flags only know "output happened,"
  not command start/exit. Needs OSC 133 (tmux >= 3.8, and the shell must emit it)
  or per-shell hooks (pre-3.8).
- **Agent "attention/needs-input"** (Claude Code waiting) — not a shell command
  lifecycle, so OSC 133 never covers it; a per-pane producer writes
  `set -p @cmd_state attention`, which folds through the *same* `#{P:}` expression.

Design consequence — **one aggregation expression, swappable per-pane source term:**
- `backend = "osc133"` (tmux >= 3.8): per-pane term = `#{pane_command_running}` /
  `#{pane_command_status}`. **Zero shell hooks, zero `#()`** for shell commands.
- `backend = "hooks"` (default; pre-3.8): per-pane term = `#{@cmd_state}`, written
  by a shared `tmux-cmd-state` helper from per-shell hooks.
- Agent-attention (either backend): OR'd in at top priority from `@cmd_state`.

Concrete adoptions worth pulling in:
- **Per-pane scoping + `#{P:}` priority-fold** as the core mechanism (this is the
  fix, and it is unsolved in the plugin ecosystem — see below).
- A **shared `tmux-cmd-state` helper** as the single writer (fixes the 4x dup),
  now writing a **pane** option, pane-addressed via `$TMUX_PANE`.
- Optional **out-of-focus alert leg** (bell / DCS-wrapped OSC to `#{pane_tty}`)
  borrowed from `claude-contrib/tmux-notify`; bell also doubles as the native
  `bell-action other` attention fallback.
- **Design the `backend` switch now** so adopting OSC 133 on tmux 3.8 is a
  source-term swap, not a rewrite.

---

## Lane 1 — tmux-native mechanisms + plugin ecosystem

### What exists
**Native (no shell hooks):** tmux tracks only output/timing-driven alert states,
none tied to command lifecycle:
- `monitor-activity` -> `window_activity_flag` (fires on *any* output),
  `monitor-bell` -> `window_bell_flag` (BEL), `monitor-silence <n>` ->
  `window_silence_flag`; styled via `window-status-activity-style` /
  `-bell-style`; `window-status-last-style` / `window_active`.
- Hooks `alert-activity|bell|silence`, scoped by `activity-action` etc.
- **Limit:** these mean "there was output / silence / a bell," NOT "a command
  started/finished." `pane-exited`/`pane-died` fire only when the pane's *program*
  exits (shell death), not per-command.

**`#{pane_current_command}` / `#{pane_current_path}`:** free, hookless
"shell-at-prompt vs running-a-program" snapshot; people branch
`window-status-format` on `#{==:#{pane_current_command},zsh}`.
- **Limit:** only the foreground process of (reliably) the active pane; a
  persistent "done, needs attention" state evaporates the instant the process
  exits; no multi-pane coverage. A snapshot of *what runs*, not a *lifecycle*.

**Plugins — no de-facto standard; most roll their own via preexec/precmd.**
- `tmux-agent-indicator` (accessd) — **closest prior art to our target.** Explicit
  per-pane state machine `running | needs-input | done | off`, hook-driven
  (Claude Code `UserPromptSubmit`->running, `PermissionRequest`->needs-input,
  `Stop`->done) with a process-detection fallback; drives pane border + window
  title + status icon; generic push API `agent-state.sh --agent X --state Y`.
  Opinionated toward AI agents, imperative shell + `@agent-indicator-*` options,
  not Nix-declarative.
- `chis.dev` recipe — hand-rolled `set-active|set-waiting|set-finished|…|clear`
  writing per-window `window-status[-current]-format`; `clear` uses
  `set-window-option -u` to fall back to global defaults. Essentially our custom
  approach, imperative.
- `tmux-notify` (rickstaa), `tmux-colortag`, `tmux-window-name` — notification /
  color-by-name / naming, respectively; none give running/done lifecycle.

**Useful substrate features:** user options `@name` (`set -wq`, read `#{@name}` /
`#{==:…}`), conditionals `#{?cond,a,b}`, hooks `after-select-window` etc.

### Links
- tmux(1): https://man.openbsd.org/tmux
- tmux-agent-indicator: https://github.com/accessd/tmux-agent-indicator ·
  https://morskov.com/blog/2026/04/19/tmux-agent-indicator-en
- tmux-notify: https://github.com/rickstaa/tmux-notify
- tmux-colortag: https://github.com/Determinant/tmux-colortag
- tmux-window-name: https://github.com/ofirgall/tmux-window-name
- chis.dev tab recipe: https://chis.dev/tmux-status
- pane_current_command idle: https://www.xn--tkuka-m3a3v.dev/zsh-and-tmux-config/
- awesome-tmux: https://github.com/rothgar/awesome-tmux

### Keep-vs-adopt: **KEEP (custom).**
No native mechanism or mainstream plugin cleanly represents a persistent
per-window command-lifecycle state. Native monitors are useful *supplements*
(silence-as-idle, bell-as-attention fallback), not a replacement.
`tmux-agent-indicator` validates our exact model but is an opinionated,
non-Nix external moving target — borrow its ideas (state enum, hook-push API,
multi-channel styling), don't depend on it.

### API implications
- Substrate confirmed: per-window user option `@<ns>_state` + `#{?}`/`#{==:}`
  branching inside one `window-status[-current]-format` template. Namespace the
  option (e.g. `@cmdstatus_state`) to coexist with themes.
- Model **channels** first-class (window-status / current / pane-border /
  window-title / icon) so one state can drive several.
- Writers are **push-based**: resolve target via `$TMUX_PANE -> #{window_id}` so
  a background producer marks the right window; `clear` via `set -u`.
- Keep native monitors available as an optional non-hook fallback source.

---

## Lane 2 — terminal shell-integration standards (OSC 133 et al.)

### What exists
- **OSC 133 (FinalTerm/FTCS, iTerm2):** `;A` prompt start, `;B` command input
  start, `;C` command output start, `;D[;exit]` command finished + exit code.
  Emitted by shells (bash/zsh/fish/PowerShell via integration scripts or prompt
  tools like starship/oh-my-posh); consumed by iTerm2, WezTerm, kitty, Ghostty,
  foot, VS Code (633 variant). Not Apple Terminal.
- **OSC 7** cwd — tmux supports it, exposed as `#{pane_path}`.
- **OSC 9;4** progress (ConEmu / Windows Terminal) — tmux *master* parses it
  (`input_osc_9`) for an internal progress bar; percent-based, not lifecycle.
- **OSC 9 / 777 / 99** desktop notifications — transient alerts, not state.

### The crux answer: can tmux give us command start/end/exit WITHOUT per-shell hooks?
**YES — but only in tmux 3.8 (unreleased at research time). NO on any shipped
tmux (incl. local 3.6a).** tmux master (targeting 3.8) parses OSC 133 A/B/C/D
itself (`input.c::input_osc_133`), stores per-pane lifecycle state, and exposes:

| Format var | Meaning |
|---|---|
| `#{pane_command_running}` | 1 while an OSC 133 command runs |
| `#{pane_command_status}` | exit status of most recent command |
| `#{pane_command_duration}` | duration (s) |
| `#{pane_command_start_time}` / `#{pane_command_end_time}` | timestamps |
| `#{pane_last_prompt_time}` | most recent prompt start |

Plus hooks `pane-command-started` / `pane-command-finished` /
`pane-shell-prompt` (payloads include exit status + timings), and a `set-hook -B`
flag to fire only when a format is true. Released 3.4–3.7 store OSC 133 marks
only for copy-mode `next-prompt`/`previous-prompt` — **no lifecycle format/hook.**

**Caveat:** OSC 133 still needs the *shell* to emit `;A/;C/;D`. That is itself a
(standardized, widely-shared) per-shell integration — many users already get it
free from starship/oh-my-posh/vendor scripts. So OSC 133 relocates and
standardizes the per-shell piece and moves the tmux-side plumbing into tmux; it
does not eliminate "something in the shell must emit state."

### Links
- tmux #3064: https://github.com/tmux/tmux/issues/3064 · #5237:
  https://github.com/tmux/tmux/issues/5237
- iTerm2 escape codes: https://iterm2.com/documentation-escape-codes.html
- OSC 133 refs: https://docs.otty.sh/vt/osc/osc-133 ·
  https://contour-terminal.org/vt-extensions/osc-133-shell-integration/
- WezTerm shell integration: https://wezterm.org/shell-integration.html

### Keep-vs-adopt: **KEEP now, DESIGN for adopt later.**
The OSC 133 backend is exactly what we want and much cleaner (tmux derives
running/done/exit-code for free; window-status just reads `#{pane_command_*}`),
but requires tmux ≥ 3.8 — unreleased, so adopting now means pinning a git build.

### API implications
- Add a backend switch `commandStatus.backend = "hooks" | "osc133"` (default
  `hooks`; `osc133` asserts tmux ≥ 3.8). On `osc133`, the tmux-side format reads
  native vars (running = `#{pane_command_running}`, attention/done from
  `#{pane_command_status}`), and the per-shell source becomes "emit OSC 133"
  (or delegate to the user's prompt tool) — no custom tmux pokes, no `@` var.
- Design the format layer against an abstract "state provider" so switching
  backends only swaps which `#{…}` variables it references.
- `allow-passthrough` is out of scope (it exports marks to the *outer* terminal;
  not needed to read `#{pane_command_*}` inside tmux).

---

## Lane 3 — cross-shell preexec + how tools signal state

### What exists
**The lifecycle triad:**
- zsh native `preexec` (gets command line) / `precmd`; register via
  `add-zsh-hook` (multiple handlers, no clobber).
- fish native `fish_preexec` / `fish_postexec` / `fish_prompt` (via `--on-event`).
- bash has only `DEBUG` trap + `PROMPT_COMMAND`; **bash-preexec** (rcaloras) is
  the de-facto shim (used by iTerm2, Ghostty, Bashhub), append to
  `preexec_functions` / `precmd_functions`. **Gotchas:** source it **last**;
  handlers must be **idempotent** (an extra DEBUG fires); subshell support off by
  default; detect via `${bash_preexec_imported:-}`. Packaged in nixpkgs
  (`bash-preexec`) — source `${pkgs.bash-preexec}/share/bash-preexec/bash-preexec.sh`.

**How tools signal state (three channels):**
1. **tmux `@` user-options** (`set -w @var`; read `#{@var}`) — in-server, no
   escape sequences / passthrough; best for persistent per-window/pane status.
   *This is what nixcfg already does.*
2. **Pane/window title** (OSC 2) — coarse, easily overwritten.
3. **Notification OSC** — fragmented (OSC 9 iTerm2, 777 urxvt/Ghostty/WezTerm,
   99 kitty). **tmux gotcha:** must `set -g allow-passthrough on` and DCS-wrap
   (`\033Ptmux;…\033\\`) AND write to `#{pane_tty}` (a background hook's stdout
   never reaches the terminal). Simplest reliable alert: `\a` -> `#{pane_tty}`
   with `bell-action any`.

**Claude Code / opencode -> tmux (directly relevant):**
- `claude-contrib/tmux-notify` — community near-standard. Uses `Stop` (done) +
  `Notification` filtered to `permission_prompt`/`elicitation_dialog` (attention);
  three **pane-scoped** mechanisms via `@`-vars: bell to `#{pane_tty}` (default),
  `display-message` when inactive, auto-focus. Deliberately pane-scoped so
  **multiple Claude instances don't collide** — argues shared status widgets
  break with multiple instances.
- Many blog integrations converge on the same recipe (Notification+Stop, write to
  `/dev/tty`/`#{pane_tty}`, be focus-aware, DCS-wrap inside tmux). Upstream FR to
  make it native: anthropics/claude-code #19976.
- **nixcfg already exceeds the consensus** (adds a `running` state via
  `UserPromptSubmit`, active-window suppression). The one thing to borrow: an
  actual out-of-focus **alert** leg.
- opencode: no tmux `@`-var convention found worth adopting (surfaces state via
  its own TUI/desktop app).

**Notify daemons:** no single de-facto tool. `rickstaa/tmux-notify` (tmux-level,
shell-agnostic, for processes you didn't launch via a hook); `undistract-me`
(abandoned), `zsh-notify`, `longtroll` (shell-level, consumers of the triad);
`noti` (maintained cross-platform sender, in nixpkgs).

### Links
- bash-preexec: https://github.com/rcaloras/bash-preexec
- claude-contrib tmux-notify:
  https://github.com/claude-contrib/claude-extensions/blob/main/plugins/tmux-notify/README.md
- claude-code FR: https://github.com/anthropics/claude-code/issues/19976
- codex tmux-aware OSC 9: https://github.com/openai/codex/pull/17836
- noti: https://github.com/variadico/noti · rickstaa/tmux-notify:
  https://github.com/rickstaa/tmux-notify

### Keep-vs-adopt: **KEEP custom `@cmd_state`; ADOPT bash-preexec for bash; ADOPT an alert leg.**
- Do NOT hand-roll a bash DEBUG trap — use bash-preexec (source last,
  idempotent handlers). zsh/fish stay native.
- Keep CC `@cmd_state` hooks (already match + exceed consensus). Add an
  out-of-focus alert (`\a`/DCS-wrapped OSC to `#{pane_tty}`) and keep
  **pane-scoping** (`$TMUX_PANE`) so concurrent agents don't stomp.
- Don't vendor undistract-me/tmux-notify; optionally expose `noti`.

### API implications
- Two source kinds: **`shellLifecycle`** (normalized preCommand/postCommand/
  prePrompt per shell; dispatch zsh add-zsh-hook / fish --on-event / bash
  bash-preexec) and **`programEvent`** (program lifecycle hook -> state enum;
  CC already `UserPromptSubmit->running`, `Notification->attention`,
  `Stop->done`).
- A shared **sink** consuming `(scope, state)` and picking channel(s): `tmux-var`
  (default), `title`, `bell`, `osc-notify`. Channel choice data-driven per state.
- **Scope must be pane-addressable** (`$TMUX_PANE`/`#{pane_id}`), not window-
  global, for multi-agent safety; suppress alerts when target already active.
- Encode invariants once: no-op when `$TMUX` unset; use the pane's own `tmux`;
  write escape channels to `#{pane_tty}`; DCS-wrap only inside tmux; keep hook
  commands non-blocking / short-timeout.

---

## Lane 4 — Nix / home-manager ecosystem

### What exists
- **home-manager `programs.tmux`:** plugins are `listOf (either package
  submodule{plugin, extraConfig})`, rendered by **folding**
  (`concatMapStringsSep`) into `tmux.conf`; final conf = `mkMerge [ mkBefore
  base; mkAfter extraConfig; plugins ]`. **No status-bar / segment abstraction
  exists** — everything status is hand-written in `extraConfig`. The idiomatic
  attrset->config seam is `mapAttrsToList (n: v: "set -g ${n} ${v}") |>
  concatStringsSep "\n"`, mirroring HM's own plugin fold.
- **catppuccin/nix `catppuccin.tmux`:** only `enable`/`flavor`/`extraConfig`;
  the real segment model lives in the **tmux plugin's runtime** var system
  (`#{E:@catppuccin_status_MODULE}` compose-by-reference), NOT in Nix. This
  "named unit -> generated style variable" is the only reusable *shape*, and it
  targets left/right **segments**, not per-window states.
- **gitmux / tmux-powerline:** external `#()` generators; no declarative Nix
  wrapper. (nixcfg deliberately avoids `#()` for state styling — its output is
  cached on tmux's async cycle and won't reliably revert; see `tmux.nix`.)
- **Cross-module wiring — nixcfg already does it, loosely.** tmux module defines
  `commandStatus.{enable,style}`, presets, the `#{?}` conditional, clear-on-
  select, shell hooks writing `@cmd_state`; claude-code module independently
  writes the **same** `@cmd_state` values from CC hooks. The seam today is a
  **loose shared string protocol** over `@cmd_state` — both modules hardcode
  state names and the set/clear/refresh commands (exactly the T3/T5 dup). No
  existing pattern where one module reads the other's option values. Shared libs
  live at `modules/lib/shared/` — the established home for a shared attrset/fn;
  nothing tmux-related there yet.

**Bottom line:** no Nix module models per-window command lifecycle states with
style + clear behavior. Build our own; borrow catppuccin's *shape*.

### Links
- catppuccin/nix tmux options: https://nix.catppuccin.com/options/main/home/catppuccin.tmux/
- catppuccin/tmux custom status (`#{E:@..._status_MODULE}`):
  https://github.com/catppuccin/tmux/blob/main/docs/tutorials/02-custom-status.md
- HM tmux.nix: https://github.com/nix-community/home-manager/blob/master/modules/programs/tmux.nix
- Local: `modules/programs/tmux/tmux.nix`,
  `modules/programs/claude-code/_hm/hooks.nix`, `modules/lib/shared/`

### Keep-vs-adopt: **BUILD our own on `extraConfig` + a shared lib.**
No Nix status framework to adopt; catppuccin/powerline/gitmux give segments, not
per-window state, and `#()` reintroduces the revert bug. Adopt the *shape*
(named unit -> generated variable), applied to **states**.

### API implications (proposed shape — feeds T2)
- **`states`** attrset (name -> {style, clearOnView, priority[, channels]}).
  Generate the `#{?}` chain and the clear predicate by folding over states
  sorted by priority — kills the hardcoded `done`/`attention` literals. Keep the
  existing `style` preset enum as a *palette* filling per-state defaults.
- **`sources`** attrset: generic `shell.enable` + per-program `event -> state`
  maps (CC: `UserPromptSubmit=running; Notification=attention; Stop=done`).
- **Single writer:** one installed `tmux-cmd-state <state>` helper
  (`writeShellApplication`) encapsulating pane resolution + active-window
  suppression + `set -w` / `set -uw` / `refresh-client -S`. Every consumer
  (zsh/bash/fish + CC `writeShellScript`) calls it — the concrete T3 fix.
- **Cross-module seam (ranked):**
  1. **Shared lib in `modules/lib/tmux-cmd-state.nix` (recommended):** exports the
     canonical state-name set, the `tmux-cmd-state` helper derivation, and a
     `mkSourceHooks` fn. Both modules import it; neither reads the other's
     `config` (no eval-ordering fragility). State-name protocol becomes a Nix
     value, not a duplicated literal.
  2. Read-the-option: CC reads `config.programs.tmux.commandStatus.states` to
     validate its map + reuse the binary (couples CC to tmux being evaluated).
  3. Register-into: tmux exposes a mergeable `sources` attrset; CC does
     `programs.tmux.commandStatus.sources.claude-code = {…}` (most declarative,
     but inverts current ownership).
  - Recommendation: **option 1 foundation**, optionally layered with option 3's
    mergeable `sources` if T5/T6 want programs to register declaratively.

---

## Multi-pane scoping & aggregation (round-two research — the crux)

A window commonly holds **many panes, each running independent commands.** The
status bar renders **one entry per window**. So the real problem is: (a) hold
state at pane granularity, and (b) reduce N panes into one window indicator.

### The current design is under-modeled
`@cmd_state` is a per-**window** user option. Two panes running different commands
in the same window write the same option and stomp each other — the window entry
reflects whichever pane's hook fired last. Correct granularity is **per-pane**.

### tmux has the primitives (verified against 3.6a man + 3.8 master)
- **Per-pane state:** pane user-options — `set -p @cmd_state X`, and inside a pane
  context a bare `#{@cmd_state}` resolves to *that pane's* value. On **tmux 3.8**,
  per-pane OSC 133 vars `#{pane_command_running}` (always `0`/`1`) and
  `#{pane_command_status}` (empty until first command completes; then the exit
  code). Also useful natively: `pane_active`, `pane_dead`, `pane_dead_status`,
  `pane_pid`, `pane_in_mode`, `pane_current_command`.
- **Pane->window aggregation:** the `#{P:...}` pane-loop expands its body once per
  pane of the window and concatenates. So a per-pane test that emits a sentinel
  char yields a non-empty string iff **any** pane matched — that is the "any pane
  is X" reduction. `window-status-format` is itself the body of an implicit
  `#{W:...}` loop, and `#{P:}` nested inside loops *that* window's panes.
- **No window-level OSC 133 aggregate exists.** There is no
  `#{window_command_running}`. The only native window aggregates are the monitor
  flags (`window_{activity,bell,silence}_flag`). So the `#{P:}` fold is mandatory
  for command lifecycle.

### The one aggregation expression (priority fold)
Priority **attention/error > running > idle**, folded across panes. Use the
**single-arg** `#{P:...}` (the two-arg form special-cases the active pane, which
we do *not* want for an "any pane" reduction):

```tmux
# error fold: emit "!" per pane whose OSC133 status is SET and != 0
#   (guard with && because pane_command_status is empty until first ;D)
#{?#{!=:#{P:#{?#{&&:#{pane_command_status},#{!=:#{pane_command_status},0}},!,}},},  #[fg=red]ERR,
  #{?#{!=:#{P:#{?#{pane_command_running},*,}},},              #[fg=yellow]RUN,
    #[fg=green]IDLE}}
```

Gotchas (verified): `pane_command_running` is `0`/`1` so it is safe in `#{?}`;
`pane_command_status` is **empty until the first command finishes** and can
legitimately be `0` (success), so test error as *"set AND != 0"* via `#{&&:}`;
keep sentinels to single safe chars (`!`, `*`), no commas/braces; use the
comma-less `#{P:}` for folds. Agent "attention" adds one arm above ERR:
`#{?#{!=:#{P:#{?#{==:#{@cmd_state},attention},A,}},},#[fg=magenta]ATTN, ...}`.

### Both backends share this ONE expression — only the per-pane term differs
- **osc133** (tmux >= 3.8): term = `#{pane_command_running}` / `#{pane_command_status}`
  — tmux derives running/done/exit from OSC 133 in-process. **Zero shell hooks,
  zero `#()`** for shell commands; the shell need only *emit* OSC 133 (often
  already provided by starship/oh-my-posh/vendor integration).
- **hooks** (default; pre-3.8): term = `#{@cmd_state}`, written per-pane by the
  shared `tmux-cmd-state` helper from per-shell hooks.
- **agent-attention** (either backend): term = `#{@cmd_state} == attention`, written
  per-pane by the CC producer, OR'd in at top priority.

### Free coarse fallback (zero producer)
`monitor-bell` + `bell-action other` + `window-status-bell-style` gives a
window-level "a background pane rang BEL" — the best native "attention" signal if
any producer emits `\a` (which the alert leg does anyway). `monitor-activity` +
`activity-action other` gives "a background pane produced output." These are
window-scoped, single-bit, clear-on-view, and cannot express running/done or
per-pane identity — useful as an optional degrade-gracefully layer, not the model.

### Ecosystem status: multi-pane aggregation is UNSOLVED
Re-examined against the plugins: `tmux-agent-indicator` does per-pane *borders*
but its window-title/status channel is last-writer-wins (assumes one agent per
window); `chis.dev` resolves `$TMUX_PANE -> #{window_id}` and rewrites the whole
tab (last writer wins, one command per window); `tmux-notify` is per-pane one-shot
notification, never a window rollup. **None uses `#{P:}` to aggregate N panes into
one window entry.** Borrowable prior art is narrow (agent-indicator's `--state`
push API shape and per-pane border channel); the reduction policy is ours to
define. This is the design's genuine novel contribution.

---

## Proposed API direction (input to T2 — for sign-off)

Synthesizing all four lanes, the recommended straw-man for T2:

```nix
programs.tmux.commandStatus = {
  enable  = true;
  backend = "hooks";          # "hooks" (default) | "osc133" (asserts tmux >= 3.8)
  style   = "background";     # palette preset -> fills states.*.style defaults

  # STATE IS PER-PANE. states are declared once; the #{P:} priority-fold that
  # aggregates panes into each window entry, plus the clear predicate, are generated.
  states = {                  # priority: higher wins the window entry when panes differ
    attention = { style = "bg=colour201 fg=colour16 bold blink"; clearOnView = true;  priority = 30; };
    error     = { style = "bg=colour196 fg=colour16 bold";       clearOnView = true;  priority = 25; };
    running   = { style = "bg=colour214 fg=colour16 bold";       clearOnView = false; priority = 20; };
    done      = { style = "bg=colour34  fg=colour16 bold";       clearOnView = true;  priority = 10; };
  };

  channels = {                # a state can drive several channels (see agent-indicator)
    windowStatus = true;      # the #{P:}-aggregated per-window entry
    paneBorder   = false;     # optional per-pane border (no aggregation needed)
  };

  sources = {
    shell.enable = true;      # per-PANE lifecycle: zsh add-zsh-hook / fish --on-event /
                              # bash via nixpkgs bash-preexec (sourced last, idempotent).
                              # On backend="osc133" this collapses to "emit OSC 133".
    claude-code = {           # contributed by the CC module via the shared lib
      UserPromptSubmit = "running";
      Notification     = "attention";
      Stop             = "done";
    };
    # nvim = {...}; opencode = {...}; build-watcher = {...};   # T6 extensibility proof
  };

  monitorFallback.enable = false;  # optional zero-producer coarse layer:
                                   # bell-action other -> attention, activity-action other

  alert = {                   # optional out-of-focus leg (borrowed from claude-contrib)
    enable = false;
    channel = "bell";         # "bell" (\a -> #{pane_tty}) | "osc-notify" (DCS-wrapped)
    onStates = [ "attention" ];
  };
};
```

Implementation principles:
- **State is per-pane.** The single writer sets a **pane** option
  (`tmux set -p -t $TMUX_PANE @cmd_state <state>`); on `osc133` the shell-command
  states come from native `#{pane_command_*}` instead. Never a window option.
- **One writer:** `tmux-cmd-state <state>` (shared lib helper) is the single place
  that sets/clears the pane's `@cmd_state`; pane-addressed via `$TMUX_PANE`; no-op
  when `$TMUX` unset; active-pane/active-window suppression centralized.
- **One generated aggregation expression:** fold `states` (by `priority`) into a
  single `#{P:}`-based priority pick for `window-status-format` (and the clear
  predicate from `filter clearOnView`). Both backends reuse it; only the per-pane
  *source term* differs (`@cmd_state` vs `#{pane_command_running}`/`_status`).
- **Backend abstraction:** the format layer reads from a per-pane state provider;
  swapping `hooks`<->`osc133` changes only the source term, not the API.
- **Shared lib seam** (`modules/lib/tmux-cmd-state.nix`): canonical state-name set
  + helper derivation + `mkSourceHooks` + the `#{P:}` fold generator; imported by
  both tmux and claude-code modules; no cross-`config` reads.

### Behavior-parity checklist to preserve through T3-T6
- Native `#{?}`/`#{P:}` styling re-evaluated every redraw (no `#()` for state style).
- `running` on command/prompt start; `done`/`error` on finish; per-shell "ran"
  guard prevents startup / bare-Enter marking.
- Active pane/window never shows a stale `done`/`attention`; navigate-to clears
  `clearOnView` states (`after-select-window` + next/previous/last-window binds).
  NOTE: with per-pane state, "clear on view" must clear the viewed **pane's**
  state (or all panes' on window select) — revisit the exact semantics in T2.
- CC lifecycle: `UserPromptSubmit->running`, `Notification->attention`,
  `Stop->done`; done/attention suppressed on the active pane.
- **Multi-pane correctness (new):** two panes with different states in one window
  resolve by `priority`, not last-writer; verify with a 3-pane window where one
  runs, one errors, one idles -> window shows the highest-priority state.
