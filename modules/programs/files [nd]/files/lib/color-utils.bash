#!/usr/bin/env bash

# color-utils.bash - Terminal color detection and formatting utilities
# Extracted from tmux-session-picker for reusability and testability

# Global color variables (will be initialized by detect_color_support)
declare -g COLOR_SUPPORT_DETECTED=false
declare -g COLOR_BOLD COLOR_DIM COLOR_UNDERLINE COLOR_REVERSE COLOR_RESET
declare -g COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE COLOR_MAGENTA COLOR_CYAN COLOR_WHITE COLOR_BLACK
declare -g COLOR_CLEAR_LINE COLOR_MOVE_UP COLOR_HIDE_CURSOR COLOR_SHOW_CURSOR

# Detect color support and initialize color variables
# Usage: detect_color_support
# Returns: 0 if colors are supported, 1 if not
detect_color_support() {
    # Check if already detected
    [[ "$COLOR_SUPPORT_DETECTED" == "true" ]] && return 0
    
    # Check if output is a terminal
    if [[ ! -t 1 ]]; then
        # No color support for non-terminal output
        _init_no_color_fallbacks
        return 1
    fi
    
    # Check TERM variable and NO_COLOR environment
    if [[ -n "$NO_COLOR" ]] || [[ "$TERM" == "dumb" ]] || [[ "$TERM" == "unknown" ]]; then
        _init_no_color_fallbacks
        return 1
    fi
    
    # Check if terminal supports colors based on TERM
    case "$TERM" in
        *color*|xterm*|rxvt*|screen*|tmux*|alacritty|kitty|gnome-terminal|linux)
            # These terminals support colors
            ;;
        *)
            # Check if tput is available and supports colors
            if command -v tput >/dev/null 2>&1; then
                local colors=$(tput colors 2>/dev/null)
                if [[ ! "$colors" =~ ^[0-9]+$ ]] || [[ $colors -lt 8 ]]; then
                    _init_no_color_fallbacks
                    return 1
                fi
            else
                _init_no_color_fallbacks
                return 1
            fi
            ;;
    esac
    
    # Initialize color codes using tput if available, fallback to ANSI
    if command -v tput >/dev/null 2>&1; then
        _init_tput_colors
    else
        _init_ansi_colors
    fi
    
    COLOR_SUPPORT_DETECTED=true
    return 0
}

# Initialize color codes using tput
_init_tput_colors() {
    # Text formatting
    COLOR_BOLD=$(tput bold 2>/dev/null || echo "")
    COLOR_DIM=$(tput dim 2>/dev/null || echo "")
    COLOR_UNDERLINE=$(tput smul 2>/dev/null || echo "")
    COLOR_REVERSE=$(tput rev 2>/dev/null || echo "")
    COLOR_RESET=$(tput sgr0 2>/dev/null || echo "")
    
    # Colors
    COLOR_RED=$(tput setaf 1 2>/dev/null || echo "")
    COLOR_GREEN=$(tput setaf 2 2>/dev/null || echo "")
    COLOR_YELLOW=$(tput setaf 3 2>/dev/null || echo "")
    COLOR_BLUE=$(tput setaf 4 2>/dev/null || echo "")
    COLOR_MAGENTA=$(tput setaf 5 2>/dev/null || echo "")
    COLOR_CYAN=$(tput setaf 6 2>/dev/null || echo "")
    COLOR_WHITE=$(tput setaf 7 2>/dev/null || echo "")
    COLOR_BLACK=$(tput setaf 0 2>/dev/null || echo "")
    
    # Cursor and line manipulation
    COLOR_CLEAR_LINE=$(tput el 2>/dev/null || echo "")
    COLOR_MOVE_UP=$(tput cuu1 2>/dev/null || echo "")
    COLOR_HIDE_CURSOR=$(tput civis 2>/dev/null || echo "")
    COLOR_SHOW_CURSOR=$(tput cnorm 2>/dev/null || echo "")
}

# Initialize color codes using ANSI escape sequences
_init_ansi_colors() {
    # Text formatting
    COLOR_BOLD='\033[1m'
    COLOR_DIM='\033[2m'
    COLOR_UNDERLINE='\033[4m'
    COLOR_REVERSE='\033[7m'
    COLOR_RESET='\033[0m'
    
    # Colors
    COLOR_RED='\033[31m'
    COLOR_GREEN='\033[32m'
    COLOR_YELLOW='\033[33m'
    COLOR_BLUE='\033[34m'
    COLOR_MAGENTA='\033[35m'
    COLOR_CYAN='\033[36m'
    COLOR_WHITE='\033[37m'
    COLOR_BLACK='\033[30m'
    
    # Cursor and line manipulation
    COLOR_CLEAR_LINE='\033[K'
    COLOR_MOVE_UP='\033[A'
    COLOR_HIDE_CURSOR='\033[?25l'
    COLOR_SHOW_CURSOR='\033[?25h'
}

# Initialize no-color fallbacks (empty strings)
_init_no_color_fallbacks() {
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_UNDERLINE=""
    COLOR_REVERSE=""
    COLOR_RESET=""
    
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_CYAN=""
    COLOR_WHITE=""
    COLOR_BLACK=""
    
    COLOR_CLEAR_LINE=""
    COLOR_MOVE_UP=""
    COLOR_HIDE_CURSOR=""
    COLOR_SHOW_CURSOR=""
    
    COLOR_SUPPORT_DETECTED=true  # Mark as detected (no color)
}

# Apply color scheme to text
# Usage: apply_color_scheme "text" color [format]
# Example: apply_color_scheme "Error message" red bold
apply_color_scheme() {
    local text="$1"
    local color="$2"
    local format="${3:-}"
    
    # Ensure color support is detected
    detect_color_support
    
    # Build color sequence
    local color_start=""
    local color_end="$COLOR_RESET"
    
    # Apply format first
    case "$format" in
        bold) color_start="$COLOR_BOLD" ;;
        dim) color_start="$COLOR_DIM" ;;
        underline) color_start="$COLOR_UNDERLINE" ;;
        reverse) color_start="$COLOR_REVERSE" ;;
    esac
    
    # Apply color
    case "$color" in
        red) color_start="$color_start$COLOR_RED" ;;
        green) color_start="$color_start$COLOR_GREEN" ;;
        yellow) color_start="$color_start$COLOR_YELLOW" ;;
        blue) color_start="$color_start$COLOR_BLUE" ;;
        magenta) color_start="$color_start$COLOR_MAGENTA" ;;
        cyan) color_start="$color_start$COLOR_CYAN" ;;
        white) color_start="$color_start$COLOR_WHITE" ;;
        black) color_start="$color_start$COLOR_BLACK" ;;
    esac
    
    printf "%s%s%s" "$color_start" "$text" "$color_end"
}

# Safe color output - outputs with or without colors based on support
# Usage: safe_color_output "text" color [format]
safe_color_output() {
    local text="$1"
    local color="${2:-}"
    local format="${3:-}"
    
    if [[ -z "$color" ]]; then
        echo "$text"
    else
        apply_color_scheme "$text" "$color" "$format"
    fi
}

# High-level semantic color functions
# Usage: color_info "message", color_success "message", etc.

color_info() {
    local message="$1"
    safe_color_output "$message" blue
}

color_success() {
    local message="$1"
    safe_color_output "$message" green
}

color_warning() {
    local message="$1"
    safe_color_output "$message" yellow
}

color_error() {
    local message="$1"
    safe_color_output "$message" red
}

color_header() {
    local message="$1"
    safe_color_output "$message" blue bold
}

color_highlight() {
    local message="$1"
    safe_color_output "$message" cyan bold
}

color_dim() {
    local message="$1"
    safe_color_output "$message" "" dim
}

# Themed message functions with icons (if Unicode is supported)
# Usage: themed_info "message", themed_success "message", etc.

# Check if Unicode is supported for icons
_supports_unicode() {
    [[ "$LANG" =~ UTF-8 ]] && [[ "$TERM" != "linux" ]] && \
    locale -k LC_CTYPE 2>/dev/null | grep -q 'charmap="UTF-8"'
}

themed_info() {
    local message="$1"
    if _supports_unicode; then
        echo "$(color_info "ℹ️  $message")"
    else
        echo "$(color_info "[INFO] $message")"
    fi
}

themed_success() {
    local message="$1"
    if _supports_unicode; then
        echo "$(color_success "✅ $message")"
    else
        echo "$(color_success "[OK] $message")"
    fi
}

themed_warning() {
    local message="$1"
    if _supports_unicode; then
        echo "$(color_warning "⚠️  $message")"
    else
        echo "$(color_warning "[WARN] $message")"
    fi
}

themed_error() {
    local message="$1"
    if _supports_unicode; then
        echo "$(color_error "❌ $message")"
    else
        echo "$(color_error "[ERROR] $message")"
    fi
}

themed_step() {
    local message="$1"
    if _supports_unicode; then
        echo "$(color_highlight "📋 $message")"
    else
        echo "$(color_highlight "[STEP] $message")"
    fi
}

# Progress spinner with colors
# Usage: color_spinner pid "message"
color_spinner() {
    local pid=$1
    local message="${2:-Working...}"
    local delay=0.1
    local i=0
    
    # Ensure color support is detected
    detect_color_support
    
    # Get spinner characters
    local spinchars
    if _supports_unicode; then
        spinchars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    else
        spinchars="|/-\\"
    fi
    
    echo -n "$COLOR_HIDE_CURSOR"
    while ps -p "$pid" > /dev/null 2>&1; do
        local char="${spinchars:i++%${#spinchars}:1}"
        printf "\r%s%s%s %s" "$COLOR_CYAN" "$char" "$COLOR_RESET" "$message"
        sleep $delay
    done
    printf "\r%s%s\n" "$COLOR_CLEAR_LINE" "$COLOR_SHOW_CURSOR"
}

# Reset all color formatting
# Usage: color_reset
color_reset() {
    detect_color_support
    echo -n "$COLOR_RESET"
}

# Clear current line
# Usage: clear_line
clear_line() {
    detect_color_support
    echo -n "$COLOR_CLEAR_LINE"
}

# Move cursor up one line
# Usage: move_up
move_up() {
    detect_color_support
    echo -n "$COLOR_MOVE_UP"
}

# Hide cursor
# Usage: hide_cursor
hide_cursor() {
    detect_color_support
    echo -n "$COLOR_HIDE_CURSOR"
}

# Show cursor
# Usage: show_cursor
show_cursor() {
    detect_color_support
    echo -n "$COLOR_SHOW_CURSOR"
}

# Test function to demonstrate all color capabilities
# Usage: test_colors
test_colors() {
    echo "=== Color Support Test ==="
    detect_color_support
    local support_status=$?
    
    if [[ $support_status -eq 0 ]]; then
        echo "Color support: DETECTED"
    else
        echo "Color support: NOT DETECTED (fallback mode)"
    fi
    
    echo
    echo "=== Basic Colors ==="
    echo "$(apply_color_scheme "Red text" red)"
    echo "$(apply_color_scheme "Green text" green)"
    echo "$(apply_color_scheme "Blue text" blue)"
    echo "$(apply_color_scheme "Yellow text" yellow)"
    echo "$(apply_color_scheme "Cyan text" cyan)"
    echo "$(apply_color_scheme "Magenta text" magenta)"
    
    echo
    echo "=== Formatting ==="
    echo "$(apply_color_scheme "Bold text" blue bold)"
    echo "$(apply_color_scheme "Dim text" "" dim)"
    echo "$(apply_color_scheme "Underlined text" green underline)"
    
    echo
    echo "=== Themed Messages ==="
    themed_info "This is an info message"
    themed_success "This is a success message"
    themed_warning "This is a warning message"
    themed_error "This is an error message"
    themed_step "This is a step message"
    
    echo
    echo "=== Unicode Support ==="
    if _supports_unicode; then
        echo "Unicode icons: SUPPORTED"
    else
        echo "Unicode icons: NOT SUPPORTED (ASCII fallback)"
    fi
}