#!/usr/bin/env bash
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
    function cf_clear_line() { true; }
    function cf_move_up() { echo "$*"; }
    function cf_hide_cursor() { true; }
    function cf_show_cursor() { true; }
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
    echo "${CF_BOLD}$*${CF_RESET}"
}

function cf_dim() {
    echo "${CF_DIM}$*${CF_RESET}"
}

function cf_underline() {
    echo "${CF_UNDERLINE}$*${CF_RESET}"
}

function cf_reverse() {
    echo "${CF_REVERSE}$*${CF_RESET}"
}

# Color functions
function cf_red() {
    echo "${CF_RED}$*${CF_RESET}"
}

function cf_green() {
    echo "${CF_GREEN}$*${CF_RESET}"
}

function cf_yellow() {
    echo "${CF_YELLOW}$*${CF_RESET}"
}

function cf_blue() {
    echo "${CF_BLUE}$*${CF_RESET}"
}

function cf_magenta() {
    echo "${CF_MAGENTA}$*${CF_RESET}"
}

function cf_cyan() {
    echo "${CF_CYAN}$*${CF_RESET}"
}

function cf_white() {
    echo "${CF_WHITE}$*${CF_RESET}"
}

function cf_black() {
    echo "${CF_BLACK}$*${CF_RESET}"
}

# Combined formatting functions
function cf_bold_red() {
    echo "${CF_BOLD}${CF_RED}$*${CF_RESET}"
}

function cf_bold_green() {
    echo "${CF_BOLD}${CF_GREEN}$*${CF_RESET}"
}

function cf_bold_yellow() {
    echo "${CF_BOLD}${CF_YELLOW}$*${CF_RESET}"
}

function cf_bold_blue() {
    echo "${CF_BOLD}${CF_BLUE}$*${CF_RESET}"
}

function cf_bold_cyan() {
    echo "${CF_BOLD}${CF_CYAN}$*${CF_RESET}"
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
        cf_blue "i  $*"
    }
    
    function cf_success() {
        cf_green "✓ $*"
    }
    
    function cf_warning() {
        cf_yellow "⚠  $*"
    }
    
    function cf_error() {
        cf_red "✗ $*"
    }
    
    function cf_step() {
        cf_cyan "» $*"
    }
else
    # ASCII alternatives for compatibility
    function cf_info() {
        cf_blue "[INFO] $*"
    }
    
    function cf_success() {
        cf_green "[OK] $*"
    }
    
    function cf_warning() {
        cf_yellow "[WARN] $*"
    }
    
    function cf_error() {
        cf_red "[ERROR] $*"
    }
    
    function cf_step() {
        cf_cyan "[STEP] $*"
    }
fi

function cf_header() {
    cf_bold_blue "$*"
}

# Progress indication
function cf_spinner() {
    local pid=$1
    local delay=0.1
    local spinchars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local temp
    
    cf_hide_cursor
    while ps -p "$pid" > /dev/null 2>&1; do
        temp="${spinchars:i++%${#spinchars}:1}"
        printf "\r$(cf_cyan "%s") %s" "$temp" "${2:-Working...}"
        sleep $delay
    done
    printf "\r%s" "$(cf_clear_line)"
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

# Note: Functions are automatically available when sourced in zsh
# No need to export functions in zsh - they're available in the current shell

# Make color codes available as variables
export CF_BOLD CF_DIM CF_UNDERLINE CF_REVERSE CF_RESET
export CF_RED CF_GREEN CF_YELLOW CF_BLUE CF_MAGENTA CF_CYAN CF_WHITE CF_BLACK
export CF_CLEAR_LINE CF_MOVE_UP CF_HIDE_CURSOR CF_SHOW_CURSOR
