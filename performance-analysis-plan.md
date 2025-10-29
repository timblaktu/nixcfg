# tmux-session-picker Performance Analysis Plan

**Date**: 2025-10-25  
**Goal**: Identify and resolve performance bottlenecks causing 2-3 second delays in fzf UI population

## Performance Instrumentation Summary

### Created Tools
1. **`home/files/lib/profiling-utils.bash`** - Comprehensive bash profiling library
   - High-precision timing using `date +%s.%N`
   - Section-based profiling with nested support
   - Command timing with `prof_time`
   - Performance counters and memory usage tracking
   - Detailed trace logging with PS4 integration

2. **`home/files/bin/tmux-session-picker-profiled`** - Instrumented version of original script
   - 50+ profiling checkpoints throughout execution
   - Section timing for major functions
   - Counter tracking for repetitive operations
   - Memory usage monitoring at key points
   - Full trace logging capability

### Key Instrumentation Points

#### Critical Performance Sections:
1. **INITIALIZATION** - Script startup and color setup
2. **GET_SESSION_LIST** - File discovery and session processing
3. **FORMAT_SESSION** - Individual session formatting (likely bottleneck)
4. **UNICODE_FUNCTIONS** - Width calculation functions
5. **BUILD_FZF** - fzf command construction and execution

#### Suspected Bottlenecks:
1. **Python3 calls in `get_display_width()`** - External process spawning
2. **Multiple grep operations per session** - File I/O intensive
3. **Binary search in `truncate_to_display_width()`** - Recursive Python calls
4. **Window detail processing** - Complex awk/grep combinations

## Testing Strategy

### Test Environment Setup
```bash
# 1. Create test resurrect directory with multiple session files
mkdir -p /tmp/test-resurrect
cd /tmp/test-resurrect

# 2. Generate synthetic session files (various sizes)
for i in {1..20}; do
  # Create realistic session files with varying complexity
  # (10-50 windows, 20-200 panes each)
done

# 3. Set test environment
export RESURRECT_DIR="/tmp/test-resurrect"
```

### Performance Test Cases

#### Test 1: Baseline Performance
- **Scenario**: List mode with 10-20 typical session files
- **Command**: `./tmux-session-picker-profiled --list`
- **Metrics**: Total execution time, section breakdown
- **Target**: < 500ms for list generation

#### Test 2: Stress Test
- **Scenario**: List mode with 50+ large session files
- **Command**: `./tmux-session-picker-profiled --list`
- **Metrics**: Scaling behavior, memory usage
- **Target**: Linear scaling, < 2GB memory

#### Test 3: Interactive Mode
- **Scenario**: Full interactive fzf session (exit immediately)
- **Command**: `./tmux-session-picker-profiled` (with automated input)
- **Metrics**: Time to fzf appearance, preview generation
- **Target**: < 1 second to fzf ready state

### Data Collection Plan

#### Profile Data Analysis
1. **Section Timing Analysis**: Identify slowest major sections
2. **Function Call Frequency**: Find repetitive expensive operations
3. **Memory Usage Patterns**: Detect memory-intensive operations
4. **External Command Analysis**: Count and time external process calls

#### Expected Findings
Based on code review, likely performance issues:

1. **Python3 Width Calculations**
   - `get_display_width()` spawns python3 for each text measurement
   - Called multiple times per session (window names, paths, summaries)
   - **Impact**: 10-50+ python3 processes per run

2. **Redundant File Processing**
   - Multiple grep operations on same files
   - Awk processing for window/pane extraction
   - **Impact**: File I/O amplification

3. **Unicode Binary Search**
   - `truncate_to_display_width()` uses binary search with recursive Python calls
   - Each iteration spawns another python3 process
   - **Impact**: Exponential process spawning

## Optimization Opportunities

### High-Impact Optimizations

1. **Python Width Calculation Caching**
   ```bash
   # Replace multiple python3 calls with single batch processing
   # Pre-calculate widths for all text in one python3 invocation
   ```

2. **File Processing Optimization**
   ```bash
   # Single-pass file parsing instead of multiple grep/awk operations
   # Pre-process files into structured format
   ```

3. **Unicode Width Approximation**
   ```bash
   # Use faster approximation for width calculation
   # Cache results for repeated strings
   ```

### Medium-Impact Optimizations

1. **Reduce Subshell Usage**
   - Replace `$(command)` with direct variable operations where possible
   - Use bash built-ins instead of external commands

2. **Optimize Window Detail Processing**
   - Batch window/pane processing
   - Reduce awk invocations

### Low-Impact Optimizations

1. **Color Code Optimization**
   - Pre-compute color sequences
   - Reduce printf complexity

## Success Metrics

### Performance Targets
- **Primary Goal**: < 1 second from command to fzf ready
- **List Generation**: < 500ms for 20 sessions
- **Memory Usage**: < 100MB peak usage
- **External Processes**: < 10 total subprocess spawns

### Validation Plan
1. **Before/After Comparison**: Document current vs optimized performance
2. **Real-world Testing**: Test with actual user session files
3. **Stress Testing**: Verify performance with large session counts
4. **Memory Profiling**: Ensure no memory leaks or excessive usage

## Next Steps

1. **Execute Test Cases**: Run profiled script with synthetic data
2. **Analyze Profile Logs**: Parse timing and counter data
3. **Identify Top 3 Bottlenecks**: Focus optimization efforts
4. **Implement Optimizations**: Address highest-impact issues first
5. **Validate Improvements**: Measure performance gains
6. **Document Results**: Update this analysis with findings

---

**Status**: Ready for execution and data collection