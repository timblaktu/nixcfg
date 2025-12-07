# ⚠️ CRITICAL PROJECT-SPECIFIC RULES ⚠️
- **SESSION CONTINUITY**: Update this CLAUDE.md file with task progress and provide end-of-response summary of changes made
- **COMPLETION STANDARD**: Tasks complete ONLY when: (1) `git add` all files, (2) `nix flake check` passes, (3) `nix run home-manager -- switch --flake '.#TARGET' --dry-run` succeeds, (4) end-to-end functionality demonstrated. **Writing code ≠ Working system**
- **NEVER WORK ON MAIN OR MASTER BRANCH**: ALWAYS ask user what branch to work on, and switch to or create it from main or master before starting work
- **MANDATORY GIT COMMITS AT INFLECTION POINTS**: ALWAYS `git add` and `git commit` ALL relevant changes before finalizing your response to user
- **CONSERVATIVE TASK COMPLETION**: NEVER mark tasks as "completed" prematurely. Err on side of leaving tasks "in_progress" or "pending" for review in next session.
- **VALIDATION ≠ FIXING**: Validation tasks should identify and document issues, not necessarily resolve them
- **STOP AND SUMMARIZE**: When discovering architectural issues during validation, STOP and provide a clear summary rather than attempting immediate fixes
- **DEPENDENCY ANALYSIS BOUNDARY**: When hitting build system complexity (Nix dependency injection, flake outputs), document the issue and recommend next steps rather than deep-diving into the build system
- **NIX FLAKE CHECK DEBUGGING**: When `nix flake check` fails, debug in-place using: (1) `nix log /nix/store/...` for detailed failure logs, (2) `nix flake check --verbose --debug --print-build-logs`, (3) `nix build .#checks.SYSTEM.TEST_NAME` for individual test execution, (4) `nix repl` + `:lf .` for interactive flake exploration. NEVER waste time on manual test reproduction - use Nix's built-in debugging tools.
- **RAPID ITERATION = FREQUENT CHECK-INS**: When user says "rapid iteration" or "quick/short responses", this means STOP AFTER EACH SMALL STEP and report back for guidance. Do NOT interpret as "work faster" - it means "communicate more frequently". After each change, explain what you did and ask what to do next.

# 🔧 **DEVELOPMENT ENVIRONMENT**
- Claude code may be running in the terminal or the web. Both use the same .claude/ and CLAUDE.md files in the repo.
- We define a session startup hook to ensure nix is installed in the environment.
  - **Web** environments are ephemeral, so nix will always need to be installed every session startup
  - **Local** environments already have nix, so hook should be a no-op (fast)
- **Environment config**: `flake-modules/dev-shells.nix` defines tooling

# CLAUDE-CODE CONFIGURATION AND STATE MANAGEMENT

**Local sessions:**
- Use `CLAUDE_CONFIG_DIR` → `claude-runtime/.claude-{account}/`
- Never touch `.claude/`
- Hook script at `home/files/bin/ensure-nix.sh` is fine (not web-specific)

**Web sessions:**
- Use `.claude/settings.json` for hooks
- Create runtime state in `.claude/` (all ignored except settings.json)
- Hook runs `bin/ensure-nix.sh` (same script, works in both contexts)

## Filesystem View of Claude Configuration and Runtime State

```
nixcfg/
├── home/files/bin/
│   └── ensure-nix.sh          # Shared hook script
├── claude-runtime/
│   ├── .claude-default/
│   │   ├── settings.json      # ✅ Checked in (Nix-managed)
│   │   ├── .claude.json       # ❌ Ignored (runtime)
│   │   └── .mcp.json          # ❌ Ignored (runtime)
│   ├── .claude-max/
│   │   └── ... (same)
│   └── .claude-pro/
│       └── ... (same)
└── .claude/                   # Web sessions ONLY
    ├── settings.json          # ✅ Checked in (web hooks)
    ├── .claude.json           # ❌ Ignored (runtime)
    ├── .mcp.json              # ❌ Ignored (runtime)
    └── logs/                  # ❌ Ignored (runtime)
```

# Common Nix Development Workflow Commands
```bash
nixpkgs-fmt <file>              # Format Nix files
nix flake check                 # Validate entire flake (MANDATORY before commits)
nix flake update                # Update flake inputs
nix build .#homeConfigurations."tim@thinky-nixos".activationPackage
home-manager switch --flake .#tim@thinky-nixos  # Test config switch
```

# 🔧 **IMPORTANT PATHS for LOCAL sessions**

1. `/home/tim/src/nixpkgs` - Local nixpkgs fork (active development: writers-auto-detection)
2. `/home/tim/src/home-manager` - Local home-manager fork (active development: autoValidate + fcitx5 fixes)  
3. `/home/tim/src/NixOS-WSL` - WSL-specific configurations (active development: plugin shim integration)
4. `/home/tim/src/git-worktree-superproject` - working tree for MY PROJECT implementing fast worktree switching for multi-repo and nix flake projects. We will eventually USE this here in nixcfg to facilitate multiple concurrent nix- development efforts


<<<<<<< HEAD
## 🚧 **ACTIVE FORK DEVELOPMENT STATUS** (2025-10-31)
||||||| e233a2a
#### Phase 1: Upstream Sync & Assessment (IMMEDIATE PRIORITY)
1. **Sync Fork with Upstream** - Merge upstream changes to get latest writers structure
2. **Assess autoWriter Compatibility** - Compare our implementation with upstream's new `auto.nix`
3. **Evaluate Integration Opportunities** - Determine how to leverage upstream's modular architecture
4. **Preserve Custom Features** - Ensure our file type detection and library injection patterns survive the sync
=======
## 🚧 **ACTIVE FORK DEVELOPMENT** (2025-10-31)
>>>>>>> cleanup-temp-files

<<<<<<< HEAD
### **nixpkgs Fork Development**
**Branch**: `writers-auto-detection` (ahead 1 commit)
**Status**: Feature development in progress
**Feature**: Automatic file type detection for nixpkgs writers
- ✅ lib.fileTypes module for automatic detection
- ✅ autoWriter function implementation  
- ✅ autoWriterBin for executable binary creation
- 🔧 Working debug harness (debug-autowriter.nix)
- 📋 **Upstream Goal**: Submit as RFC/PR for nixpkgs inclusion
||||||| e233a2a
#### Phase 2: Enhanced Unified Module (Next Sprint)  
1. **Leverage Upstream Writers** - Use new modular upstream structure as foundation
2. **Implement mkValidatedFile** - Build on upstream's `autoWriter` for seamless file type detection
3. **Library Injection System** - Preserve and enhance our `builtins.replaceStrings` library pattern
4. **Dynamic Discovery** - Replace hardcoded `validatedScriptNames` with upstream-compatible detection
5. **Testing Integration** - Combine our validation framework with upstream's enhanced writers
6. **Backward Compatibility** - Ensure smooth migration from current validated-scripts module
=======
### Critical Dependencies
- **nixpkgs**: `writers-auto-detection` branch - autoWriter/autoWriterBin for file type detection
- **home-manager**: `auto-validate-feature` + fcitx5 fixes
- **NixOS-WSL**: `plugin-shim-integration` - VSOCK communication + bare mount support
- **⚠️ WARNING**: All forks have uncommitted work - coordinate upstream submissions before major upgrades
>>>>>>> cleanup-temp-files

<<<<<<< HEAD
### **home-manager Fork Development**  
**Branches**: 
- `auto-validate-feature` (current) - autoValidate feature
- `feature-test-with-fcitx5-fix` - fcitx5 compatibility fix
**Status**: Multiple features in development
**Features**:
1. **autoValidate Integration**: Automatic validation for home.file
   - ✅ Source attribute conflict resolution (mkMerge)
   - 🔧 Integration with file-type detection
2. **fcitx5 Package Path Fix**: Compatibility with recent nixpkgs
   - ✅ Updated package path (libsForQt5.fcitx5-with-addons → fcitx5-with-addons)
- 📋 **Upstream Goal**: Submit both features for home-manager inclusion
||||||| e233a2a
### Key Architectural Decisions Documented:
- **Universal File Schema**: `mkValidatedFile` supports any file type with validation, testing, and completion generation
- **Type-Specific Validators**: Modular validation system for scripts, configs, data, assets, and static files  
- **Elimination of Coordination Overhead**: No more hardcoded cross-module dependencies
- **Extensible Design**: Easy addition of new file types through type registry
- **Migration Strategy**: Staged rollout with compatibility layer to ensure zero disruption
=======
## 🔄 **MULTI-CONTEXT DEVELOPMENT STRATEGY** (2025-10-31)
>>>>>>> cleanup-temp-files

<<<<<<< HEAD
### **NixOS-WSL Fork Development**
**Branches**:
- `plugin-shim-integration` (current) - Plugin architecture development
- `feature/bare-mount-support` - Enhanced mount automation
**Status**: Advanced plugin architecture development  
**Features**:
1. **Plugin Shim Integration**: WSL plugin communication via VSOCK
   - ✅ VSOCK-based communication
   - ✅ Windows container builds integration
   - ✅ Comprehensive documentation (331+ lines)
   - ✅ Test infrastructure updates
2. **Bare Mount Support**: Enhanced WSL mount automation
   - ✅ Comprehensive automation support
   - ✅ Idempotent Windows script generation
- 📋 **Upstream Goal**: Major feature contribution to NixOS-WSL project

### **⚠️ CRITICAL DEVELOPMENT DEPENDENCIES**
1. **Cross-Fork Integration**: nixpkgs autoWriter used by home-manager autoValidate
2. **Active Development**: All forks have significant uncommitted/unpushed work
3. **Upstream Timing**: Features need coordination for proper upstream submission
4. **Breaking Changes Risk**: Major upgrades could conflict with ongoing development

### **🎯 FORK RESOLUTION STRATEGY**
**Phase 1: Feature Completion**
- Complete nixpkgs writers-auto-detection testing
- Finalize home-manager autoValidate integration
- Complete NixOS-WSL plugin shim documentation

**Phase 2: Upstream Coordination**  
- Prepare nixpkgs RFC for autoWriter feature
- Submit home-manager PRs for autoValidate + fcitx5 fixes
- Coordinate NixOS-WSL plugin architecture contribution

**Phase 3: Synchronized Upgrades**
- Only after upstream acceptance or feature stability
- Maintain local forks until upstream integration complete

## 🔄 **MULTI-CONTEXT DEVELOPMENT STRATEGY** (2025-10-31)

### **🎯 Strategic Challenge**
**Problem**: Fork development blocks other work due to manual flake.nix switching
- Fork features need months for upstream contribution
- Other nixcfg development shouldn't be delayed
- Manual input switching is error-prone and friction-heavy
- Need clear indication of development context

### **🏗️ PROPOSED CONTEXT SWITCHING STRATEGY: git-worktree-superproject**

See /home/tim/src/git-worktree-superproject for details.

## 📋 **CURRENT TASKS**

**Future Development** (DEFERRED until git-worktree-superproject is validated)
- [ ] Complete ongoing fork development work  
- [ ] Coordinate upstream contributions post-migration
||||||| e233a2a
### Success Criteria:
- Functional equivalence with existing modules
- Zero coordination overhead between modules
- Extensibility for any file type
- Improved developer experience with unified API
=======
### **🎯 Strategic Challenge**
**Problem**: Fork development blocks other work due to manual flake.nix switching
- Fork features need months for upstream contribution
- Other nixcfg development shouldn't be delayed
- Manual input switching is error-prone and friction-heavy
- Need clear indication of development context

### **🏗️ PROPOSED CONTEXT SWITCHING STRATEGY: git-worktree-superproject**

For details, see:
- **LOCAL SESSIONS**: /home/tim/src/git-worktree-superproject 
- **WEB SESSIONS**:   https://github.com/timblaktu/git-worktree-superproject

## 📋 **CURRENT TASKS**

### Recently Completed
- **tmux-session-picker fixes** (2025-11-08): Fixed file discovery, session switching, and added auto-rename for uniqueness. See `.archive/tmux-session-picker-fixes-2025-11-08.md`

### Active Development

#### **PDF-to-Markdown Conversion Tools** (2025-12-07) - 🔴 DOCLING BLOCKED - UPSTREAM FIX IN PROGRESS
**Status**: marker-pdf ✅ WORKING | docling ❌ BROKEN (C++20 template resolution with nlohmann_json)

**PRIORITY**: Fix docling-parse in nixpkgs/upstream - NO WORKAROUNDS

**The Problem - C++20 Template Resolution Failure**:
- **Root Cause**: docling-parse C++20 build environment incompatible with nlohmann_json bool conversions
- **Affects**: Both nlohmann_json 3.11.x and 3.12.x versions
- **Error**: "'bool' is not a class, struct, or union type" during SFINAE template resolution

**Active Work - UPSTREAM CONTRIBUTIONS REQUIRED**:
1. **docling-parse fork**: `/home/tim/src/docling-parse` (branch: `fix/nlohmann-json-3.12-bool-conversion`)
2. **nixpkgs fork**: `/home/tim/src/nixpkgs` (needs docling-parse package fix)
3. **Investigation docs**: `docs/nlohmann-json-bool-api-investigation-2025-12-07.md`

**Fix Strategy - IN ORDER OF PRIORITY**:
1. **CMake Fix**: Modify docling-parse CMakeLists.txt to use C++17 instead of C++20
2. **Compiler Flags**: Add flags to resolve template instantiation issues
3. **Code Patches**: Fix bool conversions to work with C++20 template resolution
4. **Nixpkgs Override**: Package the fixed version in nixpkgs

**Next Session Commands - CRITICAL FOR CONTINUITY**:
```bash
# PRIORITY 1: Test CMake C++17 fix
cd /home/tim/src/docling-parse
git checkout -b fix/cmake-cpp17
sed -i 's/CMAKE_CXX_STANDARD.*20/CMAKE_CXX_STANDARD 17/g' CMakeLists.txt
git add CMakeLists.txt && git commit -m "fix: use C++17 for nlohmann_json compatibility"

# Build test with C++17
nix-build -E 'with import <nixpkgs> {}; python312Packages.docling-parse.overrideAttrs (old: {
  src = /home/tim/src/docling-parse;
})'

# PRIORITY 2: If C++17 works, create nixpkgs PR
cd /home/tim/src/nixpkgs
git checkout -b fix/docling-parse-cpp17
# Edit pkgs/development/python-modules/docling-parse/default.nix
```

**Session Continuity Requirements**:
- ALWAYS check `/home/tim/src/docling-parse` fork status first
- NEVER suggest pip/venv workarounds - fix must be in nixpkgs
- Document all attempts in investigation file
- Create upstream issues/PRs as needed
