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

## 📊 **CURRENT SYSTEM STATUS**

**Current Branch**: `dev`
**Build State**: ✅ All flake checks passing, home-manager deployments successful
**Architecture**: Multi-language system requiring architectural evaluation:
- **Bash**: 1000+ line workspace management script (proof-of-concept evolved)
- **Rust**: Production-ready AST-based Nix flake modification  
- **Python**: Comprehensive pytest test suite (728+ tests)

**Critical Question**: Should this be unified into a pure Rust implementation?

## 🔧 **IMPORTANT PATHS**

1. `/home/tim/src/nixpkgs` - Local nixpkgs fork (active development: writers-auto-detection)
2. `/home/tim/src/home-manager` - Local home-manager fork (active development: autoValidate + fcitx5 fixes)  
3. `/home/tim/src/NixOS-WSL` - WSL-specific configurations (active development: plugin shim integration)

## 🚧 **ACTIVE FORK DEVELOPMENT STATUS** (2025-10-31)

### **nixpkgs Fork Development**
**Branch**: `writers-auto-detection` (ahead 1 commit)
**Status**: Feature development in progress
**Feature**: Automatic file type detection for nixpkgs writers
- ✅ lib.fileTypes module for automatic detection
- ✅ autoWriter function implementation  
- ✅ autoWriterBin for executable binary creation
- 🔧 Working debug harness (debug-autowriter.nix)
- 📋 **Upstream Goal**: Submit as RFC/PR for nixpkgs inclusion

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

### **🏗️ PROPOSED CONTEXT SWITCHING STRATEGIES**

#### **Strategy 1: Branch-Based Input Convention (Git Super-Repo Pattern)**
**Concept**: nixcfg branch name determines flake input selection
**Implementation**: 
- `main` branch → all upstream inputs (github:NixOS/nixpkgs, etc.)
- `dev` branch → all development fork inputs (git+file:///home/tim/src/*)
- `nixpkgs-dev` branch → nixpkgs fork only, others upstream
- `home-manager-dev` branch → home-manager fork only, others upstream

**Pros**: 
- Convention-based, version controlled
- Clear visual indication via branch name
- Can have specialized branches for specific feature combinations

**Cons**: 
- Requires branch switching to change context
- Need dynamic flake.nix or conditional logic

#### **Strategy 2: Git Worktree Multi-Context Architecture**
**Concept**: Separate working directories for different development contexts
**Implementation**:
```
~/src/nixcfg-main/        # main branch, upstream inputs
~/src/nixcfg-dev/         # dev branch, all fork inputs  
~/src/nixcfg-nixpkgs/     # nixpkgs-dev branch, nixpkgs fork only
~/src/nixcfg-feature-X/   # feature branch, custom input mix
```

**Pros**:
- Complete context isolation
- No git branch switching needed
- Each worktree can have different flake.nix
- Can work on multiple contexts simultaneously

**Cons**:
- Multiple working directories to maintain
- Higher disk usage
- Potential for divergent configurations

#### **Strategy 3: Dynamic Input Resolution System**
**Concept**: Smart flake.nix that auto-detects appropriate inputs
**Implementation**:
- Check current git branch name (`git rev-parse --abbrev-ref HEAD`)
- Check for existence of local fork directories
- Environment variable overrides (`NIX_USE_FORKS=nixpkgs,home-manager`)
- Fallback hierarchy: ENV → branch name → local detection → upstream

**Pros**:
- Automatic context detection
- Flexible override system
- Single flake.nix handles all cases

**Cons**:
- Complex flake.nix logic
- Potential for unexpected behavior
- Harder to debug input resolution

#### **Strategy 4: Explicit Profile Selection System**
**Concept**: Explicit profile files define input sets
**Implementation**:
```
profiles/
├── upstream.nix          # All upstream inputs
├── all-forks.nix         # All development forks
├── nixpkgs-only.nix      # nixpkgs fork, others upstream
└── testing.nix          # Specific input mix for testing
```

**Pros**:
- Explicit, version controlled
- Easy to understand and modify
- Can create custom profiles for specific needs

**Cons**:
- Manual profile selection required
- Need mechanism to choose active profile

#### **Strategy 5: Command-Line Input Override System**
**Concept**: Default to upstream, override inputs at build time
**Implementation**:
```bash
# Use upstream (default)
nix run home-manager -- switch --flake .

# Override specific inputs
nix run home-manager -- switch --flake . \
  --override-input nixpkgs git+file:///home/tim/src/nixpkgs?ref=writers-auto-detection

# Wrapper scripts for common combinations
hm-switch-dev     # Uses all forks
hm-switch-nixpkgs # Uses nixpkgs fork only
```

**Pros**:
- Uses nix built-in override system
- No flake.nix modifications needed
- Scriptable with wrapper functions

**Cons**:
- Command-line complexity
- Easy to forget which overrides are active
- Not version controlled

#### **Strategy 6: Multiple Flake Configuration Pattern**
**Concept**: Separate flake files for different contexts
**Implementation**:
```
flake.nix              # Symlink to active configuration
flake-upstream.nix     # Upstream inputs
flake-dev.nix          # Development fork inputs
flake-nixpkgs.nix      # nixpkgs fork only
```

**Pros**:
- Simple, explicit configuration files
- Easy to understand and maintain
- Can version control all variants

**Cons**:
- Manual symlink management
- Configuration duplication
- Risk of configurations drifting apart

## 🏗️ **ARCHITECTURE EVALUATION REQUIRED**

The git-worktree-superproject has evolved from a simple bash proof-of-concept into a sophisticated multi-language system:

### **Current Architecture**
- **Bash Script**: 1000+ lines of workspace management, git operations, configuration handling
- **Rust Binary**: Production-ready AST-based Nix flake modification with comprehensive testing  
- **Python Tests**: 728+ pytest tests providing comprehensive coverage of bash functionality

### **Key Question**
**Should this multi-language system be unified into a pure Rust implementation?**

**Considerations**:
- **Maintainability**: Is 1000+ lines of bash sustainable long-term?
- **Type Safety**: Runtime shell errors vs compile-time Rust guarantees
- **Performance**: Shell process spawning vs native operations
- **Testing**: Multi-language test coordination vs unified Rust testing
- **Distribution**: Shell script portability vs binary compilation requirements

## 📋 **CURRENT TASKS** (2025-11-02)

**Goal**: Rust migration planning complete - Implementation ready to begin

**Completed Planning**:
- [x] **Architecture analysis**: Multi-language system evaluation complete ✅
- [x] **Migration decision**: Approved unified Rust implementation ✅
- [x] **Phase 1 Planning**: Core infrastructure migration (git, config, CLI, filesystem) ✅
- [x] **Phase 2 Planning**: Advanced features (Nix integration, repo management, state) ✅  
- [x] **Phase 3 Planning**: Testing and polish (test migration, performance, hardening) ✅

**Current Status**: Planning complete - Ready for implementation

**Next Session Priority**: Begin Phase 1 implementation → Core infrastructure migration

**Implementation Strategy**:
- **No backwards compatibility needed**: Single-user implementation
- **Preserve existing assets**: Integrate current Rust AST system
- **Clean slate approach**: New Rust project structure from scratch
- **Test-driven development**: Migrate Python tests to native Rust testing

**Priority 2: Future Development** (DEFERRED pending Rust migration completion)
- [ ] Complete ongoing fork development work  
- [ ] Coordinate upstream contributions post-migration

## 🎯 **SESSION CONTEXT**

**Current Focus**: Rust migration implementation planning complete
**Critical Priority**: Begin Phase 1 implementation of unified Rust workspace manager
**Strategic Goal**: Replace 1,416-line bash script with structured Rust implementation
**Innovation Opportunity**: Unified codebase with 10-100x performance improvements

**Implementation Phases Defined**:
- **Phase 1**: Core infrastructure (git operations, configuration, CLI, filesystem)
- **Phase 2**: Advanced features (Nix integration, repository management, state tracking)
- **Phase 3**: Testing and polish (test migration, performance optimization, hardening)

**Architecture Decision Finalized**:
- **Approved**: Unified Rust implementation (libgit2, clap, serde, comprehensive testing)
- **Rejected**: Multi-language bash/rust/python coordination approach
- **Implementation**: Clean slate with existing Rust AST system integration

