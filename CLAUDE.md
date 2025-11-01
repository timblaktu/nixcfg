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

1. `/home/tim/src/nixpkgs` - Local nixpkgs fork
2. `/home/tim/src/home-manager` - Local home-manager fork  
3. `/home/tim/src/NixOS-WSL` - WSL-specific configurations

## 📋 **CURRENT TASKS** (2025-10-31)

**Priority 0: CRITICAL CORRECTION NEEDED**
- [ ] **URGENT**: Revert destructive "upgrade" that disabled core functionality
- [ ] Restore working state with local nixpkgs fork and full feature set
- [ ] Document proper upgrade approach that maintains functionality

**Priority 1: Proper Infrastructure Updates** (DEFERRED until correction)
- [x] ✅ Review pytest + NixOS test framework integration documentation (NIXOS-PYTEST.md) - COMPLETED
- [ ] Plan proper upgrade strategy that maintains all functionality

**Note**: Session ready for development work. NIXOS-PYTEST.md contains complete implementation plan for surgical pytest integration at testScript interface layer.

**Priority 2: Test Infrastructure Development** 
- [ ] Design test infrastructure architecture for unified Nix configuration
- [ ] Create tests/lib.nix helper for NixOS test framework integration
- [ ] Add checks output to flake.nix for test integration
- [ ] Create base VM configuration template for test environments

**Priority 3: Core Validation Tests**
- [ ] Implement Home Manager configuration validation tests
- [ ] Test Claude Code configuration deployment across platforms
- [ ] Validate shell environment configurations (zsh, bash) in test VMs
- [ ] Create development tools validation tests (git, editors, etc.)

**Priority 4: Multi-Platform Testing**
- [ ] Create multi-architecture testing (x86_64, aarch64) validation
- [ ] Develop WSL-specific functionality tests with nested virtualization
- [ ] Implement cross-platform package compatibility tests

**Priority 5: CI/CD & Documentation**
- [ ] Set up CI/CD integration for automated test execution
- [ ] Document testing workflow and debugging procedures

## 🎯 **SESSION CONTEXT**

**Current Focus**: NixOS Test Framework with surgical pytest fixture integration for multi-platform validation
**Innovation Goal**: "Dog food" pytest fixture interface before upstream contribution (RFC candidate)

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

