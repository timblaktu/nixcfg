# Static slash commands for Claude Code - eliminates git churn from symlinks
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;
  
  # Create the nixmemory command as a proper package
  claudeNixmemoryCmd = pkgs.writeShellApplication {
    name = "claude-nixmemory";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail
      
      # Determine the account from environment or default to max
      ACCOUNT="''${CLAUDE_ACCOUNT:-max}"
      CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-${cfg.nixcfgPath}/claude-runtime/.claude-$ACCOUNT}"
      MEMORY_FILE="$CONFIG_DIR/CLAUDE.md"
      
      # Check if memory file exists
      if [[ ! -f "$MEMORY_FILE" ]]; then
        echo "❌ Memory file not found: $MEMORY_FILE"
        echo "   Creating new memory file..."
        mkdir -p "$(dirname "$MEMORY_FILE")"
        touch "$MEMORY_FILE"
      fi
      
      # Make file writable temporarily
      chmod u+w "$MEMORY_FILE" 2>/dev/null || true
      
      # Configure editor
      EDITOR="''${EDITOR:-vi}"
      
      # Check if we're in a tmux session
      if [[ -n "''${TMUX:-}" ]]; then
        echo "📝 Opening user-global memory file in tmux pane..."
        echo "File: $MEMORY_FILE"
        
        # Open editor in a new horizontal pane below
        tmux split-window -d -v -p 30 "$EDITOR '$MEMORY_FILE'"
        
        echo "✅ Opened $EDITOR in tmux pane below"
        echo "💡 Tips:"
        echo "  • Switch panes: Prefix then arrow keys"
        echo "  • Close pane: Exit editor normally"
        echo "  • File will be made read-only after you exit the editor"
        
      # Check if tmux is available but we're not in a session  
      elif command -v tmux >/dev/null 2>&1; then
        echo "📝 Memory file location: $MEMORY_FILE"
        echo ""
        echo "You're not in a tmux session. Options:"
        echo "1. Start tmux first: tmux new -s claude"
        echo "2. Edit directly in terminal: $EDITOR $MEMORY_FILE"
        echo "3. Use /nixremember to append content"
        echo ""
        echo "Note: Terminal editors can't open from Claude Code commands."
        
      else
        echo "📝 Memory file location: $MEMORY_FILE"
        echo ""
        echo "Edit with: $EDITOR $MEMORY_FILE"
        echo "Or use /nixremember to append content"
        echo ""
        echo "Note: Terminal editors can't open from Claude Code commands."
      fi
      
      # Set read-only after a delay if in tmux
      if [[ -n "''${TMUX:-}" ]]; then
        (
          # Wait for editor to close
          while tmux list-panes -F '#{pane_current_command}' 2>/dev/null | grep -q "$EDITOR"; do
            sleep 2
          done
          # Restore read-only permissions
          chmod 444 "$MEMORY_FILE" 2>/dev/null || true
        ) &
      fi
    '';
  };
  
  # Create the nixremember command as a proper package
  claudeNixrememberCmd = pkgs.writeShellApplication {
    name = "claude-nixremember";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail
      
      # Check if content was provided
      if [[ $# -eq 0 ]]; then
        echo "❌ No content provided to remember"
        echo "Usage: /nixremember <content to remember>"
        exit 1
      fi
      
      # Determine the account
      ACCOUNT="''${CLAUDE_ACCOUNT:-max}"
      CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-${cfg.nixcfgPath}/claude-runtime/.claude-$ACCOUNT}"
      MEMORY_FILE="$CONFIG_DIR/CLAUDE.md"
      
      # Create memory file if it doesn't exist
      if [[ ! -f "$MEMORY_FILE" ]]; then
        mkdir -p "$(dirname "$MEMORY_FILE")"
        touch "$MEMORY_FILE"
      fi
      
      # Make writable temporarily
      chmod u+w "$MEMORY_FILE" 2>/dev/null || true
      
      # Add entry with timestamp
      TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
      {
        echo ""
        echo "## Memory Entry - $TIMESTAMP"
        echo "$*"
      } >> "$MEMORY_FILE"
      
      # Restore read-only
      chmod 444 "$MEMORY_FILE" 2>/dev/null || true
      
      echo "✅ Added to memory: $*"
      echo "📝 Memory file: $MEMORY_FILE"
      
      # Auto-commit if configured
      if [[ "''${CLAUDE_AUTO_COMMIT:-false}" == "true" ]] && command -v git >/dev/null 2>&1; then
        cd "$(dirname "$MEMORY_FILE")" 2>/dev/null || exit 0
        if git rev-parse --git-dir >/dev/null 2>&1; then
          git add "$MEMORY_FILE" 2>/dev/null || true
          git commit -m "Auto-commit: Memory update via /nixremember" 2>/dev/null || true
        fi
      fi
    '';
  };

in {
  options.programs.claude-code.staticCommands = {
    enable = mkOption {
      type = types.bool;
      default = false;  # Start with false to test alongside existing implementation
      description = "Use static slash command files that call commands on PATH (eliminates git churn)";
    };
  };
  
  config = mkIf (cfg.enable && cfg.memoryCommands.enable && cfg.staticCommands.enable) {
    # Install the actual command implementations to PATH
    home.packages = [ claudeNixmemoryCmd claudeNixrememberCmd ];
    
    # NOTE: The static wrapper files in claude-runtime/.claude-*/commands/ are 
    # manually maintained as real files in git. They are simple 3-line scripts
    # that exec the commands installed above. This eliminates git churn from
    # symlink target changes on every home-manager rebuild.
  };
}