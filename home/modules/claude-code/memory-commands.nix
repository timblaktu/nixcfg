{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;

  # Path to the user's global memory file in nixcfg  
  userGlobalMemoryPath = "${cfg.nixcfgPath}/claude-runtime/.claude-\${CLAUDE_ACCOUNT:-max}/CLAUDE.md";

  # Create the memory editing script
  nixMemoryScript = pkgs.writeScript "nixmemory" ''
    #!/usr/bin/env bash
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
      # -d keeps focus on current pane, -p 30 makes it 30% height
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
      echo "Please edit the file manually, then return to Claude Code."
      
    else
      echo "📝 Memory file location: $MEMORY_FILE"
      echo ""
      echo "Since terminal editors can't open from Claude Code commands,"
      echo "please edit this file directly in your terminal:"
      echo ""
      echo "  $EDITOR $MEMORY_FILE"
      echo ""
      echo "Or use /nixremember to append content"
    fi
    
    # Note: Only make read-only if we opened in tmux (file gets closed)
    # For other cases, user will handle the file manually
    if [[ -n "''${TMUX:-}" ]]; then
      # Wait a moment for the tmux pane to be created
      sleep 1
      
      # Set up a background process to restore read-only permissions
      # when the editor process in the tmux pane exits
      (
        # Find the tmux pane with our editor
        while tmux list-panes -F "#{pane_current_command}" | grep -q "''${EDITOR##*/}"; do
          sleep 2
        done
        # Editor closed, restore permissions
        chmod 444 "$MEMORY_FILE"
        echo "✅ Memory file made read-only: $MEMORY_FILE"
      ) &
    fi
  '';

  # Create the remember script
  nixRememberScript = pkgs.writeScript "nixremember" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Check if content was provided
    if [[ $# -eq 0 ]]; then
      echo "❌ Usage: /nixremember <content to remember>"
      exit 1
    fi
    
    # Determine the account from environment or default to max
    ACCOUNT="''${CLAUDE_ACCOUNT:-max}"
    CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-${cfg.nixcfgPath}/claude-runtime/.claude-$ACCOUNT}"
    MEMORY_FILE="$CONFIG_DIR/CLAUDE.md"
    
    # Ensure memory file exists
    if [[ ! -f "$MEMORY_FILE" ]]; then
      mkdir -p "$(dirname "$MEMORY_FILE")"
      touch "$MEMORY_FILE"
    fi
    
    # Make file writable temporarily
    chmod u+w "$MEMORY_FILE" 2>/dev/null || true
    
    # Append content with timestamp
    {
      echo ""
      echo "## Memory Entry - $(date '+%Y-%m-%d %H:%M:%S')"
      echo "$*"
    } >> "$MEMORY_FILE"
    
    # Make read-only again
    chmod 444 "$MEMORY_FILE"
    
    echo "✅ Added to memory: $*"
  '';

in
{
  options.programs.claude-code.memoryCommands = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable custom memory management commands for Nix-managed Claude Code";
    };

    makeWritable = mkOption {
      type = types.bool;
      default = true;
      description = "Make CLAUDE.md files writable (mode 644 instead of 444)";
    };
  };

  config = mkIf (cfg.enable && cfg.memoryCommands.enable) {
    # Add custom slash commands
    programs.claude-code.slashCommands.custom = {
      nixmemory = {
        description = "Edit user-global memory file (Nix-aware)";
        usage = "/nixmemory";
        handler = "${nixMemoryScript}";
        aliases = [ "usermemory" "globalmemory" ];
        permissions = [ ];
      };

      nixremember = {
        description = "Append content to user-global memory (Nix-aware)";
        usage = "/nixremember <content>";
        handler = "${nixRememberScript}";
        aliases = [ "userremember" "globalremember" ];
        permissions = [ ];
      };
    };

    # Override the CLAUDE.md file permissions in activation script
    home.activation.claudeMemoryPermissions = lib.hm.dag.entryAfter [ "claudeConfigTemplates" ] (mkIf cfg.memoryCommands.makeWritable ''
      echo "🔓 Setting writable permissions for CLAUDE.md files..."
      
      # Update permissions for all account CLAUDE.md files
      ${concatStringsSep "\n" (mapAttrsToList (name: account: ''
        if [[ "${toString account.enable}" == "true" ]]; then
          accountDir="${cfg.nixcfgPath}/claude-runtime/.claude-${name}"
          if [[ -f "$accountDir/CLAUDE.md" ]]; then
            $DRY_RUN_CMD chmod 644 "$accountDir/CLAUDE.md"
            echo "✅ Made writable: $accountDir/CLAUDE.md"
          fi
        fi
      '') cfg.accounts)}
      
      # Update base directory if needed
      ${optionalString (cfg.defaultAccount != null) ''
        baseDir="${cfg.nixcfgPath}/claude-runtime/.claude"
        if [[ -f "$baseDir/CLAUDE.md" ]]; then
          $DRY_RUN_CMD chmod 644 "$baseDir/CLAUDE.md"  
          echo "✅ Made writable: $baseDir/CLAUDE.md"
        fi
      ''}
    '');

    # Deploy command files to each account's commands directory
    # Only create symlinks if static commands are NOT enabled
    home.file = lib.mkMerge (lib.flatten (mapAttrsToList
      (name: account:
        if account.enable && !cfg.staticCommands.enable then [{
          # nixmemory command files
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/nixmemory.sh" = {
            source = nixMemoryScript;
            executable = true;
          };
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/nixmemory.md" = {
            text = ''
              # /nixmemory - Edit User Memory
            
              Opens the user-global memory file in your default editor.
            
              ## Usage
              ```
              /nixmemory
              ```
            
              ## Aliases
              - /usermemory
              - /globalmemory
            
              ## Description
              This command opens the Nix-managed user memory file for the current Claude Code account.
            
              **Behavior:**
              1. **If in tmux**: Opens editor in a horizontal pane below
              2. **Not in tmux**: Shows file location for manual editing  
              3. **No tmux**: Provides direct editing instructions
            
              **Note:** Unlike /memory, terminal editors cannot open directly from Claude Code commands.
              This command uses tmux split-pane integration to work around this limitation.
            
              ## Environment Variables
              - EDITOR: The text editor to use (defaults to vi)
              - CLAUDE_ACCOUNT: The current account (defaults to max)
              - CLAUDE_CONFIG_DIR: The configuration directory path
              - TMUX: Detected automatically to enable tmux integration
            '';
          };

          # nixremember command files
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/nixremember.sh" = {
            source = nixRememberScript;
            executable = true;
          };
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/nixremember.md" = {
            text = ''
              # /nixremember - Add to User Memory
            
              Appends content to the user-global memory file.
            
              ## Usage
              ```
              /nixremember <content to remember>
              ```
            
              ## Aliases
              - /userremember
              - /globalremember
            
              ## Description
              This command appends the provided content to the Nix-managed user memory file
              with a timestamp. The file is made temporarily writable during the operation.
            
              ## Examples
              ```
              /nixremember This project uses TypeScript with React
              /nixremember Important: Always run tests before committing
              ```
            '';
          };

          # Alias command files
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/usermemory.sh" = {
            source = nixMemoryScript;
            executable = true;
          };
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/usermemory.md" = {
            text = "See /nixmemory";
          };

          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/globalmemory.sh" = {
            source = nixMemoryScript;
            executable = true;
          };
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/globalmemory.md" = {
            text = "See /nixmemory";
          };

          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/userremember.sh" = {
            source = nixRememberScript;
            executable = true;
          };
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/userremember.md" = {
            text = "See /nixremember";
          };

          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/globalremember.sh" = {
            source = nixRememberScript;
            executable = true;
          };
          "${cfg.nixcfgPath}/claude-runtime/.claude-${name}/commands/globalremember.md" = {
            text = "See /nixremember";
          };
        }] else [ ]
      )
      cfg.accounts));
  };
}
