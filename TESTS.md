# Overview of Tests in nixcfg Repository

  Why tests-flake.nix Was Necessary

  The tests-flake.nix file was created to bridge the gap between Home Manager module context and flake checks context. Here's
  why:

  1. Context Mismatch: The validated scripts tests are defined within Home Manager modules (bash.nix), which have access to
  special arguments like mkValidatedScript, mkBashScript, etc. These are provided by the Home Manager module system.
  2. Flake Checks Requirements: Flake checks (flake-modules/tests.nix) operate in a different context - they need plain
  derivations that can be built by Nix, without Home Manager's special module system.
  3. Bridge Solution: tests-flake.nix acts as an adapter that:
    - Imports the bash scripts module with minimal dependencies
    - Provides the required arguments (mkValidatedScript, etc.) that would normally come from Home Manager
    - Exports the tests as plain derivations that flake checks can consume

  Test Infrastructure in Your Repository

  Your nixcfg repo has a comprehensive multi-layered testing architecture:

  1. Test Types

  - Configuration Evaluation Tests (eval-*): Verify NixOS configurations can be evaluated without errors
  - Module Integration Tests: Check that custom modules integrate correctly
  - Service Configuration Tests: Ensure services like SSH are properly configured
  - Build Dry-Run Tests: Verify configurations can be built (without actually building)
  - Script Validation Tests: Test individual bash/python scripts for syntax and behavior
  - VM-Based Integration Tests: Full system tests using NixOS test framework

  2. Test Locations

  tests/                          # Standalone test modules
  ├── ssh-auth.nix               # SSH authentication tests
  ├── sops-nix.nix              # SOPS encryption tests
  ├── sops-simple.nix           # Simple SOPS roundtrip test
  └── integration/              # VM-based integration tests
      ├── ssh-management.nix
      ├── sops-deployment.nix
      └── bitwarden-mock.nix

  flake-modules/
  └── tests.nix                  # Main test orchestration

  home/modules/validated-scripts/
  ├── tests.nix                  # Test utilities for scripts
  ├── tests-flake.nix           # Bridge for flake consumption
  └── bash.nix                  # Contains actual script tests

  Nix Best Practices for Running Tests

  Method 1: Flake Checks (Recommended)

  # Run ALL tests
  nix flake check

  # Continue even if some fail
  nix flake check --keep-going

  # Run specific test
  nix build .#checks.x86_64-linux.eval-thinky-nixos

  # Show detailed errors
  nix build .#checks.x86_64-linux.test-name --show-trace

  Pros:
  - Native Nix integration
  - Automatic caching
  - Parallel execution
  - CI/CD friendly

  Method 2: Test Applications

  # Interactive test runner with colored output
  nix run .#test-all

  # Run only integration tests
  nix run .#test-integration

  # Generate configuration snapshot
  nix run .#snapshot

  # Quick regression test
  nix run .#regression-test

  Pros:
  - Better formatted output
  - Interactive feedback
  - Grouped test execution

  Method 3: Direct Test Execution

  # Build and run individual test derivation
  nix-build -A checks.x86_64-linux.ssh-simple-test

  # Run VM-based test
  nix-build -A checks.x86_64-linux.ssh-integration-test

  Pros:
  - Direct control
  - Useful for debugging
  - Can inspect build artifacts

  Test Framework Features

  1. Caching: Test results are cached by Nix, only re-running when inputs change
  2. Parallelism: Tests automatically run in parallel based on available cores
  3. Reproducibility: Tests are deterministic and isolated
  4. VM Tests: Full system integration tests using NixOS test framework
  5. Validation: Both syntax checking and runtime behavior testing

  Current Issue

  The error shown indicates that the validated scripts tests are failing because the bash.nix module expects arguments
  (mkValidatedScript) that aren't being provided properly through tests-flake.nix. This is exactly the problem that
  tests-flake.nix was meant to solve - it needs to properly instantiate the module context.

  Best Practice Summary

  For your workflow:
  1. Development: Use nix flake check --keep-going to run all tests
  2. Debugging: Use specific test builds with --show-trace
  3. CI/CD: Use nix flake check in GitHub Actions
  4. Before commits: Run nix run .#regression-test for quick validation

# CRITICAL ANALYSIS: Current Test Organization

Based on my comprehensive exploration of your repository, here's the breakdown of test locations and why `flake-modules/tests.nix` is so large. Your tests are spread across **3 main locations**:

1. **`flake-modules/tests.nix` (2,412 lines)** - PRIMARY ACTIVE TESTS
   - All 30+ tests that run via `nix flake check`
   - Contains configuration evaluation, module integration, and **black-box functional tests**
   - This is where the tmux-session-picker runtime tests are located

2. **`home/modules/validated-scripts/` (3,700+ lines across multiple files)** - ORPHANED TESTS
   - `bash.nix` contains 72+ test definitions as `passthru.tests` on script derivations
   - Tests are **defined but not collected** into flake checks
   - Test collection function exists in `default.nix` but is **never called**

3. **`tests/` directory (6 files)** - LEGACY/UNUSED
   - SOPS, SSH, integration tests
   - **Not imported** into flake at all

### **Why flake-modules/tests.nix is So Big**

The file is large because it's doing **ALL the testing work** for your entire repository:

- **Configuration evaluation tests** (checking nixos/home-manager configs build)
- **Module integration tests** (checking modules work together)
- **Service configuration tests** (SSH, users, etc.)
- **Cross-module integration** (WSL + base, SOPS + base, etc.)
- **Script functionality tests** (tmux-session-picker black-box tests with 9+ sub-tests each)

### **The Core Problem: Architectural Mismatch**

You have tests in two places that **should be connected but aren't**:

```
❌ CURRENT STATE:
┌─────────────────────────────────────┐
│ flake-modules/tests.nix (2,412 lines)│  ← All tests run here
│ - Config tests                       │
│ - Module tests                       │
│ - Script functional tests (manual)   │  ← These are DUPLICATED!
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ validated-scripts/bash.nix          │  ← Tests defined here
│ - Scripts with passthru.tests       │
│ - 72+ test derivations               │  ← But NEVER RUN!
└─────────────────────────────────────┘
```

### **The nixpkgs Pattern (What You Should Have)**

```
✅ CORRECT PATTERN:
┌─────────────────────────────────────┐
│ home/common/tmux.nix                │
│ tmux-session-picker = writeShellApp {│
│   passthru.tests = {                │  ← Tests WITH derivation
│     help = ...;                     │
│     args = ...;                     │
│   };                                │
│ }                                   │
└─────────────────────────────────────┘
           ↓ (auto-collected)
┌─────────────────────────────────────┐
│ flake-modules/tests.nix (300 lines) │  ← Much smaller!
│ checks = collectAllScriptTests      │
│   // moduleIntegrationTests;        │  ← Just collection
└─────────────────────────────────────┘
```

### **Specific Findings About Your Tests**

**In `flake-modules/tests.nix`:**
- Lines 1-500: Configuration and module tests (appropriate location)
- Lines 500-2412: **Script functional tests that should be `passthru.tests`** on the script derivations in `home/common/*.nix`

**In `validated-scripts/bash.nix`:**
- 72+ test derivations defined as `passthru.tests`
- Collection function exists: `collectScriptTests`
- **Problem**: Never exported to flake checks, so tests never run

### **Action Items to Fix This**

1. **Move script tests to their derivations** in `home/common/*.nix`:
   ```nix
   # home/common/tmux.nix
   tmux-session-picker = pkgs.writeShellApplication {
     name = "tmux-session-picker";
     text = builtins.readFile ../files/bin/tmux-session-picker;
     runtimeInputs = [ ... ];
     passthru.tests = {
       help-availability = pkgs.runCommand ... { } ''...'';
       argument-validation = pkgs.runCommand ... { } ''...'';
     };
   };
   ```

2. **Create test collection in flake-modules/tests.nix**:
   ```nix
   checks =
     # Configuration/module tests
     { ... }
     //
     # Auto-collected script tests
     (lib.concatMapAttrs collectScriptTests [
       config.home.common.tmux
       config.home.common.git
       # ... other modules
     ]);
   ```

3. **Result**: `flake-modules/tests.nix` shrinks from 2,412 lines to ~300-500 lines
