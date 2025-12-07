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
error: no matching function for call to 'nlohmann::json_abi_v3_12_0::basic_json<>::basic_json(bool&)'
```

### Failed Workarounds
- `result = val;` - Direct assignment fails
- `nlohmann::json(val)` - Constructor doesn't exist
- `nlohmann::json::parse("true")` - Parse method also fails internally

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

## Potential Solutions

### If Bug in nlohmann_json
1. Create minimal reproducible example
2. File issue upstream with nlohmann/json
3. Create patch for nixpkgs nlohmann_json package
4. Submit PR to nixpkgs with patch

### If Intentional API Change
1. Understand new API pattern
2. Create migration guide
3. Fix all affected packages properly
4. Document pattern for future reference

## Priority
**HIGH** - This blocks multiple packages and the root cause must be correctly identified before proceeding with fixes.