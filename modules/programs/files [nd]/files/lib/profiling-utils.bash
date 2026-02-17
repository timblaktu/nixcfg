#!/usr/bin/env bash

# profiling-utils.bash - Performance profiling and benchmarking utilities for bash scripts
# Designed for analyzing performance bottlenecks and optimizing script execution

# Global profiling state
declare -g PROF_ENABLED=false
declare -g PROF_START_TIME=""
declare -g PROF_OUTPUT_FILE=""
declare -g PROF_SECTION_STACK=()
declare -g PROF_COUNTERS=()

# Initialize profiling system
# Usage: prof_init [output_file] [enable_trace]
# Example: prof_init "/tmp/profile.log" true
prof_init() {
    local output_file="${1:-/tmp/bash_profile_$$.log}"
    local enable_trace="${2:-false}"
    
    PROF_ENABLED=true
    PROF_OUTPUT_FILE="$output_file"
    PROF_START_TIME=$(date +%s.%N)
    PROF_SECTION_STACK=()
    
    # Create/clear output file with header
    {
        echo "# Bash Script Profiling Report"
        echo "# Generated: $(date)"
        echo "# Script: ${BASH_SOURCE[1]:-$0}"
        echo "# PID: $$"
        echo "# Format: TIMESTAMP|ELAPSED|SECTION|EVENT|DETAILS"
        echo ""
    } > "$PROF_OUTPUT_FILE"
    
    # Enable detailed tracing if requested
    if [[ "$enable_trace" == "true" ]]; then
        prof_enable_trace
    fi
    
    prof_log "INIT" "Profiling initialized" "output=$output_file"
}

# Enable detailed line-by-line tracing using PS4
prof_enable_trace() {
    # Set PS4 to include high-precision timestamps and line numbers
    export PS4='+ $(prof_trace_log)'
    set -x
    prof_log "TRACE" "Line-by-line tracing enabled" ""
}

# Disable detailed tracing
prof_disable_trace() {
    set +x
    unset PS4
    prof_log "TRACE" "Line-by-line tracing disabled" ""
}

# Internal function for PS4 trace logging
prof_trace_log() {
    if [[ "$PROF_ENABLED" == "true" ]]; then
        local timestamp=$(date +%s.%N)
        local elapsed=$(echo "$timestamp - $PROF_START_TIME" | bc -l 2>/dev/null || echo "0")
        local source_file="${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-unknown}}"
        printf "TRACE|%.6f|${BASH_LINENO[1]}|${source_file##*/}|" "$elapsed"
    fi
}

# Log profiling event
# Usage: prof_log event_type description [details]
prof_log() {
    [[ "$PROF_ENABLED" != "true" ]] && return 0
    
    local event_type="$1"
    local description="$2"
    local details="${3:-}"
    local timestamp=$(date +%s.%N)
    local elapsed=$(echo "$timestamp - $PROF_START_TIME" | bc -l 2>/dev/null || echo "0")
    
    local current_section="MAIN"
    if [[ ${#PROF_SECTION_STACK[@]} -gt 0 ]]; then
        current_section="${PROF_SECTION_STACK[-1]}"
    fi
    
    printf "%.6f|%.6f|%s|%s|%s|%s\n" \
        "$timestamp" "$elapsed" "$current_section" \
        "$event_type" "$description" "$details" >> "$PROF_OUTPUT_FILE"
}

# Start a profiling section (supports nested sections)
# Usage: prof_section_start "section_name" [description]
prof_section_start() {
    [[ "$PROF_ENABLED" != "true" ]] && return 0
    
    local section_name="$1"
    local description="${2:-$section_name}"
    
    PROF_SECTION_STACK+=("$section_name")
    prof_log "START" "$description" "depth=${#PROF_SECTION_STACK[@]}"
}

# End current profiling section
# Usage: prof_section_end [expected_section]
prof_section_end() {
    [[ "$PROF_ENABLED" != "true" ]] && return 0
    
    local expected_section="${1:-}"
    local current_section="${PROF_SECTION_STACK[-1]:-}"
    
    if [[ -n "$expected_section" && "$current_section" != "$expected_section" ]]; then
        prof_log "ERROR" "Section mismatch" "expected=$expected_section actual=$current_section"
        return 1
    fi
    
    prof_log "END" "$current_section" "depth=${#PROF_SECTION_STACK[@]}"
    
    # Remove last element from stack
    if [[ ${#PROF_SECTION_STACK[@]} -gt 0 ]]; then
        unset 'PROF_SECTION_STACK[-1]'
    fi
}

# Time a specific command or function
# Usage: prof_time "command_name" command [args...]
# Example: prof_time "file_listing" ls -la /tmp
prof_time() {
    [[ "$PROF_ENABLED" != "true" ]] && return 0
    
    local command_name="$1"
    shift
    
    local start_time=$(date +%s.%N)
    prof_log "CMD_START" "$command_name" "command=$*"
    
    # Execute command and capture exit code
    local exit_code=0
    "$@" || exit_code=$?
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    prof_log "CMD_END" "$command_name" "duration=${duration}s exit_code=$exit_code"
    return $exit_code
}

# Increment a performance counter
# Usage: prof_counter "counter_name" [increment]
prof_counter() {
    [[ "$PROF_ENABLED" != "true" ]] && return 0
    
    local counter_name="$1"
    local increment="${2:-1}"
    
    # Initialize counter if it doesn't exist
    local counter_var="PROF_COUNTER_${counter_name//[^a-zA-Z0-9_]/_}"
    if [[ -z "${!counter_var:-}" ]]; then
        declare -g "$counter_var=0"
    fi
    
    # Increment counter
    local new_value=$((${!counter_var} + increment))
    declare -g "$counter_var=$new_value"
    
    prof_log "COUNTER" "$counter_name" "value=$new_value increment=$increment"
}

# Add a benchmark checkpoint
# Usage: prof_checkpoint "checkpoint_name" [description]
prof_checkpoint() {
    [[ "$PROF_ENABLED" != "true" ]] && return 0
    
    local checkpoint_name="$1"
    local description="${2:-$checkpoint_name}"
    
    prof_log "CHECKPOINT" "$checkpoint_name" "$description"
}

# Memory usage profiling (if available)
prof_memory() {
    [[ "$PROF_ENABLED" != "true" ]] && return 0
    
    local description="${1:-memory_usage}"
    
    if command -v ps >/dev/null 2>&1; then
        # Get memory info for current process
        local mem_info=$(ps -o pid,vsz,rss,pmem -p $$ 2>/dev/null | tail -n 1)
        prof_log "MEMORY" "$description" "$mem_info"
    elif [[ -f "/proc/$$/status" ]]; then
        # Alternative: read from /proc
        local vmsize=$(grep VmSize /proc/$$/status 2>/dev/null | awk '{print $2 $3}')
        local vmrss=$(grep VmRSS /proc/$$/status 2>/dev/null | awk '{print $2 $3}')
        prof_log "MEMORY" "$description" "VmSize=$vmsize VmRSS=$vmrss"
    fi
}

# Generate profiling summary
# Usage: prof_summary [show_details]
prof_summary() {
    [[ "$PROF_ENABLED" != "true" ]] && return 0
    
    local show_details="${1:-false}"
    
    prof_log "SUMMARY" "Generating profiling summary" ""
    
    if [[ "$show_details" == "true" && -f "$PROF_OUTPUT_FILE" ]]; then
        echo "=== Profiling Summary ==="
        echo "Log file: $PROF_OUTPUT_FILE"
        echo ""
        
        # Show section timings
        echo "Section Timings:"
        awk -F'|' '
            /START/ { start[$4] = $2 }
            /END/ { 
                if ($4 in start) {
                    duration = $2 - start[$4]
                    printf "  %-20s: %8.3f seconds\n", $4, duration
                }
            }
        ' "$PROF_OUTPUT_FILE"
        
        echo ""
        
        # Show command timings
        echo "Command Timings:"
        awk -F'|' '
            /CMD_END/ { 
                match($6, /duration=([0-9.]+)/, arr)
                if (arr[1]) {
                    printf "  %-20s: %8.3f seconds\n", $5, arr[1]
                }
            }
        ' "$PROF_OUTPUT_FILE"
    fi
}

# Finalize profiling and cleanup
prof_finalize() {
    [[ "$PROF_ENABLED" != "true" ]] && return 0
    
    prof_log "FINALIZE" "Profiling session ended" ""
    
    # Disable tracing if it was enabled
    set +x 2>/dev/null || true
    unset PS4 2>/dev/null || true
    
    # Show summary
    prof_summary true
    
    PROF_ENABLED=false
    echo "Profiling data saved to: $PROF_OUTPUT_FILE"
}

# Utility function for quick function profiling
# Usage: prof_function function_name [args...]
# Example: prof_function my_slow_function arg1 arg2
prof_function() {
    local func_name="$1"
    shift
    
    prof_section_start "$func_name"
    prof_time "$func_name" "$func_name" "$@"
    prof_section_end "$func_name"
}

# Auto-profiling wrapper that can be sourced to profile entire scripts
# Usage: PROF_AUTO=true source profiling-utils.bash
if [[ "${PROF_AUTO:-false}" == "true" ]]; then
    # Auto-initialize profiling
    prof_init "/tmp/auto_profile_$(basename "${BASH_SOURCE[1]:-script}")_$$.log"
    
    # Set trap to finalize on exit
    trap prof_finalize EXIT
    
    echo "Auto-profiling enabled for $(basename "${BASH_SOURCE[1]:-script}")"
fi

# Performance testing utilities

# Run a command multiple times and report statistics
# Usage: prof_benchmark "command_description" iterations command [args...]
prof_benchmark() {
    local description="$1"
    local iterations="$2"
    shift 2
    
    echo "Benchmarking: $description ($iterations iterations)"
    
    local times=()
    local total_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start_time=$(date +%s.%N)
        "$@" >/dev/null 2>&1
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
        
        times+=("$duration")
        total_time=$(echo "$total_time + $duration" | bc -l 2>/dev/null || echo "$total_time")
        
        printf "  Run %2d: %8.3f seconds\n" "$i" "$duration"
    done
    
    # Calculate statistics
    local avg_time=$(echo "$total_time / $iterations" | bc -l 2>/dev/null || echo "0")
    
    echo "  Average: $(printf "%8.3f" "$avg_time") seconds"
    echo "  Total:   $(printf "%8.3f" "$total_time") seconds"
    echo ""
}

# Export key functions for use in other scripts
if [[ -n "$BASH_VERSION" ]]; then
    export -f prof_init prof_log prof_section_start prof_section_end prof_time
    export -f prof_counter prof_checkpoint prof_memory prof_summary prof_finalize
    export -f prof_function prof_benchmark 2>/dev/null || true
fi