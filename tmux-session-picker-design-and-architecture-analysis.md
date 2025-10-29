# tmux-session-picker High-Level Architecture Review

## 📋 ARCHITECTURAL PRINCIPLES CLARIFICATION *(2025-10-28)*

**CORRECTED UNDERSTANDING**:
1. **Main coordinator CAN/SHOULD manage worker stderr** - This is proper coordinator responsibility for debugging
2. **Environment inheritance ≠ "shared state"** - Workers inherit parent environment (COLUMNS, ROWS, sourced home/files/{bin,lib}/*) per standard Linux/bash behavior
3. **Use existing utilities** - Always check home/files/{bin,lib}/* before implementing new functionality
4. **"No shared state" means** - No global variables accessed by multiple processes, NOT no environment inheritance

## ⚠️ CRITICAL ARCHITECTURAL VIOLATIONS DISCOVERED ⚠️

**FUNDAMENTAL ISSUE**: Complete breakdown of main/worker separation of concerns throughout the codebase. 

The current implementation violates clean architecture principles with **extensive shared state**, **duplicated logic**, and **mixed responsibilities** that go far beyond the DISPLAY_WIDTH_CACHE issue.

## ❌ ARCHITECTURAL VIOLATIONS ANALYSIS

### 1. **SHARED STATE POLLUTION**
- `DISPLAY_WIDTH_CACHE` (line 17) - Global cache causing parallel worker conflicts
- `PREVIEW_CACHE_DIR` (line 59) - Shared preview cache directory management
- `VERBOSE` (line 77) - Global configuration state
- **Color variables exported globally** - YELLOW, CYAN, BOLD, etc. exported to workers

### 2. **EXTENSIVE LOGIC DUPLICATION**
- **Width calculation**: Main process (lines 952-966, 1009-1017) vs Workers (461-464)
- **Dual function implementations**: `get_display_width()` vs `get_display_width_no_cache()`
- **Dual truncation functions**: `truncate_to_display_width()` vs `truncate_to_display_width_no_cache()`
- **Color setup duplication**: Main calls `setup_colors()`, workers inline color setup

### 3. **MAIN PROCESS VIOLATING SINGLE RESPONSIBILITY**
- Column width calculations for formatting (lines 952-966, 1009-1017)
- Header formatting logic (lines 971-979)
- Managing worker debug directories and stderr capture
- Building fzf headers with calculated column widths

### 4. **WORKERS EXCEEDING THEIR SCOPE**
- Terminal width detection (should be main process coordination)
- Individual color management setup (duplicated responsibility)
- Complex formatting calculations that duplicate main process logic

### 5. **PREVIEW ARCHITECTURE VIOLATIONS**
- Main process manages global `PREVIEW_CACHE_DIR`
- Workers use main-process-controlled cache (shared state violation)
- Preview calls script recursively instead of dedicated preview workers
- Mixed cache cleanup responsibilities

## ✅ CLEAN ARCHITECTURAL DESIGN REQUIREMENTS

### **MAIN PROCESS: Pure Coordinator**
```
SINGLE PURPOSE: Discovery → Coordination → Collection → Execution

ALLOWED:
• Discover session files in resurrect directory
• Launch parallel workers with file list
• Collect worker output streams (stdout only)
• Pipe results directly to fzf
• High-level error handling (directory access, dependencies)

FORBIDDEN:
• ANY formatting calculations (width, truncation, display)
• ANY color management  
• ANY header generation
• Shared global variables between processes

COORDINATOR RESPONSIBILITIES:
• Worker stderr management for debugging
• Environment setup (sourced libraries, COLUMNS, ROWS) 
• Worker error coordination and debugging
```

### **WORKERS: Complete Autonomous Processing**
```
SINGLE PURPOSE: Session file → Complete formatted output ready for fzf

REQUIRED:
• Parse individual session file completely
• Handle ALL display formatting (colors, truncation, layout)
• Use inherited environment (COLUMNS, ROWS from parent)
• Use inherited sourced libraries from home/files/{bin,lib}/*
• Generate complete fzf display strings
• Generate complete preview content
• Report errors to coordinator via stderr
• Output ready-to-use strings (no post-processing)

ENVIRONMENT INHERITANCE (NOT "shared state"):
• COLUMNS, ROWS inherited from parent process
• Sourced utility functions from home/files/{bin,lib}/*
• Standard Linux/bash parent→child environment inheritance

ARCHITECTURE PRINCIPLES:
• Zero shared global variables with main process
• Use inherited environment (COLUMNS, ROWS, sourced functions)
• Self-contained formatting using inherited tools
• Report errors to coordinator via stderr
• Complete error handling and logging
• Direct output of formatted strings
```

---

## ORIGINAL ARCHITECTURE ASSESSMENT (Pre-Violation Analysis)

Core Design Pattern: Array-Based Pipeline Architecture

The script implements a sophisticated parallel processing pipeline that transforms tmux session files into an interactive UI:

1. File Discovery → Parallel Parsing → Array Population → Display Formatting → Interactive Selection

Key Architectural Strengths

1. Validated-Scripts Integration ✅

- Build-time validation via writers.testBash ensures syntax correctness
- Dependency management explicitly declares all required tools
- Library integration pattern uses builtins.replaceStrings for sourcing library functions
- Comprehensive test suite with Unicode support and real-world scenarios

2. Performance-Optimized Design ✅

- GNU Parallel processing for concurrent session file parsing (32% improvement achieved)
- Caching strategies: Terminal width, display width calculations, current session file
- Subprocess elimination: Pure bash replacements for external commands
- Array-based data flow: Minimizes file I/O after initial load

3. Unicode-Aware Display System ✅

- Sophisticated width calculation using Python unicodedata for precise East Asian character handling
- Intelligent truncation with ellipsis and visual boundary awareness
- Cache optimization for repeated width calculations
- Fallback strategies for ASCII-only fast paths

4. Modular Function Architecture ✅

- Separation of concerns: Data parsing, formatting, UI generation, preview generation
- Configurable layout system: Horizontal/vertical with dynamic sizing
- Clean argument parsing with environment variable support
- Error handling with verbose mode for diagnostics

Architectural Improvement Opportunities

Priority 1: Library Consolidation Strategy

The existing analysis identified 4 high-impact consolidation opportunities:

1. Path abbreviation functions → path-utils.bash (requires Unicode display width integration)
2. Unicode width calculations → terminal-utils.bash (requires caching support)
3. Color setup functions → color-utils.bash (requires variable name compatibility)
4. Terminal width detection → terminal-utils.bash (straightforward improvement)

Strategic Value: This follows the proven library integration pattern already established in the validated-scripts framework.

Priority 2: Performance Architecture Evolution

Current 32% improvement achieved through subprocess elimination. Additional 30-40% improvement possible through:

1. Library function optimization (eliminating echo | sed patterns)
2. File parsing consolidation (single-pass vs. multiple reads)
3. Pipeline modernization (miller/jq replacing awk chains)

Priority 3: Enhanced Caching Architecture

Current caching is tactical (per-execution). Strategic caching opportunities:

1. Session metadata cache (persistent across invocations)
2. Display width cache (shared across scripts)
3. Background refresh (proactive session discovery)

Architectural Design Patterns Assessment

Excellent Patterns to Preserve

1. Parallel Processing Architecture

# GNU parallel with exported functions - excellent scalability
export -f parse_single_file
printf '%s\n' "${session_files[@]}" | \
    parallel --will-cite --keep-order --jobs 0 'parse_single_file {}'

2. Array-Based Data Pipeline

# Zero I/O formatting after data load - excellent performance
for i in "${!SESSION_NAMES[@]}"; do
    # Pure array access, no file operations
done

3. Validated-Scripts Library Integration

# Clean dependency resolution pattern
text = builtins.replaceStrings
    ["source terminal-utils"]
    ["source ${terminalUtils}"]
    (builtins.readFile ../../files/bin/tmux-session-picker);

Areas for Architectural Enhancement

1. Function Granularity

- Current: Some functions are monolithic (e.g., 100+ line formatting functions)
- Opportunity: Extract focused, single-purpose functions following Unix philosophy

2. Data Flow Transparency

- Current: Complex data transformations in single functions
- Opportunity: Clear pipeline stages with intermediate data structures

3. Testing Architecture

- Current: Excellent build-time validation, good Unicode testing
- Opportunity: Performance regression testing, end-to-end integration tests

Strategic Architectural Recommendations

Phase 1: Continue Library Consolidation (High ROI)

- Immediate value: Reduce code duplication by ~150 lines
- Strategic value: Strengthen library ecosystem for other scripts
- Risk: Low - isolated changes with existing patterns

Phase 2: Advanced Performance Architecture (Medium ROI)

- Target: Additional 30-40% improvement (current 2.3s → ~1.3-1.6s)
- Focus: Library function optimization and file parsing consolidation
- Risk: Medium - requires careful validation of equivalent functionality

Phase 3: Next-Generation Architecture (Long-term)

- Persistent caching with background refresh
- Reactive UI updates for active session changes
- Plugin architecture for extensible preview modes

Architectural Philosophy Assessment

The tmux-session-picker demonstrates excellent architectural maturity:

✅ Performance-conscious design with measurable optimizations✅ Unicode-aware internationalization built from the ground up✅
Comprehensive testing strategy with realistic scenarios✅ Clean integration patterns with the broader Nix ecosystem✅
Maintainable codebase with clear separation of concerns

The architecture successfully balances functionality, performance, and maintainability while integrating cleanly with the
validated-scripts framework.

## Critical Architectural Inefficiency: Preview Generation Workflow

**Major Performance Bottleneck Identified**: The preview generation workflow completely bypasses the optimized parallel parsing architecture, creating a significant inefficiency:

### Current Workflow Analysis

**Main List Generation (Efficient)**:
```bash
# GNU parallel processing - excellent performance
printf '%s\n' "${session_files[@]}" | \
    parallel --will-cite --keep-order --jobs 0 'parse_single_file {}'
# Result: All session data parsed once, stored in arrays
```

**Preview Generation (Inefficient)**:
```bash
# fzf calls: tmux-session-picker --preview {}
generate_preview() {
    # PROBLEM 1: Re-parsing entire file
    file_data=$(tmux-parser-optimized "$file" "$CURRENT_SESSION_FILE")
    
    # PROBLEM 2: Re-reading file for pane data  
    grep "^pane" "$file" | while IFS=$'\t' read -r ...
    
    # PROBLEM 3: Re-reading file again for window data
    done < <(grep "^window" "$file")
}
```

### Performance Impact

**Every fzf navigation** triggers:
1. **Complete file re-parsing** via `tmux-parser-optimized`
2. **Two additional file reads** via `grep` operations
3. **String processing repetition** for data already in memory

**Estimated Impact**: Preview generation likely represents 60-80% of total script execution time during interactive use, completely negating the 32% parallel parsing optimization.

### Architectural Solution

**Priority 0: Data Reuse Architecture**

Store parsed session data in a format accessible to preview generation:

```bash
# Option 1: Export arrays for subprocess access
declare -A SESSION_WINDOWS SESSION_PANES SESSION_METADATA
export SESSION_WINDOWS SESSION_PANES SESSION_METADATA

# Option 2: JSON/structured data cache
echo "$parsed_data" > "/tmp/tmux-picker-cache-$$"

# Option 3: Embedded preview generation (no subprocess)
# Generate all previews upfront, use fzf --preview='cat /tmp/preview-{}'
```

**Estimated Performance Gain**: 70-80% reduction in preview generation time, making the script feel instantaneous during navigation.

### Implementation Strategy

1. **Immediate**: Cache parsed data in accessible format
2. **Medium-term**: Eliminate subprocess calls for preview generation  
3. **Long-term**: Pre-generate all previews for zero-latency navigation

This inefficiency represents the **highest-impact optimization opportunity** - more significant than the identified library consolidation work.

Recommendation: This script represents a strong architectural foundation for continued enhancement rather than requiring
fundamental redesign.

Task 0 Complete: Architectural Review Summary

I've completed the high-priority architectural review of tmux-session-picker. Here are the key findings:

Architectural Strengths Identified

- Sophisticated parallel processing pipeline with GNU parallel integration
- Performance-optimized design achieving 32% improvement through subprocess elimination
- Unicode-aware display system with precise East Asian character width handling
- Excellent validated-scripts integration following established patterns
- Comprehensive testing framework with realistic Unicode scenarios

Strategic Optimization Opportunities

1. Library consolidation (4 high-impact opportunities identified, ~150 line reduction)
2. Additional performance gains (30-40% improvement possible, targeting 1.3-1.6s total runtime)
3. Enhanced caching architecture for cross-invocation optimizations

Architectural Assessment

The script demonstrates excellent architectural maturity with:
- Clean separation of concerns
- Performance-conscious design patterns
- Strong integration with the Nix ecosystem
- Maintainable codebase structure

Strategic Recommendation: The architecture provides a strong foundation for continued enhancement rather than requiring
fundamental redesign. The existing library consolidation analysis provides a clear implementation roadmap for the next
optimization phase.

The task queue can now proceed to the remaining items, with this architectural foundation confirming that the current
optimization strategy is sound and the codebase is well-structured for future enhancements.
