#!/usr/bin/env bash

# datetime-utils.bash - Date and time utilities for tmux-session-picker
# Extracted from tmux-session-picker for reusability and testability

# Parse tmux resurrect timestamp from filename
# Usage: parse_resurrect_timestamp "tmux_resurrect_20231024T142530.txt"
# Output: "20231024T142530"
parse_resurrect_timestamp() {
    local filename="$1"
    [[ -z "$filename" ]] && return 1
    
    # Extract timestamp from tmux resurrect filename format
    local basename=$(basename "$filename" .txt)
    local timestamp=$(echo "$basename" | sed 's/tmux_resurrect_//')
    
    # Validate timestamp format (YYYYMMDDTHHMMSS)
    if [[ "$timestamp" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then
        echo "$timestamp"
        return 0
    else
        return 1
    fi
}

# Format timestamp into compact display format
# Usage: format_compact_timestamp "20231024T142530"
# Output: "1024 142530" (MMDD HHMMSS format)
format_compact_timestamp() {
    local timestamp="$1"
    [[ -z "$timestamp" ]] && return 1
    
    # Validate input format
    if [[ ! "$timestamp" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then
        return 1
    fi
    
    # Extract components: YYYYMMDDTHHMMSS
    local year="${timestamp:0:4}"
    local month="${timestamp:4:2}"
    local day="${timestamp:6:2}"
    local hour="${timestamp:9:2}"
    local minute="${timestamp:11:2}"
    local second="${timestamp:13:2}"
    
    # Format as compact MMDD HHMMSS
    printf "%s%s %s%s%s" "$month" "$day" "$hour" "$minute" "$second"
}

# Convert timestamp to human-readable format
# Usage: timestamp_to_readable "20231024T142530"
# Output: "2023-10-24 14:25:30"
timestamp_to_readable() {
    local timestamp="$1"
    [[ -z "$timestamp" ]] && return 1
    
    # Validate input format
    if [[ ! "$timestamp" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then
        return 1
    fi
    
    # Extract components
    local year="${timestamp:0:4}"
    local month="${timestamp:4:2}"
    local day="${timestamp:6:2}"
    local hour="${timestamp:9:2}"
    local minute="${timestamp:11:2}"
    local second="${timestamp:13:2}"
    
    # Format as ISO-like datetime
    printf "%s-%s-%s %s:%s:%s" "$year" "$month" "$day" "$hour" "$minute" "$second"
}

# Convert timestamp to relative time description
# Usage: timestamp_to_relative "20231024T142530"
# Output: "2 hours ago", "3 days ago", etc.
timestamp_to_relative() {
    local timestamp="$1"
    [[ -z "$timestamp" ]] && return 1
    
    # Validate input format
    if [[ ! "$timestamp" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then
        return 1
    fi
    
    # Convert to epoch time
    local year="${timestamp:0:4}"
    local month="${timestamp:4:2}"
    local day="${timestamp:6:2}"
    local hour="${timestamp:9:2}"
    local minute="${timestamp:11:2}"
    local second="${timestamp:13:2}"
    
    # Create date string for parsing
    local date_str="${year}-${month}-${day} ${hour}:${minute}:${second}"
    
    # Get epoch seconds (use date command if available)
    local file_epoch
    if command -v date >/dev/null 2>&1; then
        file_epoch=$(date -d "$date_str" +%s 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            # Fallback for different date implementations
            file_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$date_str" +%s 2>/dev/null)
        fi
    fi
    
    # If date parsing failed, return formatted timestamp
    if [[ -z "$file_epoch" ]]; then
        timestamp_to_readable "$timestamp"
        return 0
    fi
    
    local current_epoch=$(date +%s)
    local diff=$((current_epoch - file_epoch))
    
    # Calculate relative time
    if [[ $diff -lt 60 ]]; then
        echo "just now"
    elif [[ $diff -lt 3600 ]]; then
        local minutes=$((diff / 60))
        [[ $minutes -eq 1 ]] && echo "1 minute ago" || echo "${minutes} minutes ago"
    elif [[ $diff -lt 86400 ]]; then
        local hours=$((diff / 3600))
        [[ $hours -eq 1 ]] && echo "1 hour ago" || echo "${hours} hours ago"
    elif [[ $diff -lt 604800 ]]; then
        local days=$((diff / 86400))
        [[ $days -eq 1 ]] && echo "1 day ago" || echo "${days} days ago"
    elif [[ $diff -lt 2592000 ]]; then
        local weeks=$((diff / 604800))
        [[ $weeks -eq 1 ]] && echo "1 week ago" || echo "${weeks} weeks ago"
    else
        # For older items, show the actual date
        timestamp_to_readable "$timestamp"
    fi
}

# Get current timestamp in resurrect format
# Usage: get_current_timestamp
# Output: "20231024T142530"
get_current_timestamp() {
    date '+%Y%m%dT%H%M%S'
}

# Compare two resurrect timestamps
# Usage: compare_timestamps "20231024T142530" "20231024T143000"
# Returns: -1 (first is older), 0 (same), 1 (first is newer)
compare_timestamps() {
    local ts1="$1"
    local ts2="$2"
    [[ -z "$ts1" || -z "$ts2" ]] && return 1
    
    # Simple string comparison works for our timestamp format
    if [[ "$ts1" < "$ts2" ]]; then
        echo "-1"
    elif [[ "$ts1" > "$ts2" ]]; then
        echo "1"
    else
        echo "0"
    fi
}

# Validate resurrect timestamp format
# Usage: validate_timestamp "20231024T142530"
# Returns: 0 if valid, 1 if invalid
validate_timestamp() {
    local timestamp="$1"
    [[ -z "$timestamp" ]] && return 1
    
    # Check format
    if [[ ! "$timestamp" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then
        return 1
    fi
    
    # Extract and validate components
    local year="${timestamp:0:4}"
    local month="${timestamp:4:2}"
    local day="${timestamp:6:2}"
    local hour="${timestamp:9:2}"
    local minute="${timestamp:11:2}"
    local second="${timestamp:13:2}"
    
    # Basic range validation
    [[ $month -ge 1 && $month -le 12 ]] || return 1
    [[ $day -ge 1 && $day -le 31 ]] || return 1
    [[ $hour -ge 0 && $hour -le 23 ]] || return 1
    [[ $minute -ge 0 && $minute -le 59 ]] || return 1
    [[ $second -ge 0 && $second -le 59 ]] || return 1
    
    return 0
}

# Sort timestamps (newest first)
# Usage: sort_timestamps_desc "20231024T142530" "20231024T143000" "20231023T100000"
# Output: One timestamp per line, sorted newest first
sort_timestamps_desc() {
    # Read from arguments or stdin
    if [[ $# -gt 0 ]]; then
        printf '%s\n' "$@" | sort -r
    else
        sort -r
    fi
}

# Sort timestamps (oldest first)
# Usage: sort_timestamps_asc "20231024T142530" "20231024T143000" "20231023T100000"
# Output: One timestamp per line, sorted oldest first
sort_timestamps_asc() {
    # Read from arguments or stdin
    if [[ $# -gt 0 ]]; then
        printf '%s\n' "$@" | sort
    else
        sort
    fi
}