#!/usr/bin/env bash

# fs-utils.bash - Filesystem validation and dependency check utilities
# Extracted from tmux-session-picker for reusability and testability

# Validate that required dependencies are available
# Usage: validate_dependencies command1 [command2 ...]
# Returns: 0 if all dependencies are found, 1 if any are missing
validate_dependencies() {
    local missing_deps=()
    local dep
    
    for dep in "$@"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "Please install the missing tools and try again." >&2
        return 1
    fi
    
    return 0
}

# Ensure directory exists and is writable
# Usage: ensure_directory_exists "/path/to/directory" [create_if_missing]
# Returns: 0 if directory exists and is writable, 1 otherwise
ensure_directory_exists() {
    local dir_path="$1"
    local create_if_missing="${2:-false}"
    
    if [[ -z "$dir_path" ]]; then
        echo "Error: Directory path cannot be empty" >&2
        return 1
    fi
    
    # Check if directory exists
    if [[ ! -d "$dir_path" ]]; then
        if [[ "$create_if_missing" == "true" ]]; then
            # Try to create the directory
            if ! mkdir -p "$dir_path" 2>/dev/null; then
                echo "Error: Cannot create directory: $dir_path" >&2
                return 1
            fi
        else
            echo "Error: Directory does not exist: $dir_path" >&2
            return 1
        fi
    fi
    
    # Check if directory is writable
    if [[ ! -w "$dir_path" ]]; then
        echo "Error: Directory is not writable: $dir_path" >&2
        return 1
    fi
    
    return 0
}

# Validate file permissions and existence
# Usage: validate_file_permissions "/path/to/file" [required_permissions]
# required_permissions: r (readable), w (writable), x (executable), combination like "rx"
# Returns: 0 if file meets requirements, 1 otherwise
validate_file_permissions() {
    local file_path="$1"
    local required_perms="${2:-r}"
    
    if [[ -z "$file_path" ]]; then
        echo "Error: File path cannot be empty" >&2
        return 1
    fi
    
    # Check if file exists
    if [[ ! -e "$file_path" ]]; then
        echo "Error: File does not exist: $file_path" >&2
        return 1
    fi
    
    # Check required permissions
    local perm
    for (( i=0; i<${#required_perms}; i++ )); do
        perm="${required_perms:$i:1}"
        case "$perm" in
            r)
                if [[ ! -r "$file_path" ]]; then
                    echo "Error: File is not readable: $file_path" >&2
                    return 1
                fi
                ;;
            w)
                if [[ ! -w "$file_path" ]]; then
                    echo "Error: File is not writable: $file_path" >&2
                    return 1
                fi
                ;;
            x)
                if [[ ! -x "$file_path" ]]; then
                    echo "Error: File is not executable: $file_path" >&2
                    return 1
                fi
                ;;
            *)
                echo "Error: Invalid permission specification: $perm" >&2
                return 1
                ;;
        esac
    done
    
    return 0
}

# Check if directory is empty
# Usage: is_directory_empty "/path/to/directory"
# Returns: 0 if empty, 1 if not empty or not a directory
is_directory_empty() {
    local dir_path="$1"
    
    [[ -z "$dir_path" ]] && return 1
    [[ ! -d "$dir_path" ]] && return 1
    
    # Check for any files (including hidden ones)
    local file_count=$(find "$dir_path" -maxdepth 1 -type f | wc -l)
    [[ $file_count -eq 0 ]]
}

# Get file age in seconds
# Usage: get_file_age "/path/to/file"
# Output: Age in seconds since last modification
get_file_age() {
    local file_path="$1"
    
    [[ -z "$file_path" ]] && return 1
    [[ ! -e "$file_path" ]] && return 1
    
    local current_time=$(date +%s)
    local file_time=$(stat -c %Y "$file_path" 2>/dev/null || stat -f %m "$file_path" 2>/dev/null)
    
    if [[ -n "$file_time" ]]; then
        echo $((current_time - file_time))
    else
        return 1
    fi
}

# Check if file is older than specified time
# Usage: is_file_older_than "/path/to/file" seconds
# Returns: 0 if file is older, 1 if newer or doesn't exist
is_file_older_than() {
    local file_path="$1"
    local max_age="$2"
    
    [[ -z "$file_path" || -z "$max_age" ]] && return 1
    [[ ! "$max_age" =~ ^[0-9]+$ ]] && return 1
    
    local file_age
    file_age=$(get_file_age "$file_path") || return 1
    
    [[ $file_age -gt $max_age ]]
}

# Safe file operations with backup
# Usage: safe_file_operation "operation" "source" [destination]
# Operations: copy, move, backup, restore
safe_file_operation() {
    local operation="$1"
    local source="$2"
    local destination="$3"
    
    case "$operation" in
        copy)
            if [[ -z "$source" || -z "$destination" ]]; then
                echo "Error: copy operation requires source and destination" >&2
                return 1
            fi
            
            if [[ ! -e "$source" ]]; then
                echo "Error: Source file does not exist: $source" >&2
                return 1
            fi
            
            cp "$source" "$destination" 2>/dev/null || {
                echo "Error: Failed to copy $source to $destination" >&2
                return 1
            }
            ;;
        
        move)
            if [[ -z "$source" || -z "$destination" ]]; then
                echo "Error: move operation requires source and destination" >&2
                return 1
            fi
            
            if [[ ! -e "$source" ]]; then
                echo "Error: Source file does not exist: $source" >&2
                return 1
            fi
            
            mv "$source" "$destination" 2>/dev/null || {
                echo "Error: Failed to move $source to $destination" >&2
                return 1
            }
            ;;
        
        backup)
            if [[ -z "$source" ]]; then
                echo "Error: backup operation requires source file" >&2
                return 1
            fi
            
            if [[ ! -e "$source" ]]; then
                echo "Error: Source file does not exist: $source" >&2
                return 1
            fi
            
            local backup_name="${source}.backup.$(date +%s)"
            cp "$source" "$backup_name" 2>/dev/null || {
                echo "Error: Failed to create backup of $source" >&2
                return 1
            }
            
            echo "$backup_name"
            ;;
        
        restore)
            if [[ -z "$source" || -z "$destination" ]]; then
                echo "Error: restore operation requires backup file and destination" >&2
                return 1
            fi
            
            if [[ ! -e "$source" ]]; then
                echo "Error: Backup file does not exist: $source" >&2
                return 1
            fi
            
            cp "$source" "$destination" 2>/dev/null || {
                echo "Error: Failed to restore from $source to $destination" >&2
                return 1
            }
            ;;
        
        *)
            echo "Error: Unknown operation: $operation" >&2
            echo "Supported operations: copy, move, backup, restore" >&2
            return 1
            ;;
    esac
    
    return 0
}

# Find files matching pattern with safety checks
# Usage: find_files_safe "/base/path" "*.txt" [max_depth]
# Output: List of matching files, one per line
find_files_safe() {
    local base_path="$1"
    local pattern="$2"
    local max_depth="${3:-3}"
    
    if [[ -z "$base_path" || -z "$pattern" ]]; then
        echo "Error: find_files_safe requires base path and pattern" >&2
        return 1
    fi
    
    if [[ ! -d "$base_path" ]]; then
        echo "Error: Base path is not a directory: $base_path" >&2
        return 1
    fi
    
    # Validate max_depth is a number
    if [[ ! "$max_depth" =~ ^[0-9]+$ ]]; then
        echo "Error: max_depth must be a number: $max_depth" >&2
        return 1
    fi
    
    # Use find with safety limits
    find "$base_path" -maxdepth "$max_depth" -name "$pattern" -type f 2>/dev/null | head -1000
}

# Check disk space availability
# Usage: check_disk_space "/path" required_mb
# Returns: 0 if enough space available, 1 if not
check_disk_space() {
    local path="$1"
    local required_mb="$2"
    
    if [[ -z "$path" || -z "$required_mb" ]]; then
        echo "Error: check_disk_space requires path and required MB" >&2
        return 1
    fi
    
    if [[ ! "$required_mb" =~ ^[0-9]+$ ]]; then
        echo "Error: Required MB must be a number: $required_mb" >&2
        return 1
    fi
    
    if [[ ! -e "$path" ]]; then
        echo "Error: Path does not exist: $path" >&2
        return 1
    fi
    
    # Get available space in MB
    local available_mb
    if command -v df >/dev/null 2>&1; then
        # Try different df formats
        available_mb=$(df -m "$path" 2>/dev/null | awk 'NR==2 {print $4}')
        if [[ -z "$available_mb" ]]; then
            available_mb=$(df -BM "$path" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/M//')
        fi
    fi
    
    if [[ -z "$available_mb" ]] || [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
        echo "Error: Could not determine available disk space" >&2
        return 1
    fi
    
    if [[ $available_mb -lt $required_mb ]]; then
        echo "Error: Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB" >&2
        return 1
    fi
    
    return 0
}

# Validate and normalize path
# Usage: normalize_path "/path/with/../dots"
# Output: Normalized absolute path
normalize_path() {
    local path="$1"
    
    [[ -z "$path" ]] && return 1
    
    # Expand tilde
    path="${path/#\~/$HOME}"
    
    # Use readlink if path exists, otherwise do basic normalization
    if [[ -e "$path" ]]; then
        readlink -f "$path" 2>/dev/null || echo "$path"
    else
        # Basic path normalization for non-existent paths
        echo "$path" | sed -e 's|/\./|/|g' -e 's|/\+|/|g' -e 's|/$||' -e 's|/[^/]*/\.\./|/|g'
    fi
}

# Create temporary file or directory safely
# Usage: create_temp "file" or create_temp "dir" [prefix]
# Output: Path to created temporary file/directory
create_temp() {
    local type="$1"
    local prefix="${2:-tmp}"
    
    case "$type" in
        file)
            mktemp -t "${prefix}.XXXXXX" 2>/dev/null || {
                echo "Error: Could not create temporary file" >&2
                return 1
            }
            ;;
        dir|directory)
            mktemp -d -t "${prefix}.XXXXXX" 2>/dev/null || {
                echo "Error: Could not create temporary directory" >&2
                return 1
            }
            ;;
        *)
            echo "Error: Invalid type. Use 'file' or 'dir'" >&2
            return 1
            ;;
    esac
}

# Cleanup temporary files/directories
# Usage: cleanup_temp "/tmp/file1" "/tmp/dir1" ...
cleanup_temp() {
    local path
    for path in "$@"; do
        if [[ -n "$path" && "$path" == /tmp/* ]]; then
            if [[ -f "$path" ]]; then
                rm -f "$path" 2>/dev/null
            elif [[ -d "$path" ]]; then
                rm -rf "$path" 2>/dev/null
            fi
        fi
    done
}

# Check if path is safe to operate on (not system directories)
# Usage: is_safe_path "/home/user/file.txt"
# Returns: 0 if safe, 1 if unsafe
is_safe_path() {
    local path="$1"
    
    [[ -z "$path" ]] && return 1
    
    # Normalize the path
    path=$(normalize_path "$path")
    
    # List of unsafe paths
    local unsafe_paths=(
        "/"
        "/bin"
        "/boot"
        "/dev"
        "/etc"
        "/lib"
        "/lib64"
        "/proc"
        "/root"
        "/run"
        "/sbin"
        "/sys"
        "/usr/bin"
        "/usr/sbin"
        "/usr/lib"
        "/var/lib"
        "/var/run"
    )
    
    local unsafe_path
    for unsafe_path in "${unsafe_paths[@]}"; do
        if [[ "$path" == "$unsafe_path" ]] || [[ "$path" == "$unsafe_path"/* ]]; then
            return 1
        fi
    done
    
    return 0
}

# Get human-readable file size
# Usage: get_file_size "/path/to/file"
# Output: File size in human-readable format (e.g., "1.2MB")
get_file_size() {
    local file_path="$1"
    
    [[ -z "$file_path" ]] && return 1
    [[ ! -e "$file_path" ]] && return 1
    
    # Try different methods to get file size
    if command -v stat >/dev/null 2>&1; then
        local size_bytes
        size_bytes=$(stat -c %s "$file_path" 2>/dev/null || stat -f %z "$file_path" 2>/dev/null)
        
        if [[ -n "$size_bytes" ]]; then
            # Convert to human-readable format
            if [[ $size_bytes -lt 1024 ]]; then
                echo "${size_bytes}B"
            elif [[ $size_bytes -lt 1048576 ]]; then
                echo "$((size_bytes / 1024))KB"
            elif [[ $size_bytes -lt 1073741824 ]]; then
                echo "$((size_bytes / 1048576))MB"
            else
                echo "$((size_bytes / 1073741824))GB"
            fi
        fi
    elif command -v du >/dev/null 2>&1; then
        du -h "$file_path" 2>/dev/null | cut -f1
    fi
}