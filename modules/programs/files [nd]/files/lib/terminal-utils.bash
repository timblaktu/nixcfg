#!/usr/bin/env bash

# terminal-utils.bash - Terminal layout and width detection utilities
# Extracted from tmux-session-picker for reusability and testability

# Unicode display width calculation functions
# Optimized version: eliminates Python subprocess overhead for common cases
get_display_width() {
    local text="$1"
    
    # Fast path: if text contains only ASCII printable and space characters
    # Remove all non-ASCII bytes and compare
    local ascii_only="${text//[^[:ascii:]]/}"
    if [[ "$text" == "$ascii_only" ]]; then
        echo ${#text}
        return
    fi
    
    # For text with Unicode, use wc to count characters properly
    # Set LC_ALL=C.UTF-8 to ensure proper UTF-8 character counting
    local char_count
    char_count=$(printf '%s' "$text" | LC_ALL=C.UTF-8 wc -m)
    
    # Simple heuristic: assume each Unicode character (beyond ASCII) is double-width
    # This works well for CJK characters and most emojis
    local ascii_count=${#ascii_only}
    local unicode_count=$((char_count - ascii_count))
    local width=$((ascii_count + unicode_count * 2))
    
    echo $width
}

# Truncate string to fit display width (accounting for unicode)
# Optimized version: uses binary search approach for better performance with Unicode
truncate_to_display_width() {
    local text="$1"
    local max_width="$2"
    local ellipsis="${3:-…}"
    
    local current_width=$(get_display_width "$text")
    
    # If it fits, return as-is
    if [[ $current_width -le $max_width ]]; then
        echo "$text"
        return
    fi
    
    # Calculate ellipsis width and target width
    local ellipsis_width=$(get_display_width "$ellipsis")
    local target_width=$((max_width - ellipsis_width))
    
    # If target width is too small, just return ellipsis
    if [[ $target_width -le 0 ]]; then
        echo "$ellipsis"
        return
    fi
    
    # For ASCII-only text, use simple character truncation
    local ascii_only="${text//[^[:ascii:]]/}"
    if [[ "$text" == "$ascii_only" ]]; then
        echo "${text:0:$target_width}$ellipsis"
        return
    fi
    
    # For Unicode text, use binary search to find optimal truncation point
    # Convert string to array of characters first using LC_ALL=C.UTF-8
    local -a chars
    local char_count
    char_count=$(printf '%s' "$text" | LC_ALL=C.UTF-8 wc -m)
    
    # Binary search for the right truncation point
    local left=0
    local right=$char_count
    local best_len=0
    
    while [[ $left -le $right ]]; do
        local mid=$(((left + right) / 2))
        local substr
        substr=$(printf '%s' "$text" | LC_ALL=C.UTF-8 cut -c1-$mid)
        local substr_width=$(get_display_width "$substr")
        
        if [[ $substr_width -le $target_width ]]; then
            best_len=$mid
            left=$((mid + 1))
        else
            right=$((mid - 1))
        fi
    done
    
    # Extract the substring and add ellipsis
    local result
    result=$(printf '%s' "$text" | LC_ALL=C.UTF-8 cut -c1-$best_len)
    echo "$result$ellipsis"
}

# Truncate text in the middle with unicode ellipsis (preserving display width)
# Usage: truncate_middle_to_display_width "very-long-filename" 10
# Output: "very-l…ame" (keeps start and end, truncates middle)
truncate_middle_to_display_width() {
    local text="$1"
    local max_width="$2"
    local ellipsis="${3:-…}"
    
    local current_width=$(get_display_width "$text")
    
    # If it fits, return as-is
    if [[ $current_width -le $max_width ]]; then
        echo "$text"
        return
    fi
    
    # Calculate ellipsis width
    local ellipsis_width=$(get_display_width "$ellipsis")
    local target_width=$((max_width - ellipsis_width))
    
    # If target width is too small, just return ellipsis
    if [[ $target_width -le 0 ]]; then
        echo "$ellipsis"
        return
    fi
    
    # For very short limits, just use end truncation
    if [[ $target_width -lt 4 ]]; then
        truncate_to_display_width "$text" "$max_width" "$ellipsis"
        return
    fi
    
    # Calculate characters to keep on each side
    local start_width=$((target_width / 2))
    local end_width=$((target_width - start_width))
    
    # Extract start portion (using binary search approach like truncate_to_display_width)
    local start_text=""
    local text_len=${#text}
    local left=0 right=$text_len best_start_len=0
    
    while [[ $left -le $right ]]; do
        local mid=$(((left + right) / 2))
        local candidate
        candidate=$(printf '%s' "$text" | LC_ALL=C.UTF-8 cut -c1-$mid)
        local candidate_width=$(get_display_width "$candidate")
        
        if [[ $candidate_width -le $start_width ]]; then
            best_start_len=$mid
            left=$((mid + 1))
        else
            right=$((mid - 1))
        fi
    done
    
    start_text=$(printf '%s' "$text" | LC_ALL=C.UTF-8 cut -c1-$best_start_len)
    
    # Extract end portion (binary search from the end)
    local end_text=""
    left=0 right=$text_len best_end_start=0
    
    while [[ $left -le $right ]]; do
        local mid=$(((left + right) / 2))
        local end_start=$((text_len - mid + 1))
        if [[ $end_start -lt 1 ]]; then
            end_start=1
        fi
        local candidate
        candidate=$(printf '%s' "$text" | LC_ALL=C.UTF-8 cut -c$end_start-)
        local candidate_width=$(get_display_width "$candidate")
        
        if [[ $candidate_width -le $end_width ]]; then
            best_end_start=$end_start
            left=$((mid + 1))
        else
            right=$((mid - 1))
        fi
    done
    
    if [[ $best_end_start -gt 0 ]]; then
        end_text=$(printf '%s' "$text" | LC_ALL=C.UTF-8 cut -c$best_end_start-)
    fi
    
    echo "$start_text$ellipsis$end_text"
}

# Detect current terminal width with fallbacks
# Usage: detect_terminal_width
# Output: Terminal width in characters (e.g., "80")
detect_terminal_width() {
    local width
    
    # Try multiple methods to get terminal width
    if [[ -n "${COLUMNS:-}" ]]; then
        width="$COLUMNS"
    elif command -v tput >/dev/null 2>&1; then
        width=$(tput cols 2>/dev/null)
    elif command -v stty >/dev/null 2>&1; then
        width=$(stty size 2>/dev/null | cut -d' ' -f2)
    fi
    
    # Validate and apply fallback
    if [[ ! "$width" =~ ^[0-9]+$ ]] || [[ $width -lt 20 ]]; then
        width=80  # Safe fallback
    fi
    
    echo "$width"
}

# Detect current terminal height with fallbacks
# Usage: detect_terminal_height
# Output: Terminal height in lines (e.g., "24")
detect_terminal_height() {
    local height
    
    # Try multiple methods to get terminal height
    if [[ -n "${LINES:-}" ]]; then
        height="$LINES"
    elif command -v tput >/dev/null 2>&1; then
        height=$(tput lines 2>/dev/null)
    elif command -v stty >/dev/null 2>&1; then
        height=$(stty size 2>/dev/null | cut -d' ' -f1)
    fi
    
    # Validate and apply fallback
    if [[ ! "$height" =~ ^[0-9]+$ ]] || [[ $height -lt 10 ]]; then
        height=24  # Safe fallback
    fi
    
    echo "$height"
}

# Calculate column layout for table display
# Usage: calculate_column_layout session_width date_width stats_width [terminal_width]
# Output: "session_width date_width stats_width remaining_width separator_chars"
calculate_column_layout() {
    local session_width="${1:-7}"
    local date_width="${2:-11}"
    local stats_width="${3:-5}"
    local terminal_width="${4:-$(detect_terminal_width)}"
    local separator_chars="${5:-3}"
    
    # Calculate remaining width for summary column
    local remaining_width=$((terminal_width - session_width - date_width - stats_width - separator_chars))
    
    # Ensure minimum width for readability
    local min_remaining="${6:-45}"
    [[ $remaining_width -lt $min_remaining ]] && remaining_width=$min_remaining
    
    echo "$session_width $date_width $stats_width $remaining_width $separator_chars"
}

# Format table columns with proper alignment
# Usage: format_table_columns "Session" "Date" "Stats" "Summary" session_width date_width stats_width remaining_width
# Output: Formatted table row with proper spacing
format_table_columns() {
    local session="$1"
    local date="$2"
    local stats="$3"
    local summary="$4"
    local session_width="$5"
    local date_width="$6"
    local stats_width="$7"
    local remaining_width="$8"
    
    # Truncate fields if they exceed their allocated width (using display width)
    session=$(truncate_to_display_width "$session" "$session_width")
    date=$(truncate_to_display_width "$date" "$date_width")
    stats=$(truncate_to_display_width "$stats" "$stats_width")
    summary=$(truncate_to_display_width "$summary" "$remaining_width")
    
    # Format with proper alignment
    printf "%-*s %-*s %*s %-*s" \
        "$session_width" "$session" \
        "$date_width" "$date" \
        "$stats_width" "$stats" \
        "$remaining_width" "$summary"
}

# Create table separator line
# Usage: create_table_separator session_width date_width stats_width remaining_width [char]
# Output: Separator line made of specified character (default: ─)
create_table_separator() {
    local session_width="$1"
    local date_width="$2"
    local stats_width="$3"
    local remaining_width="$4"
    local char="${5:-─}"
    local separator_chars="${6:-3}"
    
    local total_width=$((session_width + date_width + stats_width + remaining_width + separator_chars))
    printf '%*s' "$total_width" '' | tr ' ' "$char"
}

# Calculate optimal fzf height as percentage of terminal
# Usage: calculate_fzf_height [percentage]
# Output: Height value suitable for fzf --height parameter
calculate_fzf_height() {
    local percentage="${1:-95}"
    local terminal_height=$(detect_terminal_height)
    
    # Calculate height and ensure minimum
    local fzf_height=$((terminal_height * percentage / 100))
    [[ $fzf_height -lt 10 ]] && fzf_height=10
    
    echo "$fzf_height"
}

# Detect if terminal supports colors
# Usage: supports_color
# Returns: 0 if colors are supported, 1 if not
supports_color() {
    # Check if output is a terminal
    [[ ! -t 1 ]] && return 1
    
    # Check TERM variable
    case "$TERM" in
        *color*|xterm*|rxvt*|screen*|tmux*|alacritty|kitty|gnome-terminal)
            return 0
            ;;
        linux)
            # Linux console supports basic colors
            return 0
            ;;
        dumb|unknown)
            return 1
            ;;
    esac
    
    # Check if tput is available and supports colors
    if command -v tput >/dev/null 2>&1; then
        local colors=$(tput colors 2>/dev/null)
        [[ "$colors" -ge 8 ]] && return 0
    fi
    
    return 1
}

# Detect Unicode support in terminal
# Usage: supports_unicode
# Returns: 0 if Unicode is supported, 1 if not
supports_unicode() {
    # Check if output is a terminal
    [[ ! -t 1 ]] && return 1
    
    # Check locale settings
    if [[ "$LANG" =~ UTF-8 ]] && [[ "$TERM" != "linux" ]]; then
        if locale -k LC_CTYPE 2>/dev/null | grep -q 'charmap="UTF-8"'; then
            return 0
        fi
    fi
    
    return 1
}

# Get appropriate progress spinner characters
# Usage: get_spinner_chars
# Output: String of characters for spinner animation
get_spinner_chars() {
    if supports_unicode; then
        echo "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    else
        echo "|/-\\"
    fi
}

# Calculate optimal preview window size for fzf layout
# Usage: calculate_preview_size layout terminal_width terminal_height
# Output: Optimal size specification for fzf preview window
calculate_preview_size() {
    local layout="$1"
    local terminal_width="${2:-$(detect_terminal_width)}"
    local terminal_height="${3:-$(detect_terminal_height)}"
    
    case "$layout" in
        horizontal)
            # For horizontal layout, use percentage of width
            if [[ $terminal_width -ge 120 ]]; then
                echo "50%"
            elif [[ $terminal_width -ge 100 ]]; then
                echo "45%"
            else
                echo "40%"
            fi
            ;;
        vertical)
            # For vertical layout, use percentage of height
            if [[ $terminal_height -ge 40 ]]; then
                echo "60%"
            elif [[ $terminal_height -ge 30 ]]; then
                echo "50%"
            else
                echo "40%"
            fi
            ;;
        *)
            echo "50%"  # Default fallback
            ;;
    esac
}

# Check if running inside tmux
# Usage: is_tmux_session
# Returns: 0 if inside tmux, 1 if not
is_tmux_session() {
    [[ -n "${TMUX:-}" ]]
}

# Get tmux session info if available
# Usage: get_tmux_session_info
# Output: "session_name:window_index:pane_index" or empty if not in tmux
get_tmux_session_info() {
    if is_tmux_session && command -v tmux >/dev/null 2>&1; then
        local session_name=$(tmux display-message -p '#S' 2>/dev/null)
        local window_index=$(tmux display-message -p '#I' 2>/dev/null)
        local pane_index=$(tmux display-message -p '#P' 2>/dev/null)
        
        if [[ -n "$session_name" && -n "$window_index" && -n "$pane_index" ]]; then
            echo "${session_name}:${window_index}:${pane_index}"
        fi
    fi
}

# Optimize column widths based on content analysis
# Usage: optimize_column_widths content_file session_col date_col stats_col summary_col terminal_width
# Output: "optimized_session_width optimized_date_width optimized_stats_width optimized_summary_width"
optimize_column_widths() {
    local content_file="$1"
    local session_col="${2:-1}"
    local date_col="${3:-2}"
    local stats_col="${4:-3}"
    local summary_col="${5:-4}"
    local terminal_width="${6:-$(detect_terminal_width)}"
    
    # If no content file, return defaults
    if [[ ! -f "$content_file" ]]; then
        calculate_column_layout 7 11 5 "$terminal_width"
        return
    fi
    
    # Analyze actual content to optimize widths
    local max_session=$(awk -F'\t' -v col="$session_col" '{if(length($col) > max) max=length($col)} END{print max+1}' "$content_file")
    local max_date=$(awk -F'\t' -v col="$date_col" '{if(length($col) > max) max=length($col)} END{print max+1}' "$content_file")
    local max_stats=$(awk -F'\t' -v col="$stats_col" '{if(length($col) > max) max=length($col)} END{print max+1}' "$content_file")
    
    # Apply reasonable limits
    [[ $max_session -lt 7 ]] && max_session=7
    [[ $max_session -gt 20 ]] && max_session=20
    [[ $max_date -lt 11 ]] && max_date=11
    [[ $max_date -gt 15 ]] && max_date=15
    [[ $max_stats -lt 5 ]] && max_stats=5
    [[ $max_stats -gt 8 ]] && max_stats=8
    
    calculate_column_layout "$max_session" "$max_date" "$max_stats" "$terminal_width"
}