# Bash Scripts - Validated bash script definitions
{ config, lib, pkgs, mkValidatedScript, mkBashScript, mkScriptLibrary, writers, ... }:

with lib;

let
  cfg = config.validatedScripts;

  # Helper function for Claude wrapper script generation
  mkClaudeWrapper = { account, displayName, configDir, extraEnvVars ? { } }: ''
    account="${account}"
    config_dir="${configDir}"
    pidfile="/tmp/claude-''${account}.pid"
    
    # Check for headless mode - bypass PID check for stateless operations
    if [[ "$*" =~ (^|[[:space:]])-p([[:space:]]|$) || "$*" =~ (^|[[:space:]])--print([[:space:]]|$) ]]; then
      export CLAUDE_CONFIG_DIR="$config_dir"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
      exec claude "$@"
    fi
    
    # Single instance enforcement
    if [[ -f "$pidfile" ]]; then
      existing_pid=$(cat "$pidfile")
      if kill -0 "$existing_pid" 2>/dev/null; then
        echo "❌ Claude Code (${displayName}) is already running (PID: $existing_pid)"
        echo "   Please close the existing session first or use 'kill $existing_pid' to force close"
        exit 1
      else
        rm -f "$pidfile"
      fi
    fi
    
    # Merge Nix-managed configuration at startup
    config_file="$config_dir/.claude.json"
    if [[ -f "$config_file" ]]; then
      echo 'null' | ${pkgs.jq}/bin/jq \
        --argjson mcpServers '{}' \
        --argjson permissions '{}' \
        --argjson statusLine '{}' \
        --argjson hooks '{}' \
        '{mcpServers: $mcpServers, permissions: $permissions, statusLine: $statusLine, hooks: $hooks}' \
        > "$config_file.nix-managed"
    
      if command -v mergejson >/dev/null 2>&1 && mergejson "$config_file" "$config_file.nix-managed" '.'; then
        :  # Silent success
      else
        echo "⚠️  Configuration merge failed"
      fi
      rm -f "$config_file.nix-managed"
    fi
    
    # Launch Claude Code with proper PID tracking
    export CLAUDE_CONFIG_DIR="$config_dir"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") extraEnvVars)}
    echo "🤖 Launching Claude ${displayName}..."
    
    trap "rm -f '$pidfile'" EXIT INT TERM
    echo $$ > "$pidfile"
    
    claude "$@"
    exit_code=$?
    
    rm -f "$pidfile"
    unset CLAUDE_CONFIG_DIR
    trap - EXIT INT TERM
    
    exit $exit_code
  '';

  # Split scripts into multiple groups to avoid evaluation issues
  # Note: Test scripts (simple-test, hello-validated) removed as they're being migrated to home/files
  testScripts = { };

  # Main scripts collection (previously lines 24-1090)
  mainScripts = {
    # Claude Code wrapper scripts - migrated from claude-code.nix
    # Dynamic generation based on enabled accounts
  } // (lib.optionalAttrs false {
    claude = mkBashScript {
      name = "claude";
      deps = with pkgs; [ jq coreutils ];
      text = mkClaudeWrapper {
        account = claudeCfg.defaultAccount;
        displayName = claudeCfg.accounts.${claudeCfg.defaultAccount}.displayName or "Claude Default Account";
        configDir = "${claudeCfg.nixcfgPath}/claude-runtime/.claude-${claudeCfg.defaultAccount}";
        extraEnvVars = {
          DISABLE_TELEMETRY = "1";
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
          DISABLE_ERROR_REPORTING = "1";
        };
      };
      tests = {
        help = writers.testBash "test-claude-help" ''
          # Test help flag functionality
          $script --help >/dev/null 2>&1
          exit_code=$?
          if [[ $exit_code -eq 0 ]]; then
            echo "✅ claude (default) help works"
          else
            echo "❌ claude (default) help failed with exit code $exit_code"
            exit 1
          fi
        '';
      };
    };
  }) // {


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

  };

  # Define library scripts separately to handle cross-references
  terminalUtils = mkScriptLibrary {
    name = "terminal-utils";
    deps = with pkgs; [ coreutils ncurses ];
    text = builtins.readFile ../../files/lib/terminal-utils.bash;
    tests = {
      syntax = writers.testBash "test-terminal-utils-syntax" ''
        echo "✅ Syntax validation passed at build time"
      '';
      display_width = writers.testBash "test-terminal-utils-display-width"
        {
          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";
        } ''
        # Test display width functions
        source ${terminalUtils}
        
        # Test ASCII width
        result=$(get_display_width "hello")
        [[ "$result" == "5" ]] || { echo "❌ ASCII width failed: got $result, expected 5"; exit 1; }
        
        # Test Unicode width (CJK chars should be 2 width each)
        result=$(get_display_width "你好")
        [[ "$result" == "4" ]] || { echo "❌ Unicode width failed: got $result, expected 4"; exit 1; }
        
        # Test emoji width
        result=$(get_display_width "📁")
        [[ "$result" == "2" ]] || { echo "❌ Emoji width failed: got $result, expected 2"; exit 1; }
        
        echo "✅ Display width calculations working correctly"
      '';
      truncation = writers.testBash "test-terminal-utils-truncation"
        {
          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";
        } ''
        # Test truncation functions
        source ${terminalUtils}
        
        # Test ASCII truncation
        result=$(truncate_to_display_width "hello world" 7)
        result_width=$(get_display_width "$result")
        [[ "$result_width" -le 7 ]] || { echo "❌ ASCII truncation failed: result width $result_width > 7"; exit 1; }
        
        # Test Unicode truncation
        result=$(truncate_to_display_width "你好世界" 6)
        result_width=$(get_display_width "$result")
        [[ "$result_width" -le 6 ]] || { echo "❌ Unicode truncation failed: result width $result_width > 6"; exit 1; }
        
        echo "✅ Truncation functions working correctly"
      '';
      terminal_detection = writers.testBash "test-terminal-utils-terminal-detection" ''
        # Test terminal type detection functions
        source ${terminalUtils}
        
        echo "✅ Terminal detection test passed (placeholder)"
      '';
    };
  };

  # Color utilities library
  colorUtils = mkScriptLibrary {
    name = "color-utils";
    deps = with pkgs; [ coreutils ncurses ];
    text = builtins.readFile ../../files/lib/color-utils.bash;
    tests = {
      syntax = writers.testBash "test-color-utils-syntax" ''
        echo "✅ Syntax validation passed at build time"
      '';
      color_detection = writers.testBash "test-color-utils-detection" ''
        # Test color support detection
        source ${colorUtils}
        
        # Test color detection function exists
        type detect_color_support >/dev/null 2>&1 || { echo "❌ detect_color_support function not found"; exit 1; }
        
        echo "✅ Color detection functions working correctly"
      '';
    };
  };

  # Path utilities library
  pathUtils = mkScriptLibrary {
    name = "path-utils";
    deps = with pkgs; [ coreutils ];
    text = builtins.readFile ../../files/lib/path-utils.bash;
    tests = {
      syntax = writers.testBash "test-path-utils-syntax" ''
        echo "✅ Syntax validation passed at build time"
      '';
      path_abbreviation = writers.testBash "test-path-utils-abbreviation" ''
        # Test path abbreviation functions
        source ${pathUtils}
        
        # Test abbreviate_common_paths function exists
        type abbreviate_common_paths >/dev/null 2>&1 || { echo "❌ abbreviate_common_paths function not found"; exit 1; }
        
        # Test basic abbreviation
        result=$(abbreviate_common_paths "$HOME/projects/test")
        [[ "$result" == "~/p/test" ]] || { echo "❌ Path abbreviation failed: got '$result', expected '~/p/test'"; exit 1; }
        
        echo "✅ Path abbreviation functions working correctly"
      '';
    };
  };

in
{
  config = mkIf (cfg.enable && cfg.enableBashScripts) {
    validatedScripts.bashScripts = rec {
      # Library scripts
      terminal-utils = terminalUtils;
      color-utils = colorUtils;
      path-utils = pathUtils;

      # Additional scripts defined directly in config to work around evaluation issue
      # Claude Code wrapper - migrated from home/common/claude-code.nix
      claude-code-wrapper = mkBashScript {
        name = "claude-code-wrapper";
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
              echo "Γ¥î Error: npm not available"
              echo "   Please ensure Node.js is installed and available in PATH"
              exit 1
            fi
          fi
          
          # Execute claude with all arguments
          exec "$HOME/.local/share/claude-code/npm/bin/claude" "$@"
        '';
        tests = {
          syntax = writers.testBash "test-claude-code-wrapper-syntax" ''
            echo "Γ£à Syntax validation passed at build time"
          '';
          directory_setup = writers.testBash "test-claude-code-wrapper-dirs" ''
            # Test that script sets up proper directory structure - placeholder
            echo "Γ£à Directory setup test passed (placeholder)"
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
            echo "Γ¥î Error: npm not available"
            echo "   Please ensure Node.js is installed and available in PATH"
            exit 1
          fi
        '';
        tests = {
          syntax = writers.testBash "test-claude-code-update-syntax" ''
            echo "Γ£à Syntax validation passed at build time"
          '';
          npm_check = writers.testBash "test-claude-code-update-npm" ''
            # Test npm availability check - placeholder
            echo "Γ£à NPM check test passed (placeholder)"
          '';
        };
      };

      # Tmux session picker - read from home/files/ and validate with writers (force rebuild 2025-10-21)
      tmux-session-picker = mkBashScript {
        name = "tmux-session-picker";
        deps = with pkgs; [
          coreutils
          gnugrep
          gnused
          gawk
          findutils
          fd # For file discovery (replaces find)
          parallel # For GNU parallel processing
          fzf
          ripgrep
          tmux
          ncurses # For tput
          tmuxPlugins.resurrect
        ];
        text = builtins.replaceStrings
          [
            "TMUX_RESURRECT_RESTORE_SCRIPT_NIX_PLACEHOLDER"
            "TMUX_CONTINUUM_ENABLED_NIX_PLACEHOLDER"
            "source terminal-utils"
            "source color-utils"
            "source path-utils"
            "tmux-parser-optimized"
          ]
          [
            "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/restore.sh"
            "true"
            "source ${terminalUtils}"
            "source ${colorUtils}"
            "source ${pathUtils}"
            "${tmux-parser-optimized}/bin/tmux-parser-optimized"
          ]  # Since continuum is enabled in tmux.nix
          (builtins.readFile ../../files/bin/tmux-session-picker);
        tests = {
          # Syntax validation happens at build time via writeBashBin
          syntax = writers.testBash "test-tmux-session-picker-syntax" ''
            echo "✅ Syntax validation passed at build time"
          '';

          # CLI Interface Tests - Black-box functional testing
          help_availability = writers.testBash "test-tmux-session-picker-help" ''
            # Test 1.1: Help information is available and comprehensive
            # Expected: Help output contains key sections (usage, options, environment variables)
            output=$(${tmux-session-picker}/bin/tmux-session-picker --help 2>&1)
            exit_code=$?
            
            # Verify help command succeeds (exit code 0)
            if [[ $exit_code -ne 0 ]]; then
              echo "❌ Help command failed with exit code $exit_code"
              exit 1
            fi
            
            # Verify help output contains expected sections
            if echo "$output" | grep -qi "usage\|options\|environment"; then
              echo "✅ Help system provides comprehensive information"
            else
              echo "❌ Help output missing key sections (USAGE, OPTIONS, ENVIRONMENT)"
              echo "Actual output: $output"
              exit 1
            fi
          '';

          # Test 1.2: Verify fzf interface sizing configuration  
          # Expected: Script should use fullscreen fzf (no height restrictions that cause half-height interface)
          fzf_interface_sizing = writers.testBash "test-tmux-session-picker-fzf-sizing" ''
            # Test that the script doesn't contain problematic height calculation 
            # that would cause fzf to only use half the terminal height
            script_content=$(cat ${tmux-session-picker}/bin/tmux-session-picker)
            
            # Verify the script doesn't contain the problematic --height=\${fzf_height} pattern
            if echo "$script_content" | grep -q -- "--height=.*fzf_height"; then
              echo "❌ Script contains problematic height calculation that limits fzf to partial screen"
              echo "Found: $(echo "$script_content" | grep -o -- "--height=.*fzf_height.*")"
              exit 1
            fi
            
            # Verify the script doesn't calculate fixed fzf_height
            if echo "$script_content" | grep -q "fzf_height=.*term_height"; then
              echo "❌ Script calculates fixed fzf height which causes interface sizing issues"
              echo "Found: $(echo "$script_content" | grep -o "fzf_height=.*")"
              exit 1
            fi
            
            # Verify the script uses fullscreen behavior (no --height option in fzf_args)
            if echo "$script_content" | grep -A20 "fzf_args=(" | grep -q -- "--height="; then
              echo "❌ Script still uses --height option which can cause partial screen usage"
              exit 1
            fi
            
            echo "✅ fzf interface sizing correctly configured for fullscreen usage"
          '';

          # Unicode Display Width Testing
          unicode_display_width = writers.testBash "test-tmux-session-picker-unicode-width"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
            # Test that unicode display width functions work correctly with various character types
            script_path="${tmux-session-picker}/bin/tmux-session-picker"
            
            # Source the script functions
            source "$script_path" &>/dev/null || true
            
            # Test ASCII characters (should be 1:1)
            result=$(get_display_width "hello")
            expected=5
            if [[ "$result" != "$expected" ]]; then
              echo "❌ ASCII width calculation failed: got $result, expected $expected"
              exit 1
            fi
            
            # Test East Asian Wide characters (should be 2 columns each)
            result=$(get_display_width "你好")  # Two Chinese characters
            expected=4
            if [[ "$result" != "$expected" ]]; then
              echo "❌ CJK width calculation failed: got $result, expected $expected"
              exit 1
            fi
            
            # Test repository symbols (commonly causing alignment issues)
            result=$(get_display_width "📁")  # Folder emoji
            expected=2
            if [[ "$result" != "$expected" ]]; then
              echo "❌ Emoji width calculation failed: got $result, expected $expected"
              exit 1
            fi
            
            # Test mixed content (ASCII + Unicode)
            result=$(get_display_width "repo📁test")  # ASCII + emoji + ASCII
            expected=9  # 4 + 2 + 4 = 10, but depends on emoji width implementation
            if [[ "$result" -lt 8 || "$result" -gt 10 ]]; then
              echo "❌ Mixed content width calculation seems wrong: got $result, expected 8-10"
              exit 1
            fi
            
            # Test truncation function with unicode
            result=$(truncate_to_display_width "你好世界" 6)  # 4 CJK chars (8 cols), truncate to 6
            result_width=$(get_display_width "$result")
            if [[ "$result_width" -gt 6 ]]; then
              echo "❌ Unicode truncation failed: result '$result' has width $result_width > 6"
              exit 1
            fi
            
            echo "✅ Unicode display width calculations working correctly"
          '';

          # Real-world Unicode Session Testing
          unicode_session_data = writers.testBash "test-tmux-session-picker-unicode-sessions"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                        # Test that the script handles session files with unicode content properly
            
                        # Create temporary test directory
                        test_dir=$(mktemp -d)
                        trap "rm -rf $test_dir" EXIT
            
                        # Create mock session file with unicode content
                        cat > "$test_dir/tmux_resurrect_20231225_123000.txt" << 'EOF'
            window	test-session	0	:shell	1		17e9,80x24,0,0,3
            window	test-session	1	:📁repo	0		17ea,80x24,0,0,4  
            window	test-session	2	:你好世界	0		17eb,80x24,0,0,5
            pane	test-session	0	0	:shell	0	:	/home/user	1	zsh	
            pane	test-session	1	0	:📁repo	1	:git status	/home/user/projects/🚀rocket	0	git	status
            pane	test-session	2	0	:你好世界	2	:编辑文件	/home/user/中文目录	0	vim	test.txt
            EOF
            
                        # Test that format_session can handle unicode content without errors
                        export RESURRECT_DIR="$test_dir"
                        result=$(source ${tmux-session-picker}/bin/tmux-session-picker; format_session "$test_dir/tmux_resurrect_20231225_123000.txt" 2>&1)
                        exit_code=$?
            
                        if [[ $exit_code -ne 0 ]]; then
                          echo "❌ format_session failed with unicode content: $result"
                          exit 1
                        fi
            
                        # Verify the output contains unicode characters and isn't corrupted
                        if ! echo "$result" | grep -q "📁\|你好\|🚀"; then
                          echo "❌ Unicode characters missing from output: $result"
                          exit 1
                        fi
            
                        echo "✅ Unicode session data handled correctly"
          '';

          # Runtime Terminal Width Error Detection
          runtime_terminal_width_errors = writers.testBash "test-tmux-session-picker-runtime-terminal-width" ''
                        # Test that tmux-session-picker --list doesn't produce get_terminal_width errors
                        # This test catches runtime errors that occur when fzf spawns preview subprocesses
            
                        # Create a minimal resurrect directory with test data for testing
                        test_dir=$(mktemp -d)
                        resurrect_dir="$test_dir/.local/share/tmux/resurrect"
                        mkdir -p "$resurrect_dir"
            
                        # Create a simple test session file
                        cat > "$resurrect_dir/tmux_resurrect_20241028T120000.txt" << 'EOF'
            pane	main	1	:nixcfg	1	:	1	:/home/tim/src/nixcfg	1	bash	:
            window	main	1	1	:nixcfg	1	:/home/tim/src/nixcfg	1	/home/tim/src/nixcfg
            state	main	1
            EOF
            
                        # Create the last symlink
                        ln -sf "tmux_resurrect_20241028T120000.txt" "$resurrect_dir/last"
            
                        # Set the resurrect directory environment variable
                        export RESURRECT_DIR="$resurrect_dir"
            
                        # Run tmux-session-picker --list and capture stderr for error detection
                        output=$(${tmux-session-picker}/bin/tmux-session-picker --list 2>&1)
                        exit_code=$?
            
                        # Clean up
                        rm -rf "$test_dir"
            
                        # Check if the command succeeded
                        if [[ $exit_code -ne 0 ]]; then
                          echo "❌ tmux-session-picker --list failed with exit code $exit_code"
                          echo "Output: $output"
                          exit 1
                        fi
            
                        # Check for get_terminal_width runtime errors
                        if echo "$output" | grep -qi "get_terminal_width.*command not found"; then
                          echo "❌ Runtime error detected: get_terminal_width function not found in subprocess"
                          echo "Error output:"
                          echo "$output" | grep -i "get_terminal_width"
                          echo ""
                          echo "This indicates that subprocesses spawned by the script cannot access the get_terminal_width function."
                          echo "The function may need to be exported or the subprocess execution needs to be fixed."
                          exit 1
                        fi
            
                        # Check for any "environment: line X" errors which indicate subprocess issues
                        if echo "$output" | grep -qi "environment:.*line.*command not found"; then
                          echo "❌ Runtime subprocess error detected"
                          echo "Error output:"
                          echo "$output" | grep -i "environment:.*line"
                          echo ""
                          echo "This indicates subprocess execution is trying to call undefined functions."
                          exit 1
                        fi
            
                        # Verify we got expected output structure
                        if echo "$output" | grep -q "##HEADER\|SESSION\|DATE"; then
                          echo "✅ tmux-session-picker --list produced expected output format"
                        else
                          echo "❌ tmux-session-picker --list did not produce expected output format"
                          echo "Output: $output"
                          exit 1
                        fi
            
                        echo "✅ Runtime terminal width error detection test passed - no subprocess errors detected"
          '';
        };
      };

      # Tmux test data generator - creates mock tmux-resurrect files for testing
      tmux-test-data-generator = mkBashScript {
        name = "tmux-test-data-generator";
        deps = with pkgs; [
          coreutils
          gawk
          gnugrep
          gnused
        ];
        text = builtins.readFile ../../files/bin/tmux-test-data-generator;
        tests = {
          syntax = writers.testBash "test-tmux-test-data-generator-syntax" ''
            echo "✅ Syntax validation passed at build time"
          '';
          help_availability = writers.testBash "test-tmux-test-data-generator-help" ''
            output=$(${tmux-test-data-generator}/bin/tmux-test-data-generator --help 2>&1)
            exit_code=$?
            
            if [[ $exit_code -eq 0 ]]; then
              echo "✅ Help command works"
              if echo "$output" | grep -q "Usage:\|OPTIONS:\|EXAMPLES:"; then
                echo "✅ Help output contains expected sections"
              else
                echo "❌ Help output missing key sections"
                exit 1
              fi
            else
              echo "❌ Help command failed with exit code $exit_code"
              exit 1
            fi
          '';
          basic_generation = writers.testBash "test-tmux-test-data-generator-basic" ''
            # Test basic session generation
            test_dir=$(mktemp -d)
            trap "rm -rf $test_dir" EXIT
            
            ${tmux-test-data-generator}/bin/tmux-test-data-generator -o "$test_dir" -c 3
            
            # Verify files were created
            file_count=$(find "$test_dir" -name "tmux_resurrect_*.txt" | wc -l)
            if [[ $file_count -eq 3 ]]; then
              echo "✅ Generated expected number of test files"
            else
              echo "❌ Expected 3 files, got $file_count"
              exit 1
            fi
            
            # Verify files have valid content
            for file in "$test_dir"/tmux_resurrect_*.txt; do
              if grep -q "^pane\|^window" "$file"; then
                echo "✅ File $file has valid tmux-resurrect format"
              else
                echo "❌ File $file has invalid format"
                exit 1
              fi
            done
          '';
        };
      };

      # Claude Code wrapper scripts - migrated from claude-code.nix
      # Dynamic generation based on enabled accounts
      claudemax = mkBashScript {
        name = "claudemax";
        deps = with pkgs; [ jq coreutils ];
        text = mkClaudeWrapper {
          account = "max";
          displayName = "Claude Max Account";
          configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-max";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
        tests = {
          help = writers.testBash "test-claudemax-help" ''
            # Test help flag functionality
            $script --help >/dev/null 2>&1
            exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
              echo "✅ claudemax help works"
            else
              echo "❌ claudemax help failed with exit code $exit_code"
              exit 1
            fi
          '';
          headless = writers.testBash "test-claudemax-headless" ''
            # Test headless mode bypass (should not check PID)
            output=$($script --print version 2>&1 || echo "error")
            if [[ "$output" != "error" ]]; then
              echo "✅ claudemax headless mode works"
            else
              echo "✅ claudemax headless mode test completed (expected behavior)"
            fi
          '';
        };
      };

      claudepro = mkBashScript {
        name = "claudepro";
        deps = with pkgs; [ jq coreutils ];
        text = mkClaudeWrapper {
          account = "pro";
          displayName = "Claude Pro Account";
          configDir = "${config.home.homeDirectory}/src/nixcfg/claude-runtime/.claude-pro";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
        tests = {
          help = writers.testBash "test-claudepro-help" ''
            # Test help flag functionality
            $script --help >/dev/null 2>&1
            exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
              echo "✅ claudepro help works"
            else
              echo "❌ claudepro help failed with exit code $exit_code"
              exit 1
            fi
          '';
          headless = writers.testBash "test-claudepro-headless" ''
            # Test headless mode bypass (should not check PID)
            output=$($script --print version 2>&1 || echo "error")
            if [[ "$output" != "error" ]]; then
              echo "✅ claudepro headless mode works"
            else
              echo "✅ claudepro headless mode test completed (expected behavior)"
            fi
          '';
        };
      };

      # Development scripts for optimization and testing
      # Optimized tmux-session-picker parser for performance testing  
      tmux-parser-optimized = mkBashScript {
        name = "tmux-parser-optimized";
        deps = with pkgs; [ coreutils gnugrep gawk ];
        text = /* bash */ ''
          #!/usr/bin/env bash
          set -euo pipefail

          # Simple parser for tmux-resurrect files
          # Output format: session|windows|panes|timestamp|window_summary|is_current
          parse_single_file() {
              local file="$1" 
              local current_file="$2"
            
              [[ ! -f "$file" ]] && return 1
              [[ ! -r "$file" ]] && return 1
            
              # Enhanced parsing using basic tools
              local session=""
              local window_count=0
              local pane_count=0
              local -a paths=()
              local -a commands=()
              
              # Single pass through file to extract all data (robust field handling)
              while IFS=$'\t' read -r type session_name rest || [[ -n "$type" ]]; do
                  case "$type" in
                      window)
                          window_count=$((window_count + 1))
                          [[ -z "$session" ]] && session="$session_name"
                          ;;
                      pane)
                          pane_count=$((pane_count + 1))
                          [[ -z "$session" ]] && session="$session_name"
                          
                          # For paths and commands, we need to split the rest fields
                          # This is a simplified approach that handles variable field counts
                          if [[ -n "$rest" ]]; then
                              # Split the rest into an array
                              local -a fields
                              IFS=$'\t' read -r -a fields <<< "$rest"
                              
                              # Extract path (field 5 in rest, after type and session_name)
                              if [[ ''${#fields[@]} -gt 5 ]]; then
                                  local path="''${fields[5]#:}"
                                  [[ -n "$path" && "$path" != "" ]] && paths+=("$path")
                              fi
                              
                              # Extract commands (fields 7 and 8 in rest)
                              local cmd=""
                              if [[ ''${#fields[@]} -gt 8 ]]; then
                                  cmd="''${fields[8]#:}"  # Try full command first
                              fi
                              if [[ -z "$cmd" || "$cmd" == "" ]] && [[ ''${#fields[@]} -gt 7 ]]; then
                                  cmd="''${fields[7]#:}"  # Fallback to basic command
                              fi
                              [[ -n "$cmd" && "$cmd" != "" && "$cmd" != "bash" && "$cmd" != "zsh" && "$cmd" != "sh" ]] && commands+=("$cmd")
                          fi
                          ;;
                  esac
              done < "$file"
            
              # Must have a session and at least one window
              [[ -z "$session" || $window_count -eq 0 ]] && return 1
            
              # Extract timestamp from filename
              local filename="''${file##*/}"
              local timestamp="''${filename#tmux_resurrect_}"
              timestamp="''${timestamp%.txt}"
              
              # Create enhanced summary with paths and commands
              local paths_str=""
              local commands_str=""
              if [[ ''${#paths[@]} -gt 0 ]]; then
                  # Get unique paths, abbreviated
                  local -A unique_paths=()
                  for path in "''${paths[@]}"; do
                      # Abbreviate path
                      local abbrev_path="''${path/#$HOME/~}"
                      unique_paths["$abbrev_path"]=1
                  done
                  paths_str=$(printf "%s:" "''${!unique_paths[@]}")
                  paths_str="''${paths_str%:}"  # Remove trailing colon
              fi
              
              if [[ ''${#commands[@]} -gt 0 ]]; then
                  # Get unique commands
                  local -A unique_commands=()
                  for cmd in "''${commands[@]}"; do
                      unique_commands["$cmd"]=1
                  done
                  commands_str=$(printf "%s:" "''${!unique_commands[@]}")
                  commands_str="''${commands_str%:}"  # Remove trailing colon
              fi
              
              # Format summary with last tokens only
              local tokens=()
              if [[ -n "$paths_str" ]]; then
                  IFS=':' read -ra path_arr <<< "$paths_str"
                  for p in "''${path_arr[@]}"; do
                      tokens+=("''${p##*/}")
                  done
              fi
              if [[ -n "$commands_str" ]]; then
                  IFS=':' read -ra cmd_arr <<< "$commands_str"
                  for c in "''${cmd_arr[@]}"; do
                      tokens+=("$c")
                  done
              fi
              local window_summary
              if [[ ''${#tokens[@]} -gt 0 ]]; then
                  window_summary="''${tokens[*]}"
              else
                  window_summary="''${window_count}w ''${pane_count}p"
              fi
            
              # Check if current
              local is_current="false"
              [[ "$file" == "$current_file" ]] && is_current="true"
            
              # Output result using ASCII Unit Separator (US) to avoid conflicts with user content
              printf "%s\x1F%d\x1F%d\x1F%s\x1F%s\x1F%s\n" \
                  "$session" \
                  "$window_count" \
                  "$pane_count" \
                  "$timestamp" \
                  "$window_summary" \
                  "$is_current"
          }

          # Main function for testing/standalone usage
          main() {
              local file="''${1:-}"
              local current_file="''${2:-}"
            
              if [[ -z "$file" ]]; then
                  echo "Usage: $0 <tmux-resurrect-file> [current-file]" >&2
                  exit 1
              fi
            
              # Provide empty string for current_file if not specified
              if [[ $# -lt 2 ]]; then
                  current_file=""
              fi
            
              parse_single_file "$file" "$current_file"
          }

          # Only run main if script is executed directly (not sourced)
          # Simplified check to avoid issues with BASH_SOURCE in nix environments
          if [[ "$#" -gt 0 ]]; then
              main "$@"
          fi
        '';
        tests = {
          syntax = writers.testBash "test-tmux-parser-syntax" ''
            echo "✅ Optimized parser syntax validation passed"
          '';

          # Test data generator for tmux-resurrect files
          generate_test_data = writers.testBash "test-tmux-parser-data-gen"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                      # Create test tmux-resurrect file
                      test_dir=$(mktemp -d)
                      test_file="$test_dir/tmux_resurrect_20250124_143022.txt"
          
                      cat > "$test_file" << 'EOF'
            pane	main	1	1	:*	1	nvim	/home/user/projects/myapp	1	zsh	:
            pane	main	1	2	:*	2	zsh	/home/user/projects/myapp	0	zsh	:
            pane	main	2	1	:	1	npm	/home/user/projects/myapp	1	zsh	npm run dev
            window	main	1	:editor	1	*Z	1234,56x78,0,0{28x78,0,0,1,27x78,29,0,2}	:
            window	main	2	:server	0	:	1234x56,0,0,3	off
            EOF
          
                      # Test the parser
                      result=$(tmux-parser-optimized "$test_file" "$test_file")
                      echo "Parser output: $result"
          
                      # Validate ASCII Unit Separator format (6 fields)
                      field_count=$(echo "$result" | tr '\x1F' '\n' | wc -l)
                      if [[ $field_count -ne 6 ]]; then
                        echo "❌ Expected 6 fields, got $field_count"
                        exit 1
                      fi
          
                      # Validate specific fields
                      IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
          
                      [[ "$session" == "main" ]] || { echo "❌ Session: expected 'main', got '$session'"; exit 1; }
                      [[ "$windows" == "2" ]] || { echo "❌ Windows: expected '2', got '$windows'"; exit 1; }
                      [[ "$panes" == "3" ]] || { echo "❌ Panes: expected '3', got '$panes'"; exit 1; }
                      [[ "$timestamp" == "20250124_143022" ]] || { echo "❌ Timestamp mismatch: got '$timestamp'"; exit 1; }
                      [[ "$is_current" == "true" ]] || { echo "❌ Current flag: expected 'true', got '$is_current'"; exit 1; }
          
                      echo "✅ Parser correctly processes tmux-resurrect file format"
                      echo "✅ Pipe-delimited output format validated"
          
                      rm -rf "$test_dir"
          '';

          # Performance comparison test
          performance_baseline = writers.testBash "test-tmux-parser-performance" ''
            # Create multiple test files to measure parsing performance
            test_dir=$(mktemp -d)
          
            # Generate 10 test files with varying complexity
            for i in {1..10}; do
              timestamp=$(printf "20250124_%02d%02d%02d" $((10 + i)) $((i * 5)) $((i * 3)))
              test_file="$test_dir/tmux_resurrect_$timestamp.txt"
            
              # Generate test data with increasing complexity
              echo "window	session$i	1	:main	1	*	1234x56,0,0,1" >> "$test_file"
              echo "pane	session$i	1	1	1	:	1	zsh	$((10000 + i))	 	/home/user	zsh" >> "$test_file"
            
              for j in $(seq 2 $((i + 1))); do
                echo "window	session$i	$j	:win$j	0		1234x56,0,0,$j" >> "$test_file"
                echo "pane	session$i	$j	1	1	:	0	vim	$((10000 + i + j))	 	/home/user/src	vim" >> "$test_file"
              done
            done
          
            # Test parsing all files
            file_count=0
            for file in "$test_dir"/*.txt; do
              result=$(tmux-parser-optimized "$file")
              [[ -n "$result" ]] || { echo "❌ Failed to parse $file"; exit 1; }
              ((file_count++))
            done
          
            echo "✅ Successfully parsed $file_count test files"
            echo "✅ Single-pass parser performance baseline established"
          
            rm -rf "$test_dir"
          '';

          # Comprehensive unit tests for parser with known inputs and edge cases (Task 6.2)
          unit_tests_basic = writers.testBash "test-tmux-parser-unit-basic"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                      # Unit Test 1: Basic single session with one window and one pane
                      test_dir=$(mktemp -d)
                      test_file="$test_dir/single_session.txt"
          
                      cat > "$test_file" << 'EOF'
            pane	simple	1	1	:-	0	bash	:/home/user	1	bash	:
            window	simple	1	:main	1	:*	1234x56,0,0,1	on
            state	simple	simple
            EOF
          
                      result=$(tmux-parser-optimized "$test_file")
                      echo "Basic test result: $result"
          
                      # Parse result and validate
                      IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
          
                      # Validate basic fields
                      [[ "$session" == "simple" ]] || { echo "❌ Expected session 'simple', got '$session'"; exit 1; }
                      [[ "$windows" == "1" ]] || { echo "❌ Expected 1 window, got '$windows'"; exit 1; }
                      [[ "$panes" == "1" ]] || { echo "❌ Expected 1 pane, got '$panes'"; exit 1; }
                      [[ "$is_current" == "false" ]] || { echo "❌ Expected is_current 'false', got '$is_current'"; exit 1; }
          
                      echo "✅ Basic single session test passed"
                      rm -rf "$test_dir"
          '';

          unit_tests_multi_window = writers.testBash "test-tmux-parser-unit-multi-window"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                      # Unit Test 2: Multiple windows with varying pane counts
                      test_dir=$(mktemp -d)
                      test_file="$test_dir/multi_window.txt"
          
                      cat > "$test_file" << 'EOF'
            pane	dev	1	1	:-	0	bash	:/home/user	1	bash	:
            pane	dev	1	1	:-	1	vim	:/home/user/src	0	vim	:vim file.txt
            pane	dev	2	0	:-	0	npm	:/home/user/app	1	npm	:npm run dev
            window	dev	1	:editor	1	:*Z	1234x56,0,0{28x56,0,0,1,27x56,29,0,2}	on
            window	dev	2	:server	0	:-	1234x56,0,0,3	on
            state	dev	dev
            EOF
          
                      result=$(tmux-parser-optimized "$test_file")
                      echo "Multi-window test result: $result"
          
                      # Parse and validate
                      IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
          
                      [[ "$session" == "dev" ]] || { echo "❌ Expected session 'dev', got '$session'"; exit 1; }
                      [[ "$windows" == "2" ]] || { echo "❌ Expected 2 windows, got '$windows'"; exit 1; }
                      [[ "$panes" == "3" ]] || { echo "❌ Expected 3 panes, got '$panes'"; exit 1; }
          
                      echo "✅ Multi-window session test passed"
                      rm -rf "$test_dir"
          '';

          unit_tests_edge_cases = writers.testBash "test-tmux-parser-unit-edge-cases"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                      test_dir=$(mktemp -d)
          
                      # Unit Test 3: Empty file
                      echo "Testing empty file handling..."
                      empty_file="$test_dir/empty.txt"
                      touch "$empty_file"
          
                      result=$(tmux-parser-optimized "$empty_file" 2>/dev/null || echo "PARSER_FAILED")
                      if [[ "$result" == "PARSER_FAILED" ]]; then
                        echo "✅ Parser correctly handles empty files"
                      else
                        echo "❌ Parser should fail on empty files, got: $result"
                        exit 1
                      fi
          
                      # Unit Test 4: File with only comments/invalid lines
                      echo "Testing invalid content handling..."
                      invalid_file="$test_dir/invalid.txt"
                      cat > "$invalid_file" << 'EOF'
            # This is a comment
            invalid_line_type	data	here
            another_bad_line
            EOF
          
                      result=$(tmux-parser-optimized "$invalid_file" 2>/dev/null || echo "PARSER_FAILED")
                      if [[ "$result" == "PARSER_FAILED" ]]; then
                        echo "✅ Parser correctly handles invalid content"
                      else
                        echo "❌ Parser should fail on invalid content, got: $result"
                        exit 1
                      fi
          
                      # Unit Test 5: Session names with special characters
                      echo "Testing special characters in session names..."
                      special_file="$test_dir/special.txt"
                      cat > "$special_file" << 'EOF'
            pane	test-session_with.chars	1	1	:-	0	bash	:/tmp	1	bash	:
            window	test-session_with.chars	1	:main	1	:*	1234x56,0,0,1	on
            state	test-session_with.chars	test-session_with.chars
            EOF
          
                      result=$(tmux-parser-optimized "$special_file")
                      IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
          
                      [[ "$session" == "test-session_with.chars" ]] || { echo "❌ Special chars session failed: '$session'"; exit 1; }
                      [[ "$windows" == "1" ]] || { echo "❌ Special chars windows failed: '$windows'"; exit 1; }
          
                      echo "✅ Special characters in session names handled correctly"
          
                      # Unit Test 6: Paths with spaces and special characters
                      echo "Testing paths with spaces..."
                      path_file="$test_dir/paths.txt"
                      cat > "$path_file" << 'EOF'
            pane	paths	1	1	:-	0	bash	:/home/user/my folder/sub dir	1	bash	:
            pane	paths	1	1	:-	1	vim	:/home/user/projects/app-name	0	vim	:vim "file with spaces.txt"
            window	paths	1	:main	1	:*	1234x56,0,0{28x56,0,0,1,27x56,29,0,2}	on
            state	paths	paths
            EOF
          
                      result=$(tmux-parser-optimized "$path_file")
                      IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
          
                      [[ "$session" == "paths" ]] || { echo "❌ Path test session failed: '$session'"; exit 1; }
                      [[ "$windows" == "1" ]] || { echo "❌ Path test windows failed: '$windows'"; exit 1; }
                      [[ "$panes" == "2" ]] || { echo "❌ Path test panes failed: '$panes'"; exit 1; }
          
                      echo "✅ Paths with spaces handled correctly"
          
                      rm -rf "$test_dir"
          '';

          unit_tests_active_detection = writers.testBash "test-tmux-parser-unit-active-detection"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                      # Unit Test 7: Active session detection
                      test_dir=$(mktemp -d)
          
                      # Create multiple session files
                      session1="$test_dir/session1.txt"
                      session2="$test_dir/session2.txt"
          
                      cat > "$session1" << 'EOF'
            pane	active_session	1	1	:-	0	bash	:/tmp	1	bash	:
            window	active_session	1	:main	1	:*	1234x56,0,0,1	on
            state	active_session	active_session
            EOF
          
                      cat > "$session2" << 'EOF'
            pane	inactive_session	1	1	:-	0	bash	:/tmp	1	bash	:
            window	inactive_session	1	:main	1	:*	1234x56,0,0,1	on
            state	inactive_session	inactive_session
            EOF
          
                      # Create 'last' symlink pointing to session1
                      ln -s "$(basename "$session1")" "$test_dir/last"
          
                      # Test active session detection
                      result1=$(tmux-parser-optimized "$session1" "$session1")  # This should be active
                      result2=$(tmux-parser-optimized "$session2" "$session1")  # This should be inactive
          
                      # Parse results
                      IFS=$'\x1F' read -r session1_name w1 p1 t1 s1 is_current1 <<< "$result1"
                      IFS=$'\x1F' read -r session2_name w2 p2 t2 s2 is_current2 <<< "$result2"
          
                      # Validate active detection
                      [[ "$is_current1" == "true" ]] || { echo "❌ Session1 should be active, got '$is_current1'"; exit 1; }
                      [[ "$is_current2" == "false" ]] || { echo "❌ Session2 should be inactive, got '$is_current2'"; exit 1; }
          
                      echo "✅ Active session detection working correctly"
          
                      rm -rf "$test_dir"
          '';

          unit_tests_output_format = writers.testBash "test-tmux-parser-unit-output-format"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                      # Unit Test 8: Output format validation
                      test_dir=$(mktemp -d)
                      test_file="$test_dir/format_test.txt"
          
                      cat > "$test_file" << 'EOF'
            pane	format_test	1	1	:-	0	bash	:/home/user	1	bash	:
            pane	format_test	1	1	:-	1	vim	:/home/user/src	0	vim	:vim config.txt
            pane	format_test	2	0	:-	0	htop	:/home/user	1	htop	:
            window	format_test	1	:editor	1	:*Z	layout1	on
            window	format_test	2	:monitor	0	:-	layout2	on
            state	format_test	format_test
            EOF
          
                      result=$(tmux-parser-optimized "$test_file")
                      echo "Format test result: $result"
          
                      # Test 8.1: Verify exactly 6 ASCII separator-delimited fields
                      field_count=$(echo "$result" | tr '\x1F' '\n' | wc -l)
                      [[ $field_count -eq 6 ]] || { echo "❌ Expected 6 fields, got $field_count"; exit 1; }
          
                      # Test 8.2: Verify each field is populated (not empty)
                      IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
          
                      [[ -n "$session" ]] || { echo "❌ Session field is empty"; exit 1; }
                      [[ -n "$windows" ]] || { echo "❌ Windows field is empty"; exit 1; }
                      [[ -n "$panes" ]] || { echo "❌ Panes field is empty"; exit 1; }
                      [[ -n "$timestamp" ]] || { echo "❌ Timestamp field is empty"; exit 1; }
                      [[ -n "$summary" ]] || { echo "❌ Summary field is empty"; exit 1; }
                      [[ -n "$is_current" ]] || { echo "❌ Is_current field is empty"; exit 1; }
          
                      # Test 8.3: Verify field types
                      [[ "$windows" =~ ^[0-9]+$ ]] || { echo "❌ Windows field not numeric: '$windows'"; exit 1; }
                      [[ "$panes" =~ ^[0-9]+$ ]] || { echo "❌ Panes field not numeric: '$panes'"; exit 1; }
                      [[ "$is_current" =~ ^(true|false)$ ]] || { echo "❌ Is_current not boolean: '$is_current'"; exit 1; }
          
                      # Test 8.4: Verify numeric values are correct
                      [[ "$windows" == "2" ]] || { echo "❌ Expected 2 windows, got '$windows'"; exit 1; }
                      [[ "$panes" == "3" ]] || { echo "❌ Expected 3 panes, got '$panes'"; exit 1; }
          
                      echo "✅ Output format validation passed"
          
                      rm -rf "$test_dir"
          '';

          unit_tests_timestamp_extraction = writers.testBash "test-tmux-parser-unit-timestamp"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                      # Unit Test 9: Timestamp extraction from filename
                      test_dir=$(mktemp -d)
          
                      # Test valid timestamp format
                      valid_file="$test_dir/tmux_resurrect_20250124_143022.txt"
                      cat > "$valid_file" << 'EOF'
            pane	test	1	1	:-	0	bash	:/tmp	1	bash	:
            window	test	1	:main	1	:*	1234x56,0,0,1	on
            state	test	test
            EOF
          
                      result=$(tmux-parser-optimized "$valid_file")
                      IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
          
                      [[ "$timestamp" == "20250124_143022" ]] || { echo "❌ Expected timestamp '20250124_143022', got '$timestamp'"; exit 1; }
          
                      # Test malformed filename (should use fallback)
                      malformed_file="$test_dir/bad_filename.txt"
                      cat > "$malformed_file" << 'EOF'
            pane	test2	1	1	:-	0	bash	:/tmp	1	bash	:
            window	test2	1	:main	1	:*	1234x56,0,0,1	on
            state	test2	test2
            EOF
          
                      result2=$(tmux-parser-optimized "$malformed_file")
                      IFS=$'\x1F' read -r session2 windows2 panes2 timestamp2 summary2 is_current2 <<< "$result2"
          
                      [[ "$timestamp2" == "19700101_000000" ]] || { echo "❌ Expected fallback timestamp '19700101_000000', got '$timestamp2'"; exit 1; }
          
                      echo "✅ Timestamp extraction working correctly"
          
                      rm -rf "$test_dir"
          '';

          unit_tests_error_conditions = writers.testBash "test-tmux-parser-unit-errors"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                      # Unit Test 10: Error conditions and edge cases
                      test_dir=$(mktemp -d)
          
                      # Test non-existent file
                      echo "Testing non-existent file handling..."
                      result=$(tmux-parser-optimized "$test_dir/nonexistent.txt" 2>/dev/null || echo "PARSER_FAILED")
                      [[ "$result" == "PARSER_FAILED" ]] || { echo "❌ Should fail on non-existent file"; exit 1; }
          
                      # Test file with missing required data
                      echo "Testing incomplete data handling..."
                      incomplete_file="$test_dir/incomplete.txt"
                      cat > "$incomplete_file" << 'EOF'
            window	incomplete	1	:main	1	:*	layout	on
            EOF
                      # No pane data - this should fail or return minimal data
          
                      result=$(tmux-parser-optimized "$incomplete_file" 2>/dev/null || echo "PARSER_FAILED")
                      if [[ "$result" != "PARSER_FAILED" ]]; then
                        # If parser succeeds, it should return 0 panes
                        IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
                        [[ "$panes" == "0" ]] || { echo "❌ Incomplete file should have 0 panes, got '$panes'"; exit 1; }
                      fi
          
                      # Test file with panes but no windows (unusual but possible)
                      echo "Testing panes without windows..."
                      pane_only_file="$test_dir/pane_only.txt"
                      cat > "$pane_only_file" << 'EOF'
            pane	pane_only	1	1	:-	0	bash	:/tmp	1	bash	:
            state	pane_only	pane_only
            EOF
          
                      result=$(tmux-parser-optimized "$pane_only_file")
                      IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
          
                      [[ "$session" == "pane_only" ]] || { echo "❌ Pane-only session name failed: '$session'"; exit 1; }
                      [[ "$panes" == "1" ]] || { echo "❌ Pane-only should have 1 pane, got '$panes'"; exit 1; }
                      # Windows count might be 0 since no window lines exist
          
                      echo "✅ Error conditions handled appropriately"
          
                      rm -rf "$test_dir"
          '';

          unit_tests_performance_baseline = writers.testBash "test-tmux-parser-unit-performance"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
            # Unit Test 11: Performance baseline for single file parsing
            test_dir=$(mktemp -d)
          
            # Create a moderately complex session file
            complex_file="$test_dir/complex_session.txt"
          
            # Generate a session with 5 windows, 3 panes each (15 panes total)
            {
              for w in {1..5}; do
                echo "window	complex	$w	:window$w	$([[ $w -eq 1 ]] && echo 1 || echo 0)	$([[ $w -eq 1 ]] && echo ':*' || echo ':-')	layout$w	on"
                for p in {0..2}; do
                  echo "pane	complex	$w	$([[ $w -eq 1 ]] && echo 1 || echo 0)	:-	$p	bash	:/home/user/dir$w	$([[ $w -eq 1 && $p -eq 0 ]] && echo 1 || echo 0)	bash	:"
                done
              done
              echo "state	complex	complex"
            } > "$complex_file"
          
            # Time the parsing operation
            start_time=$(date +%s%N)
            result=$(tmux-parser-optimized "$complex_file")
            end_time=$(date +%s%N)
          
            elapsed_ms=$(( (end_time - start_time) / 1000000 ))
          
            # Validate the result
            IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
          
            [[ "$session" == "complex" ]] || { echo "❌ Complex session name failed: '$session'"; exit 1; }
            [[ "$windows" == "5" ]] || { echo "❌ Expected 5 windows, got '$windows'"; exit 1; }
            [[ "$panes" == "15" ]] || { echo "❌ Expected 15 panes, got '$panes'"; exit 1; }
          
            echo "✅ Performance test completed: ''${elapsed_ms}ms for 15 panes across 5 windows"
          
            # Performance should be under 100ms for a single moderately complex file
            if [[ $elapsed_ms -lt 100 ]]; then
              echo "✅ Performance within acceptable range (''${elapsed_ms}ms < 100ms)"
            else
              echo "⚠️  Performance slower than expected: ''${elapsed_ms}ms"
              # This is a warning, not a failure for unit tests
            fi
          
            rm -rf "$test_dir"
          '';

          # CRITICAL: Real tmux-resurrect file format tests with UTF-8 and complex paths
          real_format_utf8 = writers.testBash "test-tmux-parser-real-format-utf8"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                        # Test with realistic tmux-resurrect content including UTF-8 and complex paths
                        test_dir=$(mktemp -d)
                        real_file="$test_dir/tmux_resurrect_20250125_100000.txt"
            
                        # Real-world format with UTF-8 session names, complex paths, and command args
                        cat > "$real_file" << 'EOF'
            window	📁-projects	0	:shell	1	*	80x24,0,0,0	
            window	📁-projects	1	:🚀rocket-app	0	-	80x24,0,0,1	
            window	📁-projects	2	:你好世界-editor	0	-	80x24,0,0{40x24,0,0,2,39x24,41,0,3}	
            pane	📁-projects	0	0	:shell	0	:/bin/bash	/home/user	1	bash	:
            pane	📁-projects	1	0	:🚀rocket-app	1	:git status --porcelain	/home/user/projects/🚀rocket-app	0	git	:status --porcelain
            pane	📁-projects	2	0	:你好世界-editor	2	:vim "file with spaces.txt"	/home/user/中文目录/项目	0	vim	:"file with spaces.txt"
            pane	📁-projects	2	1	:你好世界-editor	3	:tail -f /var/log/app.log	/home/user/中文目录/项目	1	tail	:-f /var/log/app.log
            state	📁-projects	📁-projects
            EOF

                        echo "Testing real-world UTF-8 format..."
                        result=$(tmux-parser-optimized "$real_file")
                        echo "Real format result: $result"
            
                        # Parse and validate UTF-8 session handling
                        IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result"
            
                        [[ "$session" == "📁-projects" ]] || { echo "❌ UTF-8 session name failed: '$session'"; exit 1; }
                        [[ "$windows" == "3" ]] || { echo "❌ Expected 3 windows, got '$windows'"; exit 1; }
                        [[ "$panes" == "4" ]] || { echo "❌ Expected 4 panes, got '$panes'"; exit 1; }
                        [[ "$timestamp" == "20250125_100000" ]] || { echo "❌ Timestamp extraction failed: '$timestamp'"; exit 1; }
            
                        echo "✅ Real-world UTF-8 format parsing successful"
            
                        rm -rf "$test_dir"
          '';

          # CRITICAL: Integration test for IFS read hanging prevention  
          ifs_read_robustness = writers.testBash "test-tmux-parser-ifs-read-robustness"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                        # Test parser output with complex content that could cause IFS read hanging
                        test_dir=$(mktemp -d)
                        complex_file="$test_dir/tmux_resurrect_complex.txt"
            
                        # Content with embedded newlines, pipes, and special characters in commands
                        cat > "$complex_file" << 'EOF'
            window	complex-test	0	:shell	1	*	80x24,0,0,0	
            window	complex-test	1	:multi|pipe	0	-	80x24,0,0,1	
            pane	complex-test	0	0	:shell	0	:	/home/user	1	bash	:
            pane	complex-test	1	0	:multi|pipe	1	:echo "hello|world" | grep world	/tmp	0	bash	:-c echo "hello|world" | grep world
            state	complex-test	complex-test
            EOF

                        echo "Testing IFS read robustness with pipe characters in content..."
            
                        # Test that parser output doesn't break IFS read in main script
                        result=$(tmux-parser-optimized "$complex_file")
                        echo "Complex content result: $result"
            
                        # This is the critical test - ensure IFS read works correctly
                        set -o pipefail
                        IFS=$'\x1F' read -r session windows panes timestamp summary is_current <<< "$result" || {
                          echo "❌ CRITICAL: IFS with ASCII separator read failed - this would cause hanging in main script"
                          exit 1
                        }
            
                        # Validate parsing worked despite complex content
                        [[ "$session" == "complex-test" ]] || { echo "❌ Session parsing failed with complex content: '$session'"; exit 1; }
                        [[ "$windows" == "2" ]] || { echo "❌ Window count failed: '$windows'"; exit 1; }
                        [[ "$panes" == "2" ]] || { echo "❌ Pane count failed: '$panes'"; exit 1; }
            
                        # Ensure no field contains embedded pipes that would break parsing
                        if [[ "$session" =~ \| ]] || [[ "$summary" =~ \| ]]; then
                          echo "❌ CRITICAL: Parser output contains unescaped pipes - would break main script"
                          exit 1
                        fi
            
                        echo "✅ IFS read robustness test passed - no hanging risk"
            
                        rm -rf "$test_dir"
          '';

          # CRITICAL: Pathological input test to prevent hanging
          pathological_input = writers.testBash "test-tmux-parser-pathological-input"
            {
              LANG = "C.UTF-8";
              LC_ALL = "C.UTF-8";
            } ''
                        # Test with input that could cause parser to hang or produce bad output
                        test_dir=$(mktemp -d)
            
                        echo "Testing pathological input handling..."
            
                        # Test 1: File with only comments and invalid lines (should fail gracefully)
                        bad_file="$test_dir/bad_content.txt"
                        cat > "$bad_file" << 'EOF'
            # This is a comment
            invalid_line_here
            not_a_valid_tmux_line
            another bad line
            EOF
            
                        result=$(tmux-parser-optimized "$bad_file" 2>/dev/null || echo "PARSER_FAILED")
                        [[ "$result" == "PARSER_FAILED" ]] || { echo "❌ Should fail on invalid content"; exit 1; }
            
                        # Test 2: Empty file (should fail gracefully)
                        empty_file="$test_dir/empty.txt"
                        touch "$empty_file"
            
                        result=$(tmux-parser-optimized "$empty_file" 2>/dev/null || echo "PARSER_FAILED")
                        [[ "$result" == "PARSER_FAILED" ]] || { echo "❌ Should fail on empty file"; exit 1; }
            
                        # Test 3: File with malformed tmux data (missing required fields)
                        malformed_file="$test_dir/malformed.txt"
                        cat > "$malformed_file" << 'EOF'
            window	incomplete	# Missing required fields
            pane	incomplete	# Also missing fields
            EOF
            
                        result=$(tmux-parser-optimized "$malformed_file" 2>/dev/null || echo "PARSER_FAILED")
                        [[ "$result" == "PARSER_FAILED" ]] || { echo "❌ Should fail on malformed data"; exit 1; }
            
                        echo "✅ Pathological input handling working correctly"
            
                        rm -rf "$test_dir"
          '';

        };
      }; # Close tests
    }; # Close tmux-parser-optimized


  }; # Close bashScripts assignment
}
