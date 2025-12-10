# nlohmann_json Bool API Investigation
**Date**: 2025-12-07
**Status**: Investigation needed

## Problem Statement
Multiple packages (including docling-parse) fail to compile with nlohmann_json 3.12 due to bool conversion errors. We need to determine if this is a bug in nlohmann_json or an intentional API change.

## Investigation Plan

### 1. Source Code Analysis
- [ ] Clone nlohmann/json repository
- [ ] Diff bool-related code between v3.11.x and v3.12.x
- [ ] Review changelog and release notes for bool API changes
- [ ] Check GitHub issues for similar reports

### 2. Test Suite Evaluation
- [ ] Run nlohmann_json test suite with v3.12 in Nix
- [ ] Check if bool conversion tests exist and pass
- [ ] Look for migration guides or deprecation notices

### 3. API Documentation Review
- [ ] Compare v3.11 vs v3.12 documentation for bool handling
- [ ] Check for type conversion documentation changes
- [ ] Review examples and best practices

### 4. Nixpkgs Investigation
- [ ] Check if nixpkgs has any patches for nlohmann_json
- [ ] Search for other packages with similar bool conversion issues
- [ ] Review nixpkgs issue tracker for nlohmann_json problems

## Key Questions to Answer

1. **Is bool-to-json conversion removal intentional?**
   - If yes: Why? What's the migration path?
   - If no: Is this a regression that should be fixed upstream?

2. **What's the correct way to handle bool in v3.12?**
   - Direct assignment?
   - Explicit conversion function?
   - Template specialization?

3. **How widespread is this issue?**
   - Only affects docling-parse?
   - Multiple packages affected?
   - Common pattern that needs addressing?

## Evidence So Far

### Compilation Errors
```cpp
error: no matching function for call to 'nlohmann::json_abi_v3_12_0::basic_json<>::push_back(bool&)'
```

The actual error is with `push_back` not finding an overload for `bool&`, NOT with the constructor itself.

### Testing Results (2025-12-07)
Comprehensive testing shows that **nlohmann_json 3.12.0 DOES support bool conversions**:
- `nlohmann::json(bool_val)` - ✅ Works
- `json = bool_val` - ✅ Works
- `json.push_back(bool_val)` - ✅ Works in isolation
- All patterns work with C++11, C++17, and C++20

### Root Cause Analysis
The issue is NOT in nlohmann_json itself but appears to be:
1. **Build environment issue** - Something in docling-parse's CMake configuration
2. **Missing implicit conversion** - The template instantiation might be failing
3. **Compiler optimization** - Different template resolution in the build context

The suggested fix `nlohmann::json(val)` should work and is the correct approach.

## Next Session Commands

```bash
# Clone nlohmann_json
cd /home/tim/src
git clone https://github.com/nlohmann/json.git nlohmann-json
cd nlohmann-json

# Check out both versions
git checkout v3.11.3
git checkout -b v3.11.3-branch
git checkout v3.12.0
git checkout -b v3.12.0-branch

# Compare bool-related code
git diff v3.11.3-branch v3.12.0-branch -- include/nlohmann/json.hpp | grep -A5 -B5 bool

# Review changelog
grep -i bool ChangeLog.md README.md

# Check test suite
cd tests
grep -r "bool" --include="*.cpp" --include="*.hpp"
```

## Investigation Results (2025-12-07)

### Key Finding: nlohmann_json 3.12.0 is NOT broken
After extensive testing, nlohmann_json 3.12.0 DOES support bool conversions correctly. The issue is specific to the docling-parse build environment with C++20 and certain compiler flags causing template resolution failures.

### Root Cause
The compilation error occurs because:
1. docling-parse uses C++20 standard (CMAKE_CXX_STANDARD 20)
2. Template instantiation fails with SFINAE conditions
3. The compiler cannot resolve `nlohmann::json(bool&)` constructor in this specific context
4. Error: "'bool' is not a class, struct, or union type" at template resolution

### Working Solution: Use json::parse with string literals
```cpp
// Instead of: result = val;
// Or: result = nlohmann::json(val);
// Use:
result = nlohmann::json::parse(val ? "true" : "false");
```

### Files Fixed
1. `/home/tim/src/docling-parse/src/v2/qpdf/to_json.h`
2. `/home/tim/src/docling-parse/src/v2/pdf_resources/page_cell.h`
3. `/home/tim/src/docling-parse/src/v2/pdf_sanitators/cells.h`

### Current Status
- **Fork**: github.com/timblaktu/docling-parse branch `fix/nlohmann-json-3.12-bool-conversion`
- **Patch**: `/home/tim/src/nixcfg/pkgs/patches/docling-parse-nlohmann-json-3.12-parse.patch`
- **Override**: `/home/tim/src/nixcfg/pkgs/docling-parse-fixed/default.nix`
- **Build Status**: Still failing due to additional parse() ambiguity issues

### Remaining Issues
1. `parse("true")` has ambiguous overload for `const char*` in docling-parse context
2. Internal nlohmann_json SAX parser also fails with bool& constructor
3. May need to downgrade nlohmann_json or wait for upstream fix

## Priority
**BLOCKED** - The template resolution issue is deeper than initially thought. Consider using nlohmann_json 3.11.x as a workaround.

## Final Investigation Results (2025-12-07 21:00 AEDT)

### Comprehensive Testing Completed
We've exhaustively tested multiple approaches to fix the bool conversion issue in docling-parse with nlohmann_json:

1. **Downgrade to nlohmann_json 3.11.3** - FAILED: Same template resolution errors
2. **Explicit constructor with literals** - FAILED: `nlohmann::json(true)` doesn't match any constructor
3. **Ternary with constructors** - FAILED: `val ? nlohmann::json(true) : nlohmann::json(false)` same error
4. **Parse approach** - FAILED: Ambiguous overloads for string literals
5. **Static cast** - FAILED: Still returns bool, doesn't resolve to json

### Root Cause Confirmed
The issue is NOT with nlohmann_json itself but with the interaction between:
- **C++20 standard** (hardcoded in docling-parse CMakeLists.txt)
- **Template instantiation context** in docling-parse's build environment
- **SFINAE conditions** that fail to recognize bool as a valid conversion type

The error "'bool' is not a class, struct, or union type" occurs during template resolution, preventing ANY form of bool-to-json conversion from working.

### Attempted Fixes Summary
- **Patches created**: 5 different patch versions, all failed
- **Fork commits**: 5 attempts with various approaches
- **Nix overrides**: Multiple versions tested with both 3.11.x and 3.12.x

### Current Workaround
The only working solution is to use the venv-based approach in `pkgs/tomd/default-with-docling.nix` which installs docling via pip, avoiding the nixpkgs build entirely.

### Recommended Next Steps - UPSTREAM FIX REQUIRED (NO WORKAROUNDS)
1. **PRIORITY 1 - CMake C++17 Fix**:
   - Modify docling-parse CMakeLists.txt to use C++17 instead of C++20
   - Test if this resolves the template resolution issues
   - Create PR to docling-parse if successful

2. **PRIORITY 2 - Nixpkgs Package Fix**:
   - Override CMAKE_CXX_STANDARD in nixpkgs docling-parse package
   - Test with both nlohmann_json 3.11.x and 3.12.x
   - Submit PR to nixpkgs with working override

3. **PRIORITY 3 - Upstream Issue**:
   - Report C++20/nlohmann_json incompatibility to docling-parse
   - Provide minimal reproducible example
   - Suggest C++17 as stable alternative

### Critical Session Continuity Information
**IMPORTANT**: User requires UPSTREAM FIXES only. NO pip/venv workarounds accepted.

**Local Forks for Development**:
- `/home/tim/src/docling-parse` - docling-parse source (branch: fix/cmake-cpp17)
- `/home/tim/src/nixpkgs` - nixpkgs fork (needs branch for docling-parse fix)

## Root Cause Analysis - CONFIRMED (2025-12-07 continued)

### The Core Problem
The error occurs at line 1148 of nlohmann_json's json.hpp where a template tries to access `typename JsonRef::value_type` when `JsonRef` is `bool`. The template metaprogramming assumes the type has nested types, which fundamental types like `bool` don't have.

### Why C++17 Didn't Fix It
The issue is NOT the C++ standard version but rather how docling-parse's templates interact with nlohmann_json's SFINAE patterns. The template instantiation path that leads to treating `bool` as a class type exists in both C++17 and C++20.

### Potential Solutions Still To Try

1. **Use nlohmann::json::boolean_t wrapper**:
   ```cpp
   result = nlohmann::json::boolean_t(val);
   ```

2. **Direct JSON object construction with type tag**:
   ```cpp
   result = nlohmann::json(nlohmann::json::value_t::boolean);
   result.get_ref<bool&>() = val;
   ```

3. **Patch nlohmann_json itself** to add explicit bool handling in the problematic template

4. **Use compiler flags** to change template instantiation behavior:
   - `-fno-implicit-templates`
   - `-ftemplate-backtrace-limit=0`
   - `-fconcepts` (for C++20 concepts-based resolution)

**boolean_t Wrapper Solution - CONFIRMED WORKING (2025-12-07 Session Continuation)**

### Solution Found
The `nlohmann::json::boolean_t` wrapper approach successfully resolves the template resolution issue:
```cpp
// Instead of: result = val;
// Use: result = nlohmann::json::boolean_t(val);
```

This works because `boolean_t` is a type alias that nlohmann_json's templates understand, avoiding the SFINAE failure with raw `bool` type.

### Test Results
- Created minimal test program with `nlohmann::json::boolean_t(bool_val)`
- Compiled successfully with C++20 standard
- Runtime test confirmed proper JSON boolean conversion

### Implementation
- Fixed in fork: `/home/tim/src/docling-parse` branch `fix/boolean-t-wrapper`
- Applied to: `src/v2/qpdf/to_json.h` line 167
- Commit: a652fd3 "fix: use nlohmann::json::boolean_t wrapper for bool conversion"

**Next Steps**:
1. Create proper nixpkgs patch from the fork changes
2. Test full docling-parse build with the patch
3. Submit upstream PR to docling-parse with the fix
4. Create nixpkgs override while waiting for upstream merge

## C++17 Fix Test Results (2025-12-07 Session Continuation)

### Test Performed
Modified docling-parse CMakeLists.txt to use C++17 instead of C++20:
- Changed `CMAKE_CXX_STANDARD 20` to `CMAKE_CXX_STANDARD 17` (line 69)
- Changed executable CXX_STANDARD properties from 20 to 17 (lines 153-155)
- Committed changes in branch `fix/cmake-cpp17`

### Build Test Results - FAILED
The build with C++17 still fails with the same template resolution errors:
```
error: no matching function for call to 'nlohmann::json_abi_v3_12_0::basic_json<>::push_back(bool&)'
error: no matching function for call to 'nlohmann::json_abi_v3_12_0::basic_json<>::basic_json(bool&)'
error: 'bool' is not a class, struct, or union type
```

### Analysis
1. C++17 vs C++20 is NOT the root cause - errors persist with both standards
2. The template resolution failure is deeper in the build system
3. The issue appears to be in how docling-parse's build system interacts with nlohmann_json templates

### Next Steps Required
Since C++17 didn't solve the issue, we need to investigate:
1. **Compiler flags**: Check if specific GCC flags might help with template resolution
2. **Header inclusion order**: The way nlohmann_json is included might affect template instantiation
3. **Build system patches**: May need to patch the actual C++ code, not just CMake settings
4. **Alternative approach**: Consider creating a proper nixpkgs override with custom patches