# Auto-reload tmux configuration on home-manager generation changes
{ config, lib, ... }:

with lib;

let
  cfg = config.programs.tmux.autoReload;
in
{
  options.programs.tmux.autoReload = {
    enable = mkEnableOption "automatic tmux config reload on home-manager generation change";
  };

  config = mkIf (cfg.enable && config.programs.tmux.enable) {
    programs.zsh.initContent = mkAfter ''
      # Auto-reload tmux config on home-manager generation change
      if [[ -n "$TMUX" ]]; then
        # Get current home-manager generation path (fast - just readlink)
        current_gen=$(readlink ~/.local/state/nix/profiles/home-manager 2>/dev/null)

        if [[ -n "$current_gen" ]]; then
          # Per-session tracking file using tmux session ID
          session_id=$(tmux display-message -p '#{session_id}' 2>/dev/null)
          gen_marker="/tmp/tmux-hm-gen-''${session_id}"

          # Check if generation changed since last check
          if [[ ! -f "$gen_marker" ]] || [[ "$(cat "$gen_marker" 2>/dev/null)" != "$current_gen" ]]; then
            # Try to acquire lock (atomic mkdir prevents race conditions)
            if mkdir "''${gen_marker}.lock" 2>/dev/null; then
              # We got the lock - reload tmux config once for this session
              tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null && \
                echo "$current_gen" > "$gen_marker"
              rmdir "''${gen_marker}.lock"
            fi
          fi
        fi
      fi
    '';

    # Also add to bash if enabled (for consistency)
    programs.bash.initExtra = mkIf config.programs.bash.enable (mkAfter ''
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
  };
}
