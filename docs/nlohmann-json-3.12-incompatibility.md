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
- **PR #184**: Submitted to docling-parse with workarounds
- **Branch**: `fix/boolean-t-wrapper` on github:timblaktu/docling-parse
- **Status**: Workarounds applied but build still fails due to nlohmann_json internal bug

## Solution Options
1. **Downgrade nlohmann_json**: Use version 3.11.x which doesn't have this issue
2. **Wait for fix**: nlohmann_json needs to fix their internal SAX parser
3. **Patch nlohmann_json**: Apply a patch to restore bool constructor compatibility
4. **Use different JSON library**: Replace nlohmann_json with alternative

## Current State
- All bool conversion workarounds have been applied to docling-parse
- nixpkgs fork configured to use the patched docling-parse
- Build fails due to nlohmann_json 3.12.0 internal bug
- This is a known issue with nlohmann_json 3.12.0

## Next Steps
1. Report issue to nlohmann_json if not already reported
2. Consider downgrading nlohmann_json in nixpkgs to 3.11.x
3. Or wait for nlohmann_json 3.12.x patch release with fix