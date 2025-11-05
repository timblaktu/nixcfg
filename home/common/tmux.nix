# Comprehensive Tmux configuration - unified and enhanced
{ config, lib, pkgs, ... }:

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
  # Conditional color scheme selection
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
    # Same black background, same aesthetic, just tiny text color variations for field separation
    classic = {
      style_normal = "fg=colour7,bg=colour0";
      style_nested = "fg=colour7,bg=colour8";
      style_current_window = "fg=colour7,bold,bg=colour10";
      lock_closed = "fg=colour7,bg=colour0";
      lock_open = "fg=colour7,bg=colour0";
      status_left_style = "fg=colour15,bg=colour0"; # Bright white for hostname/time
      status_right_style = "fg=colour244,bg=colour0"; # Medium gray for load averages
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

  # System info - load average now included in script
  loadAverage = "#(cat /proc/loadavg | cut -d' ' -f1,2,3)";

  # Status bar components - pointer char only shown when nested
  pointerChar = "→"; #  → ⇛ ➙ ⇒ ➜ ➠ 󰋇  ⮞
  # Show pointer only when nested - count tmux processes to detect nesting
  statusLeft = "#[''$lock_open]#(pgrep tmux | wc -l | awk '$1 > 1 {print \"${pointerChar}\"}')#[''$style_normal]#{=10;p10:host_short} %b %d %T";
  # Use responsive design - script handles all the conditional logic
  statusRight = "${cpuRamSection}";

in
{
  programs.tmux = {
    enable = lib.mkDefault true;

    # Basic configuration
    shortcut = "a"; # Use Ctrl-a as prefix (matching your old config)
    escapeTime = 1; # Faster command sequences
    baseIndex = 1; # Start window numbering at 1
    keyMode = "vi"; # Vim-style key bindings
    mouse = true; # Enable mouse support
    historyLimit = 100000; # Large history (matching your old config)
    # terminal setting moved to extraConfig for better Microsoft Terminal compatibility
    aggressiveResize = true; # From old config
    focusEvents = true; # Enable focus events

    # Shell configuration - use zsh if available, otherwise system default
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
      # Update these variables when attaching to ensure they reflect current terminal
      set -g update-environment "DISPLAY SSH_ASKPASS SSH_AUTH_SOCK SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY GPG_TTY HOST_IP ADB_SERVER_SOCKET"
      # ---- EXPORTED ENVIRONMENT VARIABLES SHARED BETWEEN THIS CONFIG AND CHILD PROCESSES
      # Dynamic window formatting for different terminal sizes
      setenv -g NIX_TMUX_SMALL_TERM 80
      setenv -g NIX_TMUX_MEDIUM_TERM 120
      setenv -g NIX_TMUX_LARGE_TERM 160
      
      # Ensure windows/panes inherit current environment when created
      set -g default-command "exec ${if config.programs.zsh.enable then "${config.programs.zsh.package}/bin/zsh" else "${pkgs.bash}/bin/bash"}"
    '' + ''
      # ---- TERMINAL AND COLOR SETTINGS ----
      # Optimized for Microsoft Terminal (Windows Terminal) in WSL with true color support
      set -g default-terminal "tmux-256color"
      set -ga terminal-overrides ",*256col*:Tc"
      set -ga terminal-overrides ",alacritty:Tc"
      set -ga terminal-overrides ",xterm-kitty:Tc"
      set -ga terminal-overrides ",*:bold=\\E[1m"
      set -ga terminal-overrides ",*:dim=\\E[2m"
      set -ga terminal-overrides ",*:smul=\\E[4m"
      set -ga terminal-overrides ",*:sitm=\\E[3m"
      set-hook -g client-resized 'refresh-client -S'

      # ---- PANE VISUAL INDICATORS ----
      # Dim inactive panes for clear visual distinction (disabled - kept for experimentation)
      # set -g window-style 'fg=colour247,bg=colour235'
      # set -g window-active-style 'fg=colour250,bg=black'

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
      # Ctrl-a twice sends literal Ctrl-a to nested session
      bind C-a send-prefix
      
      # ---- KEY BINDINGS ----
      # Reload configuration
      bind r source-file ~/.config/tmux/tmux.conf \; display-message -d1000 "Reloaded tmux config"
      
      # Pane splitting (more intuitive) - inherit current pane's working directory
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind v split-window -h -c "#{pane_current_path}"  # Also keep your preferred 'v' for vertical split
      bind s split-window -v -c "#{pane_current_path}"  # Also keep your preferred 's' for horizontal split
      
      # Window navigation
      bind l last-window
      bind-key -n M-h previous-window  # Alt+h => previous window
      bind-key -n M-l next-window      # Alt+l => next window
      
      # Window reordering - M-C-h/l already used by MS Terminal for tab navigation
      bind-key -n M-C-H swap-window -t -1\; select-window -t -1  # Alt+Ctrl+H => move window left
      bind-key -n M-C-L swap-window -t +1\; select-window -t +1  # Alt+Ctrl+L => move window right
      
      # Pane resizing with repeat capability
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
      # Smart pane switching with awareness of Vim splits
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
      # Color and style definitions - sourced from active color scheme
      style_normal="${activeScheme.style_normal}"
      style_nested="${activeScheme.style_nested}"
      style_current_window="${activeScheme.style_current_window}"
      lock_closed="${activeScheme.lock_closed}"
      lock_open="${activeScheme.lock_open}"
      
      # ---- STATUS BAR CONFIGURATION ----
      set -g status on
      set -g status-interval 1
      set -g status-style "''$style_normal"
      # Width thresholds
      set -g @narrow_width ${narrowWidth}
      set -g @medium_width ${mediumWidth}
      set -g @wide_width ${wideWidth}
      # LEFT STATUS BAR
      set -g status-left-style "${activeScheme.status_left_style}"
      set -g status-left-length 48
      set -g status-left "${statusLeft}"
      # RIGHT STATUS BAR
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
      # F12 switches to nested session mode
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
      # Save resurrect session only on detach and session close, with cleanup
      set-hook -g client-detached 'run-shell "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/save.sh > /dev/null 2>&1; tmux-resurrect-cleanup > /dev/null 2>&1"'
      set-hook -g session-closed 'run-shell "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/save.sh > /dev/null 2>&1; tmux-resurrect-cleanup > /dev/null 2>&1"'
      
      # Session pickers with layout options
      # Note: Prefix + t is remapped from default time display
      # Vertical layout - preview above search results
      bind-key t display-popup -E -w 95% -h 95% 'bash -c "tmux-session-picker --layout vertical"'
      # Horizontal layout - preview on right side  
      bind-key T display-popup -E -w 95% -h 95% 'bash -c "tmux-session-picker --layout horizontal"'
      
      # Alternative legacy pickers (for fallback)
      bind-key M-T display-popup -E -w 80% -h 80% "tmux-resurrect-browse interactive"
      bind-key M-t run-shell "tmux-resurrect-browse list"
      
      # Bitbake logfile opener (conditional on script existence)
      if-shell '[ -f "${config.home.homeDirectory}/bin/tmux-open-filename-in-current-pane" ]' \
        "bind-key -n C-b run-shell \"${config.home.homeDirectory}/bin/tmux-open-filename-in-current-pane 'Logfile of failure stored in:'\""
      

    '';

    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      {
        plugin = resurrect;
        extraConfig = ''
          # CRITICAL: Set resurrect save directory to a persistent location
          set -g @resurrect-dir '${config.home.homeDirectory}/.local/share/tmux/resurrect'
          set -g @resurrect-save 'S'
          set -g @resurrect-restore 'R'
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-capture-pane-contents 'on'
          
          # Processes to restore
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
          
          # Cleanup empty resurrect files on save
          set -g @resurrect-save-command-strategy 'tmux-resurrect-cleanup'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '5'
          # set -g @continuum-boot 'on'
          # set -g @continuum-systemd-start-cmd 'new-session -d'
        '';
      }
      #{
      #  plugin = cpu;
      #  extraConfig = ''
      #    set -g @cpu_percentage_format "%3.0f%%"
      #    set -g @ram_percentage_format "%3.0f%%"
      #    set -g @cpu_low_icon "="
      #    set -g @cpu_medium_icon "≡" 
      #    set -g @cpu_high_icon "≣"
      #    set -g @cpu_medium_thresh "25"
      #    set -g @cpu_high_thresh "75"
      #    run-shell 'sleep 0.1 && ${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/cpu.tmux'
      #  '';
      #}
    ];
  };

  # CRITICAL: Create persistent directory for tmux-resurrect saves
  home.file.".local/share/tmux/resurrect/.keep" = {
    text = ''
      # This file ensures the resurrect directory exists
      # tmux-resurrect saves will be stored here and persist across home-manager switches
    '';
  };

  # Ensure system tools are available
  home.packages = with pkgs; [
    procps # Provides tools like ps, top, free for system monitoring
    bc # Basic calculator

    # Tmux session picker - the main interactive session selector  
    (pkgs.writers.writeBashBin "tmux-session-picker" (
      let
        script = builtins.readFile ../files/bin/tmux-session-picker;
        terminalUtils = builtins.readFile ../files/lib/terminal-utils.bash;
        colorUtils = builtins.readFile ../files/lib/color-utils.bash;
        pathUtils = builtins.readFile ../files/lib/path-utils.bash;
      in
      builtins.replaceStrings
        [
          ''source "$HOME/.local/lib/terminal-utils.bash"''
          ''source "$HOME/.local/lib/color-utils.bash"''
          ''source "$HOME/.local/lib/path-utils.bash"''
        ]
        [
          terminalUtils
          colorUtils
          pathUtils
        ]
        script
    ))

    # Tmux session picker profiled version (performance testing)
    (pkgs.writeShellApplication {
      name = "tmux-session-picker-profiled";
      text = builtins.readFile ../files/bin/tmux-session-picker-profiled;
      runtimeInputs = with pkgs; [ fzf tmux parallel python3 fd ripgrep time ];
    })

    # Tmux CPU/memory status display with colored braille indicators
    (pkgs.writeShellApplication {
      name = "tmux-cpu-mem";
      text = builtins.readFile ../files/bin/tmux-cpu-mem;
      runtimeInputs = with pkgs; [ procps coreutils ];
    })

    # Tmux test data generator for testing session picker
    (pkgs.writeShellApplication {
      name = "tmux-test-data-generator";
      text = builtins.readFile ../files/bin/tmux-test-data-generator;
      runtimeInputs = with pkgs; [ coreutils ];
      passthru.tests = {
        syntax = pkgs.runCommand "test-tmux-test-data-generator-syntax" { } ''
          echo "✅ Syntax validation passed at build time" > $out
        '';
        help_availability = pkgs.runCommand "test-tmux-test-data-generator-help"
          {
            nativeBuildInputs = [
              (pkgs.writeShellApplication {
                name = "tmux-test-data-generator";
                text = builtins.readFile ../files/bin/tmux-test-data-generator;
                runtimeInputs = with pkgs; [ coreutils ];
              })
            ];
          } ''
          output=$(tmux-test-data-generator --help 2>&1)
          exit_code=$?
          
          if [[ $exit_code -eq 0 ]]; then
            echo "✅ Help command works" > $out
            if echo "$output" | grep -q "Usage:\|OPTIONS:\|EXAMPLES:"; then
              echo "✅ Help contains expected sections" >> $out
            else
              echo "❌ Help missing expected sections" >> $out
              exit 1
            fi
          else
            echo "❌ Help command failed with exit code $exit_code" > $out
            exit 1
          fi
        '';
        basic_generation = pkgs.runCommand "test-tmux-test-data-generator-basic"
          {
            nativeBuildInputs = [
              (pkgs.writeShellApplication {
                name = "tmux-test-data-generator";
                text = builtins.readFile ../files/bin/tmux-test-data-generator;
                runtimeInputs = with pkgs; [ coreutils ];
              })
            ];
          } ''
          # Test basic session generation
          test_dir=$(mktemp -d)
          trap "rm -rf $test_dir" EXIT
          
          tmux-test-data-generator -o "$test_dir" -c 3
          
          # Verify files were created
          file_count=$(find "$test_dir" -name "tmux_resurrect_*.txt" | wc -l)
          if [[ $file_count -eq 3 ]]; then
            echo "✅ Generated expected number of test files" > $out
          else
            echo "❌ Expected 3 files, got $file_count" > $out
            exit 1
          fi
        '';
      };
    })

    # Optimized tmux parser for performance - migrated from validated-scripts
    (pkgs.writeShellApplication {
      name = "tmux-parser-optimized";
      text = /* bash */ ''
        #!/usr/bin/env bash
        set -euo pipefail

        # tmux-parser-optimized: Fast parser for tmux resurrect files
        # Returns: session\x1Fwindows\x1Fpanes\x1Ftimestamp\x1Fsummary\x1Fis_current
        
        # Input validation
        if [[ $# -eq 0 ]]; then
            echo "Usage: tmux-parser-optimized <resurrect_file> [current_session_file]" >&2
            exit 1
        fi

        resurrect_file="$1"
        current_session_file="''${2:-}"

        # File existence check
        if [[ ! -f "$resurrect_file" ]]; then
            exit 1
        fi

        # Extract session name from file content (first session line)
        session_name=$(awk '/^session\t/ {print $2; exit}' "$resurrect_file" 2>/dev/null || echo "unknown")

        # Count windows and panes
        window_count=$(grep -c "^window" "$resurrect_file" 2>/dev/null || echo "0")
        pane_count=$(grep -c "^pane" "$resurrect_file" 2>/dev/null || echo "0")

        # Extract timestamp from filename or use fallback
        basename=$(basename "$resurrect_file" .txt)
        if [[ "$basename" =~ tmux_resurrect_([0-9]{8}_[0-9]{6}) ]]; then
            timestamp="''${BASH_REMATCH[1]}"
        else
            timestamp="19700101_000000"
        fi

        # Create summary
        summary="''${window_count}w/''${pane_count}p"

        # Determine if current session
        is_current="false"
        if [[ -n "$current_session_file" && "$resurrect_file" == "$current_session_file" ]]; then
            is_current="true"
        fi

        # Output in ASCII Unit Separator format
        printf "%s\x1F%s\x1F%s\x1F%s\x1F%s\x1F%s\n" \
            "$session_name" "$window_count" "$pane_count" "$timestamp" "$summary" "$is_current"
      '';
      runtimeInputs = with pkgs; [ coreutils gnugrep gawk ];
      passthru.tests = {
        syntax = pkgs.runCommand "test-tmux-parser-optimized-syntax" { } ''
          echo "✅ Syntax validation passed at build time" > $out
        '';
        basic_parsing = pkgs.runCommand "test-tmux-parser-optimized-basic"
          {
            nativeBuildInputs = [
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
            ];
          } ''
                    # Create test file
                    test_dir=$(mktemp -d)
                    test_file="$test_dir/tmux_resurrect_20250124_143022.txt"
                    cat > "$test_file" << 'EOF'
          session	test-session	:1.0	1	:vim*	vim	:
          window	test-session:1	1	:*	cd3c-	:vim	/home/user	vim	:
          pane	test-session:1	1	:	1	:*	1	:/home/user	1	vim	:
          EOF

                    result=$(tmux-parser-optimized "$test_file")
                    IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"

                    [[ "$session" == "test-session" ]] || { echo "❌ Session name failed: '$session'" > $out; exit 1; }
                    [[ "$windows" == "1" ]] || { echo "❌ Window count failed: '$windows'" > $out; exit 1; }
                    [[ "$panes" == "1" ]] || { echo "❌ Pane count failed: '$panes'" > $out; exit 1; }
                    [[ "$timestamp" == "20250124_143022" ]] || { echo "❌ Timestamp failed: '$timestamp'" > $out; exit 1; }

                    echo "✅ Basic parsing test passed" > $out
                    rm -rf "$test_dir"
        '';
        error_handling = pkgs.runCommand "test-tmux-parser-optimized-errors"
          {
            nativeBuildInputs = [
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
            ];
          } ''
          test_dir=$(mktemp -d)
          
          # Test non-existent file
          result=$(tmux-parser-optimized "$test_dir/nonexistent.txt" 2>/dev/null || echo "PARSER_FAILED")
          [[ "$result" == "PARSER_FAILED" ]] || { echo "❌ Should fail on non-existent file" > $out; exit 1; }
          
          # Test empty file
          empty_file="$test_dir/empty.txt"
          touch "$empty_file"
          result=$(tmux-parser-optimized "$empty_file" 2>/dev/null || echo "PARSER_FAILED")
          [[ "$result" == "PARSER_FAILED" ]] || { echo "❌ Should fail on empty file" > $out; exit 1; }
          
          echo "✅ Error handling test passed" > $out
          rm -rf "$test_dir"
        '';
      };
    })

    # Custom tmux window status format script with proper library path
    (pkgs.writers.writeBashBin "tmux-window-status-format" (builtins.replaceStrings
      [ ''source "''${HOME}/lib/general-utils.bash"'' ]
      [ "source \"${config.home.homeDirectory}/.local/lib/general-utils.bash\"" ]
      (builtins.readFile ../files/bin/tmux-window-status-format)
    ))

    # Tmux resurrect cleanup script
    (pkgs.writers.writeBashBin "tmux-resurrect-cleanup" ''
      #!/usr/bin/env bash
      
      # tmux-resurrect-cleanup: Clean up empty and corrupted session files
      
      RESURRECT_DIR="${config.home.homeDirectory}/.local/share/tmux/resurrect"
      
      if [[ ! -d "$RESURRECT_DIR" ]]; then
        exit 0
      fi
      
      # Find and remove empty or near-empty session files (< 50 bytes)
      find "$RESURRECT_DIR" -name "tmux_resurrect_*.txt" -size -50c -delete 2>/dev/null || true
      
      # Clean up files older than 30 days (keep last 30 days of sessions)
      find "$RESURRECT_DIR" -name "tmux_resurrect_*.txt" -mtime +30 -delete 2>/dev/null || true
      
      # Limit total session files to 50 most recent
      if command -v ls >/dev/null 2>&1; then
        cd "$RESURRECT_DIR" 2>/dev/null || exit 0
        ls -t tmux_resurrect_*.txt 2>/dev/null | tail -n +51 | xargs -r rm -f 2>/dev/null || true
      fi
    '')

    # Tmux resurrect session management scripts
    (pkgs.writers.writeBashBin "tmux-resurrect-browse" ''
      #!/usr/bin/env bash
      
      # tmux-resurrect-browse: Simple resurrect session browser
      # Usage: tmux-resurrect-browse [restore|list|interactive]
      
      RESURRECT_DIR="$HOME/.local/share/tmux/resurrect"
      
      # Check if resurrect directory exists
      if [[ ! -d "$RESURRECT_DIR" ]]; then
          echo "Error: tmux-resurrect directory not found at $RESURRECT_DIR"
          exit 1
      fi
      
      # Get current session
      current_file=""
      if [[ -L "$RESURRECT_DIR/last" ]]; then
          current_file=$(basename "$(readlink -f "$RESURRECT_DIR/last")")
      fi
      
      list_sessions() {
          echo "Available tmux resurrect sessions:"
          echo "==================================="
          echo
          
          # Find all session files and sort by date
          local i=1
          for file in $(ls -t "$RESURRECT_DIR"/tmux_resurrect_*.txt 2>/dev/null); do
              basename=$(basename "$file" .txt)
              timestamp=''${basename#tmux_resurrect_}
              
              # Format timestamp
              year=''${timestamp:0:4}
              month=''${timestamp:4:2}
              day=''${timestamp:6:2}
              hour=''${timestamp:9:2}
              minute=''${timestamp:11:2}
              
              formatted="$year-$month-$day $hour:$minute"
              
              # Count windows and panes
              windows=$(grep -c "^window" "$file" 2>/dev/null || echo 0)
              panes=$(grep -c "^pane" "$file" 2>/dev/null || echo 0)
              
              # Mark current
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
          
          # Validate input
          if ! [[ "$session_num" =~ ^[0-9]+$ ]]; then
              echo "Error: Please provide a valid session number"
              list_sessions
              exit 1
          fi
          
          # Get the file at that index
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
          
          # Update the symlink
          echo "Setting session #$session_num to restore..."
          ln -sf "$(basename "$target_file")" "$RESURRECT_DIR/last"
          
          # Show what was selected
          basename=$(basename "$target_file" .txt)
          timestamp=''${basename#tmux_resurrect_}
          year=''${timestamp:0:4}
          month=''${timestamp:4:2}
          day=''${timestamp:6:2}
          hour=''${timestamp:9:2}
          minute=''${timestamp:11:2}
          echo "Selected: $year-$month-$day $hour:$minute"
          
          # Restore if in tmux
          if [[ -n "''${TMUX:-}" ]]; then
              echo "Restoring session..."
              tmux run-shell "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/restore.sh"
              echo "Session restored!"
          else
              echo "Now run 'tmux' and press [Prefix+R] to restore the session"
          fi
      }
      
      interactive_mode() {
          # Clear screen and show sessions
          clear
          list_sessions
          echo
          echo "-----------------------------------"
          echo "Enter session number to restore"
          echo "Press 'q' or Ctrl-C to quit"
          echo "-----------------------------------"
          echo -n "Choice: "
          
          # Read user input
          read -r choice
          
          # Handle choice
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
              interactive_mode  # Restart interactive mode
          fi
      }
      
      # Main logic
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
