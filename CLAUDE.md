# Unified Nix Configuration - Working Document

## ⚠️ CRITICAL PROJECT-SPECIFIC RULES ⚠️ 
- **SESSION CONTINUITY**: Update this CLAUDE.md file with task progress and provide end-of-response summary of changes made
- **COMPLETION STANDARD**: Tasks complete ONLY when: (1) `git add` all files, (2) `nix flake check` passes, (3) `nix run home-manager -- switch --flake '.#TARGET' --dry-run` succeeds, (4) end-to-end functionality demonstrated. **Writing code ≠ Working system**
- **MANDATORY GIT COMMITS AT INFLECTION POINTS**: ALWAYS `git add` and `git commit` ALL relevant changes when:
  - Completing ANY task (even partially)
  - Reaching any stopping point in your response
  - Making significant progress on multi-step tasks
  - Creating or modifying ANY files (documentation, code, configs)
  - Before ending ANY response to user, regardless of completion status
- **CONSERVATIVE TASK COMPLETION**: NEVER mark tasks as "completed" prematurely. Err on side of leaving tasks "in_progress" or "pending" for review in next session. Only mark "completed" when ALL criteria are verifiably met:
  - Implementation is 100% functional
  - All tests pass (`nix flake check`)
  - End-to-end validation successful
  - No remaining work items for that specific task
- **STOP AND SUMMARIZE**: When discovering architectural issues during validation, STOP and provide a clear summary rather than attempting immediate fixes
- **VALIDATION ≠ FIXING**: Validation tasks should identify and document issues, not necessarily resolve them  
- **DEPENDENCY ANALYSIS BOUNDARY**: When hitting build system complexity (Nix dependency injection, flake outputs), document the issue and recommend next steps rather than deep-diving into the build system
- **DOCUMENTATION FIRST**: Read existing docs (like tmux-session-picker-optimization-tasks.md) before implementing
- **VALIDATED-SCRIPTS LIBRARY PATTERN**: Library dependencies in validated-scripts use `builtins.replaceStrings` to replace `"source library-name"` with `"source ${libraryDerivation}"`. This creates working library integration where functions are sourced from Nix store paths. DO NOT assume "code duplication" - verify actual functionality before claiming architectural problems. The pattern `mkScriptLibrary` → string replacement → runtime sourcing is CORRECT and WORKING.
- **NIX FLAKE CHECK DEBUGGING**: When `nix flake check` fails, debug in-place using: (1) `nix log /nix/store/...` for detailed failure logs, (2) `nix flake check --verbose --debug --print-build-logs`, (3) `nix build .#checks.SYSTEM.TEST_NAME` for individual test execution, (4) `nix repl` + `:lf .` for interactive flake exploration. NEVER waste time on manual test reproduction - use Nix's built-in debugging tools.

## 🤖 PROJECT STATUS

**ARCHITECTURAL CONSOLIDATION: Unified Home Files Module**

Major architectural decision: Consolidating `home/modules/files` and `home/modules/validated-scripts` into a single, comprehensive `home/files` module that provides validated file management for any file type (scripts, configs, data, assets, static files).

## 📋 CURRENT TASK QUEUE

### IMMEDIATE: Fix Failing Tests (Post-Merge Issues)

**STATUS**: tmuxfix branch successfully merged to main, but tests need fixing due to truncation pattern changes.

**COMPLETED**:
- ✅ **Double Ellipsis Bug Fixed**: Removed redundant ellipsis append in `_format_session_row` 
- ✅ **IFS Robustness Test Fixed**: Updated test patterns from `📁-proj…` to `📁-pr…` to match 7-char session width

**REMAINING TEST FAILURES**:
1. **Session Discovery Test**: Wrong sort order - sessions not sorted newest-first as expected
2. **Session File Validation Test**: Test expects `project_work` but finds `proj…` (truncation mismatch)
3. **Multiple Other Tests**: Unicode display width, tmux environment detection, syntax tests

**ROOT CAUSE**: Test expectations written for different truncation behavior than current implementation

### NEXT ACTIONS:
1. **Fix test validation patterns** to match current truncation behavior
2. **Investigate session sorting** - ensure newest sessions appear first  
3. **Run full test suite** and systematically fix pattern mismatches
4. **Verify functionality** - ensure scripts work correctly despite test issues

### ARCHITECTURAL PROJECTS (DEFERRED):
- Upstream nixpkgs writers sync and unified files module (postponed until tests fixed)