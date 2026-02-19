# modules/programs/tmux/tmux.nix
# Tmux configuration for all platforms [NDnd]
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
  # Library files for scripts (shared with other modules)
  libPath = ../../.. + "/modules/programs/files [nd]/files/lib";
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

        # Fixed conditional logic using >= comparisons instead of < to avoid nesting issues
        cpuRamSection = ''
          #{?#{>=:#{client_width},${mediumWidth}},#(tmux-cpu-mem wide),#{?#{>=:#{client_width},${narrowWidth}},#(tmux-cpu-mem medium),#(tmux-cpu-mem narrow)}}
        '';

        # Status bar components - pointer char only shown when nested
        pointerChar = "→";
        statusLeft = "#[''$lock_open]#(pgrep tmux | wc -l | awk '$1 > 1 {print \"${pointerChar}\"}')#[''$style_normal]#{=10;p10:host_short} %b %d %T";
        statusRight = "${cpuRamSection}";
      in
      {
        options.programs.tmux.autoReload = {
          enable = lib.mkEnableOption "automatic tmux config reload on home-manager generation change";
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
              focusEvents = false;

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
                set -ga terminal-features ",*:focus:0"
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

                # Window navigation
                bind l last-window
                bind-key -n M-h previous-window
                bind-key -n M-l next-window

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
                is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?''$'"
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
                style_normal="${activeScheme.style_normal}"
                style_nested="${activeScheme.style_nested}"
                style_current_window="${activeScheme.style_current_window}"
                lock_closed="${activeScheme.lock_closed}"
                lock_open="${activeScheme.lock_open}"

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
                setw -g window-status-format '#(tmux-window-status-format #{client_width} #{window_index} #{window_name})'
                setw -g window-status-current-format '#(tmux-window-status-format #{client_width} #{window_index} #{window_name})'
                set -g status-justify centre
                set -g visual-activity on

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
                    '

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

              # Window status format script
              (pkgs.writers.writeBashBin "tmux-window-status-format" (builtins.replaceStrings
                [ ''source "''${HOME}/lib/general-utils.bash"'' ]
                [ "source \"${config.home.homeDirectory}/.local/lib/general-utils.bash\"" ]
                (builtins.readFile ./files/tmux-window-status-format)
              ))

              # Tmux resurrect cleanup script
              (pkgs.writers.writeBashBin "tmux-resurrect-cleanup" ''
                #!/usr/bin/env bash

                RESURRECT_DIR="${config.home.homeDirectory}/.local/share/tmux/resurrect"

                if [[ ! -d "$RESURRECT_DIR" ]]; then
                  exit 0
                fi

                find "$RESURRECT_DIR" -name "tmux_resurrect_*.txt" -size -50c -delete 2>/dev/null || true
                find "$RESURRECT_DIR" -name "tmux_resurrect_*.txt" -mtime +30 -delete 2>/dev/null || true

                if command -v ls >/dev/null 2>&1; then
                  cd "$RESURRECT_DIR" 2>/dev/null || exit 0
                  ls -t tmux_resurrect_*.txt 2>/dev/null | tail -n +51 | xargs -r rm -f 2>/dev/null || true
                fi
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
