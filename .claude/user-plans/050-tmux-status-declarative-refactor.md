# Plan 050 — Declarative, DRY tmux command/process status bar

Status: IMPLEMENTATION (Phase 1 = LOCAL; research + design signed off)
Working branch: `feat/tmux-command-status-indicator`
Owner: Tim
Created: 2026-08-17

## Goal

Refactor the per-window tmux command/process status indicator (built ad hoc over
this session) into a **single DRY, Nix-declarative abstraction**: I should be
able to declare in Nix *which programs* feed the tmux status bar and *how each
state is styled*, and have the shell hooks, per-program hooks, tmux format
conditional, and navigate-to clear all be **generated** from that one
declaration. BUT: research upstream / community prior art FIRST (Task 1) so we
adopt an existing standard/plugin where possible instead of inventing more.

## Current state (what exists as of 2026-08-17)

All on branch `feat/tmux-command-status-indicator`. `9f44a7c` is pushed to
`origin`; the following are **committed but NOT pushed** (deployed live only via a
local `path:` override — a plain `home-manager switch` on nixcfg-work would
revert them):

- `9f44a7c` add per-window command-running/complete indicators (initial)
- `79dc572` drop the running-state marker char
- `8d88bc3` add `dev-switch` (flake app: local `--override-input` dev loop)
- `9596030` redesign: running/done, **native `#{?}` styling** (fixed a
  "never reverts" bug caused by styling emitted from a cached `#()` job)
- `aa2a57a` selectable styles via `programs.tmux.commandStatus.style`
- `eea6067` don't mark the ACTIVE window done on completion (active-aware)
- `8ba3045` Claude Code lifecycle -> window states (adds `attention` state)

**How it currently works (the mechanism to preserve behaviorally):**
- Per-window tmux user option `@cmd_state` in {`running`,`attention`,`done`,unset}.
- Native `#{?}` conditional in `window-status-format` / `-current-format` maps
  state -> `#[...]` style (re-evaluated every redraw; the `#()` script
  `tmux-window-status-format` is pure index+name only).
- `after-select-window` hook + `next/previous/last-window` bind appends clear
  `done`/`attention` when a window is navigated to.
- Shell hooks (zsh preexec/precmd, bash DEBUG+PROMPT_COMMAND, fish
  preexec/postexec) set `running` on start, and on completion set `done`
  (background window) or clear (active window). A per-shell "ran" guard prevents
  startup/bare-Enter marking.
- Claude Code hooks (`programs.claude-code.hooks.tmuxStatus`, default on) set
  state from CC events via a `writeShellScript` helper: `UserPromptSubmit`->
  running, `Notification`->attention, `Stop`->done; done/attention suppressed on
  the active window.
- `dev-switch` (pkgs/dev-switch) is the iteration tool: `nix run '.#dev-switch'
  -- -d -o nixcfg=~/src/nixcfg ~/src/nixcfg-work` deploys local edits with no
  push/relock.

**Files:**
- `modules/programs/tmux/tmux.nix` — option `programs.tmux.commandStatus.{enable,style}`,
  `cmdStateStyles` presets, `cmdStateStyle` conditional, `cmdStateClearOnSelect`,
  `windowStatusFormat`, the three shell-hook blocks.
- `modules/programs/tmux/files/tmux-window-status-format` — pure index+name script.
- `modules/programs/claude-code/_hm/hooks.nix` — `hooks.tmuxStatus` option,
  `tmuxStateScript` helper, `tmuxStatusHooks` set (merged via `mergeHookSets`).
- `pkgs/dev-switch/default.nix` — the dev-loop tool.

## DRY / design problems to fix (Task 3 target)

1. **The "active-aware set `@cmd_state`" logic is written 4x**: zsh precmd, bash
   postcmd, fish postexec, AND the CC `tmuxStateScript`. Should be ONE shared
   installed helper (e.g. `tmux-cmd-state <state>`) that every consumer calls.
2. **State names are string-literals duplicated** across shell hooks, CC hooks,
   and the tmux `#{?}` conditional + clear command. Adding/renaming a state
   touches many places.
3. **State->style mapping and the format conditional are hand-written**; adding a
   state means hand-editing the nested `#{?}` and the clear predicate. These
   should be GENERATED from a declared state set (name, style-per-preset,
   `clearOnView` bool, priority).
4. **No single place to declare a program integration.** Wiring a new program
   (opencode, nvim, a build watcher) means hand-writing hooks again. Want a
   declarative `sources`/`integrations` describing event->state mappings.

## Declarative vision (Task 2 will finalize the API after research)

Straw-man (subject to research + sign-off):

```nix
programs.tmux.commandStatus = {
  enable = true;
  style = "background";              # existing preset selector, or per-state styles
  states = {                         # declared once; format + clear generated
    running   = { style.background = "bg=colour214 fg=colour16 bold"; clearOnView = false; };
    attention = { style.background = "bg=colour201 fg=colour16 bold blink"; clearOnView = true; };
    done      = { style.background = "bg=colour34 fg=colour16 bold"; clearOnView = true; };
  };
  sources = {
    shell.enable = true;             # generic preexec/precmd lifecycle (all shells)
    claude-code = {                  # wired from the CC module
      running   = "UserPromptSubmit";
      attention = "Notification";
      done      = "Stop";
    };
    # nvim = {...}; opencode = {...}; build-watcher = {...};
  };
};
```
One shared `tmux-cmd-state` helper is the single writer; the tmux conditional and
the clear predicate are generated by folding over `states`; each `source`
generates its hooks. Cross-module seam: the CC module consumes the tmux module's
declared states/helper (or a shared lib in `modules/lib/`).

## Scope & phasing (revised 2026-08-17, Tim's direction)

Priority is **getting the per-pane indicator working LOCALLY first; upstream work is
LAST and gated.** Full implementation scope is KEPT (Tim chose "keep full scope" —
no features cut); only the SEQUENCING changed: all local implementation (T3-T6)
precedes any upstream action (T8).

- **Phase 1 — LOCAL (T3-T6), full scope, do now.** Implement the signed-off T2
  design end-to-end: per-pane state via one shared `tmux-cmd-state` helper (T3),
  generated `#{P:}` fold + clear predicate from declared `states` (T4), the
  `sources` model with CC re-wired (T5), and the nvim extensibility proof (T6).
  Deploy via `dev-switch -d`; push + relock nixcfg-work for durability.
- **Phase 2 — UPSTREAM (T8), deferred + gated.** Only after Phase 1 is COMPLETE
  AND tmux 3.8 has shipped: draft the GitHub issue + `format.c` patch per the T7
  CONDITIONAL GO. Do NOT start T8 before BOTH conditions hold.

Rationale: T7 confirmed the upstream kernel (native `#{window_command_running}`) is
small, gated on unreleased tmux 3.8, and best proposed as a follow-up to the shipped
3.8 pane-level work — so it must not block local value. See
`docs/tmux-upstream-contribution-assessment.md`.

### Phase-1 exit → MERGE TO MAIN, then shelve (Tim's direction 2026-08-17)
At the Phase-1 stopping point (**after T6**; T8 is Phase-2 upstream and is BLOCKED on
tmux 3.8 anyway), **shelve this plan and merge the tested `feat/tmux-command-status-
indicator` branch into `main`**, so Tim's in-flight **MacBook / nix-darwin
(nix-darwin) bring-up** branches can build on the tested tmux work off a shared base.
T8 stays deferred (unchanged — it was always going to wait for tmux 3.8). Before the
merge: (a) finish T5+T6; (b) run the owed interactive verification (window-pane-changed
clear is proven; the focus-events/nvim/CC-leak checks need a real WT tmux server
restart — Tim runs those); (c) reconcile durability — main carrying this work
supersedes the `dev-switch` local override, and nixcfg-work's `flake.lock` pin to
nixcfg will need a bump to pick it up. Cross-platform note: the mechanism is largely
Mac-portable (tmux + shell/CC hooks are OS-agnostic); the WSL-specific bits
(`tmux-battery` sysfs, focus-events history) are already gated. Confirm the merge with
Tim (never auto-merge to main).

## Tasks

| ID | Task | Phase | Status |
|----|------|-------|--------|
| T1 | Research upstream/community prior art (parallel subagents) | research | TASK:COMPLETE 2026-08-17 |
| T7 | Upstream-contribution review of the design PROPOSAL (tmux fit) | research | TASK:COMPLETE 2026-08-17 (CONDITIONAL GO) |
| T2 | Design the declarative Nix API (sign-off) | design | TASK:COMPLETE 2026-08-17 (signed off, full scope) |
| T3 | Refactor to one shared per-pane `tmux-cmd-state` helper (kill the 4x dup) | 1 · LOCAL | TASK:COMPLETE 2026-08-17 |
| T4 | Generate tmux conditional + clear predicate from declared `states` | 1 · LOCAL | TASK:COMPLETE 2026-08-17 |
| T5 | Model `sources` (shell + per-program); re-wire CC via it | 1 · LOCAL | TASK:COMPLETE 2026-08-17 |
| T6 | Prove extensibility: add one more program declaratively (e.g. nvim) | 1 · LOCAL | TASK:COMPLETE 2026-08-17 |
| T8 | Upstream: GitHub issue + `format.c` patch for `#{window_command_running}` | 2 · UPSTREAM | TASK:PENDING (BLOCKED: needs T3-T6 + tmux 3.8 released) |

### T1 — Research (parallel subagents) `TASK:COMPLETE 2026-08-17`

Use parallel subagents (Agent tool or a Workflow) — one per lane — then
synthesize. **Do not write code in T1**; produce a findings doc with a
recommendation: adopt-existing vs. keep-custom, and the API shape it implies.

Research lanes (one subagent each):
1. **tmux-native + plugins**: `monitor-activity`/`monitor-silence`/`monitor-bell`
   + `window-status-activity-style`; `#{pane_current_command}` styling patterns;
   plugins (tmux-window-name, tpm ecosystem) that color windows by
   running/idle/process. Is there a conventional "command running/done" plugin?
2. **Terminal shell-integration standards**: OSC 133 (FinalTerm/iTerm2 semantic
   prompt marks: command start/end/exit-code), OSC 7 (cwd), OSC 9 / OSC 9;4
   (notifications / progress; ConEmu + Windows Terminal). **Key question: can
   tmux consume OSC 133 to know command start/end/exit WITHOUT shell preexec/
   precmd hooks?** (tmux 3.4+ has some OSC handling / `allow-passthrough`.) This
   could replace our per-shell hooks entirely with a standard.
3. **Cross-shell preexec + agent-state prior art**: bash-preexec, zsh/fish
   hooks; how other tools/TUIs (incl. Claude Code community, opencode) signal
   state to tmux/terminal (pane_title/OSC); notification daemons.
4. **Nix ecosystem**: existing home-manager / flake / NUR modules that
   declaratively configure tmux status per-program or model "status sources";
   how `programs.tmux` plugins are structured; any declarative status-bar
   abstraction to borrow.

**DoD:** a findings file at `docs/tmux-status-prior-art.md` (create it) with, per
lane: what exists, links, and a keep-vs-adopt recommendation; plus a proposed API
direction feeding T2. Present the synthesis to Tim before T2.

**T1 findings (COMPLETE 2026-08-17):** Findings doc written to
`docs/tmux-status-prior-art.md` (4 parallel research lanes + a round-two deep-dive
on multi-pane scoping/aggregation, all synthesized).

**Headline (round two, prompted by Tim):** the CURRENT design is under-modeled —
`@cmd_state` is a per-WINDOW option, so multiple panes running independent commands
in one window stomp a single shared value. **Correct granularity is per-PANE**,
aggregated to the one-per-window status entry via the native **`#{P:}` pane-loop**
(priority fold: attention/error > running > idle; pure native format, no `#()`).
tmux HAS these primitives (pane user-options `set -p @x`; on tmux 3.8 native
per-pane OSC 133 vars `#{pane_command_running}`/`#{pane_command_status}`; monitor
flags for a free coarse fallback). Multi-pane->one-window aggregation is
**genuinely unsolved in the plugin ecosystem** (all are per-pane-border,
last-writer-wins, or one-shot notify; none uses `#{P:}`) — so it is this design's
novel contribution. One `#{P:}` aggregation expression serves BOTH backends; only
the per-pane source term differs (`@cmd_state` vs native `#{pane_command_*}`).

Verdict: **Re-scope to per-pane + `#{P:}` aggregation; keep a thin custom producer
only for what tmux cannot derive (agent attention; running/done on pre-3.8);
do not adopt an external framework — borrow shapes; design the backend seam now.**
Key results per lane:
1. **tmux-native/plugins:** no native mechanism represents a persistent per-window
   command *lifecycle* state (`monitor-activity/silence/bell` = output/timing only;
   `#{pane_current_command}` = hookless snapshot that evaporates on exit). No
   de-facto plugin; `tmux-agent-indicator` (accessd) is the closest model and
   validates our design but is opinionated/non-Nix — borrow its ideas.
2. **OSC 133:** tmux **3.8** (UNRELEASED; local is 3.6a) parses OSC 133 A/B/C/D and
   exposes `#{pane_command_running}`/`#{pane_command_status}`/`pane-command-finished`
   — exactly what we want, but needs a git build now, and the shell must still emit
   the marks. => design a `backend = "hooks" | "osc133"` switch; keep `hooks`
   default.
3. **cross-shell + agent-state:** use native zsh `add-zsh-hook` / fish `--on-event`
   + **bash-preexec** (nixpkgs) for bash (source last, idempotent). Our CC
   `@cmd_state` hooks already match+exceed community consensus (adds `running`).
   Borrow an out-of-focus **alert leg** (`\a`/DCS-OSC to `#{pane_tty}`) and keep
   **pane-scoping** (`$TMUX_PANE`) for multi-agent safety.
4. **Nix ecosystem:** no HM/community module models per-window lifecycle states
   (catppuccin = left/right segments in the plugin runtime, not Nix). Build our own
   on `extraConfig` folding; borrow catppuccin's "named unit -> generated variable"
   shape. **Cross-module seam: a shared lib `modules/lib/tmux-cmd-state.nix`**
   (canonical state-name set + `tmux-cmd-state` helper + `mkSourceHooks`), imported
   by both tmux and claude-code modules — no cross-`config` reads.

Proposed API straw-man (states + sources + backend + alert), single `tmux-cmd-state`
writer, generated `#{?}`/clear from folded `states`, and a behavior-parity checklist
are all in the findings doc's "Proposed API direction" section — that is the input to
T2. **Present to Tim before starting T2.**

### T2 — Design declarative API `TASK:COMPLETE 2026-08-17` (signed off, full scope)

> **RESOLVED (2026-08-17):** the design below (decisions D1-D9 + the frozen schema)
> is SIGNED OFF at full scope. Sequencing history: sign-off was deferred until after
> T7 (the upstream-contribution review); T7 completed (CONDITIONAL GO) and found no
> generality refinement was needed, so T2 was signed off unchanged. T3-T6 (Phase 1,
> LOCAL) are now unblocked; the upstream follow-through is the gated Phase-2 task T8.
> The decision walkthrough below is kept as the design record.

**This task is a guided decision session. Do NOT write module code.** Read the T1
findings doc (`docs/tmux-status-prior-art.md`, esp. "Multi-pane scoping &
aggregation" and "Proposed API direction") FIRST, then walk Tim through the eight
decisions below **one topic at a time** using `AskUserQuestion` (each with a
recommended option marked). After each answer, record it in the "T2 decisions
(RESOLVED)" subsection created below. When all eight are resolved, write the final
`states`/`sources`/`backend` schema into this task block as the frozen spec that
T3-T6 implement, and get one explicit "sign off / go" from Tim. Output
**USER_INPUT_REQUIRED** whenever waiting on him.

**Context the next session needs (self-contained):**
- The refactor target files, the current mechanism, and the DRY problems are in
  this plan's "Current state" and "DRY / design problems" sections above.
- The straw-man API, the exact `#{P:}` aggregation recipe (with gotchas), and the
  behavior-parity checklist are in `docs/tmux-status-prior-art.md`.
- Headline constraint: **state must be PER-PANE**, aggregated to the window via a
  single generated `#{P:}` priority-fold; both backends share that one expression
  and differ only in the per-pane source term.

**The eight decisions to walk Tim through (each: present options + recommendation):**

1. **Backend default & scope.** `backend = "hooks"` default now, with `osc133`
   designed-but-gated on `tmux >= 3.8` (Tim is on 3.6a, so `osc133` needs a
   git/pinned tmux to actually run)? Options: (a) ship `hooks` now, design
   `osc133` seam but don't wire it *(recommended)*; (b) also pin tmux 3.8 and make
   `osc133` real this cycle; (c) `hooks` only, defer the seam entirely.
2. **Cross-module seam.** (a) shared lib `modules/lib/tmux-cmd-state.nix` that both
   the tmux and claude-code modules import — no cross-`config` reads
   *(recommended)*; (b) claude-code reads `config.programs.tmux.commandStatus.*`;
   (c) tmux exposes a mergeable `sources` attrset and CC registers into it;
   (d) 1+3 (shared lib foundation + mergeable `sources` for extensibility).
3. **`clearOnView` semantics with per-pane state.** When Tim navigates to a
   window/pane, what clears? (a) clear only the **viewed pane's** clearOnView
   states; (b) clear **all panes'** clearOnView states in the selected window
   *(recommended — matches today's "tab goes back to normal when I look at it")*;
   (c) clear on pane-focus (`pane-focus-in`, needs `focus-events`), most granular.
4. **State set + priorities.** Approve `{attention:30, error:25, running:20,
   done:10}` *(recommended)* — note this ADDS an `error` state (from OSC 133
   non-zero exit / `$?`) not in the current impl. Keep `error`, or fold error into
   `attention`/`done`?
5. **Alert leg (out-of-focus bell/OSC).** Include `alert = { enable, channel,
   onStates }` in the API now, default `enable = false` *(recommended)*, or defer
   it to a later task?
6. **Native monitor fallback.** Include `monitorFallback.enable` (bell-action
   other -> attention, activity-action other) as an optional zero-producer layer,
   default off *(recommended)*, or drop it?
7. **Channels.** Expose `channels = { windowStatus, paneBorder }` so a state can
   also color the pane border? Options: (a) windowStatus only for now, keep
   `paneBorder` as a documented future field *(recommended)*; (b) implement both
   now.
8. **`style` preset vs per-state styles.** Keep the existing `style` preset enum
   as a palette that fills `states.*.style` defaults, with per-state override
   allowed *(recommended)*; also pick the default preset (currently `background`;
   preview via the temp tool in "Non-blocking pending items").

**DoD:** all eight decisions recorded under "T2 decisions (RESOLVED)" with Tim's
choices + date; the frozen `states`/`sources`/`backend` schema written into this
task block; Tim's explicit go. No code. This unblocks T3.

#### T2 decisions (RESOLVED 2026-08-17)
Walked through with Tim via AskUserQuestion, one topic at a time. Choices:

- **D1 backend — HOOKS now; osc133 = designed seam only, DEFERRED.** Ship the
  `hooks` backend on tmux 3.6a this cycle. Design the format layer against an
  abstract per-pane "state provider" so the `osc133` backend is a *source-term
  swap*, not a rewrite — but do NOT implement it now. The real osc133 backend
  (pin tmux >= 3.8 git build + per-shell OSC-133 emitter + `backend` switch made
  dual) moves to a **follow-up plan** (see Non-blocking pending items). Tim's Q on
  OSC 133 answered inline: OSC 133 standardizes the *escape sequence + its
  semantics* (the terminal<->shell wire protocol), NOT who prints it; upstream
  bash/zsh don't emit it by default — a prompt tool (starship/oh-my-posh) or a
  terminal shell-integration snippet injects the marks via precmd/preexec. So the
  osc133 backend still needs a shell-side emitter; its win is tmux 3.8 deriving
  running/done/exit/duration for free from an ecosystem-shared standard.
- **D2 seam — SHARED LIB + MERGEABLE SOURCES.** Foundation: shared lib
  `modules/lib/tmux-cmd-state.nix` (canonical state-name set + `tmux-cmd-state`
  helper derivation + `mkSourceHooks` + the `#{P:}` fold generator) imported by
  BOTH the tmux and claude-code modules — no cross-`config` reads. PLUS a
  mergeable `sources` attrset so programs register declaratively (unblocks T6).
- **D3 clearOnView — BOTH mechanisms (fix today's whole-window clear).** Clear the
  **viewed PANE's** clearOnView states, not the whole window. Wire BOTH:
  `after-select-window` (clears the newly-active pane; no focus-events dependency)
  AND `pane-focus-in` (clears any pane focused within a window; requires
  `focus-events on`, degrades gracefully to the after-select-window path if
  focus-events aren't delivered). This corrects the current impl, which clears all
  panes / the whole window.
- **D4 states/priorities — KEEP `error` as a distinct state.** Full set
  `{attention:30, error:25, running:20, done:10}`. On the hooks backend, `error` =
  command finished with non-zero `$?` (the post-command hook captures `$?` and
  maps to `error` vs `done`); on the future osc133 backend, `error` derives from
  `#{pane_command_status} != 0`.
- **D5 alert leg — INCLUDE, default OFF.** `alert = { enable=false;
  channel="bell"; onStates=["attention"]; }` in the schema now, ships disabled;
  zero behavior change until opted in.
- **D6 monitor fallback — INCLUDE, default OFF.** `monitorFallback.enable=false`;
  optional zero-producer coarse layer (bell-action other -> attention,
  activity-action other).
- **D7 channels — windowStatus NOW, paneBorder documented-future.**
  `channels = { windowStatus=true; paneBorder=false; }`. Implement only the
  `#{P:}`-aggregated per-window entry this cycle; `paneBorder` is a wired-later
  field (per-pane, needs no aggregation, clean future add).
- **D8 style — PALETTE + per-state override, default preset `background`.** Keep
  the `style` enum (`italic|color|reverse|background|blink`) as a palette that
  fills `states.*.style` defaults; any state may override via `states.<n>.style`.
  Default preset stays `background`.
- **D9 per-program source ownership — PROGRAM-OWNED + read-only registry
  (hybrid).** Each program declares its event->state map in ITS OWN namespace
  (`programs.<prog>.tmuxStatus.events = { <nativeEvent> = <state>; }`) and installs
  its own native hooks by folding the shared lib's `mkProgramSource` output into
  its native hook mechanism (CC: `mkHook`/`mergeHookSets`; nvim: autocmds; etc.).
  NO cross-`config` reads. Each program ALSO publishes a **read-only** entry into
  `programs.tmux.commandStatus.sources.<prog>` purely for introspection ("one place
  to see every feed") — nothing critical reads it back, so there is no eval-order
  coupling. This is the concrete answer to "how a program hooks into the mechanism":
  Nix unifies the TARGET (`tmux-cmd-state <state>`, the single sink) and the
  DECLARATION SHAPE (`events = { ev = state; }`); the tiny last-mile adapter into
  each program's native event format lives in that program's module (irreducible,
  because event systems differ structurally). Invariant: a program's hook must run
  in the target pane's process tree so `$TMUX_PANE` resolves (true for CC + shells;
  a detached daemon would pass the pane id explicitly — deferred edge case).

#### T2 frozen spec (the API T3-T6 implement)

```nix
programs.tmux.commandStatus = {
  enable  = true;
  backend = "hooks";          # ONLY backend this cycle. "osc133" is designed as a
                              # source-term seam but NOT implemented (deferred plan).
  style   = "background";     # palette preset (italic|color|reverse|background|blink);
                              # fills states.*.style defaults; per-state override allowed.

  # STATE IS PER-PANE. The single writer sets a PANE option (tmux set -p @cmd_state).
  # states are declared once; the #{P:} priority-fold that aggregates panes into each
  # window entry AND the clear predicate are GENERATED from this set (no hand-written
  # nested #{?} / literal state names).
  states = {                  # priority: higher wins the window entry when panes differ
    attention = { style = "bg=colour201 fg=colour16 bold blink"; clearOnView = true;  priority = 30; };
    error     = { style = "bg=colour196 fg=colour16 bold";       clearOnView = true;  priority = 25; };
    running   = { style = "bg=colour214 fg=colour16 bold";       clearOnView = false; priority = 20; };
    done      = { style = "bg=colour34  fg=colour16 bold";       clearOnView = true;  priority = 10; };
  };

  channels = {
    windowStatus = true;      # implemented now: the #{P:}-aggregated per-window entry
    paneBorder   = false;     # documented FUTURE field; per-pane, no aggregation. Not wired now.
  };

  sources = {                 # D2+D9: `shell` is a real generic source tmux installs;
                              # per-program entries are READ-ONLY registry publications
                              # (introspection only — the program installs its own hooks).
    shell.enable = true;      # per-PANE lifecycle: zsh add-zsh-hook / fish --on-event /
                              # bash via nixpkgs bash-preexec (sourced LAST, idempotent handlers).
                              # tmux/shell module OWNS installation of this one.
    # claude-code = { … };    # PUBLISHED read-only by the CC module (see below); do not
                              # hand-edit here. nvim/opencode publish likewise (T6).
  };

  monitorFallback.enable = false;  # optional zero-producer coarse layer (bell-action
                                   # other -> attention, activity-action other). Off.

  alert = {                   # optional out-of-focus leg (default off)
    enable   = false;
    channel  = "bell";        # "bell" (\a -> #{pane_tty}) | "osc-notify" (DCS-wrapped)
    onStates = [ "attention" ];
  };
};
```

**Per-program integration (D9) — the shared lib + program-owned pattern:**

```nix
# modules/lib/tmux-cmd-state.nix exports (imported by BOTH tmux and program modules):
{
  stateNames    = [ "attention" "error" "running" "done" ];   # single source of truth
  mkHelper      = { pkgs }: <writeShellApplication "tmux-cmd-state">;  # the ONE sink:
                  # pane-addressed via $TMUX_PANE, active-pane suppression for clearOnView
                  # states, set -p / set -up @cmd_state, refresh-client -S, no-op if !$TMUX.
                  # REPLACES tmuxStateScript in hooks.nix AND the 3 shell-hook copies in tmux.nix.
  mkProgramSource = { events }: { commands = <{ ev = "${helper}/bin/tmux-cmd-state <state>"; }>; };
                  # validates each state ∈ stateNames; returns per-event command strings.
  mkFold        = { states }: <the #{P:} priority-fold + clear predicate>;  # generator for T4.
}
```

```nix
# A program declares intent in ITS OWN namespace (here: claude-code):
programs.claude-code.tmuxStatus = {
  enable = true;              # replaces today's hooks.tmuxStatus.enable
  events = {                  # CC-native event -> canonical state (was hardcoded in hooks.nix)
    UserPromptSubmit = "running";
    Notification     = "attention";
    Stop             = "done";
  };
};
# The CC module then, WITHOUT reading tmux config:
#   1. src = tmuxCmdState.mkProgramSource { inherit (cfg.tmuxStatus) events; };
#   2. folds src.commands into its existing mkHook/mergeHookSets (kills the inline map);
#   3. calls tmuxCmdState.mkHelper for the binary (kills tmuxStateScript);
#   4. publishes a READ-ONLY programs.tmux.commandStatus.sources.claude-code = cfg.tmuxStatus.events
#      for introspection only.
```

This is the concrete T5 target and the extensibility proof T6 repeats for a second
program (e.g. nvim) with zero new mechanism — only a new `events` map + a fold into
that program's native hook installer.

**Invariants T3-T6 must uphold (from the parity checklist):**
1. **State is per-PANE**, written by ONE `tmux-cmd-state <state>` helper
   (`set -p -t $TMUX_PANE @cmd_state`); no-op when `$TMUX` unset; active-pane/window
   suppression centralized in that helper.
2. **One generated `#{P:}` aggregation expression** (priority fold across panes)
   serves `window-status-format`; the clear predicate is generated from
   `filter clearOnView`. No `#()` for state styling (avoids the revert bug).
3. **clearOnView clears the VIEWED PANE** via after-select-window + pane-focus-in
   (D3) — never the whole window.
4. **Multi-pane correctness:** a 3-pane window (one running, one error, one idle)
   must show the highest-priority state; verify explicitly in T3/T4.
5. Per-shell "ran" guard prevents startup / bare-Enter marking; CC
   `UserPromptSubmit->running`, `Notification->attention`, `Stop->done`,
   done/attention suppressed on the active pane.

**SIGNED OFF 2026-08-17 (Tim).** T7 found no generality refinement is needed — the
frozen spec above is the implementation target for T3-T6 at FULL scope (Tim chose
"keep full scope" for the local phase; nothing cut). One forward-looking note
carried into T4: keep the `#{P:}` aggregation behind the shared-lib `mkFold`
generator (the single seam) so that IF the upstream `#{window_command_running}` var
lands, the fold collapses to that native var in one place. T2 COMPLETE; T3 unblocked
as the first Phase-1 task.

### T3-T6
Implement per the signed-off design. Keep behavior parity with current commits.
Use the `dev-switch -d` loop to test each step. **DoD each:** `nix flake check`
passes (pre-commit hook) AND live behavior verified via the nested-capture
technique (see session transcript) or a fresh shell / fresh `claude`.

#### T3 progress (2026-08-17) — code-complete, awaiting live deploy verify
**Done this session (commit follows):**
- Created **`modules/lib/tmux-cmd-state.nix`** — the shared lib (D2 seam). Exports
  `stateNames = [attention error running done]`, `clearOnViewStates =
  [attention error done]`, and `mkHelper { }` -> a `writeShellApplication`
  `tmux-cmd-state`. The helper is the SINGLE writer: `running` sets
  unconditionally; `attention|error|done` set on a background window but clear on
  the ACTIVE window (suppression); `clear`/"" unset; no-op outside tmux. State is
  **per-PANE** (`set -p @cmd_state` / `set -up`), addressed via `$TMUX_PANE`,
  resolving tmux from PATH. The case-arm pattern (`attention|error|done`) is
  FOLDED from `clearOnViewStates` via `lib.concatStringsSep` (DRY).
- Rewired all **4 duplicated consumers** to call the one helper by store path:
  - `modules/programs/tmux/tmux.nix`: added `tmuxCmdState`/`tmuxCmdStatePkg`/
    `cmdStateBin` bindings; installed the pkg on PATH (`home.packages`); collapsed
    the **zsh**, **bash**, **fish** hook blocks so each only keeps its shell-native
    "ran"/first-command guard and calls `${cmdStateBin} running|done` (all set/
    clear/active-suppression/redraw logic now lives in the helper).
  - `modules/programs/claude-code/_hm/hooks.nix`: deleted the inline
    `tmuxStateScript`; imported the shared lib (`tmuxCmdStateBin`); the three
    `tmuxStatusHooks` (UserPromptSubmit->running, Notification->attention,
    Stop->done) now call the shared binary. Both modules import the SAME file ->
    identical store path (true dedup).

**Verified this session:**
- `nix build` of `mkHelper {}` succeeds — **shellcheck passes** (store path
  `7vx4igzxhk57vvkb8h5nrk3ipm3z62j2-tmux-cmd-state`).
- `nix flake check --no-build` **exit 0** (whole flake evaluates with the rewire).
- **Writer smoke test against an isolated tmux server** (private `-S` socket, 2
  windows): background `running`->running, `done`->done, `attention`->attention;
  `done` on the ACTIVE window -> unset (suppressed); `clear`->unset; outside tmux
  -> clean exit 0 no-op. All 6 cases correct = parity with the prior per-window impl.

**Regression found + fixed during live verify (thoroughness pass, 2026-08-17):**
Switching the WRITER to per-pane (`set -p`) while `cmdStateClearOnSelect` still did
`set -uw @cmd_state` (unset the WINDOW option) broke clear-on-view: the marker lived
on the pane option but the clearer targeted the (unset) window option, so navigating
to a done/attention window never reset it. **Fix:** `cmdStateClearOnSelect` now does
`set -up @cmd_state` (unset the PANE option; the predicate reads the selected
window's active pane). Verified `set -up` clears cleanly, no stderr. (T4 GENERATES
this predicate from the state set + adds the `pane-focus-in` leg; T3 restores parity.)

**Live verification DONE — deployed via
`dev-switch -d -o nixcfg=~/src/nixcfg ~/src/nixcfg-work` (exit 0), then:**
- **Real deployed zsh hook, end-to-end** in a nested tmux using the exact deployed
  `window-status-format`: background `sleep 2` -> `@cmd_state=running` + amber
  (colour214) RENDERED; on finish -> `done` + green (colour34) RENDERED; navigate to
  it -> CLEARED; run in the now-active window -> SUPPRESSED (empty). All correct.
- **Writer** unit-verified vs an isolated tmux server (6/6 state cases); **reader**
  verified: `#{E:window-status-format}` expands the per-pane option for the active pane.
- **bash/fish**: correctly emit NO hook on this host (only `programs.zsh` enabled;
  `~/.bashrc`/fish not HM-managed here) - proper gating, not a gap; same proven-helper
  call, eval-validated by `nix flake check` for hosts that enable them.
- **CC hooks**: all three account `settings.json` (max/work/pro) wire the SAME proven
  helper store path (`7vx4...-tmux-cmd-state`) for running/attention/done.

**Known intentional T4 gap (documented, not a regression):** in a MULTI-pane
background window a command in a NON-active pane won't aggregate to the window entry
until T4's `#{P:}` fold (window-status-format reads only the active pane). Single-pane
windows are exact parity; this boundary was verified explicitly (Case B).

Next: **T4** (`mkFold`: the `#{P:}` priority-fold + generated clear predicate,
replacing the hand-written nested `#{?}` and the now-`set -up` clearer).

#### T4 progress (2026-08-17) — code-complete + fold live-verified
**Done this session:**
- Added **`mkFold { styles }`** to `modules/lib/tmux-cmd-state.nix` (the D2/T4
  seam). It folds the ONE declared state set into the two native-format artifacts,
  so adding/renaming/reprioritising a state is now a one-place edit:
  - `.styleExpr` — the `#{P:}` per-pane **priority-fold** for `window-status-format`.
    For each state (highest priority first) emits that state's `#[style]` iff ANY
    pane in the window carries `@cmd_state == <state>`, via a sentinel folded through
    the **single-arg** `#{P:}` pane-loop wrapped in `#{!=:…,}`. This aggregates a
    BACKGROUND pane's state to the one-per-window entry — **closing the T3
    active-pane-only gap** (the "Known intentional T4 gap" above).
  - `.clearPredicate` — `if -F "<cond>" "set -up @cmd_state"`, true when the pane's
    own `@cmd_state` is a clearOnView state (attention/error/done). Deliberately a
    per-pane read (bare `#{@cmd_state}`), NOT a `#{P:}` fold — D3 clears the VIEWED
    pane, never the whole window.
  - Canonical `statePriority = {attention=30;error=25;running=20;done=10;}` added to
    the lib as the single source of truth the fold sorts on.
- Rewired `modules/programs/tmux/tmux.nix`:
  - Extended each `cmdStateStyles` preset with an **`error`** style (colour196) so
    the palette covers all four `stateNames` (no producer sets `error` yet — that is
    a T5 sources concern — so its arm is present but zero-cost).
  - Replaced the hand-written nested `#{?}` `cmdStateStyle` with `cmdFold.styleExpr`
    and the literal `cmdStateClearOnSelect` with `cmdFold.clearPredicate`
    (`cmdFold = tmuxCmdState.mkFold { styles = activeCmdStyle; }`). No hand-written
    conditional or predicate remains.
  - Added the **`pane-focus-in`** clear leg (D3) alongside `after-select-window`,
    both wired to the generated predicate.

**Verified this session:**
- `mkFold` output inspected via `nix eval` — priority order attention→error→
  running→done, brace-balanced.
- **`#{P:}` fold live on tmux 3.6a** (isolated `-S` server, 2-pane window): no-state
  →IDLE; running on the BACKGROUND pane with the active pane idle →RUN (aggregation
  — the T3 gap is closed); +attention on active pane →ATT (priority beats running);
  error on bg + active cleared →ERR; all cleared →IDLE. 5/5 correct = invariant #4
  (multi-pane highest-priority-wins) proven.
- **Clear predicate** live: done/error/attention →cleared, running →kept. 4/4.
- `nix flake check --no-build`: **exit 0** (`all checks passed!`) — whole flake
  evaluates with the mkFold rewire; the `vm-tmux` check derivation evaluated clean.

**D3 mechanism REFINED (2026-08-17) — window-pane-changed, not pane-focus-in.**
Tim asked to root-cause the `focusEvents = false` setting rather than blindly flip it.
Four parallel research subagents (findings folded into this plan + the tmux source
`~/src/tmux`) established:
- The original global focus-events disable (ccd345b 2026-01-22 + terminal-features
  focus:0 e1000d6 2026-01-26) was a **stopgap for a Claude Code bug**: CC enabled
  `?1004h` but mis-rendered the `^[[I`/`^[[O` focus sequences as visible garbage.
  That CC bug (issues #11391/#18363) was CLOSED Jan 2026, fixed ~v2.0.67; we run
  **2.1.191**.
- tmux forwards `^[[I`/`^[[O` to a pane **only if that app itself enabled `?1004h`**
  (per-pane MODE_FOCUSON gate, tmux `window.c:693-704`); `pane-focus-in`/`-out` hooks
  fire regardless. So the global-off was a sledgehammer for one app's bug.
- **Key win:** tmux's **`window-pane-changed`** hook fires on EVERY active-pane change
  (select-pane incl. the C-h/j/k/l nav binds, mouse click, last-pane, split-window),
  is driven by core `window_set_active_pane()` and needs **no focus-events at all**
  (strictly more complete than `after-select-pane`, which misses last-pane + splits).

**Applied:** replaced the `pane-focus-in` leg with **`window-pane-changed`** (works
live NOW regardless of focus-events). Live-verified on an isolated server with
focus-events OFF: navigate-to-pane clears that pane's done/attention (4/4), keeps
running, clears only the VIEWED pane (D3), fires on the last-pane path. Independently,
**re-enabled `focusEvents = true` + removed `terminal-features ",*:focus:0"`** — a
SEPARATE concern (not needed by the indicator) that restores neovim
FocusGained/checktime autoread-on-refocus, now safe given CC 2.1.191. Full rationale
in the `focusEvents` comment in `tmux.nix`. (Residual: CC #72067 cosmetic re-render on
focus-out looks like activity to `monitor-activity`, which is off by default here.)

**Deployed + verified (2026-08-17, via `dev-switch -d`, exit 0):**
- The deployed `~/.config/tmux/tmux.conf` `window-status-format` is EXACTLY the
  mkFold output (real `#[bg=colour214/34/196/201…]` styles in the `#{P:}` fold + the
  `#(tmux-window-status-format …)` script). Render-checked via `#{E:window-status-
  format}` on the EXACT deployed 423-char string (not placeholders): no-state → no
  color; bg-pane running → colour214; running+done → colour214 (priority 20>10);
  done → colour34; error → colour196. Style selection + multi-pane priority proven
  as-deployed. (`#()` index+name is async-empty in a fresh server — expected,
  unchanged, separately proven in T3.) → **render gap CLOSED.**
- `window-pane-changed` hook is LIVE on the real running server (confirmed via
  `show-options -g window-pane-changed` = the exact generated predicate). The
  pane-view clear works now.
- Deployed config has `focus-events on` and NO `terminal-features focus:0`.

**Still owed — focus-events activation needs a tmux SERVER RESTART (Tim runs it).**
Discovered on the live server: `focus-events` is already `on`, BUT
`terminal-features` still carries **43 accumulated `focus:0` entries** (from months of
`set -ga terminal-features ",*:focus:0"` appending on every reload). Removing the
config line does NOT remove already-appended entries — `set -ga` only appends. So
focus reporting stays blocked until a full `tmux kill-server` (continuum will
restore). This concretely confirms e1000d6's "requires full tmux server restart" note.
After restart: (1) confirm no `^[[I` garbage in Claude Code across ~20 window
switches; (2) nvim `:set autoread` + `au FocusGained,BufEnter * checktime`, edit a
file from another pane, switch back → auto-reloads.

Next: **T5** (model `sources`; re-wire CC via `mkProgramSource`).

#### T5 progress (2026-08-17) — code-complete + flake-check green
**Done this session:**
- **Shared lib** (`modules/lib/tmux-cmd-state.nix`): added **`mkProgramSource
  { events }`** — the D9 per-program source generator. It maps a program's
  native-event->canonical-state attrset to `.commands` (each = a call to the ONE
  shared `tmux-cmd-state` writer), **validating every mapped state against
  `stateNames` at eval time** (a typo like `"runing"` is a build-time throw naming
  the offending event, not a silent no-op marker). Verified: valid map resolves to
  the same writer store path as T3/T4 (`7vx4…-tmux-cmd-state`, true dedup); a bad
  state throws the expected message.
- **tmux module** (`tmux.nix`): added **`programs.tmux.commandStatus.sources`** — a
  submodule with a real **`shell.enable`** gate (default on) plus a freeform
  `attrsOf (attrsOf str)` introspection registry. The zsh/bash/fish shell hook
  blocks are now gated on `commandStatus.enable && sources.shell.enable`, so the
  generic shell source can be toggled off independently (e.g. to drive the
  indicator ONLY from Claude Code) without disabling the whole indicator.
- **claude-code module** (`hooks.nix`): **relocated** the CC source to its own
  namespace **`programs.claude-code.tmuxStatus = { enable; events; }`** (replaces
  `hooks.tmuxStatus.enable`; no external setters existed — verified). `events`
  defaults to the prior hardcoded map (`UserPromptSubmit=running`,
  `Notification=attention`, `Stop=done`). The three CC hooks are now **generated by
  folding `mkProgramSource` output through `mkHook`**, deleting the inline
  event->state map (and the now-dead `tmuxCmdStateBin` binding). Generated commands
  are **byte-identical** to the previous impl (same writer store path + same state
  strings), so behavior parity is by construction — no live re-verification of the
  marker rendering is needed beyond T3/T4's (which used this exact helper path).

**Design refinement discovered at implementation (supersedes D9 step 4):** the
planned cross-module auto-publish of the CC event map into
`programs.tmux.commandStatus.sources.claude-code` was **dropped**. D9 framed it as
"read-only introspection, no eval-order coupling", but a WRITE to another module's
option still requires that option to be **declared** in the eval — and claude-code
composes **standalone** (the flake's checks evaluate it against **upstream**
home-manager `programs.tmux`, which has no `commandStatus`). The write then fails
with `option 'programs.tmux.commandStatus' does not exist`, and — verified via a
minimal `evalModules` test — an `mkIf (config.programs.tmux ? commandStatus)` guard
does **NOT** suppress it (the module system records the unmatched definition path
regardless of the mkIf condition). The declaration coupling is irreducible, so
auto-publish is incompatible with dendritic composability. The event map stays fully
introspectable at its **source of truth** (`programs.claude-code.tmuxStatus.events`);
the `sources` registry remains as an optional hand-set unified view. This surfaced
as a real `nix flake check` failure and was fixed before the green run.

**Verified this session:**
- `nix eval` of `mkProgramSource`: attr names + command values correct; store-path
  dedup with T3/T4; bad-state throw fires with the right message.
- `nix flake check --no-build`: **exit 0** (`all checks passed!`) — the whole flake,
  including the CC module (standalone, against upstream tmux) and the `vm-tmux`
  check (our tmux module with the new `sources` option + `mkFold`), evaluates clean.

**Render-identity PROVEN (not deferred).** Rather than lean on the parity argument, I
diffed the actual rendered artifacts for `tim@thinky-nixos` between the pre-T5 tree
(HEAD~1) and T5 (HEAD) via `nix eval`:
- CC assembled hooks (`config.programs.claude-code._internal.hooks` — the whole
  `settings.json`, all 30 events): **byte-for-byte IDENTICAL**.
- tmux `config.programs.tmux.extraConfig` (the `tmux.conf`): **IDENTICAL**.
- zsh `config.programs.zsh.initContent` (the shell command-status hook block):
  **IDENTICAL**.
So T5 changes ZERO deployed bytes — it is a pure structural refactor. Because T3/T4
already live-verified these exact artifacts (same writer store path, same rendered
content), a `dev-switch` deploy of T5 would write identical files; live re-verification
is genuinely redundant, not skipped. The only still-owed live check is the SEPARATE,
pre-existing focus-events **tmux server restart** verification from T4 (unrelated to
T5's surface) — Tim runs that.

Next: **T6** (prove extensibility: add one more program declaratively, e.g. nvim,
via a new `events` map folded into that program's native hook installer — zero new
mechanism).

#### T6 progress (2026-08-17) — COMPLETE (nvim source added; extensibility proven)

**Decision (Tim, via AskUserQuestion 2026-08-17):** the second program is **neovim**,
sourced from its **Overseer task runner** (`RUNNING→running`, `SUCCESS→done`,
`FAILURE→error`), default **enabled**. Rationale for Overseer over the alternatives:
the generic `shell` source already marks a pane `running` for nvim's *entire*
lifetime (nvim is a foreground command → zsh preexec fires `running` on launch,
precmd `done` on exit), so an nvim source must signal *finer-grained sub-events*;
Overseer task status is the genuinely-useful, on-theme signal (a build/test finishing
in a background nvim pane flips amber→green/red, cleared on view). Overseer is ALSO a
different native event system than shells (CC) — the strongest extensibility proof.

**Done this session (`modules/programs/neovim/neovim.nix`):**
- Imported the SAME shared lib `modules/lib/tmux-cmd-state.nix` (no new mechanism);
  `nvimSource = mkProgramSource { events = ncfg.events; }`.
- Added option **`programs.neovim.tmuxStatus = { enable; events; }`** in neovim's own
  namespace (mirrors `programs.claude-code.tmuxStatus`; D9). `events` defaults to
  `{ RUNNING="running"; SUCCESS="done"; FAILURE="error"; }`. NO auto-publish into
  `programs.tmux.commandStatus.sources` (T5 established that write breaks standalone
  composition). Declaring `options.programs.neovim.tmuxStatus` merges cleanly with
  HM's builtin `programs.neovim` option tree (regular namespace, not a submodule).
- Last-mile adapter = an **Overseer component** (the native hook installer for that
  program — NOT shell hooks, NOT CC hooks). Overseer has no global status autocmd
  (verified against the plugin source: only `OverseerListUpdate` for the sidebar); the
  supported global mechanism is a named component in `component_aliases.default`.
  Overseer resolves a named component by `require("overseer.component.<name>")`, so
  the generated component Lua is placed on the runtimepath via nixvim **`extraFiles`**
  (`lua/overseer/component/tmux_cmd_state.lua`) and `"tmux_cmd_state"` is appended to
  `component_aliases.default` (both gated on `ncfg.enable` — zero-cost when off). The
  component's `on_status(self, task, status)` looks the status up in a Nix-baked
  `status_cmd` table and fires the shared writer via `vim.fn.jobstart({"sh","-c",cmd})`
  (guarded on `vim.env.TMUX`). STATUS strings verified against overseer
  `constants.lua` (`Enum{PENDING,RUNNING,CANCELED,SUCCESS,FAILURE,DISPOSED}`) and the
  `on_status` dispatch signature against `task.lua`.

**Verified this session:**
- `nix eval` on `tim@thinky-nixos`: `tmuxStatus.events` correct; `component_aliases.
  default` gains `"tmux_cmd_state"`; `extraFiles` gains the component file.
- **Generated component Lua references the SAME writer store path**
  `7vx4igzxhk57vvkb8h5nrk3ipm3z62j2-tmux-cmd-state` as the CC and shell sources
  (T3/T4/T5) — true cross-program dedup, zero new plumbing. **Lua parses clean**
  (`lua -e loadfile`).
- **Zero-cost when disabled:** `extendModules { tmuxStatus.enable = false; }` drops the
  component from the alias AND omits the extraFile (only the pre-existing
  `queries/nix/injections.scm` remains).
- **`nix flake check --no-build`: exit 0** (`all checks passed!`) — every host that
  imports the neovim module (7 homeConfigurations) + the `vm-tmux` check evaluate
  clean with the new source.

**Extensibility proven:** adding a SECOND program required only (a) a new `events` map
in that program's own namespace and (b) a fold of `mkProgramSource.commands` into that
program's native hook installer (an Overseer component) — with ZERO changes to the
shared lib and the SAME single `tmux-cmd-state` writer. This is the T2/D9 target
repeated for a structurally-different event system (component callbacks vs shell/CC
hooks), which is the strongest form of the proof.

**Functional verification DONE (headless, 2026-08-17) — beyond eval/parse.** After a
self-audit flagged that eval+Lua-parse was weaker than T3/T4's functional standard, ran
the real generated component through REAL headless nvim (`nvim 0.12.2 --headless -l`)
against an isolated tmux server (private `-S` socket), calling `on_status(self, task,
STATUS)` with the same call shape Overseer's `task:dispatch("on_status", status)` uses
(verified against `task.lua`):
- **RUNNING → `@cmd_state=running`**, **SUCCESS → `done`**, **FAILURE → `error`** on a
  BACKGROUND window: **3/3 PASS** (component's `jobstart` fires the shared writer, which
  sets the per-pane option; nvim correctly sees `$TMUX`/`$TMUX_PANE`/tmux-on-PATH).
- **SUCCESS on the ACTIVE pane → unset** (writer's active-pane suppression): PASS.
- **PENDING (unmapped status) → no-op**: covered by the `status_cmd[status]` nil-guard.
- Also confirmed Overseer's `validate_component` accepts the component shape (only a
  `constructor` is required; `desc`/whitespace-free-name satisfied) — so it will NOT
  error at load and cannot break other Overseer tasks.
- (Test methodology note: a first pass FAILED because the detached test window's command
  EXITED, destroying the pane + its pane-scoped option before the read; keeping the pane
  alive past the read fixed it — a TEST bug, not a component bug.)

**DEPLOYED + END-TO-END VERIFIED ON THE LIVE HOST (2026-08-17, `pa161878-nixos`).**
Deployed committed HEAD `b748b30` via `dev-switch -o nixcfg=~/src/nixcfg ~/src/nixcfg-work`
(exit 0; nixcfg input overridden to the branch HEAD). Then closed BOTH previously-owed
gaps with REAL Overseer, on the DEPLOYED config:
- Component file deployed to `~/.config/nvim/lua/overseer/component/tmux_cmd_state.lua`
  carrying the writer store path `7vx4…-tmux-cmd-state`.
- **Real Overseer task through its OWN dispatch** (deployed `nvim --headless`,
  `overseer.new_task{ components={"default"} }` — the default alias now includes
  `tmux_cmd_state`), polled on a BACKGROUND tmux window:
  - `sleep 6` task: at t=3s `@cmd_state=running`; after completion `@cmd_state=done`.
    **PASS running-phase + PASS done-phase.** Independent `task:subscribe("on_status")`
    witness logged `RUNNING` then `SUCCESS` 2s apart — Overseer's real dispatch fired our
    component.
  - `sleep 3; exit 1` task → Overseer `FAILURE` → `@cmd_state=error`. **PASS.**
- **Render (reader side) against the DEPLOYED `~/.config/tmux/tmux.conf`
  `window-status-format`:** a background pane with `@cmd_state=running` expands to
  `#[bg=colour214 fg=colour16 bold]` (amber); `=error` expands to `colour196` (red).
  **PASS both.** So the full loop — real Overseer STATUS → component → shared writer →
  per-pane `@cmd_state` → generated `#{P:}` style fold → colored window entry — works
  as-deployed.

Nothing about T6 remains owed. (The SEPARATE T4 focus-events **tmux server restart** is
still owed but is unrelated to T6.)

**Phase 1 (T3–T6) is now code-complete.** Next stopping point per plan §"Phase-1 exit":
shelve plan 050 and **merge `feat/tmux-command-status-indicator` → `main`** (confirm
with Tim; never auto-merge to main), reconciling durability (main supersedes the
`dev-switch` override; nixcfg-work's `flake.lock` pin to nixcfg needs a bump). T8
stays deferred (Phase-2 upstream, gated on tmux 3.8).

### T7 — Upstream-contribution review (tmux) `TASK:COMPLETE 2026-08-17` (go/no-go = CONDITIONAL GO)

**COMPLETE.** Ran BEFORE T2 sign-off and BEFORE any implementation (T3-T6). No code
dependency — it reviewed the **design PROPOSAL** frozen in the T2 block above
(decisions D1-D9 + the frozen `commandStatus` schema) plus the T1 findings doc.
Deliverable: `docs/tmux-upstream-contribution-assessment.md`. Findings + Tim's
CONDITIONAL GO decision are recorded in the "T7 findings" subsection below; the
upstream follow-through is now tracked as the gated Phase-2 task **T8**.

**Purpose (Tim's ask, verbatim intent):** thoroughly review the current design
PROPOSAL for its appropriateness as a **technical upstream contribution to the tmux
project** — primarily reviewing the design for **generality** and alignment with the
**tmux project's conventions/UX/maintainer norms** to maximize the chance the
maintainers would adopt it. Review + written assessment; **no upstream submission in
this task.**

**What to review the proposal AGAINST (do this thoroughly):**
- Read the T2 frozen spec + `docs/tmux-status-prior-art.md` (esp. the multi-pane
  aggregation section) first.
- Isolate the tmux-GENERAL kernel from all Nix/home-manager/`sources`/CC glue — only
  the tmux-native part is upstreamable.
- Pressure-test generality: does the proposal encode ANY app-specific concept
  ("agent"/"claude"/"attention-as-AI") that a maintainer would reject? Re-express in
  generic terms.
- Judge fit with tmux idioms/UX and maintainer (Nicholas Marriott) norms: minimal,
  general, composes with existing formats/hooks/options, opt-in, zero-cost unused,
  naming consistent with `#{pane_command_*}` / `window_*_flag`.
- Decide the right FORM (see scope item 2) and whether it's a go/no-go.

**The upstream-relevant kernel (why there is anything to propose):** T1 established
that tmux has **no native window-level aggregate of per-pane command state** —
there is no `#{window_command_running}` / `#{window_command_status}`; the only
native window aggregates are the monitor flags (`window_{activity,bell,silence}_flag`),
which cannot express command lifecycle or per-pane identity. Our `#{P:}`
priority-fold is a *userspace workaround* for that gap, and multi-pane→one-window
aggregation is unsolved across the plugin ecosystem too. So the candidate
contribution is: give tmux a first-class way to aggregate per-pane OSC 133 command
state to the window level.

**Scope (research + assessment doc):**
1. **Separate the tmux-GENERAL mechanism from our Nix glue.** Only the tmux-native
   part is upstreamable: the missing window-level command-state aggregate and/or a
   blessed `#{P:}` aggregation idiom. Everything Nix/home-manager/`sources`/CC is
   out of scope for upstream.
2. **Pick the contribution FORM.** Options to weigh: (a) a native format var
   `#{window_command_running}` / `#{window_command_status}` (a C aggregate over the
   window's panes, mirroring the existing `window_*_flag` pattern and the 3.8
   `#{pane_command_*}` vars); (b) a documented `#{P:}` recipe / example in the
   manpage or FAQ; (c) a new hook. Recommend one.
3. **Match tmux contribution NORMS.** Maintainer (Nicholas Marriott) leans minimal
   and general and rejects bloat/app-specific features; study the C style
   (tabs, tmux's declaration conventions), GitHub PR vs mailing-list flow, and the
   3.8 OSC 133 work (issues #3064 / #5237) as the closest precedent + the thread to
   engage. Shape the proposal like recently-merged changes.
4. **Generality / naming / UX review.** Strip every app-specific concept — NO
   "agent"/"claude"/"attention-as-AI"; express signals in generic terms. Ensure any
   proposed primitive composes with existing formats/hooks/options (no bespoke
   subsystem), is opt-in, and is zero-cost when unused. Names must be consistent
   with `#{pane_command_*}` / `window_*_flag`.
5. **Deliverable:** `docs/tmux-upstream-contribution-assessment.md` — the general
   kernel isolated; the recommended form; a draft problem statement framed for the
   maintainer; the venue + precedent thread; a minimal C sketch if (a) is chosen;
   and a **go/no-go** recommendation. Present to Tim for the go/no-go.

**DoD:** the assessment doc exists with an explicit go/no-go, the proposed form, and
the upstream venue/precedent identified; presented to Tim. No code submitted
upstream. (Interactive at the end for the go/no-go decision.)

#### T7 findings (assessment written 2026-08-17 — go/no-go PENDING Tim)

Deliverable written: **`docs/tmux-upstream-contribution-assessment.md`**. Upstream
state verified against tmux `master` @ `30abbe36` (local clone + GitHub API), not
memory. Headline findings:

- **The pane-level command lifecycle the plan polyfills is already NATIVE in tmux
  3.8** (`master`, unreleased; latest tag 3.7c): `#{pane_command_running}`,
  `#{pane_command_status}`, `#{pane_command_duration}`, hooks
  `pane-command-{started,finished}` + `pane-shell-prompt`, and `set-hook -B -T`
  (fire a hook when a format becomes true). Our `@cmd_state` hooks backend is a
  pre-3.8 userspace polyfill of exactly this; plan 051's `osc133` backend just
  *consumes* these — nothing to defend upstream there.
- **The ONLY general, upstreamable kernel is the missing window-level aggregate.**
  Confirmed absent in `master` (`grep 'window_command' format.c` → 0 matches).
  Our generated `#{P:}` priority-fold is a userspace workaround for a real native
  gap. Candidate: native `#{window_command_running}` (+ optional exit rollup)
  mirroring the existing `#{window_activity_flag}`/`window_bell_flag`/
  `window_silence_flag` machinery (`WINDOW_*`/`WINLINK_*` bits maintained eagerly
  in `alerts.c`, trivial `format_cb_*` in `format.c`).
- **Maintainer signal is unusually positive:** nicm HIMSELF floated a window-level
  "monitor-command like monitor-silence" on #5237 (closed 2026-08-06) — but with a
  reservation ("might not work so well"). Contribution flow is hand-apply-to-
  OpenBSD-CVS-and-close (only 7/last-100 PRs merged); minimalism/anti-app-specific
  is documented and strict.
- **Recommended FORM:** (a) native window aggregate format var(s) mirroring the
  alert flags [primary]; optionally (b) a `#{P:}` recipe in the manpage as a
  low-risk opener/fallback; NOT (c) a `monitor-command` option (heavier, and the
  one nicm doubted). Venue: GitHub issue first, referencing #5237 + #3064.
- **Generality strip:** `attention`/agent/`claude`/`sources`/`styles`/`channels`/
  `clearOnView` are ALL downstream — none is upstream material. `error` generalizes
  to plain exit-status arithmetic. Confirming this lets T3-T6 proceed as pure
  nixcfg refactors with zero "should this be upstream?" hesitation.

**Recommendation: CONDITIONAL GO** — prepare the proposal now (assessment + draft
issue), but GATE actual submission on tmux 3.8 shipping (build on released
pane-level vars first); submit as a narrow window-aggregate patch stripped of all
Nix/agent concepts. Open questions to resolve before submitting: exit-status
aggregation semantics (recommend boolean-running-only first), per-session
(`winlink`) vs per-window scope, timing gate on 3.8, and the modest value ceiling
(saves a `#{P:}` fold, doesn't unlock the impossible). Full detail + draft problem
statement + C-style/precedent notes in the assessment doc.

**Impact on T2 sign-off:** NO schema change required. T7 finds the frozen T2 spec
already correctly scoped as a Nix abstraction over tmux primitives. One
forward-looking note (not a change): keep the aggregation behind the shared-lib
`mkFold` generator (already the D2/T4 design) so that IF the upstream
`#{window_command_running}` aggregate ever lands, T4's `#{P:}` fold collapses to
that single native var in one place. This vindicates the existing seam.

**DECISION (Tim, 2026-08-17): CONDITIONAL GO.** T7 COMPLETE. Prepare the upstream
proposal now (this assessment + a draft GitHub issue against #5237/#3064 + a later
`format.c` patch mirroring the alert-flag machinery), but GATE actual submission on
tmux 3.8 shipping (build on the released pane-level vars first). Submit as a narrow
`#{window_command_running}` window-aggregate patch stripped of all Nix/agent/
attention concepts. Open questions to settle before submitting (from assessment §6):
exit-status aggregation semantics (ship boolean-running-only first), per-session
(`winlink`) vs per-window scope, the 3.8 timing gate, and the modest value ceiling.

**STILL AWAITING Tim:** explicit T2 sign-off. T7 found NO schema change is required
(the frozen T2 spec is correctly scoped), so this is a formality — Tim's "go" on T2
marks it COMPLETE and unblocks T3.

### T8 — Upstream contribution: window-level command aggregate `TASK:PENDING` (Phase 2 — BLOCKED/gated)

**Depends on: T3-T6 all COMPLETE, AND tmux 3.8 released.** Until BOTH hold this task
yields BLOCKED-BY-DEP (T3-T6 not done) or ENVIRONMENT_NOT_CAPABLE (tmux 3.8 not yet
released — local is 3.6a; latest tag 3.7c as of 2026-08-17; the OSC 133 pane-level
work is in `master`, unreleased). Do NOT attempt it or invent a workaround before
both conditions hold. **This is the LAST task in the plan by design (Tim: upstream
after local).**

Execute the CONDITIONAL GO from T7 (full detail in
`docs/tmux-upstream-contribution-assessment.md`):
1. Open a GitHub issue on tmux/tmux referencing #5237 (the 3.8 OSC 133 thread where
   nicm floated a window-level aggregate) and #3064 (OSC 133 origin), framed as the
   minimal completion of the shipped per-pane work: there is no window-level rollup
   the way `window_activity/bell/silence_flag` aggregate per-pane monitor state. Use
   the draft problem statement in the assessment doc §5.
2. Prepare a `format.c` patch adding `#{window_command_running}` (boolean "any pane
   running" first — defer any exit-status rollup), maintained alongside the
   `WINDOW_*`/`WINLINK_*` alert-flag machinery in `alerts.c` (assessment §3-§4).
   Match KNF/`style(9)`: `format_cb_*` callback + alphabetized `format_table[]` row.
3. Strip every app-specific concept (no agent/claude/attention). Resolve the open
   questions in assessment §6 (aggregation semantics; per-session vs per-window
   scope) BEFORE submitting.

**DoD:** a GitHub issue opened + a patch prepared (PR or mailing-list) matching tmux
norms; both referenced back in this task block. **Interactive:** confirm the final
submission with Tim before posting anything to the tmux project.

## Follow-up plan (from T2/D1) — CREATED
- **osc133 backend migration** (deferred by D1) is scaffolded as
  **`.claude/user-plans/051-tmux-osc133-backend.md`** (Status: PLANNING, blocked on
  this plan completing). It covers: pin a tmux >= 3.8 build, add a per-shell OSC-133
  emitter (or delegate to the user's prompt tool), implement the `backend="osc133"`
  source term (`#{pane_command_running}`/`#{pane_command_status}`) behind the seam
  T3-T6 leave in place, and make `backend` a real dual switch. Do NOT start it until
  this plan (050) is COMPLETE — 051 depends on the `hooks` backend + the abstract
  state-provider seam landing here first.

## Non-blocking pending items (carried over)
- **Pick `commandStatus.style` default** (currently `background`). Preview tool at
  `/tmp/tmux-cmdstyle-preview <name>` (temp; regenerate if gone) against the
  `cmdstyle-demo` tmux session (temp). `attention` always blinks regardless.
- **Durability**: push the 6 unpushed commits + `nix flake update nixcfg` in
  `~/src/nixcfg-work` so a plain switch keeps them. github.com push works now
  (Tim trusts it in GlobalProtect); use `GH_TOKEN=$(gh auth token) git push`.
- **Optional**: leading-gap before `status-right` so the battery `█` isn't glued
  to the last window (cosmetic; the "block after rs485dma" was the battery, not a
  bug). Optional `prefix + C` binding to clear all `@cmd_state` markers.
- **WT rendering**: do NOT need `forceFullRepaint` (that earlier theory was
  wrong; the stray block was the battery indicator).

## Guardrails
Serialize all nix. No AI attribution. `dev-switch -d` for the iteration loop
(no push per tweak). The pre-commit hook runs `nix flake check` only when `.nix`
is staged (~6 min); `.md`/script-only commits skip it.
