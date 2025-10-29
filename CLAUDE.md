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

## CURRENT FOCUS: **HYBRID UNIFIED FILES MODULE: autoWriter + Enhanced Libraries**

**CRITICAL ARCHITECTURAL FINDING**: nixpkgs `autoWriter` provides 90% of proposed functionality out-of-the-box. **REVISED STRATEGY**: Build thin integration layer leveraging autoWriter + preserve unique high-value components from validated-scripts.

## 📋 CURRENT TASK QUEUE

### 🎯 ACTIVE: Hybrid Unified Files Module Design

**IMPLEMENTATION STRATEGY (REVISED)**:
1. **Leverage nixpkgs autoWriter as foundation** - File type detection, writer dispatch, validation
2. **Preserve script library system** - `mkScriptLibrary` pattern for non-executable sourced scripts
3. **Retain enhanced testing framework** - Integration tests, help validation, library function tests  
4. **Keep domain-specific generators** - Claude wrappers, tmux helpers, etc.
5. **Add configuration file support** - JSON/YAML schema validation beyond autoWriter scope

**KEY RETENTION DECISIONS**:
- **Script Library System**: `terminalUtils`, `colorUtils` - autoWriter only creates executables
- **Cross-Reference Injection**: `"source library-name"` → `"source ${libraryDerivation}"` pattern
- **Enhanced Testing**: Integration tests beyond autoWriter's syntax validation
- **Domain Generators**: Claude wrapper PID management, config merging logic

**CODE REDUCTION ESTIMATE**: ~70% elimination (2700 → 800 lines) while preserving all unique value
