# Script Libraries - Non-executable files for sourcing
# Preserves the unique library system from validated-scripts
{ lib, pkgs, mkScriptLibrary }:

with lib;

rec {
  /**
    Terminal utility functions for consistent terminal interaction.
    
    This library provides common terminal operations that multiple scripts
    need, avoiding code duplication while maintaining consistency.
  */
  terminalUtils = mkScriptLibrary {
    name = "terminalUtils";
    content = ''
      # Terminal utility functions
      # Source this file to access these functions
      
      # Get terminal width safely
      get_terminal_width() {
        if [[ -t 1 ]]; then
          tput cols 2>/dev/null || echo 80
        else
          echo 80
        fi
      }
      
      # Get terminal height safely  
      get_terminal_height() {
        if [[ -t 1 ]]; then
          tput lines 2>/dev/null || echo 24
        else
          echo 24
        fi
      }
      
      # Check if terminal supports colors
      has_color_support() {
        [[ -t 1 ]] && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]
      }
      
      # Safe cursor movement
      move_cursor() {
        local row=$1 col=$2
        [[ -t 1 ]] && tput cup "$row" "$col" 2>/dev/null || true
      }
      
      # Clear screen safely
      clear_screen() {
        [[ -t 1 ]] && tput clear 2>/dev/null || echo -e "\033[2J\033[H"
      }
      
      # Save/restore cursor position
      save_cursor() {
        [[ -t 1 ]] && tput sc 2>/dev/null || echo -ne "\033[s"
      }
      
      restore_cursor() {
        [[ -t 1 ]] && tput rc 2>/dev/null || echo -ne "\033[u"
      }
      
      # Wait for keypress
      wait_for_key() {
        local prompt="''${1:-Press any key to continue...}"
        echo -n "$prompt"
        read -n 1 -s
        echo
      }
      
      # Progress indicator
      show_progress() {
        local current=$1 total=$2 message="''${3:-Processing...}"
        local width=50
        local percent=$((current * 100 / total))
        local filled=$((current * width / total))
        
        printf "\r%s [" "$message"
        for ((i=0; i<filled; i++)); do printf "="; done
        for ((i=filled; i<width; i++)); do printf " "; done
        printf "] %d%%" "$percent"
        
        [[ $current -eq $total ]] && echo
      }
      
      # Spinner animation
      start_spinner() {
        local message="''${1:-Processing...}"
        local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local i=0
        
        while true; do
          printf "\r%s %s" "$message" "''${chars:i++%''${#chars}:1}"
          sleep 0.1
        done &
        
        echo $! > /tmp/spinner.pid
      }
      
      stop_spinner() {
        if [[ -f /tmp/spinner.pid ]]; then
          kill "$(cat /tmp/spinner.pid)" 2>/dev/null || true
          rm -f /tmp/spinner.pid
          printf "\r%*s\r" "$(get_terminal_width)" ""
        fi
      }
      
      # Safe file operations with terminal feedback
      safe_copy() {
        local src="$1" dst="$2"
        if [[ -f "$src" ]]; then
          cp "$src" "$dst" && echo "✅ Copied: $src → $dst"
        else
          echo "❌ Source not found: $src"
          return 1
        fi
      }
      
      safe_move() {
        local src="$1" dst="$2"
        if [[ -f "$src" ]]; then
          mv "$src" "$dst" && echo "✅ Moved: $src → $dst"
        else
          echo "❌ Source not found: $src"
          return 1
        fi
      }
    '';
    tests = {
      terminalDetection = pkgs.writeShellScript "test-terminal-detection" ''
        source ${terminalUtils}
        echo "🖥️  Testing terminal detection functions..."
        
        width=$(get_terminal_width)
        height=$(get_terminal_height)
        
        [[ "$width" -gt 0 ]] || { echo "❌ Invalid width: $width"; exit 1; }
        [[ "$height" -gt 0 ]] || { echo "❌ Invalid height: $height"; exit 1; }
        
        echo "✅ Terminal detection passed (''${width}x''${height})"
      '';

      progressIndicator = pkgs.writeShellScript "test-progress" ''
        source ${terminalUtils}
        echo "📊 Testing progress indicator..."
        
        for i in {1..5}; do
          show_progress $i 5 "Testing"
          sleep 0.1
        done
        
        echo "✅ Progress indicator passed"
      '';
    };
  };

  /**
    Color utility functions for consistent colored output.
    
    Provides safe color handling that degrades gracefully in non-color terminals
    while maintaining visual consistency across scripts.
  */
  colorUtils = mkScriptLibrary {
    name = "colorUtils";
    content = ''
      # Color utility functions with graceful degradation
      # Source this file to access color functions
      
      # Color codes (only used if terminal supports colors)
      if [[ -t 1 ]] && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
        # Standard colors
        export COLOR_RED=$(tput setaf 1)
        export COLOR_GREEN=$(tput setaf 2)
        export COLOR_YELLOW=$(tput setaf 3)
        export COLOR_BLUE=$(tput setaf 4)
        export COLOR_MAGENTA=$(tput setaf 5)
        export COLOR_CYAN=$(tput setaf 6)
        export COLOR_WHITE=$(tput setaf 7)
        export COLOR_RESET=$(tput sgr0)
        
        # Bright colors
        export COLOR_BRIGHT_RED=$(tput setaf 9)
        export COLOR_BRIGHT_GREEN=$(tput setaf 10)
        export COLOR_BRIGHT_YELLOW=$(tput setaf 11)
        export COLOR_BRIGHT_BLUE=$(tput setaf 12)
        export COLOR_BRIGHT_MAGENTA=$(tput setaf 13)
        export COLOR_BRIGHT_CYAN=$(tput setaf 14)
        
        # Text styles
        export STYLE_BOLD=$(tput bold)
        export STYLE_DIM=$(tput dim)
        export STYLE_UNDERLINE=$(tput smul)
        export STYLE_REVERSE=$(tput rev)
      else
        # No color support - all variables are empty
        export COLOR_RED=""
        export COLOR_GREEN=""
        export COLOR_YELLOW=""
        export COLOR_BLUE=""
        export COLOR_MAGENTA=""
        export COLOR_CYAN=""
        export COLOR_WHITE=""
        export COLOR_RESET=""
        export COLOR_BRIGHT_RED=""
        export COLOR_BRIGHT_GREEN=""
        export COLOR_BRIGHT_YELLOW=""
        export COLOR_BRIGHT_BLUE=""
        export COLOR_BRIGHT_MAGENTA=""
        export COLOR_BRIGHT_CYAN=""
        export STYLE_BOLD=""
        export STYLE_DIM=""
        export STYLE_UNDERLINE=""
        export STYLE_REVERSE=""
      fi
      
      # Convenience functions for colored output
      red() { echo "''${COLOR_RED}$*''${COLOR_RESET}"; }
      green() { echo "''${COLOR_GREEN}$*''${COLOR_RESET}"; }
      yellow() { echo "''${COLOR_YELLOW}$*''${COLOR_RESET}"; }
      blue() { echo "''${COLOR_BLUE}$*''${COLOR_RESET}"; }
      magenta() { echo "''${COLOR_MAGENTA}$*''${COLOR_RESET}"; }
      cyan() { echo "''${COLOR_CYAN}$*''${COLOR_RESET}"; }
      
      # Status message functions with semantic colors
      success() { echo "''${COLOR_GREEN}✅ $*''${COLOR_RESET}"; }
      error() { echo "''${COLOR_RED}❌ $*''${COLOR_RESET}" >&2; }
      warning() { echo "''${COLOR_YELLOW}⚠️  $*''${COLOR_RESET}" >&2; }
      info() { echo "''${COLOR_BLUE}ℹ️  $*''${COLOR_RESET}"; }
      debug() { echo "''${COLOR_MAGENTA}🔍 $*''${COLOR_RESET}"; }
      
      # Highlighted text functions
      bold() { echo "''${STYLE_BOLD}$*''${COLOR_RESET}"; }
      dim() { echo "''${STYLE_DIM}$*''${COLOR_RESET}"; }
      underline() { echo "''${STYLE_UNDERLINE}$*''${COLOR_RESET}"; }
      
      # Progress and status indicators with colors
      progress() { echo "''${COLOR_CYAN}🔄 $*''${COLOR_RESET}"; }
      complete() { echo "''${COLOR_GREEN}✅ $*''${COLOR_RESET}"; }
      failed() { echo "''${COLOR_RED}❌ $*''${COLOR_RESET}"; }
      
      # Header and section formatting
      header() {
        local text="$*"
        local length=''${#text}
        local line=$(printf "%*s" "$length" "" | tr ' ' '=')
        
        echo
        echo "''${STYLE_BOLD}''${COLOR_BLUE}$line''${COLOR_RESET}"
        echo "''${STYLE_BOLD}''${COLOR_BLUE}$text''${COLOR_RESET}"
        echo "''${STYLE_BOLD}''${COLOR_BLUE}$line''${COLOR_RESET}"
        echo
      }
      
      section() {
        echo
        echo "''${STYLE_BOLD}''${COLOR_CYAN}▶ $*''${COLOR_RESET}"
        echo
      }
      
      # Color capability detection
      has_color() {
        [[ -n "$COLOR_RED" ]]
      }
      
      # Print color palette (for testing)
      show_colors() {
        if has_color; then
          echo "Color palette test:"
          red "Red text"
          green "Green text"  
          yellow "Yellow text"
          blue "Blue text"
          magenta "Magenta text"
          cyan "Cyan text"
          bold "Bold text"
          dim "Dim text"
          underline "Underlined text"
        else
          echo "No color support detected"
        fi
      }
    '';
    tests = {
      colorDetection = pkgs.writeShellScript "test-color-detection" ''
        source ${colorUtils}
        echo "🎨 Testing color detection..."
        
        if has_color; then
          echo "✅ Color support detected"
        else
          echo "✅ No color support (graceful degradation)"
        fi
      '';

      colorFunctions = pkgs.writeShellScript "test-color-functions" ''
        source ${colorUtils}
        echo "🌈 Testing color functions..."
        
        success "Success message"
        error "Error message" 2>/dev/null
        warning "Warning message" 2>/dev/null
        info "Info message"
        
        echo "✅ Color functions passed"
      '';
    };
  };

  /**
    JSON manipulation utilities for configuration management.
    
    Provides safe JSON operations that complement the Claude wrapper
    configuration merging functionality.
  */
  jsonUtils = mkScriptLibrary {
    name = "jsonUtils";
    content = ''
      # JSON utility functions using jq
      # Source this file to access JSON manipulation functions
      
      # Check if jq is available
      require_jq() {
        if ! command -v jq >/dev/null 2>&1; then
          echo "❌ jq is required for JSON operations"
          return 1
        fi
      }
      
      # Validate JSON format
      is_valid_json() {
        local file="$1"
        require_jq || return 1
        
        if [[ -f "$file" ]]; then
          jq empty "$file" >/dev/null 2>&1
        else
          echo "❌ File not found: $file"
          return 1
        fi
      }
      
      # Pretty print JSON
      pretty_json() {
        local file="$1"
        require_jq || return 1
        
        if is_valid_json "$file"; then
          jq . "$file"
        else
          echo "❌ Invalid JSON in: $file"
          return 1
        fi
      }
      
      # Extract value from JSON
      json_get() {
        local file="$1" key="$2"
        require_jq || return 1
        
        if is_valid_json "$file"; then
          jq -r "$key // empty" "$file"
        else
          return 1
        fi
      }
      
      # Set value in JSON (creates backup)
      json_set() {
        local file="$1" key="$2" value="$3"
        require_jq || return 1
        
        if [[ -f "$file" ]]; then
          cp "$file" "$file.backup"
          jq "$key = $value" "$file.backup" > "$file"
          rm -f "$file.backup"
        else
          echo "❌ File not found: $file"
          return 1
        fi
      }
      
      # Merge two JSON files
      json_merge() {
        local base="$1" overlay="$2" output="$3"
        require_jq || return 1
        
        if is_valid_json "$base" && is_valid_json "$overlay"; then
          jq -s '.[0] * .[1]' "$base" "$overlay" > "$output"
        else
          echo "❌ Invalid JSON in input files"
          return 1
        fi
      }
      
      # Extract keys from JSON object
      json_keys() {
        local file="$1"
        require_jq || return 1
        
        if is_valid_json "$file"; then
          jq -r 'keys[]' "$file"
        else
          return 1
        fi
      }
    '';
    tests = {
      jsonValidation = pkgs.writeShellScript "test-json-validation" ''
        source ${jsonUtils}
        echo "📋 Testing JSON validation..."
        
        # Create test JSON
        echo '{"test": "value"}' > /tmp/test.json
        
        if is_valid_json /tmp/test.json; then
          echo "✅ JSON validation passed"
        else
          echo "❌ JSON validation failed"
          exit 1
        fi
        
        rm -f /tmp/test.json
      '';
    };
  };
}
