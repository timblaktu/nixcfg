# Yazi Linemode Visual Improvements

## Problem Statement
The current yazi custom linemode displays timestamps in `MMDDHHMMSS` format (e.g., `1015170223`) which creates visual noise and is hard to parse when viewing file lists.

## Visual Improvement Strategies

### Option A: Add Separators (Simple)
- Format: `MM-DD HH:MM` (e.g., `10-15 17:05`)
- Complexity: **LOW** - simple date format change
- Benefits: Immediate readability improvement, maintains 10-char width

### Option B: Relative Time Display
- Recent files: just time (`17:05`)
- This week: day+time (`Oct14 16:55`)
- Older: full date (`2025-10-02`)
- Complexity: **MEDIUM** - requires time difference calculations

### Option C: Smart Context
- Very recent: relative (`34m ago`)
- Today: time only (`16:58`)
- This week: day+time (`Mon 16:55`)
- Older: short date (`10/02/25`)
- Complexity: **MEDIUM** - multiple time range logic

### Option D: Unicode Month Indicators
- Format: `❿15 17:05` (circled numbers for months)
- Complexity: **LOW** - month lookup table + formatting
- Benefits: Compact, visually distinct months

### Option E: Omit Repeated Elements (RECOMMENDED)
When sorted by mtime, eliminate repeated digits from left:
```
Original:           Improved:
1015170539    →     1015170539
1015165823    →         165823  
1015165312    →           5312
1014165508    →       14165508
```
- Complexity: **LOW** - simple string comparison
- Benefits: Reduces visual noise, emphasizes differences

### Option F: Tree-like Visual Enhancement
Combines Option E with tree characters to show grouping:
```
1015170539    →     1015170539
    165823    →     ├───165823
      5312    →     │   └─5312
  14165508    →     ├─14165508
```
- Complexity: **MEDIUM-HIGH** - requires grouping logic
- Benefits: Beautiful visual hierarchy

## Implementation Details

### Accessing Sort State
```lua
local sort_by = cx.active.current.files.sorter.by
-- Returns: "modified", "size", "permissions", etc.
```

### Module-Level State Tracking
Since linemode functions are called per-file, use module variables:

```lua
-- At module level (outside function)
local previous_values = {}

function Linemode:compact_meta()
  local current_size = -- calculate size string
  local current_mtime = -- calculate mtime string  
  local current_perm = -- calculate perm string
  
  -- Apply omission logic based on sort method
  local sort_by = cx.active.current.files.sorter.by
  
  if sort_by == "modified" and previous_values.mtime then
    current_mtime = omit_repeated_chars(previous_values.mtime, current_mtime)
  elseif sort_by == "size" and previous_values.size then
    current_size = omit_repeated_chars(previous_values.size, current_size)
  elseif sort_by == "permissions" and previous_values.perm then
    current_perm = omit_repeated_chars(previous_values.perm, current_perm)
  end
  
  -- Store for next call
  previous_values = {
    size = current_size,
    mtime = current_mtime,
    perm = current_perm
  }
  
  return formatted_result
end

function omit_repeated_chars(previous, current)
  local result = ""
  for i = 1, #current do
    if i <= #previous and string.sub(previous, i, i) == string.sub(current, i, i) then
      result = result .. " "
    else
      result = result .. string.sub(current, i)
      break
    end
  end
  return result
end
```

### Gotchas and Considerations

1. **State Reset**: Yazi might call linemode functions out of order or refresh the view
   - Consider tracking file indices or detecting list refreshes
   - Reset `previous_values` when appropriate

2. **Sort-Aware Logic**: Only apply omission when sorted by the relevant field
   - Prevents confusing display when files aren't grouped by the omitted field

3. **Unicode Considerations**: Some terminals may not display Unicode month indicators properly

4. **Performance**: Module-level state tracking is minimal overhead

## Current Implementation Location
- Main linemode code: `/home/tim/src/nixcfg/home/files/yazi-init.lua`
- Debug wrapper: `/home/tim/src/nixcfg/home/files/yazi-debug`
- Test examples: `/home/tim/src/nixcfg/linemode-mtime.txt`

## Recommendation
Start with **Option E** (omit repeated elements) as it provides significant visual improvement with low implementation complexity and works universally across size, mtime, and permissions fields when properly sorted.

## Status Bar Analysis & Optimization Opportunities

### Current Status Bar Configuration
Your yazi is currently using the **default status bar** with no custom configuration. The status bar appears at the bottom of the yazi interface and updates dynamically as you navigate. Based on your current configuration in `home/modules/base.nix`, you have:

```nix
settings = {
  mgr = {
    linemode = "compact_meta";  # Your custom linemode
    ratio = [ 1 3 5 ];         # Pane width ratios
    show_hidden = true;
    show_symlink = true;
    sort_by = "mtime";         # Sorted by modification time
    sort_dir_first = true;
    sort_reverse = true;       # Newest first
  };
  # No status bar customization currently
};
```

### What the Default Status Bar Shows
The default yazi status bar typically displays:
- **File count information** (e.g., "42/156 files")
- **Current file details** (size, modification time, permissions)
- **Selection status** (when files are selected)
- **Current directory path**
- **Progress indicators** (for operations like copying)

### Status Bar vs Linemode Trade-offs

#### Current Approach: Detailed Linemode
**Pros:**
- Information visible for ALL files simultaneously
- Quick scanning without navigation
- Consistent 20-character format maintains alignment

**Cons:**
- Visual noise on every line
- Repetitive information (especially when sorted by mtime)
- Takes up horizontal space for each file entry

#### Alternative Approach: Enhanced Status Bar
**Potential Benefits:**
- Clean file list (names only or basic info)
- Detailed information for CURRENT file only
- More space for additional context (full timestamps, file type, etc.)

### Status Bar Customization Options

#### Component Extension Architecture
Like linemode functions, status bar customization uses Yazi's component system:

```lua
-- In init.lua - Status bar component extension
function Status:custom_status()
  local file = cx.active.current.files:selected()
  if not file then return {} end
  
  -- Show detailed information for current file only
  local size = format_size(file.cha.len)
  local mtime = os.date("%Y-%m-%d %H:%M:%S", file.cha.mtime)
  local perms = string.format("%o", file.cha.mode & 0x1FF)
  
  return {
    ui.Span(size):fg("blue"),
    ui.Span(" │ "):fg("gray"),
    ui.Span(mtime):fg("green"),  
    ui.Span(" │ "):fg("gray"),
    ui.Span(perms):fg("yellow")
  }
end
```

#### Configuration Integration
```nix
# In home/modules/base.nix
settings = {
  mgr = {
    linemode = "size";  # Use simpler built-in linemode
  };
  status = {
    # Custom status configuration would go here
  };
};
```

### Hybrid Approach Recommendations

#### Option 1: Status-Focused Design
- **Linemode**: Use built-in `size` linemode (shows just file size)
- **Status Bar**: Custom component showing detailed mtime/permissions for current file
- **Benefits**: Clean list view, detailed current file info

#### Option 2: Context-Aware Display  
- **When sorted by mtime**: Show size in linemode, mtime in status bar
- **When sorted by size**: Show mtime in linemode, size in status bar  
- **Always**: Show permissions in status bar only
- **Benefits**: Avoid redundant information based on sort method

#### Option 3: Keep Current + Enhance Status
- **Linemode**: Keep your current compact_meta implementation
- **Status Bar**: Add extra context (full timestamp, file type, path depth)
- **Benefits**: Maximum information density

### Implementation Priority

1. **Current Status**: Your compact_meta linemode is working well ✅
2. **Next Step**: Experiment with status bar enhancements for current file
3. **Future**: Implement context-aware switching based on sort method

### Technical Implementation Notes

- Status bar components use `ui.Span()` objects for styling
- Access current file via `cx.active.current.files:selected()`
- Can display multi-line status information
- Supports rich formatting (colors, separators, icons)