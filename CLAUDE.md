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

### MAJOR DISCOVERY: Upstream nixpkgs Writers Restructuring

**CRITICAL FINDING**: Upstream nixpkgs has undergone a massive restructuring of the `writers` module that directly aligns with our unified files module goals. The new upstream structure includes:

- **Modular Architecture**: `pkgs/build-support/writers/` now split into:
  - `scripts.nix` - All script writers (bash, python, rust, etc.)
  - `data.nix` - Data format writers (JSON, YAML, TOML, etc.) 
  - `auto.nix` - **AUTOMATIC WRITER SELECTION** based on file type detection
- **Enhanced `makeScriptWriter`**: Now supports path-based script creation (`"/bin/name"` syntax)
- **Improved `makeBinWriter`**: Better compilation script support
- **New Writers**: Enhanced support for Guile, Nim, Nu, Ruby, Lua, Rust, JS, etc.

**OUR FORK STATUS**: We already have `autoWriter` functionality implemented in our fork that appears to parallel the upstream work. However, the massive upstream restructuring suggests we should sync with upstream and build on their foundation rather than maintaining parallel implementations.

**RESEARCH SUMMARY**: 
- **Upstream Changes**: Only one minor change to writers since our fork - a Nim compilation fix in `scripts.nix`
- **Our Advanced Features**: Our fork includes `lib.fileTypes` module and `autoWriter` with automatic file type detection
- **Strategic Advantage**: We can contribute our auto-detection work upstream while gaining their modular architecture
- **Sync Recommendation**: STRONGLY RECOMMENDED - upstream's restructuring provides the exact foundation we need

### Revised Task Queue: 

#### Phase 1: Upstream Sync & Assessment (IMMEDIATE PRIORITY)
1. **Sync Fork with Upstream** - Merge upstream changes to get latest writers structure
2. **Assess autoWriter Compatibility** - Compare our implementation with upstream's new `auto.nix`
3. **Evaluate Integration Opportunities** - Determine how to leverage upstream's modular architecture
4. **Preserve Custom Features** - Ensure our file type detection and library injection patterns survive the sync

#### Phase 2: Enhanced Unified Module (Next Sprint)  
1. **Leverage Upstream Writers** - Use new modular upstream structure as foundation
2. **Implement mkValidatedFile** - Build on upstream's `autoWriter` for seamless file type detection
3. **Library Injection System** - Preserve and enhance our `builtins.replaceStrings` library pattern
4. **Dynamic Discovery** - Replace hardcoded `validatedScriptNames` with upstream-compatible detection
5. **Testing Integration** - Combine our validation framework with upstream's enhanced writers
6. **Backward Compatibility** - Ensure smooth migration from current validated-scripts module

### Key Architectural Decisions Documented:
- **Universal File Schema**: `mkValidatedFile` supports any file type with validation, testing, and completion generation
- **Type-Specific Validators**: Modular validation system for scripts, configs, data, assets, and static files  
- **Elimination of Coordination Overhead**: No more hardcoded cross-module dependencies
- **Extensible Design**: Easy addition of new file types through type registry
- **Migration Strategy**: Staged rollout with compatibility layer to ensure zero disruption

### Success Criteria:
- Functional equivalence with existing modules
- Zero coordination overhead between modules
- Extensibility for any file type
- Improved developer experience with unified API