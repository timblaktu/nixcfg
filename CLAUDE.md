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


### 🎯 NEXT SESSION IMPLEMENTATION QUEUE - **MODULE-BASED ORGANIZATION EXTENSION**

**✅ STRATEGIC ANALYSIS COMPLETE**: Research confirms home/files dumping ground should be eliminated entirely following nixpkgs patterns.

**🏗️ IMPLEMENTATION ROADMAP** (Priority Order):

**📋 IMMEDIATE: Module-Based Migration Following tmux.nix Pattern**
1. ✅ **git.nix** - Extract `syncfork.sh`, `gitfuncs.sh` (2 scripts) **COMPLETE**
2. ✅ **development.nix** - Extract `claudevloop`, `restart_claude`, `mkclaude_desktop_config` (3 scripts) **COMPLETE**  
3. ✅ **terminal.nix** - Extract `setup-terminal-fonts`, `check-terminal-setup`, `diagnose-emoji-rendering`, `is_terminal_background_light_or_dark.sh` (4 scripts) **COMPLETE**
4. **system.nix** - Extract `bootstrap-*.sh`, `build-wsl-tarball` (3 scripts)
5. **shell-utils.nix** - Extract all `/lib/*.bash` libraries + `mytree.sh`, `colorfuncs.sh` (11 libraries + 2 utilities)

**🎯 ARCHITECTURAL DECISIONS FINALIZED**:
- ✅ **Module-based organization** confirmed as correct approach (following Linux packaging principles)
- ✅ **home/files elimination** validated by nixpkgs research - no dumping ground directories
- ✅ **shell-utils.nix consolidation** - text utilities belong with shell utilities, not separate module
- ✅ **Function-over-implementation** - organize by purpose, not language/OS

**🔧 PROVEN PATTERN** (from tmux.nix success):
```nix
# home/common/DOMAIN.nix
SCRIPT-NAME = pkgs.writeShellApplication {
  name = "script-name";
  text = builtins.readFile ../files/bin/script-name;
  runtimeInputs = with pkgs; [ dependencies ];
};
```

### 📚 SESSION HANDOFF SUMMARY (2025-10-30)

**🎯 IMPLEMENTATION SUCCESS**: terminal.nix module-based organization completed successfully
- **✅ terminal.nix Complete**: 4 terminal utility scripts extracted using writeShellApplication pattern:
  - `setup-terminal-fonts` (WSL terminal font configuration) with jq, coreutils, util-linux dependencies
  - `check-terminal-setup` (terminal alignment verification) with jq, coreutils dependencies  
  - `diagnose-emoji-rendering` (comprehensive terminal diagnostics) with xxd, coreutils, util-linux dependencies
  - `is_terminal_background_light_or_dark` (background detection utility) with coreutils, util-linux dependencies
- **✅ Quality Assurance**: All scripts build successfully in home-manager after fixing shellcheck warnings
- **✅ Integration Success**: Added terminal.nix import to base.nix with enableTerminal option (default: true)
- **✅ Migration Cleanup**: Removed terminal script references from zsh.nix overrides and files/default.nix exclusions

**🔄 ARCHITECTURAL TRANSFORMATION PROGRESS**: From dumping ground to intentional organization
- **✅ tmux.nix**: 6 scripts extracted (COMPLETE)
- **✅ git.nix**: 2 scripts extracted (COMPLETE)
- **✅ development.nix**: 3 scripts extracted (COMPLETE)
- **✅ terminal.nix**: 4 scripts extracted (COMPLETE) ← **JUST COMPLETED**
- **Remaining**: system.nix, shell-utils.nix (8 scripts + 11 libraries)

**📋 NEXT SESSION TASK QUEUE**: Continue module-based organization implementation

**🎯 IMMEDIATE PRIORITY**: system.nix module creation
1. **Create home/common/system.nix** following terminal.nix pattern
2. **Extract 3 system scripts**:
   - `bootstrap-*.sh` scripts → writeShellApplication with appropriate dependencies
   - `build-wsl-tarball` → writeShellApplication with build tools
3. **Remove references** from migration files
4. **Test integration** with nix flake check + home-manager dry-run

**🔧 PROVEN IMPLEMENTATION PATTERN** (from terminal.nix success):
```nix
# home/common/system.nix 
{ config, lib, pkgs, ... }: {
  config = mkIf cfg.enableSystem {
    home.packages = with pkgs; [
      (pkgs.writeShellApplication {
        name = "script-name";
        text = builtins.readFile ../files/bin/script-name;
        runtimeInputs = with pkgs; [ dependencies ];
      })
    ];
  };
}
```

**📊 MIGRATION PROGRESS TRACKER** (15 of 22 scripts complete - 68%):
- ✅ tmux.nix: 6 scripts (COMPLETE)
- ✅ git.nix: 2 scripts (COMPLETE) 
- ✅ development.nix: 3 scripts (COMPLETE)
- ✅ terminal.nix: 4 scripts (COMPLETE) ← **JUST COMPLETED**
- 🎯 system.nix: 3 scripts (NEXT SESSION PRIORITY)
- ⏳ shell-utils.nix: 11 libraries + 2 utilities (FINAL PHASE)

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
