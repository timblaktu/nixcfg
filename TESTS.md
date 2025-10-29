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
