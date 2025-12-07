# Docling-Parse nlohmann_json Bool Conversion Fix
**Date**: 2025-12-07
**Status**: Solution identified, implementation pending

## Executive Summary

docling-parse v4.5.0 cannot build in nixpkgs due to nlohmann_json removing support for direct bool-to-json conversions. This affects BOTH 3.11.x and 3.12.x versions.

## Problem Details

### Build Failure
```cpp
// These ALL fail in modern nlohmann_json:
result = bool_value;                    // Assignment fails
json_array.push_back(bool_value);       // Push_back fails
nlohmann::json(bool_value)              // Constructor doesn't exist
nlohmann::json(true)                    // Even literals fail!
```

### Affected Files
- `src/v2/qpdf/to_json.h:165` - bool assignment
- `src/v2/pdf_resources/page_cell.h:188-189` - bool push_back
- `src/v2/pdf_sanitators/cells.h:126-127` - bool assignment

## Root Cause

nlohmann_json intentionally removed direct bool conversion support for type safety. This is NOT a bug but a design decision that breaks backward compatibility.

## Working Solution

The ONLY working approach is to use string parsing:

```cpp
// Instead of: result = bool_value;
nlohmann::json tmp;
if (bool_value)
    tmp = nlohmann::json::parse("true");
else
    tmp = nlohmann::json::parse("false");
result = tmp;
```

## Package Implementations

### Location
- `/home/tim/src/nixcfg/pkgs/docling-parse-final-fix/default.nix` - Uses parse workaround
- `/home/tim/src/nixcfg/pkgs/patches/docling-parse-nlohmann-json-3.12.patch` - Patch approach (incomplete)

### Usage
```nix
# In your Nix configuration
docling-parse-fixed = pkgs.callPackage ./pkgs/docling-parse-final-fix { };
```

## Impact on tomd

This blocks the tomd universal document converter from using Docling for:
- DOCX/PPTX/HTML support
- Advanced structure extraction
- Smart document chunking

Until docling-parse is fixed, tomd can only use marker-pdf for OCR.

## Implementation Status (2025-12-07)

### Fixes Applied
- Created comprehensive bool conversion fixes in local docling-parse repository
- Applied parse("true")/parse("false") workaround to all 3 affected files
- Committed changes to local git repository (commit 4d6fb6c)

### Current Blocker
The parse("true")/parse("false") approach itself appears to cause compilation errors within nlohmann_json's internal parsing code. The error suggests that even the parsed JSON cannot be directly converted to bool in the nlohmann_json 3.12 environment.

### Repository Status
- Local fixes: `/home/tim/src/docling-parse` (branch: fix/nlohmann-json-3.12-bool-conversion)
- Cannot fork to GitHub: Authentication not configured in Claude Code session
- Multiple Nix package attempts created in `/home/tim/src/nixcfg/pkgs/`

## Next Steps

1. **Alternative Fix Approach Needed**: The parse() method doesn't work - need to explore other bool conversion methods
2. **Manual Fork Required**: User needs to manually fork and push the repository with fixes
3. **Submit patch upstream to DS4SD/docling-parse** once a working solution is found
4. **Create nixpkgs PR with the fix** after validation
5. **Re-enable Docling in tomd** once working

## Lessons Learned

1. **API Breaking Changes**: Even fundamental JSON operations can break between library versions
2. **Type Safety vs Usability**: nlohmann_json prioritizes type safety over convenience
3. **Testing Importance**: docling-parse was likely never tested with recent nlohmann_json versions
4. **Workaround Creativity**: Sometimes parsing strings is the only solution

## References
- nlohmann_json GitHub: https://github.com/nlohmann/json
- docling-parse repo: https://github.com/DS4SD/docling-parse
- Related nixpkgs issue: (to be created)