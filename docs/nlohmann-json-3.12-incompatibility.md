# nlohmann_json 3.12.0 Incompatibility with docling-parse

## Summary
docling-parse cannot build with nlohmann_json 3.12.0 due to a fundamental incompatibility where the library made bool constructors explicit/deleted but its own internal SAX parser still tries to use them.

## Issue Details
- **Root Cause**: nlohmann_json 3.12.0 explicitly deleted the bool constructor to prevent implicit conversions
- **Problem**: The library's internal SAX parser (used by `json::parse()`) attempts to construct json objects from bool values
- **Result**: Compilation fails with template instantiation errors

## Attempted Fixes
1. **Direct construction**: `nlohmann::json(bool_value)` - FAILS (constructor deleted)
2. **Brace initialization**: `nlohmann::json{bool_value}` - FAILS (constructor deleted)
3. **Literal constants**: `nlohmann::json(true)` / `nlohmann::json(false)` - FAILS (still bool type)
4. **Parse method**: `nlohmann::json::parse(val ? "true" : "false")` - FAILS (SAX parser internally uses bool constructor)
5. **Assignment**: `result = bool_value` - FAILS (assignment operator doesn't accept bool)

## PR Status
- **PR #184**: Submitted to docling-parse with attempted workarounds
- **Branch**: `fix/boolean-t-wrapper` on github:timblaktu/docling-parse
- **Status**: Workarounds cannot fix the nlohmann_json internal bug
- **Recommendation**: PR should be closed as the approach is fundamentally flawed

## Solution Implemented
✅ **Downgraded nlohmann_json to 3.11.3 in nixpkgs**
- Branch: `docling-parse-fix` on github:timblaktu/nixpkgs
- Commit: 259687eb0 "downgrade nlohmann_json to 3.11.3 for docling-parse compatibility"
- Result: docling-parse builds successfully

## Current State
- nlohmann_json downgraded to 3.11.3 in nixpkgs fork
- docling-parse builds successfully with the downgraded nlohmann_json
- docling and all dependencies build without errors
- This is a temporary fix until nlohmann_json fixes their 3.12.x SAX parser

## Next Steps
1. Report issue to nlohmann_json if not already reported
2. Consider downgrading nlohmann_json in nixpkgs to 3.11.x
3. Or wait for nlohmann_json 3.12.x patch release with fix