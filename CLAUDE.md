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

## 📋 **CURRENT TASKS** (2025-10-31)

**Priority 0: CRITICAL CORRECTION** ✅ **COMPLETED**
- [x] ✅ **URGENT**: Revert destructive "upgrade" that disabled core functionality - COMPLETED
- [x] ✅ Restore working state with local nixpkgs fork and full feature set - COMPLETED 
- [x] ✅ Document proper upgrade approach that maintains functionality - COMPLETED

**Priority 1: Local Fork Development Resolution** (NEW TOP PRIORITY)
- [ ] **CRITICAL**: Complete ongoing fork development before major upgrades
- [ ] Coordinate nixpkgs writers-auto-detection feature for upstream submission
- [ ] Resolve home-manager autoValidate feature development  
- [ ] Complete NixOS-WSL plugin shim integration work
- [ ] Plan fork synchronization strategy with upstream

**Priority 2: Infrastructure Updates** (DEFERRED - awaiting fork resolution)
- [x] ✅ Review pytest + NixOS test framework integration documentation (NIXOS-PYTEST.md) - COMPLETED
- [ ] Plan upgrade strategy that maintains fork development work (LOW PRIORITY)

**Note**: Major package upgrades deferred until active fork development is resolved to prevent conflicts.

**Priority 3: Test Infrastructure Development** (DEFERRED - post fork resolution)
- [ ] Design test infrastructure architecture for unified Nix configuration
- [ ] Create tests/lib.nix helper for NixOS test framework integration
- [ ] Add checks output to flake.nix for test integration
- [ ] Create base VM configuration template for test environments

**Priority 4: Core Validation Tests** (DEFERRED - post fork resolution)
- [ ] Implement Home Manager configuration validation tests
- [ ] Test Claude Code configuration deployment across platforms
- [ ] Validate shell environment configurations (zsh, bash) in test VMs
- [ ] Create development tools validation tests (git, editors, etc.)

**Priority 5: Multi-Platform Testing** (DEFERRED - post fork resolution)
- [ ] Create multi-architecture testing (x86_64, aarch64) validation
- [ ] Develop WSL-specific functionality tests with nested virtualization
- [ ] Implement cross-platform package compatibility tests

**Priority 6: CI/CD & Documentation** (DEFERRED - post fork resolution)  
- [ ] Set up CI/CD integration for automated test execution
- [ ] Document testing workflow and debugging procedures

**Priority 7: pytest Integration** (DEFERRED - post fork resolution)
- [ ] Implement pytest fixture interface for NixOS test framework (surgical integration)
- [ ] Complete NIXOS-PYTEST.md implementation plan

## 🎯 **SESSION CONTEXT**

**Current Focus**: Local fork development resolution and coordination before major system upgrades
**Critical Priority**: Complete ongoing feature development in nixpkgs, home-manager, and NixOS-WSL forks
**Strategic Goal**: Successful upstream contribution of developed features before major package updates

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

