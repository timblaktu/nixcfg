# modules/lib/tmux-cmd-state.nix
#
# Shared per-pane tmux command-status helper (plan 050 T3). This is the SINGLE
# writer of the per-pane @cmd_state user option that programs.tmux.commandStatus
# renders. It replaces FOUR hand-duplicated copies of the same set/clear/active-
# suppression logic that had accreted across the config:
#   - zsh precmd/preexec         (modules/programs/tmux/tmux.nix)
#   - bash DEBUG/PROMPT_COMMAND   (modules/programs/tmux/tmux.nix)
#   - fish preexec/postexec       (modules/programs/tmux/tmux.nix)
#   - claude-code tmuxStateScript (modules/programs/claude-code/_hm/hooks.nix)
#
# Imported by BOTH the tmux module and the claude-code module (no cross-`config`
# reads - this is the shared-lib seam from plan 050 decision D2):
#
#   let tmuxCmdState = import ../../lib/tmux-cmd-state.nix { inherit pkgs lib; };
#   in  tmuxCmdState.mkHelper { }          # -> the tmux-cmd-state derivation
#
# State is PER-PANE (`set -p @cmd_state`), addressed via $TMUX_PANE, per the
# frozen T2 spec (invariant #1). For single-pane windows this renders identically
# to the previous per-window (`set -w`) implementation; multi-pane aggregation to
# the window entry via the native `#{P:}` fold is added in T4. clearOnView states
# (attention/error/done) are suppressed on the ACTIVE window - you are already
# looking at it, so no notification marker is needed. No-op when not inside tmux.
#
# Later tasks grow this file: T4 added `mkFold` (the `#{P:}` priority-fold + clear
# predicate generator, below); T5 adds `mkProgramSource` (event->state maps for
# per-program sources).
{ pkgs, lib ? pkgs.lib }:
rec {
  # Canonical state-name set - the single source of truth shared by every
  # consumer (shell sources, per-program sources, the format fold in T4).
  # Priority order (highest first) is documented in the frozen T2 spec:
  # attention:30 > error:25 > running:20 > done:10.
  stateNames = [ "attention" "error" "running" "done" ];

  # States that clear when the containing window is viewed (decision D3). Drives
  # both the helper's active-window suppression below and (T4) the generated
  # clear predicate. `running` is intentionally absent - a command in flight
  # stays marked even while you watch it.
  clearOnViewStates = [ "attention" "error" "done" ];

  # Canonical priority order (higher wins the window entry when panes carry
  # different states). Single source of truth for the fold generator below -
  # attention:30 > error:25 > running:20 > done:10 (frozen T2 spec). Adding /
  # renaming / reprioritising a state is a one-place edit here.
  statePriority = { attention = 30; error = 25; running = 20; done = 10; };

  # The ONE writer. `tmux-cmd-state <state>`:
  #   running                 -> set unconditionally (a command is in flight)
  #   attention|error|done    -> set on a BACKGROUND window; on the ACTIVE window
  #                              clear instead (you are viewing it - no marker)
  #   clear | "" (no arg)     -> unset the marker
  # Resolves tmux from PATH (`command -v tmux`) so it talks to the pane's own
  # running server, not whatever tmux happens to be in the store closure. No-op
  # when $TMUX / $TMUX_PANE are unset, so it is harmless outside tmux.
  mkHelper = _:
    let
      # case-pattern generated from the state set, so adding/renaming a
      # clearOnView state is a one-line edit here - never a hand-edited case arm.
      clearPattern = lib.concatStringsSep "|" clearOnViewStates;
    in
    pkgs.writeShellApplication {
      name = "tmux-cmd-state";
      runtimeInputs = [ ]; # tmux is resolved at runtime from the pane's PATH.
      text = ''
        [ -n "''${TMUX:-}" ] && [ -n "''${TMUX_PANE:-}" ] || exit 0
        t="$(command -v tmux 2>/dev/null)" || exit 0
        state="''${1:-}"

        _set()    { "$t" set-option -p  -t "$TMUX_PANE" @cmd_state "$1" 2>/dev/null || true; }
        _unset()  { "$t" set-option -up -t "$TMUX_PANE" @cmd_state     2>/dev/null || true; }
        _redraw() { "$t" refresh-client -S 2>/dev/null || true; }
        _window_active() { [ "$("$t" display -p -t "$TMUX_PANE" '#{window_active}' 2>/dev/null)" = 1 ]; }

        case "$state" in
          clear|"")
            _unset ;;
          ${clearPattern})
            if _window_active; then _unset; else _set "$state"; fi ;;
          *)
            _set "$state" ;;
        esac
        _redraw
      '';
    };

  # mkFold { styles } — generate the two native-format artifacts T4 needs from the
  # ONE declared state set, so adding/renaming/reprioritising a state never means
  # hand-editing a nested #{?} or a literal clear predicate again:
  #
  #   .styleExpr      the #{P:} priority-fold consumed by window-status-format. For
  #                   each state (highest priority first) it emits that state's
  #                   #[style] iff ANY pane in the window carries
  #                   @cmd_state == <state>. The per-pane test emits a sentinel char
  #                   folded through the SINGLE-ARG #{P:} pane-loop (the two-arg form
  #                   special-cases the active pane, which we do NOT want for an "any
  #                   pane" reduction); the surrounding #{!=:...,} is true iff the
  #                   fold produced any sentinel. This aggregates a BACKGROUND pane's
  #                   state up to the one-per-window entry - the multi-pane case the
  #                   T3 active-pane-only read could not express.
  #
  #   .clearPredicate  `if -F "<cond>" "set -up @cmd_state"`, true when the pane's
  #                   own @cmd_state is a clearOnView state (attention/error/done).
  #                   Used by after-select-window / pane-focus-in / the nav-key binds
  #                   to clear the VIEWED pane. This is deliberately a per-pane read
  #                   (bare #{@cmd_state}), NOT a #{P:} fold: decision D3 clears the
  #                   pane you looked at, never the whole window.
  #
  # `styles` is an attrset name -> tmux style string (e.g. "bg=colour214 fg=colour16
  # bold") and MUST cover every stateName. priority + clearOnView are read from this
  # lib's canonical metadata, so the caller only supplies the palette.
  mkFold = { styles }:
    let
      byPriority = lib.sort (a: b: statePriority.${a} > statePriority.${b}) stateNames;
      # highest-priority arm outermost; each arm is self-balanced (#{?c,t,e}).
      mkArm = name: inner:
        "#{?#{!=:#{P:#{?#{==:#{@cmd_state},${name}},x,}},},#[${styles.${name}}],${inner}}";
      styleExpr = lib.foldr mkArm "" byPriority;
      # OR the clearOnView states: @cmd_state == <state> -> 1, else fall through to 0.
      mkClearArm = name: inner: "#{?#{==:#{@cmd_state},${name}},1,${inner}}";
      clearCond = lib.foldr mkClearArm "0" clearOnViewStates;
      clearPredicate = ''if -F "${clearCond}" "set -up @cmd_state"'';
    in
    { inherit styleExpr clearPredicate; };

  # The `clear` pseudo-target — NOT a renderable state, so it is absent from
  # stateNames / statePriority / any fold arm. It unconditionally UNSETS the pane's
  # @cmd_state (the writer's `clear|""` case), returning the pane to its original
  # style. A program source maps it to an event meaning "this program is now idle /
  # ready" so a long-lived foreground app can retract a `running` the shell's
  # preexec set on launch (the shell's precmd never fires while the app holds the
  # foreground, so only the app itself can clear it). Unlike the clearOnView states
  # it clears REGARDLESS of window focus - "idle" is idle whether or not you are
  # looking at it. Distinct from the "done" marker, which is a background completion
  # NOTIFICATION that lingers until viewed.
  clearTarget = "clear";

  # Valid targets a program source may map an event to: every renderable state plus
  # the `clear` pseudo-target. mkProgramSource validates against THIS (not bare
  # stateNames) so `SessionStart = "clear"` is accepted while a typo still throws.
  sourceTargets = stateNames ++ [ clearTarget ];

  # mkProgramSource { events } — the D9/T5 per-program source generator. A program
  # declares its native-event -> target map (e.g. CC's `UserPromptSubmit = "running"`
  # or `SessionStart = "clear"`), and this returns the shell command each event
  # should run: a call to the ONE shared `tmux-cmd-state` writer. The program then
  # folds `.commands` into its OWN native hook mechanism (CC: mkHook/mergeHookSets;
  # nvim: autocmds; etc.) - the tiny last-mile adapter into each event system is
  # irreducible and lives in that program's module, but the TARGET (the single sink)
  # and the DECLARATION SHAPE (`events = { ev = state; }`) are unified here.
  #
  #   .commands   attrset <nativeEvent> -> "<tmux-cmd-state>/bin/tmux-cmd-state <target>"
  #
  # Every mapped target is validated against `sourceTargets` (stateNames + `clear`)
  # at eval time, so a typo (`"runing"`) is a build-time throw naming the offending
  # event, not a silent no-op marker that never renders.
  mkProgramSource = { events }:
    let
      bin = "${mkHelper { }}/bin/tmux-cmd-state";
      toCommand = ev: target:
        if lib.elem target sourceTargets then "${bin} ${target}"
        else
          throw ("tmux-cmd-state.mkProgramSource: event '" + ev
            + "' maps to unknown target '" + target + "' (valid targets: "
            + lib.concatStringsSep ", " sourceTargets + ")");
    in
    { commands = lib.mapAttrs toCommand events; };
}
