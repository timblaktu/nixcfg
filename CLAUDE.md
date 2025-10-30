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

## 📋 CURRENT STATUS: MODULE-BASED SCRIPT ORGANIZATION BREAKTHROUGH (2025-10-30)

### 🎯 COMPLETED: Architectural Issue Resolution via Module-Based Organization

**✅ BREAKTHROUGH ACHIEVED**: Resolved validated-scripts removal by implementing **module-based script organization** following Linux packaging principles.

**Major Architectural Discovery**: 
- ❌ **OS-based classification** (`linux-home-files.nix`, `wsl-home-files.nix`) is **anti-pattern**
- ✅ **Module-based organization** (`tmux.nix`, `git.nix`, etc.) follows **standard Linux packaging**
- ✅ **Scripts belong with their functional domains**, not arbitrary OS groupings

### 🎯 SUCCESSFUL IMPLEMENTATION (2025-10-30)

**✅ MIGRATION COMPLETED**:
1. ✅ **Moved 6 tmux scripts** from `home/files/bin` to `home/common/tmux.nix` as `writeShellApplication` packages
2. ✅ **Fixed all test references** to use conventional `nixpkgs.writers` pattern instead of `validatedScripts`
3. ✅ **Updated tmux.nix internal references** to use its own packages instead of home directory paths
4. ✅ **`nix flake check` now passes** - eliminated all `validatedScripts` missing attribute errors

**Key Pattern Established**:
```nix
# ✅ Correct: Scripts with their functional modules
# home/common/tmux.nix
tmux-session-picker = pkgs.writeShellApplication {
  name = "tmux-session-picker";
  text = builtins.readFile ../files/bin/tmux-session-picker;
  runtimeInputs = with pkgs; [ fzf tmux parallel python3 fd ripgrep ];
};
```


### 🎯 NEXT SESSION TASK QUEUE - **EXTEND MODULE-BASED ORGANIZATION PRINCIPLE**

**🔍 PRIORITY 1: STRATEGIC ANALYSIS - home/files Future Architecture**
- **Audit remaining home/files/bin scripts** for functional module extraction opportunities  
- **Analyze home/files/lib bash libraries** for shell package management integration
- **Evaluate whether home/files "dumping ground" should be eliminated entirely**
- **Design intentional packaging strategy** for general utilities vs functional domain scripts

**💭 PRIORITY 2: PACKAGING PATTERN RESEARCH**
- **Study nixpkgs script organization patterns** for bash/python/etc utilities
- **Create decision framework** for script categorization and placement
- **Investigate shell package management** for bash library organization
- **Define criteria** for "general utility" vs "domain-specific" classification

**🔧 PRIORITY 3: IMPLEMENTATION OPPORTUNITIES**
- **Extract git-related scripts** to `git.nix` module (following tmux pattern)
- **Extract development tools** to appropriate modules (`development.nix`, etc.)
- **Consider bash library packaging** in dedicated shell utilities module
- **Evaluate Claude wrapper scripts** for dedicated claude-code module

**💡 STRATEGIC QUESTION**: Should `home/files` exist at all, or should everything be intentionally packaged with functional domains following standard Linux/Nix packaging principles?

### 📚 SESSION HANDOFF SUMMARY (2025-10-30)

**🎯 BREAKTHROUGH ACHIEVED**: Resolved architectural crisis through **module-based organization**
- **Immediate Success**: `nix flake check` now passes - eliminated all `validatedScripts` missing attribute errors
- **Root Solution**: Moved scripts to their **functional modules** (tmux scripts → `tmux.nix`) following Linux packaging principles
- **Key Discovery**: OS-based classification was the **wrong approach** - function-based organization is correct

**🔄 TRANSITION COMPLETED**: From broken state to working architecture
- **Old System**: ❌ `validated-scripts` module (successfully removed)
- **Failed Approach**: ❌ OS-based script collections (`linux-home-files.nix`, etc.)
- **New System**: ✅ **Module-based organization** (`tmux.nix` contains tmux scripts, etc.)

**📋 NEXT SESSION FOCUS**: **EXTEND MODULE-BASED PRINCIPLE TO ALL SCRIPTS**
- Audit remaining `home/files` content for similar extraction opportunities
- Question whether `home/files` "dumping ground" should exist at all
- Design intentional packaging strategy following established Linux/Nix patterns
- Consider complete elimination of arbitrary script collections in favor of purposeful module organization

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
