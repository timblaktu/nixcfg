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

## 📋 CURRENT STATUS: PRIORITY 1 INCOMPLETE ❌

### 🚨 **CRITICAL ISSUE: HOME-MANAGER BUILD FAILING**

**❌ PRIORITY 1 BLOCKED**: Scripts have shellcheck violations preventing deployment
- 28 scripts migrated to modules but fail to build
- Multiple shellcheck violations in wifi and stress scripts
- home-manager switch --dry-run fails
- **LESSON**: `nix flake check --no-build` insufficient for validation

**🔧 IMMEDIATE FIXES NEEDED**:
- Fix shellcheck violations in remote-wifi-analyzer (multiple SC2086, SC2034, SC2064, SC2155)
- Fix remaining violations in wifi-test-comparison
- Validate actual home-manager deployment works
- **STANDARD**: All scripts must pass `writeShellApplication` shellcheck before claiming "complete"

### 📚 **RECENT FIXES COMPLETED** (For Reference)

**🔧 TECHNICAL SOLUTIONS IMPLEMENTED**:
- Fixed fzf preview correlation via `{+}` placeholder for complete session data
- Resolved parallel command quoting with array expansion
- Implemented build-time library inlining for sandboxed environments
- Standardized test library setup patterns across all tmux tests

### 🔧 **PROVEN IMPLEMENTATION PATTERNS** (Reference)

**Scripts**: `writeShellApplication` with `runtimeInputs` dependencies  
**Libraries**: `writeText` for bash libraries, installed to `~/.local/lib/*.bash`
**Library Sourcing**: Always use absolute paths: `source "$HOME/.local/lib/library-name.bash"`
**Integration**: Import + enableOption in base.nix
**Quality**: shellcheck compliance required





## 📋 NEXT SESSION PRIORITIES

**🎯 ARCHITECTURAL IMPROVEMENTS** (Priority order for next sessions):

### 🎯 **PRIORITY 1: Complete Module-Based Organization** ❌
**STATUS**: **INCOMPLETE** - Scripts migrated but deployment BROKEN

**CRITICAL ISSUE**: home-manager switch --dry-run FAILS due to shellcheck violations
- Scripts structurally migrated to modules 
- But writeShellApplication enforces strict shellcheck compliance
- Multiple scripts fail to build with violations

**FAILING SCRIPTS** (Confirmed):
- ❌ tmux-session-picker-profiled: shellcheck violations
- ❌ remote-wifi-analyzer: Multiple SC2086, SC2034, SC2064, SC2155 violations  
- ❌ wifi-test-comparison: shellcheck violations
- ❌ Other scripts likely failing (deployment blocked)

**COMPLETED WORK**:
- ✅ **Module Structure**: Scripts moved to appropriate modules
- ✅ **PowerShell Handling**: Preserved as Windows documentation
- ✅ **Some Fixes**: Fixed restart-usb*, soundcloud-dl, stress.sh shellcheck issues
- ✅ **Cleanup**: Removed backup files

**🚨 CRITICAL LESSON**: `nix flake check --no-build` is INSUFFICIENT validation
- Must test `home-manager switch --dry-run` for real deployment validation
- writeShellApplication enforces strict shellcheck compliance
- Migration ≠ Working deployment

**🔧 IMMEDIATE PRIORITY 1 COMPLETION TASKS**:
1. **Fix tmux-session-picker-profiled shellcheck violations**
2. **Fix remote-wifi-analyzer shellcheck violations** (SC2086, SC2034, SC2064, SC2155)
3. **Fix wifi-test-comparison shellcheck violations**
4. **Test home-manager switch --dry-run until SUCCESS**
5. **Only then mark Priority 1 complete**

### 🎯 **PRIORITY 2: Test Infrastructure Modernization** (BLOCKED)
**STATUS**: Cannot proceed until Priority 1 deployment works
**APPROACH**: Move tests from flake-modules/tests.nix to individual script derivations  
**IMPLEMENTATION STEPS**:
1. Research nixpkgs `passthru.tests` patterns
2. Create test migration strategy for existing 38+ tests
3. Implement `passthru.tests` on script derivations
4. Consolidate flake-modules/tests.nix to collection logic only
5. Validate all tests still pass after migration

### 🎯 **PRIORITY 3: Cross-Platform Validation**  
**GOAL**: Survey and fix hardcoded OS/platform-specific code  
**PATTERN**: Implement conditional platform detection guards  
**EXAMPLES**: `explorer.exe` vs `open` vs `xdg-open`, WSL-specific paths  
**BENEFIT**: Robust multi-platform support, no runtime errors on wrong platforms

### 🎯 **PRIORITY 4: Enhanced Configuration Features**
**OPTIONS**: Unified files module research, autoWriter integration, advanced shell features
**STATUS**: Lower priority, architectural foundation now solid

**🔧 SYSTEM STATUS**: All builds passing, all critical functionality operational, ready for next phase

