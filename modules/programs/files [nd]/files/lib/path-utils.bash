#!/usr/bin/env bash

# path-utils.bash: Reusable path manipulation and display utilities
# Extracted from tmux-session-picker for use across multiple scripts

# Abbreviate common paths for compact display
# Usage: abbreviate_common_paths "/home/user/projects/myproject"
# Output: "~/p/myproject"
abbreviate_common_paths() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    
    # Common abbreviations
    path="${path/#$HOME\//~/}"
    path="${path/#\/home\/$USER\//~/}"
    
    # Abbreviate common directories
    path=$(echo "$path" | sed \
        -e 's|~/projects/|~/p/|' \
        -e 's|~/Projects/|~/P/|' \
        -e 's|~/src/|~/s/|' \
        -e 's|~/Documents/|~/D/|' \
        -e 's|~/Downloads/|~/dl/|' \
        -e 's|~/Desktop/|~/dt/|' \
        -e 's|/usr/local/|/u/l/|' \
        -e 's|/var/log/|/v/l/|' \
        -e 's|/opt/|/o/|' \
        -e 's|/etc/|/e/|')
    
    echo "$path"
}

# Truncate long paths intelligently by showing last segments
# Usage: truncate_long_paths "/very/long/path/to/file" 20
# Output: "…/path/to/file" (if path exceeds max_length)
truncate_long_paths() {
    local path="$1"
    local max_length="${2:-20}"
    [[ -z "$path" ]] && return 1
    
    # If path is within limit, return as-is
    if [[ ${#path} -le $max_length ]]; then
        echo "$path"
        return 0
    fi
    
    # Split path into segments
    local segments=(${path//\// })
    local count=${#segments[@]}
    
    # For very short limits, just show filename
    if [[ $max_length -lt 10 && $count -gt 0 ]]; then
        echo "…/${segments[$count-1]}"
        return 0
    fi
    
    # Try different segment combinations
    for (( i=2; i<=count; i++ )); do
        local truncated="…"
        for (( j=$((count-i)); j<count; j++ )); do
            truncated="$truncated/${segments[j]}"
        done
        
        if [[ ${#truncated} -le $max_length ]]; then
            echo "$truncated"
            return 0
        fi
    done
    
    # Fallback: just show last segment with ellipsis
    echo "…/${segments[$count-1]}"
}

# Normalize path display by combining abbreviation and truncation
# Usage: normalize_path_display "/home/user/projects/myproject/subdir" 25
# Output: "~/p/myproject/subdir" or "…/myproject/subdir" if needed
normalize_path_display() {
    local path="$1"
    local max_length="${2:-30}"
    [[ -z "$path" ]] && return 1
    
    # First abbreviate common paths
    local abbreviated=$(abbreviate_common_paths "$path")
    
    # Then truncate if still too long
    truncate_long_paths "$abbreviated" "$max_length"
}

# Get relative path from one directory to another
# Usage: get_relative_path "/home/user/projects" "/home/user/projects/subdir/file"
# Output: "subdir/file"
get_relative_path() {
    local from="$1"
    local to="$2"
    [[ -z "$from" || -z "$to" ]] && return 1
    
    # Normalize paths (remove trailing slashes)
    from="${from%/}"
    to="${to%/}"
    
    # If 'to' doesn't start with 'from', return full path
    if [[ "$to" != "$from"* ]]; then
        echo "$to"
        return 0
    fi
    
    # Remove the 'from' prefix and leading slash
    local relative="${to#$from}"
    relative="${relative#/}"
    
    # If empty, return current directory indicator
    [[ -z "$relative" ]] && relative="."
    
    echo "$relative"
}

# Extract filename without extension
# Usage: get_basename_no_ext "/path/to/file.txt"
# Output: "file"
get_basename_no_ext() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    
    local basename=$(basename "$path")
    echo "${basename%.*}"
}

# Extract file extension
# Usage: get_file_extension "/path/to/file.txt"
# Output: "txt"
get_file_extension() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    
    local basename=$(basename "$path")
    if [[ "$basename" == *.* ]]; then
        echo "${basename##*.}"
    else
        return 1  # No extension
    fi
}

# Check if path is within a specific directory
# Usage: path_is_within "/home/user" "/home/user/projects/file"
# Returns: 0 if within, 1 if not
path_is_within() {
    local parent="$1"
    local child="$2"
    [[ -z "$parent" || -z "$child" ]] && return 1
    
    # Normalize paths
    parent="${parent%/}"
    child="${child%/}"
    
    # Check if child starts with parent
    [[ "$child" == "$parent"* ]]
}

# Expand path shortcuts and resolve to absolute path
# Usage: expand_path "~/projects/../documents/file.txt"
# Output: "/home/user/documents/file.txt"
expand_path() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    
    # Expand tilde
    path="${path/#\~/$HOME}"
    
    # Use readlink if path exists, otherwise do basic cleanup
    if [[ -e "$path" ]]; then
        readlink -f "$path"
    else
        # Basic path normalization for non-existent paths
        # Remove ./ and resolve ../ sequences
        echo "$path" | sed -e 's|/\./|/|g' -e 's|/[^/]*/\.\./|/|g' -e 's|^\./||'
    fi
}