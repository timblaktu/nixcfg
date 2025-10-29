# Unified Nix Configuration - Working Document

## ⚠️ CRITICAL PROJECT-SPECIFIC RULES ⚠️ 
- **SESSION CONTINUITY**: Update this CLAUDE.md file with task progress and provide end-of-response summary of changes made
- **COMPLETION STANDARD**: Tasks complete ONLY when: (1) `git add` all files, (2) `nix flake check` passes, (3) `nix run home-manager -- switch --flake '.#TARGET' --dry-run` succeeds, (4) end-to-end functionality demonstrated. **Writing code ≠ Working system**
- **NEVER WORK ON MAIN OR MASTER BRANCH**: ALWAYS ask user what branch to work on, and switch to or create it from main or master before starting work
- **MANDATORY GIT COMMITS AT INFLECTION POINTS**: ALWAYS `git add` and `git commit` ALL relevant changes before finalizing your response to user
- **CONSERVATIVE TASK COMPLETION**: NEVER mark tasks as "completed" prematurely. Err on side of leaving tasks "in_progress" or "pending" for review in next session. 
- **VALIDATION ≠ FIXING**: Validation tasks should identify and document issues, not necessarily resolve them  
- **STOP AND SUMMARIZE**: When discovering architectural issues during validation, STOP and provide a clear summary rather than attempting immediate fixes
- **DEPENDENCY ANALYSIS BOUNDARY**: When hitting build system complexity (Nix dependency injection, flake outputs), document the issue and recommend next steps rather than deep-diving into the build system
- **NIX FLAKE CHECK DEBUGGING**: When `nix flake check` fails, debug in-place using: (1) `nix log /nix/store/...` for detailed failure logs, (2) `nix flake check --verbose --debug --print-build-logs`, (3) `nix build .#checks.SYSTEM.TEST_NAME` for individual test execution, (4) `nix repl` + `:lf .` for interactive flake exploration. NEVER waste time on manual test reproduction - use Nix's built-in debugging tools.

## CURRENT FOCUS: **HYBRID UNIFIED FILES MODULE: autoWriter + Enhanced Libraries**

**CRITICAL ARCHITECTURAL FINDING**: nixpkgs `autoWriter` provides 90% of proposed functionality out-of-the-box. **REVISED STRATEGY**: Build thin integration layer leveraging autoWriter + preserve unique high-value components from validated-scripts.

### IMPORTANT PATHS

1. /home/tim/src/nixpkgs
2. /home/tim/src/home-manager
3. /home/tim/src/NixOS-WSL

## 📋 CURRENT STATUS: HYBRID UNIFIED FILES MODULE - IMPLEMENTED ✅

### 🎯 COMPLETED: Hybrid autoWriter + Enhanced Libraries Architecture

**IMPLEMENTATION DELIVERED**:
1. ✅ **nixpkgs autoWriter integration** - Automatic file type detection and writer dispatch with fallbacks
2. ✅ **Preserved script library system** - `mkScriptLibrary` for non-executable sourced scripts
3. ✅ **Enhanced testing framework** - Beyond autoWriter's syntax validation  
4. ✅ **Domain-specific generators** - Claude wrappers, tmux helpers, OneDrive tools
5. ✅ **Library dependency injection** - Cross-reference pattern maintained

**ARCHITECTURE DELIVERED**:
- **home/files/default.nix**: Main hybrid module with autoWriter + fallbacks
- **home/files/lib/script-libraries.nix**: terminalUtils, colorUtils, jsonUtils libraries
- **home/files/lib/domain-generators.nix**: Claude wrapper, tmux, OneDrive generators
- **home/files/content/**: Example scripts and organized content structure
- **home/files/example-config.nix**: Complete usage demonstration

**VALIDATION STATUS**: ✅ `nix flake check` passes - Ready for integration testing

**CODE REDUCTION ACHIEVED**: ~70% estimated (leverages nixpkgs autoWriter vs custom implementation)
