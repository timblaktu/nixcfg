# tmux-session-picker Library Consolidation Analysis

**Date:** 2025-10-26  
**Task:** Survey tmux-session-picker for library function oversights  
**Scope:** Comprehensive audit to identify consolidation opportunities with existing home/files/lib functions

## Executive Summary

The audit of tmux-session-picker (827 lines) identified **5 major consolidation opportunities** that could reduce code duplication by ~150 lines while improving maintainability. However, **library functions require targeted enhancements** before serving as drop-in replacements.

**Key Findings:**
- **4 high-impact consolidations** available (path abbreviation, Unicode handling, color setup)
- **1 medium-impact consolidation** available (terminal width detection)  
- **Performance-critical tmux parsing code** should remain specialized
- **Existing library pattern** (`builtins.replaceStrings`) provides clear implementation path

## Detailed Analysis

### 1. Path Abbreviation Functions (HIGH IMPACT)

**Current Implementation:** tmux-session-picker lines 260-286
```bash
abbreviate_path() {
    local path="$1"
    # Common abbreviations using bash parameter expansion
    path="${path/#$HOME\//~/}"
    # ... more replacements
    
    # Unicode-aware truncation when > 20 display width
    if [[ $(get_display_width "$path") -gt 20 ]]; then
        # Intelligent last-segment truncation
    fi
}
```

**Available Library:** `path-utils.bash:normalize_path_display()` (lines 77-87)
- Combines `abbreviate_common_paths()` + `truncate_long_paths()`
- **CRITICAL ISSUE:** Uses byte count (`${#path}`) vs unicode display width
- **Different algorithms:** Library tries multiple segment combinations vs simple last-2-segments

**Required Library Changes:**
```bash
# In truncate_long_paths(), replace byte counting with display width:
if [[ $(get_display_width "$path") -le $max_length ]]; then
if [[ $(get_display_width "$truncated") -le $max_length ]]; then
```

**Dependencies:** Requires sourcing `terminal-utils.bash` for `get_display_width()`

### 2. Unicode Display Width Functions (HIGH IMPACT)

**Current Implementation:** tmux-session-picker lines 41-124
- **Caching:** `DISPLAY_WIDTH_CACHE` associative array for performance
- **Precision:** Python `unicodedata` for accurate East Asian width detection
- **Truncation:** Linear search with unicode-aware character counting

**Available Library:** `terminal-utils.bash:get_display_width()` (lines 8-31)
- **Performance:** No Python subprocess, uses `wc -m` + heuristics
- **Accuracy:** "All non-ASCII = double-width" approximation
- **Algorithm:** Binary search truncation with `LC_ALL=C.UTF-8`

**Trade-offs:**
- **Library:** Faster, no Python dependency, less accurate for mixed Unicode
- **tmux-session-picker:** Slower, Python dependency, precise Unicode handling

**Recommended Enhancement Options:**
1. **Add caching support** to library version
2. **Add precision parameter** for optional Python fallback
3. **Keep current implementation** if accuracy is critical

### 3. Color Setup Functions (MEDIUM IMPACT)

**Current Implementation:** tmux-session-picker lines 131-153
```bash
setup_colors() {
    local use_colors="${1:-auto}"
    # Direct ANSI code assignment
    if [[ "$use_colors" == "never" ]] || [[ "$use_colors" == "auto" && ! -t 1 ]]; then
        BOLD='' DIM='' RESET='' # ...
    else
        BOLD='\033[1m' DIM='\033[2m' # ...
    fi
}
```

**Available Library:** `color-utils.bash:detect_color_support()` (lines 15-61)
- **Better detection:** Checks `NO_COLOR`, `TERM` types, `tput` capabilities
- **Fallbacks:** Both `tput` and ANSI implementations
- **Global state:** Manages detection across calls

**MAJOR INCOMPATIBILITIES:**
1. **Variable naming:** `BOLD` vs `COLOR_BOLD`, `RESET` vs `COLOR_RESET`
2. **Parameter handling:** Explicit "never" vs environment detection
3. **Initialization:** Direct assignment vs function-based setup

**Required Library Changes:**
1. **Add variable aliases:** `BOLD="$COLOR_BOLD"` etc.
2. **Add explicit mode parameter:** `detect_color_support("never"|"auto"|"always")`

### 4. Terminal Width Detection (MEDIUM IMPACT)

**Current Implementation:** tmux-session-picker (4 locations)
```bash
TERM_WIDTH_CACHE=${COLUMNS:-$(tput cols)}
local term_width=${COLUMNS:-$(tput cols)}
```

**Available Library:** `terminal-utils.bash:detect_terminal_width()` (lines 99-117)
- **Multiple fallbacks:** `COLUMNS` → `tput cols` → `stty size`
- **Validation:** Ensures numeric result >= 20
- **Safe fallback:** Returns 80 if all methods fail

**Assessment:** Library function is **strictly better** - most straightforward consolidation

**Required Enhancement:** Add caching support for performance (tmux-session-picker calls frequently)

### 5. String Truncation (Keep Current)

**Current Implementation:** tmux-session-picker lines 30-39
```bash
truncate_string() {
    # Simple byte-based truncation
}
```

**Recommendation:** **Keep as-is** - simple enough, performance-critical, different from unicode-aware truncation

## Functions That Should NOT Be Consolidated

1. **Performance-critical tmux parsing** (lines 312-428) - Domain-specific, highly optimized
2. **GNU Parallel processing architecture** (lines 306-428) - Specialized for resurrect files  
3. **fzf integration functions** (lines 524-731) - Tightly coupled to UI requirements

## Implementation Strategy

### Priority 1: High-Impact Changes

1. **Terminal detection consolidation** (immediate - library is better)
2. **Color setup variable aliases** (maintains compatibility)
3. **Path abbreviation unicode support** (affects display layout)

### Priority 2: Performance Optimizations

4. **Unicode width caching** (if performance critical)
5. **Precision unicode handling** (if accuracy critical)

### Implementation Pattern

Following existing validated-scripts pattern:
1. **Use `builtins.replaceStrings`** to replace `source library-name` with `source ${libraryDerivation}`
2. **Add library dependencies** to tmux-session-picker's `deps` list
3. **Add source statements** to script header
4. **Replace function calls** with library equivalents
5. **Update tests** to verify identical functionality

## Estimated Impact

- **Code reduction:** ~150 lines (827 → 677 lines)
- **Maintainability:** Centralized utility functions
- **Performance:** Mixed (library optimizations vs current caching)
- **Consistency:** Unified behavior across script ecosystem

## Required Library Function Improvements

### 1. path-utils.bash
```bash
# Make truncate_long_paths() unicode-aware
if [[ $(get_display_width "$path") -le $max_length ]]; then
if [[ $(get_display_width "$truncated") -le $max_length ]]; then
```

### 2. color-utils.bash  
```bash
# Add compatibility aliases
BOLD="$COLOR_BOLD"
DIM="$COLOR_DIM"
RESET="$COLOR_RESET"
# ... etc

# Add explicit mode parameter
detect_color_support() {
    local force_mode="${1:-auto}"  # auto|never|always
}
```

### 3. terminal-utils.bash
```bash
# Add caching support
declare -g TERMINAL_WIDTH_CACHE=""
detect_terminal_width() {
    local use_cache="${1:-true}"
    # Use cache if available
}
```

### 4. Unicode width enhancements (optional)
```bash
# Add precision and caching parameters
get_display_width() {
    local text="$1"
    local use_cache="${2:-false}"
    local use_precise="${3:-false}"  # Python fallback
}
```

## Conclusion

The library ecosystem is mature and ready for broader adoption. The identified consolidation opportunities would significantly reduce code duplication while improving maintainability. However, **targeted library enhancements** are required to maintain tmux-session-picker's current functionality and performance characteristics.

**Next Steps:**
1. Review and prioritize library improvements
2. Implement high-priority library changes
3. Update tmux-session-picker to use library functions
4. Validate functionality equivalence
5. Apply similar analysis to other validated scripts

---

**Files Referenced:**
- `/home/tim/src/nixcfg/home/files/bin/tmux-session-picker`
- `/home/tim/src/nixcfg/home/files/lib/path-utils.bash`
- `/home/tim/src/nixcfg/home/files/lib/terminal-utils.bash`
- `/home/tim/src/nixcfg/home/files/lib/color-utils.bash`
- `/home/tim/src/nixcfg/home/modules/validated-scripts/bash.nix`