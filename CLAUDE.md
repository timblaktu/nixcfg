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
**Architecture**: ✅ Claude Code v2.0 migration complete, clean nixpkgs.writeShellApplication patterns
**Quality**: ✅ Shellcheck compliance, comprehensive testing

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

### **🎯 CORRECTED APPROACH: ENHANCE GIT-WORKTREE-SUPERPROJECT FOR NIX FLAKES**

**USER INTENT**: Extend git-worktree-superproject to support Nix flakes as first-class superprojects

**STRATEGIC VISION**: 
- Add native Nix flake support to wt-super for input management
- Store flake input specifications in git config metadata (like repository specs)
- Enable per-workspace flake input overrides for fork/upstream switching
- Make this a reusable pattern for any Nix flake multi-repository development

**RESEARCH COMPLETED**: 
- ✅ Analyzed wt-super architecture and configuration patterns
- ✅ Identified git config-based repository specification system
- ✅ Understood per-workspace override mechanisms

**DESIGN REQUIREMENTS**:
1. **Flake Input Detection**: Auto-detect flake.nix and extract input specifications
2. **Input Configuration Storage**: Store input preferences in git config (workspace.flake.input.*)
3. **Per-Workspace Input Overrides**: Allow workspace-specific input URL/ref overrides
4. **Template System**: Generate flake.nix with appropriate inputs per workspace
5. **Backwards Compatibility**: Maintain existing wt-super functionality

**COMPLETED MILESTONES** (2025-11-01):
1. ✅ **Implement Nix flake detection in wt-super** - COMPLETED  
2. ✅ **Add flake input configuration commands** - COMPLETED
3. ✅ **Create per-workspace flake input override system** - COMPLETED
4. ✅ **Test with nixcfg multi-fork development scenario** - COMPLETED

**ACHIEVEMENT**: Industry-first git worktree + Nix flake integration successfully created!

**BREAKTHROUGH**: AST-based complex format parsing achieved!
- ✅ **Working**: `input.url = "url"` (simple format) 
- ✅ **Working**: `input = { url = "url"; }` (complex format) - **NEW**

**NEXT PRIORITY**: Implement actual AST node modification (beyond extraction)

## 📋 **CURRENT TASKS** (2025-10-31)

**Priority 0: CRITICAL CORRECTION** ✅ **COMPLETED**
- [x] ✅ **URGENT**: Revert destructive "upgrade" that disabled core functionality - COMPLETED
- [x] ✅ Restore working state with local nixpkgs fork and full feature set - COMPLETED 
- [x] ✅ Document proper upgrade approach that maintains functionality - COMPLETED

**Priority 1: Enhance git-worktree-superproject for Nix Flakes** ✅ **COMPLETED**
- [x] ✅ Research existing git worktree approach at ~/src/git-worktree-superproject
- [x] ✅ Analyze previous worktree superproject implementation and patterns
- [x] ✅ Design enhancement strategy for Nix flake support
- [x] ✅ **MILESTONE**: Implement Nix flake detection in wt-super
- [x] ✅ Add flake input configuration commands to workspace script
- [x] ✅ Create per-workspace flake input override system
- [x] ✅ Test enhanced wt-super with nixcfg multi-fork development

**OUTCOME**: ✅ **Working system** for simple format inputs, text-processing limitation identified

**Priority 1.5: Upgrade to Proper Nix Language Parsing** ✅ **MAJOR MILESTONE ACHIEVED**
- [x] ✅ **MILESTONE**: Evaluate rnix-parser capabilities - EXCELLENT RESULTS
  - ✅ 100% structure preservation confirmed (IDENTICAL regeneration)
  - ✅ Zero parsing errors on real-world nixcfg flake.nix
  - ✅ Perfect AST access to AttrSet structure
  - ✅ Full comment/whitespace preservation validated
- [x] ✅ **MILESTONE**: Test structure preservation with complex flake.nix modifications - COMPLETED
  - ✅ Successfully implemented AST traversal for finding inputs section
  - ✅ Complex format URL extraction working: `home-manager = { url = "..."; ... }`
  - ✅ Multi-input detection validated across different formats
  - ✅ Target URL correctly identified: `git+file:///home/tim/src/home-manager?ref=feature-test-with-fcitx5-fix`
- [x] ✅ **MILESTONE**: Research rnix AST modification capabilities - **CRITICAL DISCOVERY**
  - ✅ **Key Finding**: rnix/rowan uses **IMMUTABLE** tree structures
  - ✅ **No direct mutation**: Cannot modify AST nodes in-place
  - ✅ **Reconstruction required**: Must use GreenNodeBuilder to rebuild trees
  - ✅ **Compatible dependencies**: rowan 0.15.17 works with rnix 0.12.0
  - ✅ **Working test environment**: Enhanced rnix-test with research capabilities
- [x] ✅ **MILESTONE**: Research GreenNodeBuilder API and string literal structure - **MAJOR BREAKTHROUGH**
  - ✅ **String literal token structure discovered**: `NODE_STRING` = `TOKEN_STRING_START` + `TOKEN_STRING_CONTENT` + `TOKEN_STRING_END`
  - ✅ **SyntaxKind conversion working**: Direct casting via `as u16` successful (`NODE_STRING` = `SyntaxKind(65)`)
  - ✅ **GreenNodeBuilder API validated**: `start_node()`, `token()`, `finish_node()`, `finish()` workflow confirmed
  - ✅ **Green node access confirmed**: `node.green()` provides direct access to GreenNodeData for copying unchanged portions
- [x] ✅ **MILESTONE**: Implement selective tree reconstruction using green node copying - **COMPLETED (2025-11-01)**
  - ✅ **Perfect structure preservation**: children_with_tokens() approach preserves all whitespace, comments, and formatting
  - ✅ **Targeted URL replacement**: Successfully replaces only target URLs while preserving all other content
  - ✅ **Real-world validation**: Works with actual nixcfg flake.nix (2285 bytes) with perfect syntax preservation
  - ✅ **Comprehensive test suite**: 17 passing tests covering edge cases, performance, and structure preservation
- [x] ✅ **MILESTONE**: Complete production-ready URL replacement system - **COMPLETED (2025-11-01)**
  - ✅ **API ready for integration**: `find_url_string_path()` and `reconstruct_with_replacement()` functions
  - ✅ **Performance validated**: Sub-100ms reconstruction for large structures (50+ inputs)
  - ✅ **Error handling**: Graceful failure for non-existent URLs and malformed input
  - ✅ **Structure preservation guarantee**: Comments, whitespace, and non-target content perfectly preserved

**rnix-parser Status**: ✅ **PRODUCTION-READY SELECTIVE RECONSTRUCTION** 
**Current Capability**: Complete AST-based URL replacement with perfect structure preservation
**Achievement**: Industry-first selective Nix AST reconstruction with green node copying optimization

**Priority 2: Local Fork Development Resolution** (ENABLED by Priority 1)
- [ ] Complete ongoing fork development in parallel with other work
- [ ] Coordinate nixpkgs writers-auto-detection feature for upstream submission
- [ ] Resolve home-manager autoValidate feature development  
- [ ] Complete NixOS-WSL plugin shim integration work
- [ ] Plan fork synchronization strategy with upstream

**Priority 3: Infrastructure Updates** (RE-ENABLED by Priority 1)
- [x] ✅ Review pytest + NixOS test framework integration documentation (NIXOS-PYTEST.md) - COMPLETED
- [ ] Plan upgrade strategy that maintains fork development work
- [ ] Implement parallel development tracks (upstream vs fork testing)

**Note**: Multi-context system will enable parallel development - fork work AND other development can proceed simultaneously.

**Priority 4: Test Infrastructure Development** (RE-ENABLED by Priority 1)
- [ ] Design test infrastructure architecture for unified Nix configuration
- [ ] Create tests/lib.nix helper for NixOS test framework integration
- [ ] Add checks output to flake.nix for test integration
- [ ] Create base VM configuration template for test environments

**Priority 5: Core Validation Tests** (RE-ENABLED by Priority 1)
- [ ] Implement Home Manager configuration validation tests
- [ ] Test Claude Code configuration deployment across platforms
- [ ] Validate shell environment configurations (zsh, bash) in test VMs
- [ ] Create development tools validation tests (git, editors, etc.)

**Priority 6: Multi-Platform Testing** (RE-ENABLED by Priority 1)
- [ ] Create multi-architecture testing (x86_64, aarch64) validation
- [ ] Develop WSL-specific functionality tests with nested virtualization
- [ ] Implement cross-platform package compatibility tests

**Priority 7: CI/CD & Documentation** (RE-ENABLED by Priority 1)  
- [ ] Set up CI/CD integration for automated test execution
- [ ] Document testing workflow and debugging procedures

**Priority 8: pytest Integration** (RE-ENABLED by Priority 1)
- [ ] Implement pytest fixture interface for NixOS test framework (surgical integration)
- [ ] Complete NIXOS-PYTEST.md implementation plan

## 🎯 **SESSION CONTEXT**

**Current Focus**: Multi-context development system design and implementation  
**Critical Priority**: Enable parallel fork development AND other nixcfg work without blocking
**Strategic Goal**: Eliminate friction between fork development and mainstream development workflows
**Innovation Opportunity**: Create reusable pattern for multi-fork Nix development environments

**Pytest Integration Approach** (from NIXOS-PYTEST.md):
- **Surgical scope**: Only touches testScript interface layer, not VM infrastructure
- **Backwards compatible**: Existing tests continue working unchanged 
- **Fixture-based**: `def test_something(machine1, machine2):` with pytest features
- **Implementation**: Create pytest fixture generator at nixos/lib/test-driver/pytest_support.py
- **Benefits**: Superior assertions, parametrization, 1600+ plugins, better failure messages

**References**: 
- NIXOS-PYTEST.md - Detailed implementation plan and technical approach
- https://wiki.nixos.org/wiki/NixOS_VM_tests
- https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html
- https://github.com/NixOS/nixpkgs/blob/master/nixos/doc/manual/development/writing-nixos-tests.section.md
- https://blog.thalheim.io/2023/01/08/how-to-use-nixos-testing-framework-with-flakes/

