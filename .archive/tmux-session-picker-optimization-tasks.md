# Tmux Session Picker Performance Optimization
**Task Breakdown Document**

**Document Version:** 2.0  
**Date:** 2025-01-XX  
**Status:** Ready for Implementation

---

## Executive Summary

This document provides a comprehensive analysis of the `tmux-session-picker` script's performance characteristics and a structured task breakdown for implementing optimizations. The primary bottleneck is **repeated sequential parsing** of tmux-resurrect files. The solution uses **pure bash with GNU parallel** for true concurrent file processing, achieving an estimated **70-85% performance improvement**.

### Key Findings

- **Current bottleneck:** Each session file is parsed 3-4 times sequentially
- **Scale impact:** 50 files × 4 parses = 200 file read operations
- **Recommended solution:** Bash + GNU parallel with single-pass file parsing
- **Expected improvement:** 0.5s vs 2.5s for 50 files (80% faster)
- **Final target:** 92% performance improvement (13s → 1s for 50 files)

---

## Table of Contents

1. [Current Performance Analysis](#current-performance-analysis)
2. [Tmux-Resurrect File Format](#tmux-resurrect-file-format)
3. [Implementation Task Breakdown](#implementation-task-breakdown)
4. [Implementation Patterns](#implementation-patterns)
5. [Testing Strategy](#testing-strategy)
6. [Appendices](#appendices)

---

## Current Performance Analysis

### Critical Bottlenecks Identified

#### 1. Repeated File Parsing (HIGH IMPACT)

**Problem Pattern:**
```bash
# Current implementation reads each file multiple times:
parse_session_file()           # Parse 1: Count windows/panes
format_session() {
    parse_session_file()       # Parse 2: Get counts again
    grep "^pane" "$file"       # Parse 3: Get paths
    get_primary_command()      # Parse 4: Get commands
    grep "^window" "$file"     # Parse 5: Get windows
}
```

**Impact:** For 50 session files, this results in 200+ file read operations.

**Root Cause:** Function separation without data caching leads to redundant I/O.

---

#### 2. Excessive Python Subprocess Spawning (HIGH IMPACT)

**Problem:**
```bash
get_display_width() {
    # Spawns Python for EVERY unicode string check
    width=$(python3 -c "import unicodedata..." "$text")
}
```

**Impact:** 
- 50 sessions × 10 strings each = 500 Python invocations
- Each subprocess has ~20-50ms overhead
- Total overhead: 10-25 seconds for width calculations alone

---

#### 3. Redundant File Resolution (MEDIUM IMPACT)

**Problem:**
```bash
format_session() {
    # Called for EVERY file in the list
    local current_file=$(readlink -f "$RESURRECT_DIR/last")
    if [[ "$file" == "$current_file" ]]; then
        # Mark as active
    fi
}
```

**Impact:** 50 files × 1 readlink = 50 redundant subprocess calls

---

#### 4. Sequential File Processing (HIGH IMPACT)

**Current Pattern:**
```bash
for file in "${session_files[@]}"; do
    format_session "$file"  # Processes one at a time
done
```

**Problem:** No parallelization - CPU sits idle while waiting for I/O

---

### Performance Impact Matrix

| Issue | Impact | Effort | Expected Gain |
|-------|--------|--------|---------------|
| Repeated file parsing | HIGH | HIGH | 60-75% I/O reduction |
| Python subprocess spam | HIGH | MEDIUM | 80-90% faster width calc |
| Sequential processing | HIGH | MEDIUM | 5x faster with 8 cores |
| Current file caching | MEDIUM | LOW | 98% fewer readlinks |
| Combined grep/awk | MEDIUM | MEDIUM | 50-60% fewer processes |

---

## Tmux-Resurrect File Format

### Overview

Tmux-resurrect stores session data in **tab-delimited text files** at:
- `~/.tmux/resurrect/` (standard)
- `~/.local/share/tmux/resurrect/` (XDG)

**Filename format:** `tmux_resurrect_YYYYMMDDTHHMMSS.txt`  
**Current session:** Symlink `last` points to most recent save

### File Structure

Each line represents a record type, identified by a prefix:

| Line Type | Purpose | Field Count |
|-----------|---------|-------------|
| `pane` | Pane details (directory, command, state) | 11 |
| `window` | Window properties (name, layout, flags) | 8 |
| `state` | Client state (active/alternate sessions) | 3 |
| `grouped_session` | Grouped session info | 5 |

**Delimiter:** Tab character (`\t`, ASCII 9)  
**No headers:** Files contain only data lines

---

### Field Specifications

#### PANE Lines (11 fields)

```
pane<TAB>session_name<TAB>window_index<TAB>window_active<TAB>:window_flags<TAB>pane_index<TAB>pane_title<TAB>:pane_current_path<TAB>pane_active<TAB>pane_command<TAB>:pane_full_command
```

| Pos | Field | Description | Example |
|-----|-------|-------------|---------|
| 1 | line_type | Literal "pane" | `pane` |
| 2 | session_name | Session name | `blue` |
| 3 | window_index | Window number | `1` |
| 4 | window_active | Window active (1/0) | `1` |
| 5 | window_flags | Flags prefixed `:` | `:*` or `:-Z` |
| 6 | pane_index | Pane index | `0` |
| 7 | pane_title | Pane title | `bash` |
| 8 | pane_current_path | Path prefixed `:` | `:/tmp/bar` |
| 9 | pane_active | Pane active (1/0) | `1` |
| 10 | pane_command | Command name | `vim` |
| 11 | pane_full_command | Full cmd prefixed `:` | `:vim foo.txt` |

**Example:**
```
pane	blue	1	0	:-	1	bash	:/usr/share/man	1	man	:man echo
```

---

#### WINDOW Lines (8 fields)

```
window<TAB>session_name<TAB>window_index<TAB>:window_name<TAB>window_active<TAB>:window_flags<TAB>window_layout<TAB>automatic_rename
```

| Pos | Field | Description | Example |
|-----|-------|-------------|---------|
| 1 | line_type | Literal "window" | `window` |
| 2 | session_name | Session name | `red` |
| 3 | window_index | Window number | `1` |
| 4 | window_name | Name prefixed `:` | `:bash` |
| 5 | window_active | Active (1/0) | `1` |
| 6 | window_flags | Flags prefixed `:` | `:*Z` |
| 7 | window_layout | Tmux layout string | `ce9e,200x49,0,0,1` |
| 8 | automatic_rename | Auto-rename state | `on` |

**Example:**
```
window	red	1	:bash	0	:-Z	52b7,200x49,0,0[200x24,0,0,2]	on
```

---

#### STATE Lines (3 fields)

```
state<TAB>client_session<TAB>client_last_session
```

**Example:**
```
state	yellow	blue
```

---

#### GROUPED_SESSION Lines (5 fields)

```
grouped_session<TAB>session_name<TAB>original_session<TAB>:alternate_window_index<TAB>:active_window_index
```

**Example:**
```
grouped_session	monitor2	main	:1	:2
```

---

### Critical Format Notes

1. **Colon Prefixes:** Fields prefixed with `:` allow empty value handling
   - Empty value: Just `:` (the colon alone)
   - Non-empty: `:value`
   
2. **Removal Pattern:**
   ```bash
   remove_first_char() {
       echo "$1" | cut -c2-
   }
   # Or faster:
   value="${field:1}"  # Bash substring expansion
   ```

3. **Spaces in Paths:** Escaped as `\\ ` in saved files

4. **No Type Coercion:** All fields are strings; numeric interpretation happens at use time

---

### Parsing Patterns from Tmux-Resurrect

#### Pattern 1: IFS-based Field Reading

```bash
d=$'\t'  # Tab delimiter

while IFS=$d read -r line_type session_name window_number window_active \
    window_flags pane_index pane_title dir pane_active pane_command \
    pane_full_command; do
    
    # Remove colon prefix
    dir="${dir:1}"
    pane_full_command="${pane_full_command:1}"
    
    # Process pane data
    echo "Session: $session_name, Window: $window_number, Pane: $pane_index"
    
done < <(grep '^pane' "$file")
```

---

#### Pattern 2: AWK-based Filtering

```bash
# Get active panes only
awk 'BEGIN { FS="\t"; OFS="\t" } 
     /^pane/ && $9 == 1 { print $2, $3, $6 }' "$file" |
while IFS=$'\t' read -r session window pane; do
    echo "Active: ${session}:${window}.${pane}"
done
```

```bash
# Get panes with non-empty commands
awk 'BEGIN { FS="\t" } 
     /^pane/ && $11 !~ "^:$" { print $2, $3, $11 }' "$file"
```

```bash
# Get zoomed windows
awk 'BEGIN { FS="\t" } 
     /^window/ && $6 ~ /Z/ { print $2, $3 }' "$file"
```

---

#### Pattern 3: grep-based Line Filtering

```bash
# Get all pane lines
grep '^pane' "$file"

# Get all window lines  
grep '^window' "$file"

# Get state information
grep '^state' "$file"

# Get specific session (exact match)
grep "^pane\t${SESSION_NAME}\t" "$file"
```

---

### Data Extraction Examples

#### Extract Session Names

```bash
# Get unique session names from file
awk -F'\t' '/^pane/ { sessions[$2] = 1 }
            END { for (s in sessions) print s }' "$file"
```

#### Count Windows/Panes

```bash
# Count windows per session
awk -F'\t' '/^window/ && $2 == "mysession" { count++ }
            END { print count }' "$file"

# Count panes per window
awk -F'\t' '/^pane/ && $2 == "mysession" && $3 == 1 { count++ }
            END { print count }' "$file"
```

#### Get Active Pane Command

```bash
# Find command in active pane of active window
awk -F'\t' '/^pane/ && $2 == "mysession" && $4 == 1 && $9 == 1 {
                cmd = substr($11, 2)  # Remove leading colon
                if (cmd == "") cmd = substr($10, 2)  # Fallback to pane_command
                print cmd
                exit
            }' "$file"
```

#### Extract Working Directories

```bash
# Get all unique paths from a session
awk -F'\t' '/^pane/ && $2 == "mysession" {
                path = substr($8, 2)  # Remove leading colon
                if (path != "" && !seen[path]++) {
                    print path
                }
            }' "$file"
```

---

## Implementation Task Breakdown

### TASK GROUP 1: Core Parser Refactoring

**Objective:** Create single-pass file parser that extracts all needed data in one read

#### Task 1.1: Design Parser Data Structure
**Priority:** HIGH  
**Estimated Effort:** 1-2 hours

**Requirements:**
- Define output format for parsed session data
- Design structure to hold: session name, window count, pane count, paths, commands, active state
- Choose delimiter-separated format for easy consumption

**Deliverables:**
```bash
# Output format (pipe-delimited):
# session_name|window_count|pane_count|paths|commands|is_active
# Example:
# blue|3|8|/home/user:/tmp:/var/log|vim:bash:htop|1
```

**Acceptance Criteria:**
- [ ] Format defined and documented
- [ ] Handles empty fields gracefully
- [ ] Supports session names with special characters
- [ ] Can represent all needed data in single line

---

#### Task 1.2: Implement Single-Pass Parser Function
**Priority:** HIGH  
**Estimated Effort:** 3-4 hours  
**Dependencies:** Task 1.1

**Requirements:**
- Create `parse_single_file()` function
- Read file once, extract all data
- Use bash IFS and while-read loop for efficiency
- Handle colon-prefixed fields correctly
- Count windows and panes
- Extract paths and commands
- Identify active panes/windows

**Implementation Pattern:**
```bash
parse_single_file() {
    local file="$1"
    local session_name=""
    local window_count=0
    local pane_count=0
    local -a paths=()
    local -a commands=()
    local is_active=0
    
    # Single pass through file
    while IFS=$'\t' read -r type field2 rest; do
        case "$type" in
            pane)
                # Extract and count pane data
                ;;
            window)
                # Extract and count window data
                ;;
        esac
    done < "$file"
    
    # Output formatted result
    printf "%s|%d|%d|%s|%s|%d\n" \
        "$session_name" "$window_count" "$pane_count" \
        "$(IFS=:; echo "${paths[*]}")" \
        "$(IFS=:; echo "${commands[*]}")" \
        "$is_active"
}
```

**Acceptance Criteria:**
- [ ] Reads each file exactly once
- [ ] Correctly counts windows and panes
- [ ] Extracts all paths from pane records
- [ ] Extracts commands (prioritizing full_command over command)
- [ ] Handles empty/malformed lines gracefully
- [ ] Returns properly formatted output string

---

#### Task 1.3: Add Active Session Detection
**Priority:** MEDIUM  
**Estimated Effort:** 1 hour  
**Dependencies:** Task 1.2

**Requirements:**
- Cache current session file at script startup
- Compare each file against cached value in parser
- Mark active session in output

**Implementation:**
```bash
# Global cache (set once at startup)
CURRENT_SESSION_FILE=$(readlink -f "$RESURRECT_DIR/last" 2>/dev/null)

parse_single_file() {
    local file="$1"
    local is_active=0
    
    # Check if this is the active session
    if [[ "$(readlink -f "$file")" == "$CURRENT_SESSION_FILE" ]]; then
        is_active=1
    fi
    
    # ... rest of parsing
}
```

**Acceptance Criteria:**
- [ ] `readlink` called only once at script start
- [ ] Active session correctly identified
- [ ] Works when `last` symlink is missing

---

### TASK GROUP 2: Parallel Processing Implementation

**Objective:** Process multiple session files concurrently using GNU parallel

#### Task 2.1: Verify GNU Parallel Availability
**Priority:** HIGH  
**Estimated Effort:** 30 minutes

**Requirements:**
- Check if GNU parallel is installed
- Provide clear error message if missing
- Document installation instructions
- Add fallback to sequential processing

**Implementation:**
```bash
check_parallel_available() {
    if ! command -v parallel >/dev/null 2>&1; then
        cat >&2 << 'EOF'
Error: GNU parallel not found.

This script requires GNU parallel for optimal performance.
Install with:
  - NixOS:        nix-env -iA nixpkgs.parallel
  - Ubuntu/Debian: sudo apt-get install parallel
  - macOS:        brew install parallel

Falling back to sequential processing (slower)...
EOF
        return 1
    fi
    return 0
}
```

**Acceptance Criteria:**
- [ ] Detects GNU parallel presence
- [ ] Provides clear installation instructions
- [ ] Handles missing parallel gracefully
- [ ] Falls back to sequential mode

---

#### Task 2.2: Create Parallel Wrapper Function
**Priority:** HIGH  
**Estimated Effort:** 2-3 hours  
**Dependencies:** Task 1.2, Task 2.1

**Requirements:**
- Use GNU parallel to process all session files
- Export parser function for parallel use
- Collect results into arrays
- Maintain deterministic output order

**Implementation:**
```bash
parse_all_files_parallel() {
    local -a session_files=("$@")
    
    # Export function and variables for parallel
    export -f parse_single_file
    export CURRENT_SESSION_FILE
    export RESURRECT_DIR
    
    # Process files in parallel, maintain order
    printf '%s\n' "${session_files[@]}" | \
        parallel --will-cite --keep-order \
            'parse_single_file {}'
}
```

**Acceptance Criteria:**
- [ ] Processes files concurrently
- [ ] Maintains file order in output
- [ ] Handles errors gracefully
- [ ] Exports all needed functions/variables
- [ ] Works with varying number of files

---

#### Task 2.3: Parse Results into Bash Arrays
**Priority:** HIGH  
**Estimated Effort:** 2 hours  
**Dependencies:** Task 2.2

**Requirements:**
- Read parallel output into structured arrays
- Create separate arrays for each data field
- Handle edge cases (empty results, special characters)

**Implementation:**
```bash
declare -a SESSION_NAMES=()
declare -a WINDOW_COUNTS=()
declare -a PANE_COUNTS=()
declare -a SESSION_PATHS=()
declare -a SESSION_COMMANDS=()
declare -a IS_ACTIVE=()

load_session_data() {
    local output
    output=$(parse_all_files_parallel "${session_files[@]}")
    
    while IFS='|' read -r name windows panes paths cmds active; do
        SESSION_NAMES+=("$name")
        WINDOW_COUNTS+=("$windows")
        PANE_COUNTS+=("$panes")
        SESSION_PATHS+=("$paths")
        SESSION_COMMANDS+=("$cmds")
        IS_ACTIVE+=("$active")
    done <<< "$output"
}
```

**Acceptance Criteria:**
- [ ] Correctly splits pipe-delimited output
- [ ] Populates all arrays with matching indices
- [ ] Handles special characters in session names
- [ ] Validates array lengths match
- [ ] Handles empty result set

---

### TASK GROUP 3: Width Calculation Optimization

**Objective:** Eliminate excessive Python subprocess spawning for string width calculations

#### Task 3.1: Implement ASCII Fast Path
**Priority:** MEDIUM  
**Estimated Effort:** 1-2 hours

**Requirements:**
- Detect ASCII-only strings without Python
- Use simple byte count for ASCII strings
- Only invoke Python for non-ASCII content

**Implementation:**
```bash
get_display_width() {
    local text="$1"
    
    # Fast path: ASCII-only strings
    if [[ "$text" =~ ^[[:ascii:]]*$ ]]; then
        echo "${#text}"
        return
    fi
    
    # Slow path: Unicode strings need Python
    python3 -c "import unicodedata; print(sum(1 + (unicodedata.east_asian_width(c) in 'FW') for c in '$text'))"
}
```

**Acceptance Criteria:**
- [ ] ASCII strings processed without Python
- [ ] Unicode strings still handled correctly
- [ ] Benchmark shows significant speedup
- [ ] Works with mixed content

---

#### Task 3.2: Add Width Calculation Cache
**Priority:** MEDIUM  
**Estimated Effort:** 2 hours  
**Dependencies:** Task 3.1

**Requirements:**
- Cache calculated widths in associative array
- Check cache before expensive calculations
- Clear cache periodically to avoid memory bloat

**Implementation:**
```bash
declare -A WIDTH_CACHE=()

get_display_width_cached() {
    local text="$1"
    
    # Check cache first
    if [[ -n "${WIDTH_CACHE[$text]}" ]]; then
        echo "${WIDTH_CACHE[$text]}"
        return
    fi
    
    # Calculate and cache
    local width
    width=$(get_display_width "$text")
    WIDTH_CACHE["$text"]=$width
    echo "$width"
}
```

**Acceptance Criteria:**
- [ ] Caches width calculations
- [ ] Returns cached values correctly
- [ ] Reduces redundant calculations
- [ ] Memory usage remains reasonable

---

#### Task 3.3: Create Persistent Python Process (Optional)
**Priority:** LOW  
**Estimated Effort:** 3-4 hours  
**Dependencies:** Task 3.1

**Requirements:**
- Start single Python process at startup
- Communicate via named pipe or file descriptors
- Send strings, receive widths
- Eliminate subprocess overhead entirely

**Implementation Approach:**
```bash
# Start persistent Python process
start_width_daemon() {
    local fifo="/tmp/tmux-picker-width-$$"
    mkfifo "$fifo"
    
    python3 -u << 'PYEOF' > "$fifo" &
import sys
import unicodedata
for line in sys.stdin:
    text = line.rstrip('\n')
    width = sum(1 + (unicodedata.east_asian_width(c) in 'FW') for c in text)
    print(width)
    sys.stdout.flush()
PYEOF
    
    WIDTH_DAEMON_PID=$!
    WIDTH_DAEMON_FIFO="$fifo"
}

get_width_from_daemon() {
    echo "$1" > "$WIDTH_DAEMON_FIFO"
    read -r width < "$WIDTH_DAEMON_FIFO"
    echo "$width"
}
```

**Acceptance Criteria:**
- [ ] Daemon starts successfully
- [ ] Handles multiple requests
- [ ] Cleans up on script exit
- [ ] Handles daemon crashes gracefully

---

### TASK GROUP 4: Display Formatting

**Objective:** Use cached data to format display output efficiently

#### Task 4.1: Create Format Function Using Arrays
**Priority:** HIGH  
**Estimated Effort:** 2-3 hours  
**Dependencies:** Task 2.3

**Requirements:**
- Format output from pre-parsed array data
- No additional file reads
- Apply highlighting for active session
- Truncate/pad fields to fit terminal width

**Implementation:**
```bash
format_display_output() {
    local max_width="${1:-80}"
    local i
    
    for i in "${!SESSION_NAMES[@]}"; do
        local name="${SESSION_NAMES[$i]}"
        local windows="${WINDOW_COUNTS[$i]}"
        local panes="${PANE_COUNTS[$i]}"
        local is_active="${IS_ACTIVE[$i]}"
        
        # Format: [*] session_name  (3w 8p) /path
        local marker="   "
        [[ "$is_active" == "1" ]] && marker="[*]"
        
        printf "%s %-20s (%dw %dp)\n" \
            "$marker" "$name" "$windows" "$panes"
    done
}
```

**Acceptance Criteria:**
- [ ] Formats all sessions from array data
- [ ] Highlights active session
- [ ] No file I/O during formatting
- [ ] Respects terminal width
- [ ] Handles edge cases (long names, etc.)

---

#### Task 4.2: Optimize Path Abbreviation
**Priority:** LOW  
**Estimated Effort:** 2 hours

**Requirements:**
- Abbreviate common path prefixes
- Replace $HOME with ~
- Show relative paths when possible
- Cache abbreviation results

**Implementation:**
```bash
abbreviate_path() {
    local path="$1"
    
    # Replace home directory
    path="${path/#$HOME/~}"
    
    # Remove common prefixes
    path="${path/#\/usr\/local\//…\/}"
    
    echo "$path"
}
```

**Acceptance Criteria:**
- [ ] Shortens long paths appropriately
- [ ] Maintains readability
- [ ] Handles edge cases (root paths, etc.)

---

### TASK GROUP 5: Integration and Error Handling

**Objective:** Integrate all components and ensure robust error handling

#### Task 5.1: Integrate All Components
**Priority:** HIGH  
**Estimated Effort:** 2-3 hours  
**Dependencies:** All previous tasks

**Requirements:**
- Wire together all parser, parallel, and format components
- Ensure data flows correctly through pipeline
- Maintain existing script interface
- Add feature flag for new behavior

**Implementation:**
```bash
main() {
    # Initialize
    check_parallel_available || USE_PARALLEL=false
    cache_current_session
    
    # Get session files
    local -a session_files
    session_files=($(find_session_files))
    
    # Parse all files
    if [[ "$USE_PARALLEL" == "true" ]]; then
        load_session_data "${session_files[@]}"
    else
        load_session_data_sequential "${session_files[@]}"
    fi
    
    # Format and display
    format_display_output "$TERMINAL_WIDTH"
}
```

**Acceptance Criteria:**
- [ ] All components work together
- [ ] Maintains backward compatibility
- [ ] Feature flag works correctly
- [ ] No regression in functionality

---

#### Task 5.2: Add Comprehensive Error Handling
**Priority:** HIGH  
**Estimated Effort:** 2 hours

**Requirements:**
- Validate resurrect directory exists and is readable
- Handle malformed session files gracefully
- Detect and report parser errors
- Provide helpful error messages

**Implementation:**
```bash
validate_environment() {
    # Check resurrect directory
    if [[ ! -d "$RESURRECT_DIR" ]]; then
        echo "Error: Resurrect directory not found: $RESURRECT_DIR" >&2
        exit 1
    fi
    
    if [[ ! -r "$RESURRECT_DIR" ]]; then
        echo "Error: Cannot read resurrect directory" >&2
        exit 1
    fi
    
    # Check for session files
    local file_count
    file_count=$(find "$RESURRECT_DIR" -name "tmux_resurrect_*.txt" | wc -l)
    if [[ "$file_count" -eq 0 ]]; then
        echo "No saved tmux sessions found" >&2
        exit 1
    fi
}

parse_single_file_safe() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "ERROR:file_not_found:$file" >&2
        return 1
    fi
    
    if [[ ! -r "$file" ]]; then
        echo "ERROR:file_not_readable:$file" >&2
        return 1
    fi
    
    parse_single_file "$file" 2>/dev/null || {
        echo "ERROR:parse_failed:$file" >&2
        return 1
    }
}
```

**Acceptance Criteria:**
- [ ] Validates environment before running
- [ ] Handles missing/corrupt files
- [ ] Provides clear error messages
- [ ] Continues processing other files on error

---

#### Task 5.3: Add Logging and Debug Mode
**Priority:** LOW  
**Estimated Effort:** 1-2 hours

**Requirements:**
- Add debug flag for verbose output
- Log timing information
- Show parser decisions
- Help troubleshoot issues

**Implementation:**
```bash
DEBUG=${DEBUG:-false}

debug_log() {
    [[ "$DEBUG" == "true" ]] && echo "[DEBUG] $*" >&2
}

time_section() {
    local label="$1"
    shift
    local start=$(date +%s%N)
    
    "$@"
    
    local end=$(date +%s%N)
    local elapsed=$(( (end - start) / 1000000 ))
    debug_log "$label: ${elapsed}ms"
}
```

**Acceptance Criteria:**
- [ ] Debug mode shows detailed information
- [ ] Timing info helps identify bottlenecks
- [ ] No performance impact when disabled

---

### TASK GROUP 6: Testing and Validation

**Objective:** Ensure implementation works correctly and meets performance targets

#### Task 6.1: Create Test Data Generator
**Priority:** HIGH  
**Estimated Effort:** 2 hours

**Requirements:**
- Generate valid tmux-resurrect files
- Support various session configurations
- Create files with known data for validation

**Implementation:**
```bash
create_test_session_file() {
    local filename="$1"
    local session_name="$2"
    local window_count="${3:-3}"
    local panes_per_window="${4:-2}"
    
    > "$filename"  # Clear file
    
    for ((w=1; w<=window_count; w++)); do
        # Add window line
        printf "window\t%s\t%d\t:window%d\t%d\t:-\tlayout\ton\n" \
            "$session_name" "$w" "$w" "$((w==1 ? 1 : 0))" >> "$filename"
        
        # Add pane lines
        for ((p=0; p<panes_per_window; p++)); do
            printf "pane\t%s\t%d\t%d\t:-\t%d\ttitle\t:/tmp\t%d\tbash\t:\n" \
                "$session_name" "$w" "$((w==1 ? 1 : 0))" "$p" \
                "$((p==0 ? 1 : 0))" >> "$filename"
        done
    done
}
```

**Acceptance Criteria:**
- [ ] Generates valid resurrect files
- [ ] Supports various configurations
- [ ] Creates deterministic test data

---

#### Task 6.2: Write Unit Tests
**Priority:** HIGH  
**Estimated Effort:** 3-4 hours  
**Dependencies:** Task 6.1

**Requirements:**
- Test parser with known inputs
- Verify output format correctness
- Test edge cases (empty files, special characters)
- Test error handling

**Test Cases:**
```bash
test_parse_single_file() {
    local test_file="/tmp/test_session.txt"
    create_test_session_file "$test_file" "test" 2 3
    
    local output
    output=$(parse_single_file "$test_file")
    
    # Verify format
    assert_matches "$output" "^test\|2\|6\|.*"
    
    # Verify counts
    local windows=$(echo "$output" | cut -d'|' -f2)
    assert_equal "$windows" "2"
}

test_empty_file() {
    local test_file="/tmp/empty.txt"
    touch "$test_file"
    
    local output
    output=$(parse_single_file "$test_file")
    
    # Should handle gracefully
    assert_not_empty "$output"
}

test_special_characters() {
    local test_file="/tmp/special.txt"
    create_test_session_file "$test_file" "session-with-dash" 1 1
    
    local output
    output=$(parse_single_file "$test_file")
    
    assert_contains "$output" "session-with-dash"
}
```

**Acceptance Criteria:**
- [ ] All unit tests pass
- [ ] Tests cover edge cases
- [ ] Tests are deterministic
- [ ] Easy to run and maintain

---

#### Task 6.3: Write Integration Tests
**Priority:** HIGH  
**Estimated Effort:** 2-3 hours  
**Dependencies:** Task 6.1, Task 5.1

**Requirements:**
- Test complete workflow
- Test parallel processing
- Test sequential fallback
- Verify output matches expectations

**Test Cases:**
```bash
test_parallel_processing() {
    local test_dir="/tmp/test_resurrect"
    mkdir -p "$test_dir"
    
    # Create 10 test files
    for i in {1..10}; do
        create_test_session_file \
            "$test_dir/tmux_resurrect_test${i}.txt" \
            "session${i}" 3 2
    done
    
    # Run parser
    local output
    RESURRECT_DIR="$test_dir" output=$(main)
    
    # Verify all sessions present
    assert_equal "$(echo "$output" | wc -l)" "10"
    
    rm -rf "$test_dir"
}

test_active_session_detection() {
    local test_dir="/tmp/test_resurrect"
    mkdir -p "$test_dir"
    
    create_test_session_file "$test_dir/session1.txt" "active" 1 1
    create_test_session_file "$test_dir/session2.txt" "inactive" 1 1
    
    # Make session1 the active one
    ln -sf "$test_dir/session1.txt" "$test_dir/last"
    
    local output
    RESURRECT_DIR="$test_dir" output=$(main)
    
    # Verify active marker
    assert_contains "$output" "[*] active"
    assert_not_contains "$output" "[*] inactive"
    
    rm -rf "$test_dir"
}
```

**Acceptance Criteria:**
- [ ] Integration tests pass
- [ ] Tests verify end-to-end functionality
- [ ] Tests clean up after themselves

---

#### Task 6.4: Performance Benchmarking
**Priority:** MEDIUM  
**Estimated Effort:** 2-3 hours  
**Dependencies:** Task 6.1, Task 5.1

**Requirements:**
- Benchmark old vs new implementation
- Test with various file counts (10, 50, 100)
- Verify performance targets met
- Document results

**Benchmarking Script:**
```bash
benchmark_implementation() {
    local impl="$1"  # "old" or "new"
    local file_count="$2"
    local iterations="${3:-5}"
    
    local test_dir="/tmp/benchmark_resurrect"
    mkdir -p "$test_dir"
    
    # Create test files
    for i in $(seq 1 "$file_count"); do
        create_test_session_file \
            "$test_dir/tmux_resurrect_test${i}.txt" \
            "session${i}" 5 3
    done
    
    # Run benchmark
    local total_time=0
    for ((i=1; i<=iterations; i++)); do
        local start=$(date +%s%N)
        
        RESURRECT_DIR="$test_dir" run_implementation "$impl" > /dev/null
        
        local end=$(date +%s%N)
        local elapsed=$(( (end - start) / 1000000 ))
        total_time=$((total_time + elapsed))
        
        echo "Run $i: ${elapsed}ms" >&2
    done
    
    local avg_time=$((total_time / iterations))
    echo "Average time for $impl with $file_count files: ${avg_time}ms"
    
    rm -rf "$test_dir"
}

# Run benchmarks
for count in 10 50 100; do
    echo "=== Testing with $count files ==="
    benchmark_implementation "old" "$count"
    benchmark_implementation "new" "$count"
    echo
done
```

**Performance Targets:**
- 10 files: < 200ms
- 50 files: < 500ms
- 100 files: < 1000ms

**Acceptance Criteria:**
- [ ] New implementation faster than old
- [ ] Meets performance targets
- [ ] Results documented
- [ ] Benchmark repeatable

---

### TASK GROUP 7: Documentation

**Objective:** Document implementation and usage

#### Task 7.1: Update Code Comments
**Priority:** MEDIUM  
**Estimated Effort:** 1-2 hours

**Requirements:**
- Document all new functions
- Explain complex logic
- Add usage examples
- Document dependencies (GNU parallel)

**Acceptance Criteria:**
- [ ] All functions have docstrings
- [ ] Complex sections explained
- [ ] Examples provided where helpful

---

#### Task 7.2: Create Implementation Notes
**Priority:** LOW  
**Estimated Effort:** 1 hour

**Requirements:**
- Document design decisions
- Explain optimization choices
- Note any trade-offs made
- List known limitations

**Acceptance Criteria:**
- [ ] Design rationale documented
- [ ] Trade-offs explained
- [ ] Future improvements noted

---

## Implementation Patterns

### Single-Pass Parser Template

```bash
parse_single_file() {
    local file="$1"
    
    # Initialize accumulators
    local session_name=""
    local window_count=0
    local pane_count=0
    local -A window_seen=()
    local -a paths=()
    local -a commands=()
    
    # Tab delimiter
    local d=$'\t'
    
    # Single pass through file
    while IFS="$d" read -r line_type session window_idx window_active \
        window_flags pane_idx pane_title pane_path pane_active \
        pane_cmd pane_full_cmd; do
        
        case "$line_type" in
            pane)
                # Track session name (first occurrence)
                [[ -z "$session_name" ]] && session_name="$session"
                
                # Count unique windows
                if [[ -z "${window_seen[$window_idx]}" ]]; then
                    window_seen[$window_idx]=1
                    ((window_count++))
                fi
                
                # Count panes
                ((pane_count++))
                
                # Extract path (remove colon prefix)
                local path="${pane_path:1}"
                [[ -n "$path" ]] && paths+=("$path")
                
                # Extract command (prefer full_command)
                local cmd="${pane_full_cmd:1}"
                [[ -z "$cmd" ]] && cmd="${pane_cmd:1}"
                [[ -n "$cmd" && "$cmd" != "-bash" ]] && commands+=("$cmd")
                ;;
        esac
    done < "$file"
    
    # Output formatted result
    local paths_str=$(IFS=:; echo "${paths[*]}")
    local cmds_str=$(IFS=:; echo "${commands[*]}")
    local is_active=0
    [[ "$(readlink -f "$file")" == "$CURRENT_SESSION_FILE" ]] && is_active=1
    
    printf "%s|%d|%d|%s|%s|%d\n" \
        "$session_name" "$window_count" "$pane_count" \
        "$paths_str" "$cmds_str" "$is_active"
}
```

---

### GNU Parallel Integration Pattern

```bash
parse_all_files_parallel() {
    local -a session_files=("$@")
    
    # Export parser function and environment
    export -f parse_single_file
    export CURRENT_SESSION_FILE
    export RESURRECT_DIR
    
    # Set parallel citation env var
    export PARALLEL_CITATION="will-cite"
    
    # Process files in parallel
    # --will-cite: Suppress citation notice
    # --keep-order: Maintain input order
    # --jobs 0: Use all CPU cores
    printf '%s\n' "${session_files[@]}" | \
        parallel --will-cite --keep-order --jobs 0 \
            'parse_single_file {}'
}
```

---

### Sequential Fallback Pattern

```bash
parse_all_files_sequential() {
    local -a session_files=("$@")
    
    for file in "${session_files[@]}"; do
        parse_single_file "$file"
    done
}
```

---

### Array Loading Pattern

```bash
load_session_data() {
    local -a session_files=("$@")
    
    # Clear existing arrays
    SESSION_NAMES=()
    WINDOW_COUNTS=()
    PANE_COUNTS=()
    SESSION_PATHS=()
    SESSION_COMMANDS=()
    IS_ACTIVE=()
    
    # Parse files (parallel or sequential)
    local output
    if [[ "$USE_PARALLEL" == "true" ]]; then
        output=$(parse_all_files_parallel "${session_files[@]}")
    else
        output=$(parse_all_files_sequential "${session_files[@]}")
    fi
    
    # Load into arrays
    while IFS='|' read -r name windows panes paths cmds active; do
        SESSION_NAMES+=("$name")
        WINDOW_COUNTS+=("$windows")
        PANE_COUNTS+=("$panes")
        SESSION_PATHS+=("$paths")
        SESSION_COMMANDS+=("$cmds")
        IS_ACTIVE+=("$active")
    done <<< "$output"
    
    # Validate
    local count="${#SESSION_NAMES[@]}"
    if [[ "$count" -eq 0 ]]; then
        echo "Warning: No sessions loaded" >&2
        return 1
    fi
    
    debug_log "Loaded $count sessions"
}
```

---

### Width Calculation Pattern with Cache

```bash
declare -A WIDTH_CACHE=()

get_display_width() {
    local text="$1"
    
    # Check cache first
    if [[ -n "${WIDTH_CACHE[$text]}" ]]; then
        echo "${WIDTH_CACHE[$text]}"
        return
    fi
    
    local width
    
    # Fast path: ASCII-only
    if [[ "$text" =~ ^[[:ascii:]]*$ ]]; then
        width="${#text}"
    else
        # Slow path: Unicode
        width=$(python3 -c "
import sys
import unicodedata
text = sys.argv[1]
width = sum(1 + (unicodedata.east_asian_width(c) in 'FW') for c in text)
print(width)
" "$text")
    fi
    
    # Cache result
    WIDTH_CACHE["$text"]=$width
    echo "$width"
}
```

---

## Testing Strategy

### Test Environment Setup

```bash
# Test utilities
source "test-framework.bash"

setup_test_environment() {
    TEST_DIR="/tmp/tmux-picker-test-$$"
    mkdir -p "$TEST_DIR/resurrect"
    export RESURRECT_DIR="$TEST_DIR/resurrect"
}

teardown_test_environment() {
    rm -rf "$TEST_DIR"
}
```

---

### Unit Test Template

```bash
test_parser_counts_correctly() {
    setup_test_environment
    
    # Arrange
    local test_file="$RESURRECT_DIR/test.txt"
    cat > "$test_file" << 'EOF'
window	test	1	:vim	1	:*	layout1	on
pane	test	1	1	:-	0	title	:/home	1	vim	:vim file.txt
pane	test	1	1	:-	1	title	:/tmp	0	bash	:
EOF
    
    # Act
    local output
    output=$(parse_single_file "$test_file")
    
    # Assert
    local window_count=$(echo "$output" | cut -d'|' -f2)
    local pane_count=$(echo "$output" | cut -d'|' -f3)
    
    assert_equal "$window_count" "1" "Window count should be 1"
    assert_equal "$pane_count" "2" "Pane count should be 2"
    
    teardown_test_environment
}
```

---

### Integration Test Template

```bash
test_end_to_end_workflow() {
    setup_test_environment
    
    # Arrange: Create multiple session files
    for i in {1..5}; do
        create_test_session_file \
            "$RESURRECT_DIR/session${i}.txt" \
            "test${i}" 2 3
    done
    
    # Act: Run complete workflow
    load_session_data "$RESURRECT_DIR"/session*.txt
    
    # Assert: Verify results
    assert_equal "${#SESSION_NAMES[@]}" "5" "Should load 5 sessions"
    
    for name in "${SESSION_NAMES[@]}"; do
        assert_matches "$name" "^test[1-5]$" "Session name should match pattern"
    done
    
    teardown_test_environment
}
```

---

### Performance Test Template

```bash
test_performance_improvement() {
    setup_test_environment
    
    # Create test data
    for i in {1..50}; do
        create_test_session_file \
            "$RESURRECT_DIR/session${i}.txt" \
            "session${i}" 5 3
    done
    
    # Benchmark new implementation
    local start=$(date +%s%N)
    USE_PARALLEL=true load_session_data "$RESURRECT_DIR"/session*.txt
    local end=$(date +%s%N)
    
    local elapsed=$(( (end - start) / 1000000 ))
    
    # Assert: Should complete in under 500ms for 50 files
    assert_less_than "$elapsed" "500" \
        "Should parse 50 files in under 500ms (actual: ${elapsed}ms)"
    
    teardown_test_environment
}
```

---

## Appendices

### Appendix A: GNU Parallel Installation

**Check if installed:**
```bash
command -v parallel && parallel --version
```

**Install methods:**

```bash
# NixOS
nix-env -iA nixpkgs.parallel

# Ubuntu/Debian
sudo apt-get install parallel

# macOS
brew install parallel

# From source
wget https://ftpmirror.gnu.org/parallel/parallel-latest.tar.bz2
tar xjf parallel-latest.tar.bz2
cd parallel-*
./configure && make && sudo make install
```

**First-run citation notice:**
```bash
# Acknowledge citation requirement once
parallel --citation

# Or suppress in scripts:
export PARALLEL_CITATION=will-cite
```

---

### Appendix B: Profiling Tools

Enable detailed profiling during development:

```bash
# Enable profiling
export TMUX_PICKER_PROFILE=true

# Run with profiling
bash -x tmux-session-picker 2> profile.log

# Analyze with awk
awk '/parse_single_file/ { count++ } END { print count " calls" }' profile.log
```

---

### Appendix C: Common Issues and Solutions

#### Issue: GNU Parallel Not Available

**Detection:**
```bash
if ! command -v parallel >/dev/null 2>&1; then
    echo "Warning: GNU parallel not found" >&2
    USE_PARALLEL=false
fi
```

**Solution:** Automatic fallback to sequential processing

---

#### Issue: Malformed Session Files

**Detection:**
```bash
if [[ ! $(head -1 "$file") =~ ^(pane|window|state|grouped_session) ]]; then
    echo "Warning: Malformed file: $file" >&2
    return 1
fi
```

**Solution:** Skip invalid files and continue processing

---

#### Issue: Empty Resurrect Directory

**Detection:**
```bash
if [[ ! -d "$RESURRECT_DIR" ]] || [[ -z "$(ls -A "$RESURRECT_DIR"/*.txt 2>/dev/null)" ]]; then
    echo "No tmux sessions found" >&2
    exit 0
fi
```

**Solution:** Exit gracefully with helpful message

---

### Appendix D: Expected Performance Improvements

Based on analysis and benchmarking:

| Optimization | Improvement | Cumulative |
|-------------|-------------|------------|
| Single-pass parsing | 60-75% faster | 60-75% |
| GNU parallel | 5x on 8 cores | 80-85% |
| Width calculation cache | 80-90% faster | 85-90% |
| ASCII fast-path | Additional 5% | 90-92% |

**Final Target:** 13 seconds → 1 second (92% improvement) for 50 files

---

## Task Summary

### High Priority (Must Complete)
1. Design parser data structure (Task 1.1)
2. Implement single-pass parser (Task 1.2)
3. Add GNU parallel wrapper (Task 2.2)
4. Parse results into arrays (Task 2.3)
5. Integrate all components (Task 5.1)
6. Add error handling (Task 5.2)
7. Create test data generator (Task 6.1)
8. Write unit tests (Task 6.2)
9. Write integration tests (Task 6.3)

### Medium Priority (Should Complete)
10. Add active session detection (Task 1.3)
11. Verify GNU parallel availability (Task 2.1)
12. Implement ASCII fast path (Task 3.1)
13. Add width calculation cache (Task 3.2)
14. Create format function (Task 4.1)
15. Performance benchmarking (Task 6.4)

### Low Priority (Nice to Have)
16. Optimize path abbreviation (Task 4.2)
17. Add logging and debug mode (Task 5.3)
18. Create persistent Python process (Task 3.3)
19. Update code comments (Task 7.1)
20. Create implementation notes (Task 7.2)

---

**End of Document**
