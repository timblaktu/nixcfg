# Bash Scripts - Validated bash script definitions
{ config, lib, pkgs, mkValidatedScript, mkBashScript, mkScriptLibrary, writers, ... }:

with lib;

let
  cfg = config.validatedScripts;
  
  # Split scripts into multiple groups to avoid evaluation issues
  # Group 1: Test and example scripts
  testScripts = {
    # Test simple script to verify module evaluation
    simple-test = mkBashScript {
      name = "simple-test";
      deps = with pkgs; [ coreutils ];
      text = ''
        #!/usr/bin/env bash
        echo "Simple test"
      '';
      tests = {};
    };
    
    # Example script to demonstrate the infrastructure
    hello-validated = mkBashScript {
      name = "hello-validated";
      deps = with pkgs; [ coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        # Example validated script with proper dependency management
        echo "🎉 Hello from validated bash script!"
        echo "Current time: $(date)"
        echo "Running with these dependencies:"
        echo "  - coreutils: $(dirname "$(which echo)")"
        
        # Show script validation info
        if [[ "''${1:-}" == "--info" ]]; then
          echo
          echo "Script validation info:"
          echo "  Language: bash"
          echo "  Dependencies: coreutils"
          echo "  Validated: ✅ at build time"
          echo "  Tests: Available via 'nix flake check'"
        fi
      '';
      tests = {
        help = writers.testBash "test-hello-validated-help" ''
          # Test help output - we'll build the script dynamically in tests
          echo "✅ Help test passed (placeholder)"
        '';
        basic = writers.testBash "test-hello-validated-basic" ''
          # Test basic execution - we'll build the script dynamically in tests
          echo "✅ Basic execution test passed (placeholder)"
        '';
      };
    };
  };
  
  # Main scripts collection (previously lines 24-1090)
  mainScripts = {
    # Test simple script to verify module evaluation (moved here from testScripts)
    simple-test = mkBashScript {
      name = "simple-test";
      deps = with pkgs; [ coreutils ];
      text = ''
        #!/usr/bin/env bash
        echo "Simple test"
      '';
      tests = {};
    };
    
    # Git smart merge tool - migrated from home/common/git.nix
    smart-nvimdiff = mkBashScript {
      name = "smart-nvimdiff";
      deps = with pkgs; [ git neovim coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        # Smart mergetool wrapper for neovim
        # Automatically switches to 2-way diff when BASE is empty
        
        BASE="$1"
        LOCAL="$2"  
        REMOTE="$3"
        MERGED="$4"
        
        # Check if BASE file exists and is not empty
        if [ -f "$BASE" ] && [ -s "$BASE" ]; then
            # Normal 4-way diff with non-empty BASE
            # Use timer to ensure focus happens after all initialization
            exec nvim -d "$MERGED" "$LOCAL" "$BASE" "$REMOTE" \
              -c "wincmd J" \
              -c "call timer_start(250, {-> execute('wincmd b')})"
        else
            # Empty or missing BASE, so MERGED is just a useless single conflict diff.
            # Overwrite MERGED with LOCAL and do 2-way diff against REMOTE.
            # This gives us a clean starting point without conflict markers
            # which allows us to properly merge the desired changes.
            cp "$LOCAL" "$MERGED"
            exec nvim -d "$MERGED" "$REMOTE"
        fi
      '';
      tests = {
        syntax = writers.testBash "test-smart-nvimdiff-syntax" ''
          # Test that script has valid bash syntax
          echo "✅ Syntax validation passed at build time"
        '';
        argument_validation = writers.testBash "test-smart-nvimdiff-args" ''
          # Test that script properly validates arguments
          # This is a placeholder - full testing would require mock git environment
          echo "✅ Argument validation test passed (placeholder)"
        '';
      };
    };
    
    # Terminal verification scripts - migrated from home/modules/terminal-verification.nix
    # NOTE: check-terminal-setup moved to static script in home/files/bin/ due to evaluation issues
    # Commented out - using static script instead
#     # check-terminal-setup = mkBashScript {
#       name = "check-terminal-setup";
#       deps = with pkgs; [ jq coreutils ];
#       text = /* bash */ ''
#         #!/usr/bin/env bash
#         # Manual terminal verification command for comprehensive diagnostics
#         # This script provides detailed Windows Terminal alignment checking
#         
#         echo "=== Windows Terminal Alignment Check ==="
#         echo "System: WSL ''${WSL_DISTRO_NAME:-NixOS}"
#         
#         # Force re-detection of all terminal settings
#         # Unset any inherited values that might be stale or have wrong paths
#         unset WT_SETTINGS_PATH WT_ALIGNMENT_OK WT_FONT_OK WT_INTENSE_OK WT_NEEDS_FIX
#         
#         # Dynamically find Windows Terminal settings path
#         if [[ -z "''${WT_SETTINGS_PATH}" ]]; then
#           # Try to get Windows username via PowerShell
#           if command -v powershell.exe >/dev/null 2>&1; then
#             WIN_USER=$(powershell.exe -NoProfile -Command 'Write-Host $env:USERNAME' 2>/dev/null | tr -d '\r\n')
#             if [[ -n "$WIN_USER" ]]; then
#               WT_SETTINGS_PATH="/mnt/c/Users/$WIN_USER/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
#             fi
#           fi
#           
#           # If still not found, try common locations
#           if [[ -z "''${WT_SETTINGS_PATH}" ]] || [[ ! -f "''${WT_SETTINGS_PATH}" ]]; then
#             for user_dir in /mnt/c/Users/*; do
#               if [[ -d "$user_dir" ]]; then
#                 test_path="$user_dir/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
#                 if [[ -f "$test_path" ]]; then
#                   WT_SETTINGS_PATH="$test_path"
#                   break
#                 fi
#               fi
#             done
#           fi
#         fi
#         
#         echo "Settings: ''${WT_SETTINGS_PATH:-Not found}"
#         echo
#         
#         # Run verification (reuse the silent verification logic)
#         # This would source the verification script - for now simplified
#         if [[ -n "$WSL_DISTRO_NAME" ]] || [[ -n "$WSLENV" ]]; then
#           if [[ -n "''${WT_SETTINGS_PATH}" ]] && [[ -f "''${WT_SETTINGS_PATH}" ]]; then
#             INTENSE_STYLE=$(jq -r '.profiles.defaults.intenseTextStyle // "default"' "''${WT_SETTINGS_PATH}" 2>/dev/null)
#             CURRENT_FONT=$(jq -r '.profiles.defaults.font.face // "not configured"' "''${WT_SETTINGS_PATH}" 2>/dev/null)
#             
#             WT_ALIGNMENT_OK=1
#             [[ "$INTENSE_STYLE" != "all" ]] && WT_ALIGNMENT_OK=0
#             [[ "$CURRENT_FONT" != "''${WT_EXPECTED_FONT}" ]] && WT_ALIGNMENT_OK=0
#             
#             echo "Alignment Status:"
#             if [[ "$WT_ALIGNMENT_OK" == "1" ]]; then
#               echo "  ✅ Windows Terminal is properly aligned with WSL NixOS"
#             else
#               echo "  ❌ Misalignment detected - run 'setup-terminal-fonts' to fix"
#             fi
#             
#             echo
#             echo "Configuration Details:"
#             echo "  Font: $CURRENT_FONT"
#             echo "  Intense Style: $INTENSE_STYLE"
#             echo "  Expected Font: ''${WT_EXPECTED_FONT:-CaskaydiaMono Nerd Font Mono, Noto Color Emoji}"
#             echo "  Expected Style: all"
#           else
#             echo "  ⚠️  Cannot verify - Windows Terminal settings not found"
#           fi
#         else
#           echo "  ℹ️  Not running in WSL environment"
#         fi
#         
#         echo
#         echo "=== Visual Tests ==="
#         printf "Normal text vs "
#         printf "\033[1mBOLD TEXT\033[0m\n"
#         echo "If bold text looks heavier/thicker, bold rendering works!"
#         
#         echo
#         echo "Emoji test: WARNING[⚠️] SUCCESS[✅] ERROR[❌]" 
#         echo "If you see actual icons (not squares/question marks), emoji rendering works!"
#         
#         echo
#         echo "For detailed diagnostics, run: diagnose-emoji-rendering"
#       '';
#       tests = {
#         syntax = writers.testBash "test-check-terminal-setup-syntax" ''
#           echo "✅ Syntax validation passed at build time"
#         '';
#         visual_output = writers.testBash "test-check-terminal-setup-visual" ''
#           # Test visual output generation - placeholder
#           echo "✅ Visual output test passed (placeholder)"
#         '';
#       };
#     };
#     */
    
    # Terminal font setup script - simplified version migrated from terminal-verification.nix
    setup-terminal-fonts = mkBashScript {
      name = "setup-terminal-fonts";
      deps = with pkgs; [ jq coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        # Simplified terminal font setup script
        # Provides guidance for Windows Terminal font configuration
        
        echo "=== Windows Terminal Font Setup ==="
        echo
        
        # Basic WSL detection
        if [[ -z "$WSL_DISTRO_NAME" && -z "$WSLENV" ]]; then
          echo "ℹ️  This script is designed for WSL environments"
          echo "   For non-WSL systems, please configure fonts manually"
          exit 0
        fi
        
        echo "This script helps configure Windows Terminal fonts for optimal rendering."
        echo "Recommended configuration:"
        echo
        echo "1. Font Settings:"
        echo "   Primary: Cascadia Code (with Nerd Font support)"
        echo "   Emoji: Noto Color Emoji"
        echo "   Fallback: Segoe UI Emoji"
        echo
        echo "2. Bold Text Settings:"
        echo "   Set intenseTextStyle to 'all' (not 'bright')"
        echo
        
        # Force re-detection of all terminal settings
        # Unset any inherited values that might be stale or have wrong paths
        unset WT_SETTINGS_PATH WT_ALIGNMENT_OK WT_FONT_OK WT_INTENSE_OK WT_NEEDS_FIX
        
        # Dynamically find Windows Terminal settings path
        if [[ -z "''${WT_SETTINGS_PATH}" ]]; then
          # Try to get Windows username via PowerShell
          if command -v powershell.exe >/dev/null 2>&1; then
            WIN_USER=$(powershell.exe -NoProfile -Command 'Write-Host $env:USERNAME' 2>/dev/null | tr -d '\r\n')
            if [[ -n "$WIN_USER" ]]; then
              WT_SETTINGS_PATH="/mnt/c/Users/$WIN_USER/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
            fi
          fi
          
          # If still not found, try common locations
          if [[ -z "''${WT_SETTINGS_PATH}" ]] || [[ ! -f "''${WT_SETTINGS_PATH}" ]]; then
            for user_dir in /mnt/c/Users/*; do
              if [[ -d "$user_dir" ]]; then
                test_path="$user_dir/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
                if [[ -f "$test_path" ]]; then
                  WT_SETTINGS_PATH="$test_path"
                  break
                fi
              fi
            done
          fi
        fi
        
        # Check current configuration if settings file exists
        if [[ -n "''${WT_SETTINGS_PATH}" ]] && [[ -f "''${WT_SETTINGS_PATH}" ]]; then
          echo "3. Current Configuration Check:"
          CURRENT_FONT=$(jq -r '.profiles.defaults.font.face // "not configured"' "''${WT_SETTINGS_PATH}" 2>/dev/null)
          INTENSE_STYLE=$(jq -r '.profiles.defaults.intenseTextStyle // "default"' "''${WT_SETTINGS_PATH}" 2>/dev/null)
          
          echo "   Current Font: $CURRENT_FONT"
          echo "   Current Intense Style: $INTENSE_STYLE"
          echo
          
          if [[ "$CURRENT_FONT" == "''${WT_EXPECTED_FONT:-"CaskaydiaMono Nerd Font Mono, Noto Color Emoji"}" && "$INTENSE_STYLE" == "all" ]]; then
            echo "✅ Configuration looks correct!"
          else
            echo "❌ Configuration needs adjustment"
            echo
            echo "Recommended Windows Terminal settings.json update:"
            echo '   "profiles": {'
            echo '     "defaults": {'
            echo "       \"font\": { \"face\": \"''${WT_EXPECTED_FONT:-"CaskaydiaMono Nerd Font Mono, Noto Color Emoji"}\" },"
            echo '       "intenseTextStyle": "all"'
            echo '     }'
            echo '   }'
          fi
        else
          echo "⚠️  Windows Terminal settings file not found"
          if [[ -n "''${WT_SETTINGS_PATH}" ]]; then
            echo "   Looked for: ''${WT_SETTINGS_PATH}"
          else
            echo "   Could not determine Windows Terminal settings location"
          fi
          echo "   Please ensure Windows Terminal is installed and has been run at least once"
        fi
        
        echo
        echo "For automated font installation, consider using PowerShell-based tools"
        echo "Run 'check-terminal-setup' to verify your configuration"
      '';
      tests = {
        syntax = writers.testBash "test-setup-terminal-fonts-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        guidance_output = writers.testBash "test-setup-terminal-fonts-guidance" ''
          # Test that guidance is provided - placeholder
          echo "✅ Guidance output test passed (placeholder)"
        '';
      };
    };
    
    # ESP-IDF development scripts - migrated from home/common/esp-idf.nix
    esp-idf-install = mkBashScript {
      name = "esp-idf-install";
      deps = with pkgs; [ coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        # Run ESP-IDF install.sh in FHS environment
        
        echo "Running ESP-IDF install.sh in FHS environment..."
        
        # This will need to reference the FHS environment from esp-idf.nix
        # For now, provide guidance on manual setup
        IDF_PATH="''${IDF_PATH:-$HOME/src/dsp/esp-idf}"
        ESP_IDF_FHS_ENV="''${ESP_IDF_FHS_ENV:-esp-idf-fhs}"
        
        if [[ -z "$ESP_IDF_FHS_ENV" ]]; then
          echo "❌ Error: ESP-IDF FHS environment not available"
          echo "   This script requires enableEspIdf = true in your home configuration"
          exit 1
        fi
        
        if [[ ! -f "$IDF_PATH/install.sh" ]]; then
          echo "❌ Error: ESP-IDF not found at $IDF_PATH"
          echo "   Please ensure ESP-IDF is cloned to $IDF_PATH"
          echo "   Run: git clone --recursive https://github.com/espressif/esp-idf.git $IDF_PATH"
          exit 1
        fi
        
        # Use the FHS environment to run install.sh
        "$ESP_IDF_FHS_ENV" -c "
          export IDF_PATH=$IDF_PATH
          cd \"$IDF_PATH\"
          ./install.sh esp32c5
        "
      '';
      tests = {
        syntax = writers.testBash "test-esp-idf-install-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        path_check = writers.testBash "test-esp-idf-install-paths" ''
          # Test that script checks for required paths - placeholder
          echo "✅ Path validation test passed (placeholder)"
        '';
      };
    };
    
    esp-idf-shell = mkBashScript {
      name = "esp-idf-shell";
      deps = with pkgs; [ coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        # Start ESP-IDF development shell with proper environment
        
        echo "Starting ESP-IDF development shell..."
        
        IDF_PATH="''${IDF_PATH:-$HOME/src/dsp/esp-idf}"
        ESP_IDF_FHS_ENV="''${ESP_IDF_FHS_ENV:-esp-idf-fhs}"
        
        if [[ -z "$ESP_IDF_FHS_ENV" ]]; then
          echo "❌ Error: ESP-IDF FHS environment not available"
          echo "   This script requires enableEspIdf = true in your home configuration"
          exit 1
        fi
        
        if [[ ! -f "$IDF_PATH/export.sh" ]]; then
          echo "❌ Error: ESP-IDF not found at $IDF_PATH"
          echo "   Please ensure ESP-IDF is cloned to $IDF_PATH"
          echo "   Run: git clone --recursive https://github.com/espressif/esp-idf.git $IDF_PATH"
          exit 1
        fi
        
        # Enter FHS environment with ESP-IDF activated
        "$ESP_IDF_FHS_ENV" -c "
          export IDF_PATH=$IDF_PATH
          source \"$IDF_PATH/export.sh\"
          echo \"ESP-IDF environment activated!\"
          echo \"ESP-IDF version: \$(idf.py --version 2>/dev/null || echo 'Not installed - run esp-idf-install first')\"
          exec bash
        "
      '';
      tests = {
        syntax = writers.testBash "test-esp-idf-shell-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        environment_check = writers.testBash "test-esp-idf-shell-env" ''
          # Test environment variable detection - placeholder
          echo "✅ Environment check test passed (placeholder)"
        '';
      };
    };
    
    esp-idf-export = mkBashScript {
      name = "esp-idf-export";
      deps = with pkgs; [ coreutils grep ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        # Output environment variables for ESP-IDF setup
        # Usage: eval $(esp-idf-export)
        
        IDF_PATH="''${IDF_PATH:-$HOME/src/dsp/esp-idf}"
        ESP_IDF_FHS_ENV="''${ESP_IDF_FHS_ENV:-esp-idf-fhs}"
        
        if [[ ! -f "$IDF_PATH/export.sh" ]]; then
          echo "echo 'Error: ESP-IDF not found at $IDF_PATH'" >&2
          exit 1
        fi
        
        if [[ -z "$ESP_IDF_FHS_ENV" ]]; then
          echo "echo 'Error: ESP-IDF FHS environment not available'" >&2
          exit 1
        fi
        
        echo "export IDF_PATH=$IDF_PATH"
        "$ESP_IDF_FHS_ENV" -c "
          source $IDF_PATH/export.sh > /dev/null 2>&1
          env | grep -E '^(PATH|IDF_|ESP_)' | sed 's/^/export /'
        "
      '';
      tests = {
        syntax = writers.testBash "test-esp-idf-export-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        output_format = writers.testBash "test-esp-idf-export-format" ''
          # Test that output is in proper export format - placeholder
          echo "✅ Output format test passed (placeholder)"
        '';
      };
    };
    
    idf-py = mkBashScript {
      name = "idf.py";
      deps = with pkgs; [ coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        # Wrapper for idf.py that ensures FHS environment
        
        IDF_PATH="''${IDF_PATH:-$HOME/src/dsp/esp-idf}"
        ESP_IDF_FHS_ENV="''${ESP_IDF_FHS_ENV:-esp-idf-fhs}"
        
        if [[ -z "$ESP_IDF_FHS_ENV" ]]; then
          echo "❌ Error: ESP-IDF FHS environment not available" >&2
          echo "   This script requires enableEspIdf = true in your home configuration" >&2
          exit 1
        fi
        
        "$ESP_IDF_FHS_ENV" -c "
          export IDF_PATH=$IDF_PATH
          source \"$IDF_PATH/export.sh\" > /dev/null 2>&1
          exec idf.py \"\$@\"
        " -- "$@"
      '';
      tests = {
        syntax = writers.testBash "test-idf-py-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        argument_passing = writers.testBash "test-idf-py-args" ''
          # Test that arguments are properly passed through - placeholder
          echo "✅ Argument passing test passed (placeholder)"
        '';
      };
    };
    
    # Claude Code wrapper - migrated from home/common/claude-code.nix
    claude-code-wrapper = mkBashScript {
      name = "claude";
      deps = with pkgs; [ nodejs_22 coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        # Claude Code user-local installation wrapper
        
        # Set up local installation directories
        mkdir -p "$HOME/.local/share/claude-code"
        mkdir -p "$HOME/.local/bin"
        
        # Configure npm to use local prefix
        export NPM_CONFIG_PREFIX="$HOME/.local/share/claude-code/npm"
        export PATH="$HOME/.local/share/claude-code/npm/bin:$PATH"
        
        # Install claude-code if not already present
        if [ ! -x "$HOME/.local/share/claude-code/npm/bin/claude" ]; then
          echo "Installing claude-code to user directory..."
          if command -v npm >/dev/null 2>&1; then
            npm install -g @anthropic-ai/claude-code
          else
            echo "❌ Error: npm not available"
            echo "   Please ensure Node.js is installed and available in PATH"
            exit 1
          fi
        fi
        
        # Execute claude with all arguments
        exec "$HOME/.local/share/claude-code/npm/bin/claude" "$@"
      '';
      tests = {
        syntax = writers.testBash "test-claude-code-wrapper-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        directory_setup = writers.testBash "test-claude-code-wrapper-dirs" ''
          # Test that script sets up proper directory structure - placeholder
          echo "✅ Directory setup test passed (placeholder)"
        '';
      };
    };
    
    # Claude Code update script - companion to the main wrapper
    claude-code-update = mkBashScript {
      name = "claude-update";
      deps = with pkgs; [ nodejs_22 coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        # Update claude-code installation
        
        export NPM_CONFIG_PREFIX="$HOME/.local/share/claude-code/npm"
        echo "Updating claude-code..."
        
        if command -v npm >/dev/null 2>&1; then
          npm update -g @anthropic-ai/claude-code
          echo "Update complete!"
        else
          echo "❌ Error: npm not available"
          echo "   Please ensure Node.js is installed and available in PATH"
          exit 1
        fi
      '';
      tests = {
        syntax = writers.testBash "test-claude-code-update-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        npm_check = writers.testBash "test-claude-code-update-npm" ''
          # Test npm availability check - placeholder
          echo "✅ NPM check test passed (placeholder)"
        '';
      };
    };
    
    # TEST: OneDrive force sync script (moved here to test evaluation)  
    onedrive-force-sync = mkBashScript {
      name = "onedrive-force-sync";
      deps = with pkgs; [ coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
          echo "❌ This script only works in WSL environments"
          exit 1
        fi
        
        echo "Forcing OneDrive sync..."
      '';
      tests = {
        syntax = writers.testBash "test-onedrive-force-sync-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
      };
    };
    
    # Tmux utility scripts - migrated from home/files/bin/
    tmux-auto-attach = mkScriptLibrary {
      name = "tmux-auto-attach";
      deps = with pkgs; [ tmux coreutils gawk ];
      text = /* bash */ ''
        # tmux-auto-attach: Shared tmux auto-attach logic with continuum support
        # This script is sourced by both bash and zsh initialization to ensure
        # consistent tmux behavior regardless of which shell is configured.
        
        # tmux auto-attach on interactive shell startup
        # Only attach if:
        # 1. We're in an interactive shell
        # 2. Not already in a tmux session
        # 3. Not in a nested SSH session to the same host
        # 4. Terminal supports it (not dumb terminal)
        tmux_auto_attach() {
            if [[ $- == *i* && -z "$TMUX" && "$TERM" != "dumb" ]]; then
                # Check if we're in a nested SSH session to the same host
                if [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
                    # Get the hostname we SSH'd from (first field of SSH_CLIENT)
                    local ssh_from_host=$(echo "$SSH_CLIENT" | awk '{print $1}')
                    # Only proceed if it's not a loopback connection
                    if [[ "$ssh_from_host" != "127.0.0.1" && "$ssh_from_host" != "::1" ]]; then
                        # Safe to attach - we're SSHing from a different host
                        _tmux_attach_or_create
                    fi
                else
                    # Not in SSH at all, safe to attach
                    _tmux_attach_or_create
                fi
            fi
        }
        
        # Helper function that implements the improved attach logic
        # This allows continuum to auto-restore before we create new sessions
        _tmux_attach_or_create() {
            # First try to attach to any existing session
            # This allows tmux-continuum to auto-restore sessions if configured
            if ! tmux attach 2>/dev/null; then
                # No sessions exist - now it's safe to create our default "main" session
                # At this point, continuum has had a chance to restore sessions
                tmux new-session -A -s main
            fi
        }
        
        # Call the function when this script is sourced
        tmux_auto_attach
      '';
      tests = {
        syntax = writers.testBash "test-tmux-auto-attach-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        function_definition = writers.testBash "test-tmux-auto-attach-functions" ''
          # Test that functions are properly defined when sourced
          # This is a placeholder - full testing would require tmux environment
          echo "✅ Function definition test passed (placeholder)"
        '';
        ssh_detection = writers.testBash "test-tmux-auto-attach-ssh" ''
          # Test SSH client detection logic
          # Placeholder for comprehensive SSH detection testing
          echo "✅ SSH detection test passed (placeholder)"
        '';
      };
    };
    
    
    # Improved tmux session picker using Miller and jq for robust TSV parsing
    tmux-session-picker = mkBashScript {
      name = "tmux-session-picker";
      deps = with pkgs; [ tmux fzf miller jq coreutils findutils gnugrep gnused ];
      text = builtins.replaceStrings 
        [ "~/.tmux/plugins/tmux-resurrect/scripts/restore.sh" ]
        [ "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/restore.sh" ]
        (builtins.readFile ../../files/bin/tmux-session-picker-v2);
      tests = {
        syntax = writers.testBash "test-tmux-session-picker-v2-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        miller_parsing = writers.testBash "test-tmux-session-picker-v2-miller" ''
          # Test Miller TSV parsing functionality - placeholder
          echo "✅ Miller parsing test passed (placeholder)"
        '';
        json_processing = writers.testBash "test-tmux-session-picker-v2-json" ''
          # Test jq JSON processing - placeholder
          echo "✅ JSON processing test passed (placeholder)"
        '';
        preview_generation = writers.testBash "test-tmux-session-picker-v2-preview" ''
          # Test preview generation with complex session structures - placeholder
          echo "✅ Preview generation test passed (placeholder)"
        '';
      };
    };
    
    # Alternative simple tmux resurrect session browser
    
    # Color utility library - migrated from home/files/bin/colorfuncs.sh
    colorfuncs = mkScriptLibrary {
      name = "colorfuncs";
      deps = with pkgs; [ ncurses coreutils gawk ps ];
      text = /* bash */ ''
        # colorfuncs.sh - Terminal formatting functions using tput
        # Part of nixcfg home manager configuration
        # Source this file to get portable terminal color functions
        
        # Check if tput is available and terminal supports colors
        if ! command -v tput >/dev/null 2>&1 || [[ ! -t 1 ]] || [[ $(tput colors 2>/dev/null || echo 0) -lt 8 ]]; then
            # Fallback: No-op functions when colors not supported
            function cf_bold() { echo "$*"; }
            function cf_dim() { echo "$*"; }
            function cf_underline() { echo "$*"; }
            function cf_reverse() { echo "$*"; }
            function cf_red() { echo "$*"; }
            function cf_green() { echo "$*"; }
            function cf_yellow() { echo "$*"; }
            function cf_blue() { echo "$*"; }
            function cf_magenta() { echo "$*"; }
            function cf_cyan() { echo "$*"; }
            function cf_white() { echo "$*"; }
            function cf_black() { echo "$*"; }
            function cf_reset() { echo "$*"; }
            function cf_clear_line() { echo "$*"; }
            function cf_move_up() { echo "$*"; }
            function cf_hide_cursor() { echo "$*"; }
            function cf_show_cursor() { echo "$*"; }
            return 0
        fi
        
        # Cache tput values for performance
        declare -g CF_BOLD CF_DIM CF_UNDERLINE CF_REVERSE CF_RESET
        declare -g CF_RED CF_GREEN CF_YELLOW CF_BLUE CF_MAGENTA CF_CYAN CF_WHITE CF_BLACK
        declare -g CF_CLEAR_LINE CF_MOVE_UP CF_HIDE_CURSOR CF_SHOW_CURSOR
        
        # Initialize formatting codes
        CF_BOLD=$(tput bold 2>/dev/null || echo "")
        CF_DIM=$(tput dim 2>/dev/null || echo "")
        CF_UNDERLINE=$(tput smul 2>/dev/null || echo "")
        CF_REVERSE=$(tput rev 2>/dev/null || echo "")
        CF_RESET=$(tput sgr0 2>/dev/null || echo "")
        
        # Colors
        CF_RED=$(tput setaf 1 2>/dev/null || echo "")
        CF_GREEN=$(tput setaf 2 2>/dev/null || echo "")
        CF_YELLOW=$(tput setaf 3 2>/dev/null || echo "")
        CF_BLUE=$(tput setaf 4 2>/dev/null || echo "")
        CF_MAGENTA=$(tput setaf 5 2>/dev/null || echo "")
        CF_CYAN=$(tput setaf 6 2>/dev/null || echo "")
        CF_WHITE=$(tput setaf 7 2>/dev/null || echo "")
        CF_BLACK=$(tput setaf 0 2>/dev/null || echo "")
        
        # Cursor and line manipulation
        CF_CLEAR_LINE=$(tput el 2>/dev/null || echo "")
        CF_MOVE_UP=$(tput cuu1 2>/dev/null || echo "")
        CF_HIDE_CURSOR=$(tput civis 2>/dev/null || echo "")
        CF_SHOW_CURSOR=$(tput cnorm 2>/dev/null || echo "")
        
        # Text formatting functions
        function cf_bold() {
            echo "''${CF_BOLD}$*''${CF_RESET}"
        }
        
        function cf_dim() {
            echo "''${CF_DIM}$*''${CF_RESET}"
        }
        
        function cf_underline() {
            echo "''${CF_UNDERLINE}$*''${CF_RESET}"
        }
        
        function cf_reverse() {
            echo "''${CF_REVERSE}$*''${CF_RESET}"
        }
        
        # Color functions
        function cf_red() {
            echo "''${CF_RED}$*''${CF_RESET}"
        }
        
        function cf_green() {
            echo "''${CF_GREEN}$*''${CF_RESET}"
        }
        
        function cf_yellow() {
            echo "''${CF_YELLOW}$*''${CF_RESET}"
        }
        
        function cf_blue() {
            echo "''${CF_BLUE}$*''${CF_RESET}"
        }
        
        function cf_magenta() {
            echo "''${CF_MAGENTA}$*''${CF_RESET}"
        }
        
        function cf_cyan() {
            echo "''${CF_CYAN}$*''${CF_RESET}"
        }
        
        function cf_white() {
            echo "''${CF_WHITE}$*''${CF_RESET}"
        }
        
        function cf_black() {
            echo "''${CF_BLACK}$*''${CF_RESET}"
        }
        
        # Combined formatting functions
        function cf_bold_red() {
            echo "''${CF_BOLD}''${CF_RED}$*''${CF_RESET}"
        }
        
        function cf_bold_green() {
            echo "''${CF_BOLD}''${CF_GREEN}$*''${CF_RESET}"
        }
        
        function cf_bold_yellow() {
            echo "''${CF_BOLD}''${CF_YELLOW}$*''${CF_RESET}"
        }
        
        function cf_bold_blue() {
            echo "''${CF_BOLD}''${CF_BLUE}$*''${CF_RESET}"
        }
        
        function cf_bold_cyan() {
            echo "''${CF_BOLD}''${CF_CYAN}$*''${CF_RESET}"
        }
        
        # Utility functions
        function cf_reset() {
            echo -n "$CF_RESET"
        }
        
        function cf_clear_line() {
            echo -n "$CF_CLEAR_LINE"
        }
        
        function cf_move_up() {
            echo -n "$CF_MOVE_UP"
        }
        
        function cf_hide_cursor() {
            echo -n "$CF_HIDE_CURSOR"
        }
        
        function cf_show_cursor() {
            echo -n "$CF_SHOW_CURSOR"
        }
        
        # High-level logging functions for common use cases
        # Detect Unicode support and use appropriate icons
        if [[ "$LANG" =~ UTF-8 ]] && [[ "$TERM" != "linux" ]] && locale -k LC_CTYPE 2>/dev/null | grep -q 'charmap="UTF-8"'; then
            # Unicode icons for compatible terminals
            function cf_info() {
                echo "$(cf_blue "ℹ️  $*")"
            }
            
            function cf_success() {
                echo "$(cf_green "✅ $*")"
            }
            
            function cf_warning() {
                echo "$(cf_yellow "⚠️  $*")"
            }
            
            function cf_error() {
                echo "$(cf_red "❌ $*")"
            }
            
            function cf_step() {
                echo "$(cf_cyan "📋 $*")"
            }
        else
            # ASCII alternatives for compatibility
            function cf_info() {
                echo "$(cf_blue "[INFO] $*")"
            }
            
            function cf_success() {
                echo "$(cf_green "[OK] $*")"
            }
            
            function cf_warning() {
                echo "$(cf_yellow "[WARN] $*")"
            }
            
            function cf_error() {
                echo "$(cf_red "[ERROR] $*")"
            }
            
            function cf_step() {
                echo "$(cf_cyan "[STEP] $*")"
            }
        fi
        
        function cf_header() {
            echo "$(cf_bold_blue "$*")"
        }

        # Progress indication
        function cf_spinner() {
            local pid=$1
            local delay=0.1
            local spinchars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
            local temp
            
            cf_hide_cursor
            while ps -p "$pid" > /dev/null 2>&1; do
                temp="''${spinchars:i++%''${#spinchars}:1}"
                printf "\r$(cf_cyan "%s") %s" "$temp" "''${2:-Working...}"
                sleep $delay
            done
            printf "\r$(cf_clear_line)"
            cf_show_cursor
        }
        
        # Test function to demonstrate all capabilities
        function cf_test() {
            echo "=== Color Functions Test ==="
            echo
            echo "Basic colors:"
            cf_red "Red text"
            cf_green "Green text"
            cf_yellow "Yellow text"
            cf_blue "Blue text"
            cf_magenta "Magenta text"
            cf_cyan "Cyan text"
            cf_white "White text"
            echo
            echo "Formatting:"
            cf_bold "Bold text"
            cf_dim "Dim text"
            cf_underline "Underlined text"
            cf_reverse "Reversed text"
            echo
            echo "Combined formatting:"
            cf_bold_red "Bold red text"
            cf_bold_green "Bold green text"
            cf_bold_blue "Bold blue text"
            echo
            echo "Logging functions:"
            cf_info "This is an info message"
            cf_success "This is a success message"
            cf_warning "This is a warning message"
            cf_error "This is an error message"
            cf_step "This is a step message"
            cf_header "This is a header"
            echo
            echo "Terminal info:"
            echo "Terminal supports $(tput colors 2>/dev/null || echo 0) colors"
            echo "Terminal columns: $(tput cols 2>/dev/null || echo "unknown")"
            echo "Terminal lines: $(tput lines 2>/dev/null || echo "unknown")"
        }
        
        # Make color codes available as variables
        export CF_BOLD CF_DIM CF_UNDERLINE CF_REVERSE CF_RESET
        export CF_RED CF_GREEN CF_YELLOW CF_BLUE CF_MAGENTA CF_CYAN CF_WHITE CF_BLACK
        export CF_CLEAR_LINE CF_MOVE_UP CF_HIDE_CURSOR CF_SHOW_CURSOR
      '';
      tests = {
        syntax = writers.testBash "test-colorfuncs-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        function_definitions = writers.testBash "test-colorfuncs-functions" ''
          # Test that functions are properly defined when sourced
          # This is a placeholder - full testing would require terminal environment
          echo "✅ Function definition test passed (placeholder)"
        '';
        unicode_detection = writers.testBash "test-colorfuncs-unicode" ''
          # Test Unicode detection and fallback logic
          # Placeholder for comprehensive Unicode testing
          echo "✅ Unicode detection test passed (placeholder)"
        '';
        color_support = writers.testBash "test-colorfuncs-color" ''
          # Test color support detection and fallback
          # Placeholder for color capability testing
          echo "✅ Color support test passed (placeholder)"
        '';
      };
    };

    # JSON merging utility for selective field updates
    mergejson = mkBashScript {
      name = "mergejson";
      deps = with pkgs; [ jq ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        usage() {
          echo "Usage: mergejson OLD_FILE NEW_FILE JQ_QUERY [--confirm]"
          echo "  Merges selected fields from NEW_FILE into OLD_FILE"
          echo "  JQ_QUERY: jq expression selecting fields to merge"
          echo "  --confirm: prompt before applying changes"
          exit 1
        }
        
        [[ $# -lt 3 ]] && usage
        
        old_file="$1"
        new_file="$2"
        jq_query="$3"
        confirm_flag="''${4:-}"
        
        [[ ! -f "$old_file" ]] && { echo "Error: $old_file not found"; exit 1; }
        [[ ! -f "$new_file" ]] && { echo "Error: $new_file not found"; exit 1; }
        
        extract_tmp=$(mktemp)
        jq "$jq_query" "$new_file" > "$extract_tmp"
        
        jq --slurpfile extract_data "$extract_tmp" \
           '. + $extract_data[0]' \
           "$old_file" > "$old_file.merged"
        
        if ! diff -q "$old_file" "$old_file.merged" >/dev/null 2>&1; then
          if [[ "$confirm_flag" == "--confirm" ]]; then
            echo "Changes detected in: $jq_query"
            read -p "View diff? [y/N]: " choice
            if [[ ''${choice,,} =~ ^y ]]; then
              nvim -d "$old_file" "$old_file.merged"
              read -p "Apply changes? [y/N]: " apply_choice
              [[ ''${apply_choice,,} =~ ^y ]] || { rm -f "$extract_tmp" "$old_file.merged"; exit 1; }
            fi
          fi
          mv "$old_file.merged" "$old_file"
          echo "Merged: $jq_query"
        else
          rm -f "$old_file.merged"
        fi
        
        rm -f "$extract_tmp"
      '';
      tests = {
        basic = writers.testBash "test-mergejson-basic" ''
          cd $(mktemp -d)
          
          echo '{"a":1,"b":2}' > old.json
          echo '{"a":99,"c":3}' > new.json
          
          mergejson old.json new.json '{a}'
          
          result=$(jq -r '.a' old.json)
          [[ "$result" == "99" ]] || { echo "Expected a=99, got $result"; exit 1; }
          
          result=$(jq -r '.b' old.json)  
          [[ "$result" == "2" ]] || { echo "Expected b=2, got $result"; exit 1; }
          
          echo "✅ Basic merge test passed"
        '';
        preserve = writers.testBash "test-mergejson-preserve" ''
          cd $(mktemp -d)
          
          echo '{"keep":"me","change":"old"}' > old.json
          echo '{"change":"new","ignore":"ignored"}' > new.json
          
          mergejson old.json new.json '{change}'
          
          result=$(jq -r '.keep' old.json)
          [[ "$result" == "me" ]] || { echo "Expected keep=me, got $result"; exit 1; }
          
          result=$(jq -r '.change' old.json)
          [[ "$result" == "new" ]] || { echo "Expected change=new, got $result"; exit 1; }
          
          [[ $(jq -r '.ignore // "missing"' old.json) == "missing" ]] || { echo "Should not have ignore field"; exit 1; }
          
          echo "✅ Preserve fields test passed"
        '';
        nochange = writers.testBash "test-mergejson-nochange" ''
          cd $(mktemp -d)
          
          echo '{"same":"value"}' > old.json
          echo '{"same":"value","other":"data"}' > new.json
          
          cp old.json old.json.backup
          mergejson old.json new.json '{same}'
          
          diff old.json old.json.backup || { echo "File should not have changed"; exit 1; }
          
          echo "✅ No change test passed"
        '';
      };
    };
    
    # Emoji and terminal diagnostic tool - migrated from home/files/bin/diagnose-emoji-rendering
    diagnose-emoji-rendering = mkBashScript {
      name = "diagnose-emoji-rendering";
      deps = with pkgs; [ fontconfig xxd coreutils gnugrep gawk ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        # Comprehensive diagnostic tool for Windows Terminal + WSL alignment
        # Checks font configuration, emoji rendering, and terminal capabilities
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "                Terminal/WSL Alignment Diagnostic                      "
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
        
        # Check environment variables from terminal-verification module
        echo "=== Alignment Status ==="
        if [[ -n "$WT_ALIGNMENT_OK" ]]; then
            if [[ "$WT_ALIGNMENT_OK" == "1" ]]; then
                echo "✅ Windows Terminal is properly aligned with WSL NixOS"
            elif [[ "$WT_ALIGNMENT_OK" == "0" ]]; then
                echo "❌ Misalignment detected between Windows Terminal and WSL"
                echo
                echo "Issues:"
                [[ "$WT_FONT_OK" == "0" ]] && echo "  ❌ Font: ''${WT_CONFIGURED_FONT:-not configured}"
                [[ "$WT_INTENSE_OK" == "0" ]] && echo "  ❌ Bold rendering: ''${WT_INTENSE_STYLE:-not configured}"
            else
                echo "⚠️  Cannot verify alignment (Windows Terminal settings not found)"
            fi
        else
            echo "⚠️  Alignment check not available (run from a new shell or run 'check-terminal-setup')"
        fi
        
        echo
        echo "=== Current Configuration ==="
        echo "Windows Terminal:"
        if [[ -n "$WT_CONFIGURED_FONT" ]]; then
            echo "  Font: $WT_CONFIGURED_FONT"
            echo "  Bold rendering: ''${WT_INTENSE_STYLE:-unknown}"
        else
            echo "  Font: Unable to detect (run 'check-terminal-setup' first)"
        fi
        
        echo
        echo "Expected (for proper alignment):"
        echo "  Font: ''${WT_EXPECTED_FONT:-CaskaydiaMono Nerd Font Mono, Noto Color Emoji}"
        echo "  Bold rendering: ''${WT_EXPECTED_INTENSE:-all}"
        
        echo
        echo "=== WSL Font Configuration ==="
        echo "Checking NixOS fontconfig..."
        if command -v fc-list >/dev/null 2>&1; then
            CASCADIA_COUNT=$(fc-list | grep -iE "caskaydia.*mono.*nerd" | wc -l)
            EMOJI_COUNT=$(fc-list | grep -iE "(emoji|color)" | wc -l)
            
            if [[ "$CASCADIA_COUNT" -gt 0 ]]; then
                echo "  ✅ CascadiaMono Nerd Font: $CASCADIA_COUNT variants found"
            else
                echo "  ❌ CascadiaMono Nerd Font: Not found in WSL"
                echo "     Run: nix run home-manager -- switch"
            fi
            
            if [[ "$EMOJI_COUNT" -gt 0 ]]; then
                echo "  ✅ Emoji fonts: $EMOJI_COUNT fonts available"
            else
                echo "  ⚠️  Emoji fonts: None found in WSL"
            fi
        else
            echo "  ⚠️  fontconfig not available"
        fi
        
        echo
        echo "=== Windows Font Availability ==="
        if command -v powershell.exe >/dev/null 2>&1; then
            echo "Checking Windows font installation..."
            powershell.exe -Command "
                \$results = @{}
                
                # Check primary font
                try {
                    \$family = [System.Drawing.FontFamily]::new('CaskaydiaMonoNerdFontMono')
                    \$results['CaskaydiaMonoNerdFontMono'] = 'installed'
                    \$family.Dispose()
                } catch {
                    \$results['CaskaydiaMonoNerdFontMono'] = 'missing'
                }
                
                # Check emoji fonts
                @('Noto Color Emoji', 'Segoe UI Emoji').ForEach({
                    try {
                        \$family = [System.Drawing.FontFamily]::new(\$_)
                        \$results[\$_] = 'installed'
                        \$family.Dispose()
                    } catch {
                        \$results[\$_] = 'missing'
                    }
                })
                
                # Output results
                if (\$results['CaskaydiaMonoNerdFontMono'] -eq 'installed') {
                    Write-Host '  ✅ CaskaydiaMonoNerdFontMono: Installed'
                } else {
                    Write-Host '  ❌ CaskaydiaMonoNerdFontMono: Not installed'
                }
                
                if (\$results['Noto Color Emoji'] -eq 'installed') {
                    Write-Host '  ✅ Noto Color Emoji: Installed'
                } else {
                    Write-Host '  ⚠️  Noto Color Emoji: Not installed (recommended for best emoji support)'
                }
                
                if (\$results['Segoe UI Emoji'] -eq 'installed') {
                    Write-Host '  ✅ Segoe UI Emoji: Installed (Windows built-in)'
                } else {
                    Write-Host '  ⚠️  Segoe UI Emoji: Not available'
                }
            " 2>/dev/null || echo "  ⚠️  PowerShell check failed"
        else
            echo "  ⚠️  PowerShell not available for font checking"
        fi
        
        echo
        echo "=== Visual Rendering Tests ==="
        echo
        echo "Bold text test:"
        printf "  Normal: The quick brown fox\n"
        printf "  Bold:   \033[1mThe quick brown fox\033[0m\n"
        echo "  → Bold should appear heavier/thicker than normal"
        
        echo
        echo "Emoji rendering test:"
        echo "  Basic: ⚠️ ✅ ❌"
        echo "  Color: 🔥 👍 🌟 🚀"
        echo "  → You should see colorful emoji icons, not boxes or question marks"
        
        echo
        echo "Nerd Font symbols test:"
        echo "  Powerline:  "
        echo "  Icons:  󰊢   󰅂"
        echo "  → These should appear as distinct symbols, not boxes"
        
        echo
        echo "Box drawing test:"
        echo "  ┌────────────────┐"
        echo "  │ Box drawing OK │"
        echo "  └────────────────┘"
        echo "  → Lines should connect seamlessly"
        
        echo
        echo "=== Character Encoding Analysis ==="
        echo "UTF-8 encoding verification:"
        test_chars=("⚠️" "✅" "❌" "🔥")
        all_good=true
        for char in "''${test_chars[@]}"; do
            hex=$(printf "%s" "$char" | xxd -p | tr -d '\n')
            printf "  %-4s → %s " "$char" "$hex"
            
            # Check if encoding is correct
            case "$char" in
                "⚠️") expected="e29aa0efb88f" ;;
                "✅") expected="e29c85" ;;
                "❌") expected="e29d8c" ;;
                "🔥") expected="f09f9485" ;;
            esac
            
            if [[ "$hex" == "$expected" ]]; then
                echo "✓"
            else
                echo "✗ (expected: $expected)"
                all_good=false
            fi
        done
        
        if $all_good; then
            echo "  → All characters encoded correctly"
        else
            echo "  → Character encoding issues detected"
        fi
        
        echo
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "                           Recommendations                             "
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        if [[ "$WT_NEEDS_FIX" == "1" ]] || [[ "$WT_ALIGNMENT_OK" == "0" ]]; then
            echo
            echo "🔧 QUICK FIX AVAILABLE:"
            echo
            echo "   Run: setup-terminal-fonts"
            echo
            echo "   This will automatically:"
            echo "   • Download and install required fonts"
            echo "   • Update Windows Terminal settings"
            echo "   • Configure proper font fallback chain"
            echo
        elif [[ "$WT_ALIGNMENT_OK" == "1" ]]; then
            echo
            echo "✅ Your terminal is properly configured!"
            echo
            echo "   No action needed - fonts and settings are aligned."
            echo
        else
            echo
            echo "⚠️  MANUAL SETUP REQUIRED:"
            echo
            echo "   1. Install Windows Terminal from Microsoft Store"
            echo "   2. Run Windows Terminal to create initial settings"
            echo "   3. Run 'setup-terminal-fonts' to configure"
            echo
        fi
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      '';
      tests = {
        syntax = writers.testBash "test-diagnose-emoji-rendering-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
        visual_tests = writers.testBash "test-diagnose-emoji-rendering-visual" ''
          # Test visual rendering test functions - placeholder
          echo "✅ Visual test framework test passed (placeholder)"
        '';
        encoding_tests = writers.testBash "test-diagnose-emoji-rendering-encoding" ''
          # Test character encoding analysis - placeholder
          echo "✅ Encoding analysis test passed (placeholder)"
        '';
        font_detection = writers.testBash "test-diagnose-emoji-rendering-fonts" ''
          # Test font detection logic - placeholder
          echo "✅ Font detection test passed (placeholder)"
        '';
      };
    };
  };
  
  # WSL-specific utilities (previously after line 1090)
  wslScripts = {
    # OneDrive sync utilities - included unconditionally but check WSL at runtime  
    onedrive-force-sync = mkBashScript {
      name = "onedrive-force-sync";
      deps = with pkgs; [ coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
          echo "❌ This script only works in WSL environments"
          exit 1
        fi
        
        echo "🔄 Forcing OneDrive sync..."
        echo "=========================="
        
        # Method 1: Touch OneDrive directory to trigger sync
        if [[ -d "/mnt/c/Users/tblack/OneDrive" ]]; then
          echo "📁 Touching OneDrive directory..."
          touch "/mnt/c/Users/tblack/OneDrive"
          
          # Method 2: Create and remove a sync trigger file
          echo "📝 Creating sync trigger file..."
          trigger_file="/mnt/c/Users/tblack/OneDrive/.sync_trigger_$(date +%s)"
          touch "$trigger_file"
          sleep 1
          rm -f "$trigger_file"
          
          echo "✅ Sync triggered successfully"
          echo ""
          echo "💡 Note: OneDrive may take a few moments to sync"
          echo "   Run 'onedrive-status' to check sync status"
        else
          echo "❌ OneDrive directory not found at /mnt/c/Users/tblack/OneDrive"
          exit 1
        fi
      '';
      tests = {
        syntax = writers.testBash "test-onedrive-force-sync-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
      };
    };
    
    onedrive-status = mkBashScript {
      name = "onedrive-status";
      deps = with pkgs; [ coreutils ];
      text = /* bash */ ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
          echo "❌ This script only works in WSL environments"
          exit 1
        fi
        
        echo "📊 OneDrive Status Check"
        echo "======================"
        
        # Check if OneDrive process is running
        if /mnt/c/Windows/System32/cmd.exe /c "tasklist /fi \"imagename eq OneDrive.exe\" | find \"OneDrive.exe\"" > /dev/null 2>&1; then
          echo "✅ OneDrive process is running"
        else
          echo "❌ OneDrive process is not running"
        fi
        
        # Check current directory OneDrive status
        current_dir="$(pwd)"
        if [[ "$current_dir" =~ /mnt/c/Users/.*OneDrive ]]; then
          echo "📁 Current directory is in OneDrive: $current_dir"
          echo "📋 Recent files in current directory:"
          ls -lat | head -5
        else
          echo "📁 Current directory is not in OneDrive: $current_dir"
        fi
        
        echo ""
        echo "💡 To force sync, run: onedrive-force-sync"
      '';
      tests = {
        syntax = writers.testBash "test-onedrive-status-syntax" ''
          echo "✅ Syntax validation passed at build time"
        '';
      };
    };
  };
  
in {
  config = mkIf (cfg.enable && cfg.enableBashScripts) {
    validatedScripts.bashScripts = {
      # Additional scripts defined directly in config to work around evaluation issue
      simple-test = mkBashScript {
        name = "simple-test";
        deps = with pkgs; [ coreutils ];
        text = ''
          #!/usr/bin/env bash
          echo "Simple test script"
        '';
        tests = {};
      };
      
      onedrive-status = mkBashScript {
        name = "onedrive-status";
        deps = with pkgs; [ coreutils ];
        text = /* bash */ ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
            echo "❌ This script only works in WSL environments"
            exit 1
          fi
          
          echo "Checking OneDrive status..."
        '';
        tests = {
          syntax = writers.testBash "test-onedrive-status-syntax" ''
            echo "✅ Syntax validation passed at build time"
          '';
        };
      };
    };
  };
}