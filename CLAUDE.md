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

## 📋 CURRENT STATUS: VALIDATED-SCRIPTS REMOVAL COMPLETED - ARCHITECTURE REDESIGN NEEDED

### 🎯 COMPLETED: Validated-Scripts Module Removal (2025-10-30)

**REMOVAL ACHIEVED**: 
1. ✅ **enableValidatedScripts option removed** - No longer exists in base.nix
2. ✅ **validated-scripts module import removed** - Direct import from base.nix eliminated  
3. ✅ **ESP-IDF tools migrated** - 4 scripts moved to wsl-home-files.nix
4. ✅ **Claude binary references fixed** - All wrappers use proper nix store paths

### 🚨 **CRITICAL ARCHITECTURAL GAP DISCOVERED (2025-10-30)**

**Issue**: Test failures reveal incomplete migration - `nix flake check` fails with:
```
error: attribute 'validatedScripts' missing
at flake-modules/tests.nix:502:42: tmux-session-picker-script = self.homeConfigurations."tim@mbp".config.validatedScripts.bashScripts.tmux-session-picker;
```

**Root Problem**: **Architectural pattern mismatch**
- ❌ **Current**: Manual OS-specific imports (`darwin-home-files.nix`, `wsl-home-files.nix`) 
- ✅ **Intended**: Automatic OS detection through `home/files` module with script classification (`linux`, `wsl`, `darwin`)
- ❌ **Missing**: `tmux-session-picker` should be classified as a "linux" script but isn't available in any OS collection
- ❌ **Tests**: Still reference old `validatedScripts` paths instead of proper `home/files` module paths

**Key Insight**: The current migration is **incomplete** - we removed validated-scripts but didn't properly implement the intended OS-based script architecture.


### 🎯 NEXT SESSION TASK QUEUE - **FOCUS ON DESIGN & DISCOVERY BEFORE IMPLEMENTATION**

**🔍 PRIORITY 1: DISCOVERY - Understand Current Architecture**
- **Investigate**: How does `home/files` module currently work and detect target OS?
- **Map**: Current script organization and access patterns in the existing system
- **Document**: What module paths should tests use to access scripts?
- **Identify**: Where/how OS-based script collections (`linux`, `wsl`, `darwin`) should be implemented

**💭 PRIORITY 2: DESIGN - OS-Based Script Architecture** 
- **Design**: Proper integration pattern for `tmux-session-picker` as a "linux" script
- **Define**: Correct module paths for accessing scripts (e.g., `config.homeFiles.scripts.tmux-session-picker`?)
- **Plan**: How automatic OS detection should work vs manual imports (`darwin-home-files.nix`, `wsl-home-files.nix`)
- **Specify**: Migration strategy from current manual approach to automatic detection

**💬 PRIORITY 3: DISCUSSION - Architecture Decisions**
- **Question**: Should we keep manual OS-specific imports or move to full automation?
- **Question**: What's the intended final architecture for script organization and access?
- **Question**: How should tests reference scripts in the new system?
- **Question**: What's the relationship between `home/files` module and `home/migration/*-home-files.nix`?

**⚠️ CRITICAL**: **DO NOT MAKE IMPLEMENTATION CHANGES** until architecture design is clarified through discussion

### 📚 SESSION HANDOFF SUMMARY (2025-10-30)

**🎯 ISSUE IDENTIFIED**: Incomplete migration from validated-scripts to unified files system
- **Immediate Blocker**: `nix flake check` fails - tests reference non-existent `validatedScripts` attributes
- **Root Cause**: Architecture mismatch between intended OS-based automatic detection and current manual imports
- **Key Finding**: `tmux-session-picker` exists but isn't classified/accessible as a "linux" script

**🔄 TRANSITION STATE**: Between old system (removed) and new system (incomplete)
- **Old System**: ❌ `validated-scripts` module (removed from base.nix)
- **Current System**: ⚠️ Manual OS-specific imports (`*-home-files.nix`) 
- **Intended System**: ✅ Automatic OS detection through `home/files` module (not implemented)

**📋 NEXT SESSION APPROACH**: **DISCOVERY → DESIGN → DISCUSSION → IMPLEMENTATION**
- Focus on understanding current `home/files` module architecture 
- Design proper OS-based script classification system
- Clarify architectural decisions before making changes
- Ensure tests use correct module paths in new system

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
