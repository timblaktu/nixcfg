# modules/programs/tmux/tmux.nix
# Tmux configuration for all platforms
#
# Provides:
#   flake.modules.homeManager.tmux - Full tmux config with plugins, keybindings, auto-reload
#   flake.modules.nixos.tmux - Basic system-level tmux defaults
#   flake.modules.darwin.tmux - Basic system-level tmux defaults
#
# Features:
#   - Vi-style keybindings with smart vim/tmux navigation
#   - Multiple color scheme options (classic, subtle, high-contrast, etc.)
#   - Responsive status bar with CPU/RAM monitoring
#   - Nested session support (F12 toggle)
#   - Session persistence with resurrect + continuum
#   - Auto-reload on home-manager generation change
#   - Session picker with fzf integration
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.tmux ];
{ config, lib, inputs, ... }:
let
  # Library files for scripts (shared from shell-utils)
  libPath = ../../.. + "/modules/programs/shell-utils/files/lib";
in
{
  flake.modules = {
    # === Home Manager Module ===
    # Full tmux configuration for user environment
    homeManager.tmux = { config, pkgs, lib, ... }:
      let
        # ---- COLOR SCHEME SELECTOR ----
        # Change this to experiment with different status bar color schemes
        # Options: "default" | "classic" | "subtle" | "high-contrast" | "solarized" | "minimal" | "balanced"
        colorScheme = "classic";

        # Width thresholds
        narrowWidth = "60";
        mediumWidth = "100";
        wideWidth = "140";

        # ---- COLOR SCHEME DEFINITIONS ----
        colorSchemes = {
          # Original monochrome scheme
          default = {
            style_normal = "fg=colour7,bg=colour0";
            style_nested = "fg=colour7,bg=colour8";
            style_current_window = "fg=colour7,bold,bg=colour10";
            lock_closed = "fg=colour7,bg=colour0";
            lock_open = "fg=colour7,bg=colour0";
            status_left_style = "fg=colour7,bg=colour0";
            status_right_style = "fg=colour7,bg=colour0";
          };

          # Classic - nearly identical to original with minimal differentiation
          classic = {
            style_normal = "fg=colour7,bg=colour0";
            style_nested = "fg=colour7,bg=colour8";
            style_current_window = "fg=colour7,bold,bg=colour10";
            lock_closed = "fg=colour7,bg=colour0";
            lock_open = "fg=colour7,bg=colour0";
            status_left_style = "fg=colour15,bg=colour0";
            status_right_style = "fg=colour244,bg=colour0";
          };

          # Scheme 1: Subtle Professional - muted colors with gentle differentiation
          subtle = {
            style_normal = "fg=colour252,bg=colour235";
            style_nested = "fg=colour252,bg=colour237";
            style_current_window = "fg=colour16,bold,bg=colour75";
            lock_closed = "fg=colour208,bg=colour235";
            lock_open = "fg=colour117,bg=colour235";
            status_left_style = "fg=colour117,bg=colour235";
            status_right_style = "fg=colour228,bg=colour235";
          };

          # Scheme 2: High Contrast - maximum clarity with strong visual separation
          high-contrast = {
            style_normal = "fg=colour255,bg=colour233";
            style_nested = "fg=colour255,bg=colour236";
            style_current_window = "fg=colour16,bold,bg=colour51";
            lock_closed = "fg=colour196,bg=colour233";
            lock_open = "fg=colour46,bg=colour233";
            status_left_style = "fg=colour46,bold,bg=colour233";
            status_right_style = "fg=colour226,bold,bg=colour233";
          };

          # Scheme 3: Solarized-Inspired - warm, comfortable colors
          solarized = {
            style_normal = "fg=colour244,bg=colour235";
            style_nested = "fg=colour244,bg=colour237";
            style_current_window = "fg=colour235,bold,bg=colour166";
            lock_closed = "fg=colour160,bg=colour235";
            lock_open = "fg=colour33,bg=colour235";
            status_left_style = "fg=colour33,bg=colour235";
            status_right_style = "fg=colour64,bg=colour235";
          };

          # Scheme 4: Minimal Modern - clean design with strategic highlights
          minimal = {
            style_normal = "fg=colour248,bg=colour234";
            style_nested = "fg=colour248,bg=colour236";
            style_current_window = "fg=colour255,bold,bg=colour127";
            lock_closed = "fg=colour203,bg=colour234";
            lock_open = "fg=colour248,bg=colour234";
            status_left_style = "fg=colour248,bg=colour234";
            status_right_style = "fg=colour51,bg=colour234";
          };

          # Scheme 5: Balanced Contrast - optimal balance (recommended)
          balanced = {
            style_normal = "fg=colour250,bg=colour235";
            style_nested = "fg=colour250,bg=colour237";
            style_current_window = "fg=colour16,bold,bg=colour214";
            lock_closed = "fg=colour203,bg=colour235";
            lock_open = "fg=colour117,bg=colour235";
            status_left_style = "fg=colour117,bg=colour235";
            status_right_style = "fg=colour156,bg=colour235";
          };
        };

        # Select active color scheme
        activeScheme = colorSchemes.${colorScheme};

        # Shared per-pane command-status helper (plan 050 T3). The SINGLE writer
        # of the @cmd_state marker - imported from modules/lib so the tmux and
        # claude-code modules share ONE implementation (no cross-config reads).
        # Replaces the previously-duplicated set/clear logic in the three shell
        # hook blocks below (and CC's tmuxStateScript).
        tmuxCmdState = import ../../lib/tmux-cmd-state.nix { inherit pkgs lib; };
        tmuxCmdStatePkg = tmuxCmdState.mkHelper { };
        cmdStateBin = "${tmuxCmdStatePkg}/bin/tmux-cmd-state";

        # Fixed conditional logic using >= comparisons instead of < to avoid nesting issues
        cpuRamSection = "#{?#{>=:#{client_width},${mediumWidth}},#(tmux-cpu-mem wide),#{?#{>=:#{client_width},${narrowWidth}},#(tmux-cpu-mem medium),#(tmux-cpu-mem narrow)}}";

        batterySection = "#(tmux-battery)";

        # Status bar components - pointer char only shown when nested
        pointerChar = "→";
        statusLeft = "#[''$lock_open]#(pgrep tmux | wc -l | awk '$1 > 1 {print \"${pointerChar}\"}')#[''$style_normal]#{=10;p10:host_short} %b %d %T";
        statusRight = "${batterySection} ${cpuRamSection}";

        # ---- COMMAND-STATUS WINDOW STYLING ----
        # Per-window command lifecycle indicator, driven by the shell preexec/precmd
        # hooks (see the commandStatus config block) which set the @cmd_state window
        # option. Styling is done with NATIVE tmux #{?} conditionals (not from #()
        # shell output) so it repaints on every redraw - #() job output is cached on
        # tmux's async cycle and would not reliably reflect a reverted state.
        #   running -> emphasized (command in flight)
        #   done    -> completion marker (cleared to original when the window is selected)
        #   unset   -> original
        # Selectable presets (programs.tmux.commandStatus.style). Each preset gives
        # three states. Amber = running/working, magenta+blink = attention (a
        # long-running app - e.g. Claude Code - wants input; see the CC tmuxStatus
        # hooks), green = done. Space-separated attrs (NOT commas) so they don't
        # clash with the #{?,} conditional separators.
        # Each preset supplies a style for every declared state (attention, error,
        # running, done - the lib's stateNames). `error` (colour196, added T4) marks
        # a command that finished non-zero; no producer sets it yet (a T5 sources
        # concern) so its arm is present but zero-cost until then.
        cmdStateStyles = {
          italic = { running = "fg=colour214 bold italics"; done = "italics"; error = "fg=colour196 bold italics"; attention = "fg=colour201 bold italics blink"; };
          color = { running = "fg=colour214 bold"; done = "fg=colour46 bold"; error = "fg=colour196 bold"; attention = "fg=colour201 bold blink"; };
          reverse = { running = "fg=colour214 bold reverse"; done = "fg=colour46 bold reverse"; error = "fg=colour196 bold reverse"; attention = "fg=colour201 bold reverse blink"; };
          background = { running = "bg=colour214 fg=colour16 bold"; done = "bg=colour34 fg=colour16 bold"; error = "bg=colour196 fg=colour16 bold"; attention = "bg=colour201 fg=colour16 bold blink"; };
          blink = { running = "fg=colour214 bold"; done = "bg=colour34 fg=colour16 bold blink"; error = "bg=colour196 fg=colour16 bold blink"; attention = "bg=colour201 fg=colour16 bold blink"; };
        };
        activeCmdStyle = cmdStateStyles.${config.programs.tmux.commandStatus.style};
        # T4: both the styling conditional and the clear predicate are now GENERATED
        # from the one declared state set by the shared lib's mkFold (no hand-written
        # nested #{?} / literal predicate). styleExpr is a #{P:} priority-fold that
        # aggregates EVERY pane's @cmd_state up to the window entry (fixes the T3
        # active-pane-only gap); clearPredicate clears the viewed pane's marker.
        cmdFold = tmuxCmdState.mkFold { styles = activeCmdStyle; };
        # Window entry = command-status style prefix + index/name, rendered with PURE
        # NATIVE tmux format ops (ZERO per-window shell-outs). This replaced the former
        # `#(tmux-window-status-format ...)` #() job, which forked a bash process
        # (sourcing the ~680-line general-utils.bash) once PER WINDOW PER REDRAW. At
        # high window counts that batch of forks re-cycling every status-interval
        # flickered the whole status bar under tmux 3.7b (which redraws on each #() job
        # completion); the native form is fork-free and immune regardless of window
        # count or tmux version.
        #
        # supDigit / windowIndexSuperscript: render the window index's ONES digit as a
        # Unicode superscript (10 -> ⁰, 11 -> ¹, ...). `#{=/-1/:...}` takes the last
        # digit; the nested `#{s/D/superscript/g:...}` chain (one arm per decimal digit,
        # generated by the fold) maps it. Digit order is irrelevant (a single 0-9 char,
        # exactly one arm fires); folded 0..9 so s/0 is outermost.
        supDigit = { "0" = "⁰"; "1" = "¹"; "2" = "²"; "3" = "³"; "4" = "⁴"; "5" = "⁵"; "6" = "⁶"; "7" = "⁷"; "8" = "⁸"; "9" = "⁹"; };
        windowIndexSuperscript =
          lib.foldr (d: acc: "#{s/${d}/${supDigit.${d}}/g:${acc}}")
            "#{=/-1/:#{window_index}}"
            [ "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" ];
        # Compact entry: superscript index immediately followed by the width-tiered
        # truncated name (8 / 12 / 16 chars at client_width <80 / <120 / else -
        # matching the retired script's NIX_TMUX_SMALL_TERM=80 / MEDIUM_TERM=120).
        windowNameFormat =
          "#{?#{<:#{client_width},80},${windowIndexSuperscript}#{=/8:#{window_name}}"
          + ",#{?#{<:#{client_width},120},${windowIndexSuperscript}#{=/12:#{window_name}}"
          + ",${windowIndexSuperscript}#{=/16:#{window_name}}}}";
        windowStatusFormat = "${cmdFold.styleExpr}${windowNameFormat}#[default]";
        # Command run when a window/pane is navigated to: clear the clearOnView
        # markers (attention/error/done) so a viewed pane returns to its original
        # style (running is left untouched). Unsets the PER-PANE option (set -up) to
        # match tmux-cmd-state's per-pane writer (T3); the predicate reads the
        # viewed pane's own @cmd_state.
        cmdStateClearOnSelect = cmdFold.clearPredicate;
      in
      {
        options.programs.tmux = {
          autoReload.enable = lib.mkEnableOption "automatic tmux config reload on home-manager generation change";
          commandStatus = {
            enable =
              (lib.mkEnableOption "per-window command-running / command-complete status indicators driven by shell preexec/precmd hooks (running -> emphasized, done -> completed marker cleared when the window is navigated to)")
              // { default = true; };
            style = lib.mkOption {
              type = lib.types.enum [ "italic" "color" "reverse" "background" "blink" ];
              default = "background";
              example = "reverse";
              description = ''
                Visual style for the per-window command-status indicator. Each option
                styles two states - running (a command is in flight, e.g. in another
                window) and done (it finished and hasn't been looked at yet, i.e. a
                little completion notification); "done" clears to the original style
                once you navigate to that window. Amber = running, green = done.

                - italic:     running = amber bold italics; done = italics only
                              (subtlest; needs a terminal/font that renders italics)
                - color:      running = bold amber text;    done = bold green text
                - reverse:    running = amber chip (reverse video); done = green chip
                - background: running = amber background;    done = green background
                - blink:      running = bold amber; done = green background, blinking
                              (most attention-grabbing; blink support is terminal-dependent)
              '';
            };

            # Plan 050 T5 (decisions D2+D9) — the `sources` model. Two kinds of feed
            # coexist here:
            #   * `shell` is a REAL generic source this module owns and installs:
            #     the zsh/bash/fish preexec/precmd lifecycle hooks that call the
            #     shared `tmux-cmd-state` writer. Toggle it independently of the
            #     whole indicator (e.g. to run ONLY the Claude Code source).
            #   * every other key is an OPTIONAL introspection registry: an
            #     `events = { <nativeEvent> = <state>; }` map giving ONE place to
            #     view a program's feed. NOTE (T5 refinement of D9): programs do
            #     NOT auto-populate this. A program module writing into another
            #     module's option requires that option to be DECLARED, but
            #     claude-code composes standalone (with upstream `programs.tmux`,
            #     which has no `commandStatus`), so an auto-publish breaks that eval
            #     ("option does not exist") and an mkIf guard does not suppress it.
            #     The source of truth stays each program's own namespace
            #     (e.g. programs.claude-code.tmuxStatus.events); a host may mirror it
            #     here BY HAND for a unified view. Freeform `attrsOf (attrsOf str)`
            #     covers such maps; the declared `shell` option keeps its own type.
            sources = lib.mkOption {
              type = lib.types.submodule {
                freeformType = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
                options.shell.enable =
                  (lib.mkEnableOption "the generic shell (zsh/bash/fish) command-lifecycle source")
                  // { default = true; };
              };
              default = { };
              example = lib.literalExpression ''
                { shell.enable = true; claude-code = { UserPromptSubmit = "running"; Stop = "done"; }; }
              '';
              description = ''
                Command-status feeds. `sources.shell.enable` toggles the built-in
                shell lifecycle source (default on). Per-program keys are an
                optional, hand-set introspection registry (event -> state map);
                programs do NOT auto-populate them (see the note above) - each
                program's own namespace (e.g. programs.claude-code.tmuxStatus.events)
                is the source of truth.
              '';
            };
          };
        };

        config = lib.mkMerge [
          # Core tmux configuration
          {
            programs.tmux = {
              enable = lib.mkDefault true;

              # Basic configuration
              shortcut = "a";
              escapeTime = 1;
              baseIndex = 1;
              keyMode = "vi";
              mouse = true;
              historyLimit = 100000;
              aggressiveResize = true;
              # Focus reporting (DECSET 1004). Re-enabled 2026-08-17 after research.
              # HISTORY: disabled 2026-01-22 (ccd345b) + terminal-features focus:0
              # added 2026-01-26 (e1000d6) because Claude Code emitted `?1004h` but
              # mis-rendered the resulting ^[[I/^[[O focus sequences as visible garbage
              # in its input box on every window switch. That was a Claude Code bug
              # (issues #11391/#18363), CLOSED Jan 2026, fixed ~v2.0.67 - we run 2.1.191.
              # WHY RE-ENABLING IS SAFE: tmux only forwards ^[[I/^[[O to a pane whose
              # app itself enabled `?1004h` (the per-pane MODE_FOCUSON gate in tmux
              # window.c) - apps that don't opt in (btop, tio, less, shells) never see
              # them regardless. So the old global-off was a sledgehammer for one app's
              # bug. BENEFIT: restores neovim FocusGained/checktime autoread-on-refocus.
              # NOTE: our command-status "clear on pane view" does NOT rely on this -
              # it uses the focus-events-free window-pane-changed hook (see below).
              # Residual: CC #72067 (open) re-renders on focus-out -> looks like pane
              # activity to `monitor-activity` (off by default here), cosmetic only.
              focusEvents = true;

              # Shell configuration
              shell = if config.programs.zsh.enable then "${config.programs.zsh.package}/bin/zsh" else "${pkgs.bash}/bin/bash";

              extraConfig = ''
                # ╔═══════════════════════════════════════════════════════════════════════════════╗
                # ║  COLOR SCHEME EXPERIMENTATION                                                 ║
                # ║  To change the status bar color scheme:                                       ║
                # ║  1. Edit the 'colorScheme' variable at the top of this file (line 8)         ║
                # ║  2. Options: "default" | "classic" | "subtle" | "high-contrast" |             ║
                # ║              "solarized" | "minimal" | "balanced"                             ║
                # ║  3. Rebuild home-manager: home-manager switch --flake '.#TARGET'             ║
                # ║  4. Reload tmux config: Ctrl-a r                                              ║
                # ╚═══════════════════════════════════════════════════════════════════════════════╝

                # ---- ENVIRONMENT HANDLING ----
                set -g update-environment "DISPLAY SSH_ASKPASS SSH_AUTH_SOCK SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY GPG_TTY HOST_IP ADB_SERVER_SOCKET"
                setenv -g NIX_TMUX_SMALL_TERM 80
                setenv -g NIX_TMUX_MEDIUM_TERM 120
                setenv -g NIX_TMUX_LARGE_TERM 160

                set -g default-command "exec ${if config.programs.zsh.enable then "${config.programs.zsh.package}/bin/zsh" else "${pkgs.bash}/bin/bash"}"
              '' + ''
                # ---- TERMINAL AND COLOR SETTINGS ----
                set -g default-terminal "tmux-256color"
                set -ga terminal-overrides ",*256col*:Tc"
                set -ga terminal-overrides ",alacritty:Tc"
                set -ga terminal-overrides ",xterm-kitty:Tc"
                set -ga terminal-overrides ",*:bold=\\E[1m"
                set -ga terminal-overrides ",*:dim=\\E[2m"
                set -ga terminal-overrides ",*:smul=\\E[4m"
                set -ga terminal-overrides ",*:sitm=\\E[3m"
                # (Removed 2026-08-17: `terminal-features ",*:focus:0"`. It stripped
                # the focus capability so tmux never requested focus reports from the
                # terminal - which also blocks neovim's FocusGained. It was a
                # belt-and-suspenders companion to the old focusEvents=false; both are
                # undone together now that Claude Code no longer mis-renders ^[[I/^[[O.
                # See the focusEvents comment above for the full rationale.)
                set-hook -g client-resized 'refresh-client -S'

                # ---- PANE BORDER ----
                set -g pane-border-lines single
                set -g pane-border-style 'fg=colour238'
                set -g pane-active-border-style 'fg=colour51,bold'
                set -g pane-border-status top
                set -g pane-border-format "#{?pane_active,#[fg=colour51 bold],#[fg=colour238]}"

                # ---- WINDOW MANAGEMENT ----
                set -g renumber-windows on
                set -g bell-action any
                set -g visual-bell off
                set -g set-titles on
                setw -g allow-rename off
                setw -g automatic-rename off
                setw -g pane-base-index 1

                # ---- PREFIX CONFIGURATION ----
                bind C-a send-prefix

                # ---- KEY BINDINGS ----
                bind r source-file ~/.config/tmux/tmux.conf \; display-message -d1000 "Reloaded tmux config"

                # Pane splitting
                bind | split-window -h -c "#{pane_current_path}"
                bind - split-window -v -c "#{pane_current_path}"
                bind v split-window -h -c "#{pane_current_path}"

                # Window navigation (append the command-status clear so navigating
                # via these keys also resets a "done" marker, like select-window does)
                bind l last-window \; ${cmdStateClearOnSelect}
                bind-key -n M-h previous-window \; ${cmdStateClearOnSelect}
                bind-key -n M-l next-window \; ${cmdStateClearOnSelect}

                # Window reordering - use prefix-based bindings (more reliable in Windows Terminal)
                bind-key < swap-window -t -1\; select-window -t -1
                bind-key > swap-window -t +1\; select-window -t +1

                # Pane resizing
                bind-key -r j resize-pane -D
                bind-key -r k resize-pane -U
                bind-key -r h resize-pane -L
                bind-key -r l resize-pane -R

                # Synchronize panes toggle
                bind s set -w synchronize-panes

                # Monitor activity toggle
                bind m set -w monitor-activity

                # Copy mode bindings
                bind-key -T copy-mode-vi v send -X begin-selection
                bind-key -T copy-mode-vi y send -X copy-selection-and-cancel

                # ---- VIM INTEGRATION (Smart Pane Navigation) ----
                # %hidden required since tmux 3.5+ (bare variable assignments are syntax errors)
                %hidden is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?''$'"
                bind-key -n 'C-h' if-shell "''$is_vim" 'send-keys C-h' 'select-pane -L'
                bind-key -n 'C-j' if-shell "''$is_vim" 'send-keys C-j' 'select-pane -D'
                bind-key -n 'C-k' if-shell "''$is_vim" 'send-keys C-k' 'select-pane -U'
                bind-key -n 'C-l' if-shell "''$is_vim" 'send-keys C-l' 'select-pane -R'
                bind-key -n 'C-\' if-shell "''$is_vim" 'send-keys C-\' 'select-pane -l'

                bind-key -T copy-mode-vi 'C-h' select-pane -L
                bind-key -T copy-mode-vi 'C-j' select-pane -D
                bind-key -T copy-mode-vi 'C-k' select-pane -U
                bind-key -T copy-mode-vi 'C-l' select-pane -R
                bind-key -T copy-mode-vi 'C-\' select-pane -l

                # ---- NESTED SESSION SUPPORT ----
                # %hidden required since tmux 3.5+ (bare variable assignments are syntax errors)
                %hidden style_normal="${activeScheme.style_normal}"
                %hidden style_nested="${activeScheme.style_nested}"
                %hidden style_current_window="${activeScheme.style_current_window}"
                %hidden lock_closed="${activeScheme.lock_closed}"
                %hidden lock_open="${activeScheme.lock_open}"

                # ---- STATUS BAR CONFIGURATION ----
                set -g status on
                set -g status-interval 1
                set -g status-style "''$style_normal"
                set -g @narrow_width ${narrowWidth}
                set -g @medium_width ${mediumWidth}
                set -g @wide_width ${wideWidth}
                set -g status-left-style "${activeScheme.status_left_style}"
                set -g status-left-length 48
                set -g status-left "${statusLeft}"
                set -g status-right-style "${activeScheme.status_right_style}"
                set -g status-right-length 80
                set -g status-right "${statusRight}"

                # ---- WINDOW CONFIG
                setw -g window-status-style "''$style_normal"
                setw -g window-status-current-style "''$style_current_window"
                setw -g window-status-format '${windowStatusFormat}'
                setw -g window-status-current-format '${windowStatusFormat}'
                set -g status-justify centre
                set -g visual-activity on

                # ---- COMMAND-STATUS: reset clearOnView markers on navigation (D3) ----
                # Clears the VIEWED pane's attention/error/done marker (per-pane, not
                # the whole window). Two legs, NEITHER of which needs focus-events (D3,
                # refined 2026-08-17 after the focus-events research - see the
                # focusEvents comment above):
                #   after-select-window - fires on window (tab) switches: select-window
                #     (prefix-N, choose-tree, mouse, the swap </> binds); clears the
                #     newly-active window's active pane.
                #   window-pane-changed - fires on ACTIVE-PANE changes WITHIN a window:
                #     select-pane (incl. the C-h/j/k/l vim-nav binds), mouse click on a
                #     pane, last-pane, and split-window. Fired from tmux's core
                #     window_set_active_pane() - independent of focus-events (verified
                #     against tmux source), so it works with focusEvents on OR off and
                #     never depends on the terminal delivering focus reports. In the
                #     hook body #{@cmd_state}/`set -up` resolve to the just-entered
                #     (now-active) pane. Strictly more complete than after-select-pane
                #     (which misses last-pane + splits).
                # next/previous/last-window are separate commands, so their bindings
                # (above) append the same clear explicitly.
                set-hook -g after-select-window '${cmdStateClearOnSelect}'
                set-hook -g window-pane-changed '${cmdStateClearOnSelect}'

                # ---- NESTED SESSION TOGGLE (F12) ----
                bind -T root F12 \
                  set prefix None \;\
                  set key-table off \;\
                  set -g status-left "#[''$lock_closed] #[''$style_normal]#{=10;p10:host_short} %b %d %T" \;\
                  send-keys C-a N \;\
                  if -F '#{pane_in_mode}' 'send-keys -X cancel' \;\
                  refresh-client -S

                bind -T off F12 \
                  set -u prefix \;\
                  set -u key-table \;\
                  set -g status-left "#[''$lock_open]#(pgrep tmux | wc -l | awk '$1 > 1 {print \"${pointerChar}\"}')#[''$style_normal]#{=10;p10:host_short} %b %d %T" \;\
                  send-keys C-a O \;\
                  refresh-client -S

                # ---- SPECIALIZED BINDINGS ----
                set-hook -g client-detached 'run-shell "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/save.sh > /dev/null 2>&1; tmux-resurrect-cleanup > /dev/null 2>&1"'
                set-hook -g session-closed 'run-shell "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/save.sh > /dev/null 2>&1; tmux-resurrect-cleanup > /dev/null 2>&1"'

                # Native session/window tree with big preview (25% tree, 75% preview)
                # Press 'v' at runtime to cycle: OFF → BIG → NORMAL
                bind-key w choose-tree -ZwNN

                # Session pickers
                bind-key t display-popup -E -w 95% -h 95% 'bash -c "tmux-session-picker --layout vertical"'
                bind-key T display-popup -E -w 95% -h 95% 'bash -c "tmux-session-picker --layout horizontal"'

                # Alternative legacy pickers
                bind-key M-T display-popup -E -w 80% -h 80% "tmux-resurrect-browse interactive"
                bind-key M-t run-shell "tmux-resurrect-browse list"

                # Bitbake logfile opener
                if-shell '[ -f "${config.home.homeDirectory}/bin/tmux-open-filename-in-current-pane" ]' \
                  "bind-key -n C-b run-shell \"${config.home.homeDirectory}/bin/tmux-open-filename-in-current-pane 'Logfile of failure stored in:'\""
              '';

              plugins = with pkgs.tmuxPlugins; [
                sensible
                yank
                {
                  plugin = resurrect;
                  extraConfig = ''
                    set -g @resurrect-dir '${config.home.homeDirectory}/.local/share/tmux/resurrect'
                    set -g @resurrect-save 'none'
                    set -g @resurrect-restore 'R'
                    set -g @resurrect-strategy-nvim 'session'
                    set -g @resurrect-strategy-vim 'session'
                    set -g @resurrect-capture-pane-contents 'on'

                    set -g @resurrect-processes '\
                        "~mosh *" \
                        "~wait4ssh *" \
                        "~tio *" \
                        "~myserial *" \
                        "~picocom *" \
                        "~connect_serial *" \
                        "~tail *" \
                        "~powershell.exe *" \
                        "~*loop *" \
                        "~claude" \
                        "~btop" \
                        "~bandwhich" \
                        "~iostat *" \
                        "~iotop-c" \
                        "~nload" \
                        "~gping *" \
                        "~dool *" \
                        "~iftop" \
                    '
                    # KNOWN LIMITATION (2026-04-07): dool will NOT auto-restore via
                    # tmux-resurrect. dool is a Python script, so its pane process
                    # appears as `python3`, and the "~dool *" pattern above never
                    # matches. We deliberately do NOT use "~python3 *" — too broad,
                    # would restore unrelated python tools. dool only runs in the
                    # monitoring dashboard's `extra` window (see
                    # modules/programs/monitoring/monitoring.nix), so the impact is
                    # limited to that one pane after a restore. Re-launch manually
                    # with `dool` if needed.

                    set -g @resurrect-save-command-strategy 'tmux-resurrect-cleanup'
                    bind-key S run-shell "tmux-save-with-rename"
                  '';
                }
                {
                  plugin = continuum;
                  extraConfig = ''
                    set -g @continuum-restore 'on'
                    set -g @continuum-save-interval '5'
                  '';
                }
              ];
            };

            # Install tmux-auto-attach to ~/bin/ (sourced by shell.nix, not an executable command)
            home.file."bin/tmux-auto-attach" = {
              source = ./files/tmux-auto-attach;
              executable = true;
            };

            # Create persistent directory for tmux-resurrect saves
            home.file.".local/share/tmux/resurrect/.keep" = {
              text = ''
                # This file ensures the resurrect directory exists
                # tmux-resurrect saves will be stored here and persist across home-manager switches
              '';
            };

            # Ensure system tools are available
            home.packages = with pkgs; [
              procps
              bc

              # Shared per-pane command-status writer (plan 050 T3). Installed on
              # PATH for interactive/keybinding use; the shell hooks and the CC
              # module reference it by store path.
              tmuxCmdStatePkg

              # Tmux session picker
              (
                let
                  baseScript = pkgs.writers.writeBashBin "tmux-session-picker" (
                    let
                      script = builtins.readFile ./files/tmux-session-picker;
                      terminalUtils = builtins.readFile (libPath + "/terminal-utils.bash");
                      colorUtils = builtins.readFile (libPath + "/color-utils.bash");
                      pathUtils = builtins.readFile (libPath + "/path-utils.bash");
                    in
                    builtins.replaceStrings
                      [
                        ''source "$HOME/.local/lib/terminal-utils.bash"''
                        ''source "$HOME/.local/lib/color-utils.bash"''
                        ''source "$HOME/.local/lib/path-utils.bash"''
                        "TMUX_RESURRECT_RESTORE_SCRIPT_NIX_PLACEHOLDER"
                        "TMUX_CONTINUUM_ENABLED_NIX_PLACEHOLDER"
                      ]
                      [
                        terminalUtils
                        colorUtils
                        pathUtils
                        "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/restore.sh"
                        "true"
                      ]
                      script
                  );
                  runtimeDeps = with pkgs; [ fzf tmux parallel python3 fd ripgrep ];
                in
                pkgs.symlinkJoin {
                  name = "tmux-session-picker";
                  paths = [ baseScript ];
                  buildInputs = [ pkgs.makeWrapper ];
                  postBuild = ''
                    wrapProgram $out/bin/tmux-session-picker \
                      --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps}
                  '';
                  passthru.tests = { };
                }
              )

              # Tmux session picker profiled version
              (pkgs.writeShellApplication {
                name = "tmux-session-picker-profiled";
                text = builtins.readFile ./files/tmux-session-picker-profiled;
                runtimeInputs = with pkgs; [ fzf tmux parallel python3 fd ripgrep time ];
              })

              # Tmux CPU/memory status display
              (pkgs.writeShellApplication {
                name = "tmux-cpu-mem";
                text = builtins.readFile ./files/tmux-cpu-mem;
                runtimeInputs = with pkgs; [ procps coreutils ];
              })

              # Tmux battery status display (reads WSL2-exposed sysfs)
              (pkgs.writeShellApplication {
                name = "tmux-battery";
                text = builtins.readFile ./files/tmux-battery;
                runtimeInputs = with pkgs; [ coreutils ];
              })

              # Tmux save with auto-rename
              (pkgs.writeShellApplication {
                name = "tmux-save-with-rename";
                text = builtins.replaceStrings
                  [ "TMUX_RESURRECT_SAVE_SCRIPT_NIX_PLACEHOLDER" ]
                  [ "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/save.sh" ]
                  (builtins.readFile ./files/tmux-save-with-rename);
                runtimeInputs = with pkgs; [ tmux ];
              })

              # Tmux test data generator
              (pkgs.writeShellApplication {
                name = "tmux-test-data-generator";
                text = builtins.readFile ./files/tmux-test-data-generator;
                runtimeInputs = with pkgs; [ coreutils ];
                passthru.tests = {
                  syntax = pkgs.runCommand "test-tmux-test-data-generator-syntax" { } ''
                    echo "✅ Syntax validation passed at build time" > $out
                  '';
                };
              })

              # Optimized tmux parser
              (pkgs.writeShellApplication {
                name = "tmux-parser-optimized";
                text = /* bash */ ''
                  #!/usr/bin/env bash
                  set -euo pipefail

                  if [[ $# -eq 0 ]]; then
                      echo "Usage: tmux-parser-optimized <resurrect_file> [current_session_file]" >&2
                      exit 1
                  fi

                  resurrect_file="$1"
                  current_session_file="''${2:-}"

                  if [[ ! -f "$resurrect_file" ]]; then
                      exit 1
                  fi

                  session_name=$(awk '/^session\t/ {print $2; exit}' "$resurrect_file" 2>/dev/null || echo "unknown")
                  window_count=$(grep -c "^window" "$resurrect_file" 2>/dev/null || echo "0")
                  pane_count=$(grep -c "^pane" "$resurrect_file" 2>/dev/null || echo "0")

                  basename=$(basename "$resurrect_file" .txt)
                  if [[ "$basename" =~ tmux_resurrect_([0-9]{8}_[0-9]{6}) ]]; then
                      timestamp="''${BASH_REMATCH[1]}"
                  else
                      timestamp="19700101_000000"
                  fi

                  summary="''${window_count}w/''${pane_count}p"

                  is_current="false"
                  if [[ -n "$current_session_file" && "$resurrect_file" == "$current_session_file" ]]; then
                      is_current="true"
                  fi

                  printf "%s\x1F%s\x1F%s\x1F%s\x1F%s\x1F%s\n" \
                      "$session_name" "$window_count" "$pane_count" "$timestamp" "$summary" "$is_current"
                '';
                runtimeInputs = with pkgs; [ coreutils gnugrep gawk ];
              })

              # Tmux resurrect cleanup script
              (pkgs.writers.writeBashBin "tmux-resurrect-cleanup" ''
                #!/usr/bin/env bash

                RESURRECT_DIR="${config.home.homeDirectory}/.local/share/tmux/resurrect"

                if [[ ! -d "$RESURRECT_DIR" ]]; then
                  exit 0
                fi

                # Resolve the 'last' symlink target so we never delete it
                LAST_FILE=""
                if [[ -L "$RESURRECT_DIR/last" ]]; then
                  LAST_FILE="$(readlink "$RESURRECT_DIR/last")"
                  # Handle both relative and absolute symlink targets
                  [[ "$LAST_FILE" != /* ]] && LAST_FILE="$RESURRECT_DIR/$LAST_FILE"
                fi

                # Delete small (empty/corrupt) files, but never the last-linked file or the symlink
                find "$RESURRECT_DIR" -name "tmux_resurrect_*.txt" -size -50c -print0 2>/dev/null \
                  | while IFS= read -r -d "" f; do
                      [[ "$f" -ef "''${LAST_FILE:-}" ]] && continue
                      rm -f "$f"
                    done

                # Delete files older than 30 days, but never the last-linked file
                find "$RESURRECT_DIR" -name "tmux_resurrect_*.txt" -mtime +30 -print0 2>/dev/null \
                  | while IFS= read -r -d "" f; do
                      [[ "$f" -ef "''${LAST_FILE:-}" ]] && continue
                      rm -f "$f"
                    done

                # Keep only the 50 most recent files, but never delete the last-linked file
                cd "$RESURRECT_DIR" 2>/dev/null || exit 0
                ls -t tmux_resurrect_*.txt 2>/dev/null | tail -n +51 | while IFS= read -r f; do
                  [[ "$RESURRECT_DIR/$f" -ef "''${LAST_FILE:-}" ]] && continue
                  rm -f "$f"
                done
              '')

              # Tmux resurrect session browser
              (pkgs.writers.writeBashBin "tmux-resurrect-browse" ''
                #!/usr/bin/env bash

                RESURRECT_DIR="$HOME/.local/share/tmux/resurrect"

                if [[ ! -d "$RESURRECT_DIR" ]]; then
                    echo "Error: tmux-resurrect directory not found at $RESURRECT_DIR"
                    exit 1
                fi

                current_file=""
                if [[ -L "$RESURRECT_DIR/last" ]]; then
                    current_file=$(basename "$(readlink -f "$RESURRECT_DIR/last")")
                fi

                list_sessions() {
                    echo "Available tmux resurrect sessions:"
                    echo "==================================="
                    echo

                    local i=1
                    for file in $(ls -t "$RESURRECT_DIR"/tmux_resurrect_*.txt 2>/dev/null); do
                        basename=$(basename "$file" .txt)
                        timestamp=''${basename#tmux_resurrect_}

                        year=''${timestamp:0:4}
                        month=''${timestamp:4:2}
                        day=''${timestamp:6:2}
                        hour=''${timestamp:9:2}
                        minute=''${timestamp:11:2}

                        formatted="$year-$month-$day $hour:$minute"

                        windows=$(grep -c "^window" "$file" 2>/dev/null || echo 0)
                        panes=$(grep -c "^pane" "$file" 2>/dev/null || echo 0)

                        marker=""
                        if [[ "$(basename "$file")" == "$current_file" ]]; then
                            marker=" [CURRENT]"
                        fi

                        printf "%2d) %s - %2d windows, %2d panes%s\n" \
                            "$i" "$formatted" "$windows" "$panes" "$marker"

                        ((i++))
                    done
                    echo
                    echo "Use: tmux-resurrect-browse restore <number> to restore a session"
                }

                restore_session() {
                    local session_num="$1"

                    if ! [[ "$session_num" =~ ^[0-9]+$ ]]; then
                        echo "Error: Please provide a valid session number"
                        list_sessions
                        exit 1
                    fi

                    local i=1
                    local target_file=""
                    for file in $(ls -t "$RESURRECT_DIR"/tmux_resurrect_*.txt 2>/dev/null); do
                        if [[ $i -eq $session_num ]]; then
                            target_file="$file"
                            break
                        fi
                        ((i++))
                    done

                    if [[ -z "$target_file" ]]; then
                        echo "Error: Session number $session_num not found"
                        list_sessions
                        exit 1
                    fi

                    echo "Setting session #$session_num to restore..."
                    ln -sf "$(basename "$target_file")" "$RESURRECT_DIR/last"

                    basename=$(basename "$target_file" .txt)
                    timestamp=''${basename#tmux_resurrect_}
                    year=''${timestamp:0:4}
                    month=''${timestamp:4:2}
                    day=''${timestamp:6:2}
                    hour=''${timestamp:9:2}
                    minute=''${timestamp:11:2}
                    echo "Selected: $year-$month-$day $hour:$minute"

                    if [[ -n "''${TMUX:-}" ]]; then
                        echo "Restoring session..."
                        tmux run-shell "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/restore.sh"
                        echo "Session restored!"
                    else
                        echo "Now run 'tmux' and press [Prefix+R] to restore the session"
                    fi
                }

                interactive_mode() {
                    clear
                    list_sessions
                    echo
                    echo "-----------------------------------"
                    echo "Enter session number to restore"
                    echo "Press 'q' or Ctrl-C to quit"
                    echo "-----------------------------------"
                    echo -n "Choice: "

                    read -r choice

                    if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
                        echo "Exiting..."
                        exit 0
                    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
                        restore_session "$choice"
                        echo
                        echo "Press any key to exit..."
                        read -n1 -r
                    else
                        echo "Invalid choice: $choice"
                        echo "Press any key to continue..."
                        read -n1 -r
                        interactive_mode
                    fi
                }

                case "''${1:-list}" in
                    list)
                        list_sessions
                        ;;
                    restore)
                        if [[ -z "''${2:-}" ]]; then
                            echo "Usage: $0 restore <session-number>"
                            echo
                            list_sessions
                            exit 1
                        fi
                        restore_session "$2"
                        ;;
                    interactive)
                        interactive_mode
                        ;;
                    *)
                        echo "Usage: $0 [list|restore <number>|interactive]"
                        exit 1
                        ;;
                esac
              '')
            ];
          }

          # Auto-reload on home-manager generation change
          (lib.mkIf config.programs.tmux.autoReload.enable {
            programs.zsh.initContent = lib.mkAfter ''
              # Auto-reload tmux config on home-manager generation change
              if [[ -n "$TMUX" ]]; then
                current_gen=$(readlink ~/.local/state/nix/profiles/home-manager 2>/dev/null)

                if [[ -n "$current_gen" ]]; then
                  session_id=$(tmux display-message -p '#{session_id}' 2>/dev/null)
                  gen_marker="/tmp/tmux-hm-gen-''${session_id}"

                  if [[ ! -f "$gen_marker" ]] || [[ "$(cat "$gen_marker" 2>/dev/null)" != "$current_gen" ]]; then
                    if mkdir "''${gen_marker}.lock" 2>/dev/null; then
                      tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null && \
                        echo "$current_gen" > "$gen_marker"
                      rmdir "''${gen_marker}.lock"
                    fi
                  fi
                fi
              fi
            '';

            programs.bash.initExtra = lib.mkIf config.programs.bash.enable (lib.mkAfter ''
              # Auto-reload tmux config on home-manager generation change
              if [[ -n "$TMUX" ]]; then
                current_gen=$(readlink ~/.local/state/nix/profiles/home-manager 2>/dev/null)

                if [[ -n "$current_gen" ]]; then
                  session_id=$(tmux display-message -p '#{session_id}' 2>/dev/null)
                  gen_marker="/tmp/tmux-hm-gen-''${session_id}"

                  if [[ ! -f "$gen_marker" ]] || [[ "$(cat "$gen_marker" 2>/dev/null)" != "$current_gen" ]]; then
                    if mkdir "''${gen_marker}.lock" 2>/dev/null; then
                      tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null && \
                        echo "$current_gen" > "$gen_marker"
                      rmdir "''${gen_marker}.lock"
                    fi
                  fi
                fi
              fi
            '');
          })

          # Per-window command lifecycle indicators.
          #
          # Shell hooks set a per-window @cmd_state user option on each command
          # boundary and force a status redraw with refresh-client -S:
          #   preexec  -> "running"  (a real command started; set regardless of focus
          #               so that switching away mid-command still shows it running)
          #   precmd   -> if this window is ACTIVE (you're looking at it) the marker is
          #               cleared to original - a completion in the window you're viewing
          #               needs no notification; if it's a BACKGROUND window it is set to
          #               "done" so you get a visual notification, cleared when you
          #               navigate to it.
          # Styling is applied by native #{?} conditionals in window-status-format
          # (see the let block / commandStatus.style). The "done" marker is also cleared
          # when the window is navigated to (after-select-window hook + nav-key binds).
          # The per-shell "ran" guard ensures shell startup and bare Enter presses do
          # NOT mark a window.
          #
          # Implemented for every shell this config might make interactive
          # (zsh / bash / fish), each guarded by its own enable flag, so the
          # indicator works regardless of which shell is selected.
          #
          # Plan 050 T5: this is the generic `shell` SOURCE. It is gated on
          # commandStatus.sources.shell.enable (default on) so it can be turned off
          # independently - e.g. to drive the indicator ONLY from per-program
          # sources like Claude Code - without disabling the whole indicator.
          (lib.mkIf
            (config.programs.tmux.commandStatus.enable
              && config.programs.tmux.commandStatus.sources.shell.enable)
            {
              programs.zsh.initContent = lib.mkIf config.programs.zsh.enable (lib.mkAfter ''
                # Tmux per-pane command status indicator (zsh preexec/precmd).
                # The shared tmux-cmd-state helper is the single writer (set/clear/
                # active-suppression + redraw all live there); the shell only owns
                # the "ran" guard so startup / bare-Enter do NOT mark a pane.
                if [[ -n "$TMUX" ]]; then
                  _tmux_cmd_ran=""
                  _tmux_cmd_preexec() { _tmux_cmd_ran=1; ${cmdStateBin} running; }
                  _tmux_cmd_precmd() {
                    [[ -n "$_tmux_cmd_ran" ]] || return   # only after a real command
                    _tmux_cmd_ran=""
                    ${cmdStateBin} done
                  }
                  autoload -Uz add-zsh-hook
                  add-zsh-hook preexec _tmux_cmd_preexec
                  add-zsh-hook precmd _tmux_cmd_precmd
                fi
              '');

              programs.bash.initExtra = lib.mkIf config.programs.bash.enable (lib.mkAfter ''
                # Tmux per-pane command status indicator (bash DEBUG trap + PROMPT_COMMAND).
                # The shared tmux-cmd-state helper is the single writer; the shell
                # owns only the first-command-of-line + "ran" guards.
                if [[ -n "$TMUX" ]]; then
                  _tmux_cmd_at_prompt=1
                  _tmux_cmd_ran=0
                  _tmux_cmd_preexec() {
                    [[ -n "$COMP_LINE" ]] && return                 # skip during completion
                    [[ "$BASH_COMMAND" == _tmux_cmd_postcmd* ]] && return
                    [[ "$_tmux_cmd_at_prompt" == 1 ]] || return     # only the first command of the line
                    _tmux_cmd_at_prompt=0
                    _tmux_cmd_ran=1
                    ${cmdStateBin} running
                  }
                  _tmux_cmd_postcmd() {
                    _tmux_cmd_at_prompt=1
                    [[ "$_tmux_cmd_ran" == 1 ]] || return           # only after a real command
                    _tmux_cmd_ran=0
                    ${cmdStateBin} done
                  }
                  trap '_tmux_cmd_preexec' DEBUG
                  case "$PROMPT_COMMAND" in
                    *_tmux_cmd_postcmd*) ;;
                    *) PROMPT_COMMAND="_tmux_cmd_postcmd''${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
                  esac
                fi
              '');

              programs.fish.interactiveShellInit = lib.mkIf config.programs.fish.enable (lib.mkAfter ''
                # Tmux per-pane command status indicator (fish preexec/postexec events).
                # The shared tmux-cmd-state helper is the single writer; the shell
                # owns only the "ran" guard.
                if set -q TMUX
                  function _tmux_cmd_preexec --on-event fish_preexec
                    set -g _tmux_cmd_ran 1
                    ${cmdStateBin} running
                  end
                  function _tmux_cmd_postexec --on-event fish_postexec
                    set -q _tmux_cmd_ran; or return   # only after a real command
                    set -e _tmux_cmd_ran
                    ${cmdStateBin} done
                  end
                end
              '');
            })
        ];
      };

    # === NixOS Module ===
    # Basic system-level tmux configuration
    nixos.tmux = { pkgs, lib, ... }: {
      programs.tmux = {
        enable = lib.mkDefault true;
        clock24 = lib.mkDefault true;
        terminal = lib.mkDefault "screen-256color";
      };
    };

    # === Darwin Module ===
    # Basic system-level tmux configuration for Darwin
    darwin.tmux = { pkgs, lib, ... }: {
      programs.tmux = {
        enable = lib.mkDefault true;
      };
    };
  };
}
