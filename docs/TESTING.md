# NixOS Configuration Testing

## Overview

This repository uses Nix-native testing integrated directly into the flake configuration. All tests are defined as flake checks and can be run using standard Nix commands.

## Benefits Over Script-Based Testing

1. **No External Dependencies**: Tests run in pure Nix environments
2. **Cached Results**: Nix caches test results, only re-running when inputs change
3. **Parallel Execution**: Tests run in parallel automatically
4. **CI/CD Integration**: Works seamlessly with GitHub Actions, Hydra, etc.
5. **Type Safety**: Nix evaluation catches errors at build time
6. **Reproducibility**: Tests are deterministic

## Quick Start

### Run All Tests
```bash
# Fastest: Run all tests with the test runner
nix run '.#apps.x86_64-linux.test-all'

# Alternative: Use flake check (includes unrelated checks)
nix flake check --keep-going
```

### Run Specific Test Categories
```bash
# Unit tests only
nix build '.#checks.x86_64-linux.sops-simple-test' -L
nix build '.#checks.x86_64-linux.ssh-simple-test' -L

# Integration tests only (requires KVM)
nix run '.#apps.x86_64-linux.test-integration'

# Quick regression check
nix run '.#apps.x86_64-linux.regression-test'
```

## GitHub Actions Local Validation

### Setup
```bash
# 1. Generate configuration file
nix run .#init-github-actions-config

# 2. Configure which jobs to run (edit github-actions.nix)
# 3. GitHub Actions now included in flake check
nix flake check
```

### Configuration
Edit `github-actions.nix` to control which jobs run:

```nix
{
  enable = true; # Enable GitHub Actions validation in flake checks
  
  jobs = {
    # Fast security checks (~30s each)
    verify-sops = { enable = true; timeout = 30; };
    audit-permissions = { enable = true; timeout = 30; };
    
    # Comprehensive security checks (~2min each)  
    gitleaks = { enable = true; timeout = 120; };
    semgrep = { enable = true; timeout = 120; };
    trufflehog = { enable = false; timeout = 120; }; # Disabled
  };
}
```

### Usage
```bash
# View current configuration
nix run .#show-github-actions-config

# Run GitHub Actions explicitly
nix build .#checks.x86_64-linux.github-actions

# Run as part of all checks (when enabled)
nix flake check
```

## Prerequisites

### System Requirements
- **CPU**: x86_64 Linux system
- **RAM**: Minimum 2GB (4GB recommended for integration tests)
- **Disk**: 5GB free space for test artifacts
- **Nix**: Version 2.18+ with flakes enabled

### For Integration Tests (VM-Based)
- **KVM Support**: Required for NixOS VM tests
  ```bash
  # Check KVM availability
  ls /dev/kvm
  # If missing, enable virtualization in BIOS
  ```
- **Permissions**: User must be in `kvm` group
  ```bash
  sudo usermod -a -G kvm $USER
  # Log out and back in for changes to take effect
  ```

### For GitHub Actions
- **Podman**: `systemctl --user start podman.socket`
- **Act**: Available in development shell
- **GitHub workflows**: Must have `.github/workflows/` directory

## Test Architecture

### Test Infrastructure Overview
```
tests/
├── Unit Tests (Direct)
│   ├── sops-simple.nix       - Basic SOPS functionality
│   ├── ssh-auth.nix          - SSH authentication components  
│   └── sops-nix.nix          - Advanced SOPS operations
│
├── Integration Tests (VM-Based)
│   ├── ssh-management.nix    - Full SSH key management pipeline
│   ├── sops-deployment.nix   - SOPS-NiX deployment scenarios
│   └── bitwarden-mock.nix    - Mock Bitwarden service
│
└── flake-modules/tests.nix   - Test orchestration & runners
```

### Test Categories

#### 1. Configuration Evaluation Tests
- **Purpose**: Ensure all host configurations can be evaluated without errors
- **Tests**: `eval-thinky-nixos`, `eval-potato`, `eval-nixos-wsl-minimal`, `eval-mbp`
- **What they catch**: Syntax errors, missing modules, undefined options

#### 2. Module Integration Tests
- **Purpose**: Verify that custom modules integrate correctly
- **Tests**: `module-base-integration`, `module-wsl-common-integration`
- **What they catch**: Module conflicts, option collisions, dependency issues

#### 3. Service Configuration Tests
- **Purpose**: Ensure critical services are properly configured
- **Tests**: `ssh-service-configured`, `user-tim-configured`
- **What they catch**: Service misconfigurations, missing users/groups

#### 4. Unit Tests
Fast tests that validate individual components:

```bash
# SOPS encryption/decryption
nix build '.#checks.x86_64-linux.sops-simple-test' -L

# SSH key management
nix build '.#checks.x86_64-linux.ssh-simple-test' -L

# Configuration evaluation
nix build '.#checks.x86_64-linux.eval-thinky-nixos' -L
```

#### 5. Integration Tests
VM-based tests that validate complete system functionality:

```bash
# SSH service integration
nix build '.#checks.x86_64-linux.ssh-integration-test' -L

# SOPS deployment integration  
nix build '.#checks.x86_64-linux.sops-integration-test' -L

# Run all integration tests
nix run '.#apps.x86_64-linux.test-integration'
```

#### 6. Security Tests
Validate security configurations and secrets management:

```bash
# GitHub Actions security checks (if enabled)
nix build '.#checks.x86_64-linux.github-actions' -L

# SOPS encryption validation
nix build '.#checks.x86_64-linux.sops-simple-test' -L

# SSH public keys registry
nix build '.#checks.x86_64-linux.ssh-public-keys-registry' -L
```

#### 7. Build Tests
Ensure configurations can be built:

```bash
# Dry-run builds (configuration evaluation)
nix build '.#checks.x86_64-linux.build-thinky-nixos-dryrun' -L
nix build '.#checks.x86_64-linux.build-nixos-wsl-minimal-dryrun' -L
```

#### 8. Cross-Module Tests
Verify module interactions and dependencies:

```bash
# WSL and base module interaction
nix build '.#checks.x86_64-linux.cross-module-wsl-base' -L

# SOPS and base module integration
nix build '.#checks.x86_64-linux.cross-module-sops-base' -L

# Home Manager integration
nix build '.#checks.x86_64-linux.cross-module-home-manager' -L
```

## Test Apps

### Interactive Test Runner
```bash
# Run all tests with progress and colored output
nix run '.#apps.x86_64-linux.test-all'
```

### Integration Test Runner  
```bash
# Run only VM-based integration tests
nix run '.#apps.x86_64-linux.test-integration'
```

### Regression Test Runner
```bash
# Quick check that all configurations still evaluate
nix run '.#apps.x86_64-linux.regression-test'
```

### Configuration Snapshot
```bash
# Generate configuration snapshots for comparison
nix run '.#apps.x86_64-linux.snapshot'
```

## Git Integration

### Pre-commit Hooks
Automatically format and validate on commit:

```bash
# Setup git hooks (archived - see .archive/scripts/setup-git-hooks)
# Note: Git hooks are already configured via Nix

# Test pre-commit validation
git add . && git commit -m "test" --dry-run
```

### Pre-push Validation
Automatic validation before pushing:

```bash
# Fast validation (default)
git push

# Skip validation
git push --no-verify

# Test pre-push hook
git push --dry-run
```

## Debugging Test Failures

### Enable Verbose Output
```bash
# Show detailed build logs
nix build '.#checks.x86_64-linux.test-name' -L

# Show trace on errors
nix build '.#checks.x86_64-linux.test-name' --show-trace

# Keep failed build directory
nix build '.#checks.x86_64-linux.test-name' --keep-failed
```

### Interactive VM Debugging
For integration tests, you can interact with the test VM:

```bash
# Build the test but don't run it
nix build '.#checks.x86_64-linux.ssh-integration-test' --keep-failed

# Find the test driver script
ls -la /tmp/nix-build-*/

# Add interactive() in the test script where you want to debug
```

### Common Issues & Solutions

#### Issue: "error: getting attributes of path '/dev/kvm': No such file or directory"
**Solution**: Enable KVM support
```bash
# Check if virtualization is enabled in BIOS
sudo dmesg | grep -i kvm

# Load KVM module
sudo modprobe kvm-intel  # For Intel CPUs
sudo modprobe kvm-amd    # For AMD CPUs
```

#### Issue: "Permission denied" accessing /dev/kvm
**Solution**: Add user to kvm group
```bash
sudo usermod -a -G kvm $USER
# Log out and back in
```

#### Issue: Test hangs or times out
**Solution**: Check resource limits
```bash
# Increase VM memory in test file
# Edit virtualisation.memorySize in test nodes

# Run with timeout
timeout 300 nix build '.#checks.x86_64-linux.test-name' -L
```

#### Issue: GitHub Actions Dependencies Missing
```bash
# Install dependencies
nix shell nixpkgs#act nixpkgs#podman

# Start podman socket
systemctl --user start podman.socket
```

#### Issue: Out of Disk Space
```bash
# Clean up test artifacts
nix-collect-garbage -d

# Remove old VM images
rm -rf ~/.cache/nixos-test/
```

## Writing New Tests

### 1. Create Test File
Add new test in `tests/` directory:

```nix
# tests/my-new-test.nix
{ pkgs, lib, ... }:

pkgs.runCommand "my-new-test" {
  meta = {
    description = "Test description";
    timeout = 30;
  };
} ''
  echo "Running test..."
  # Test logic here
  touch $out
''
```

### 2. Register in Test Module
Add to `flake-modules/tests.nix`:

```nix
checks = {
  # ... existing tests ...
  my-new-test = import ../tests/my-new-test.nix { 
    inherit pkgs; 
    lib = pkgs.lib; 
  };
};
```

### 3. Run New Test
```bash
nix build '.#checks.x86_64-linux.my-new-test' -L
```

## Continuous Integration

### GitHub Actions
The repository includes automated testing via GitHub Actions:

- **Security Scan**: Gitleaks, TruffleHog, Semgrep
- **SOPS Validation**: Ensure all secrets are encrypted
- **Permission Audit**: Check file permissions
- **Configuration Tests**: Validate all host configurations

### Local CI Simulation
```bash
# Enable GitHub Actions validation
nix run .#init-github-actions-config

# Run same checks as CI
nix build .#checks.x86_64-linux.github-actions
```

## Best Practices

### Test-Driven Development
1. Write tests for new modules/configurations
2. Run tests locally before committing
3. Use integration tests for complex interactions
4. Validate security implications

### Performance Testing
1. Measure build times: `time nix build`
2. Profile memory usage during tests
3. Monitor test execution times
4. Optimize slow tests

### Security Testing
1. Enable GitHub Actions validation
2. Test SOPS encryption/decryption
3. Validate SSH key management
4. Review file permissions regularly

### Debugging Failures
1. Use `-L` flag for detailed logs
2. Check `/tmp/nixos-test-*` for VM artifacts
3. Enable debug mode for complex issues
4. Isolate failing components

## Test Maintenance

### Updating Test Baselines
When intentionally changing configuration:

```nix
# Update snapshot baseline in flake-modules/tests.nix
snapshotBaseline = {
  "thinky-nixos" = { stateVersion = "25.05"; };  # Updated version
  # ...
};
```

### Marking Tests as Skipped
For temporarily broken tests:

```nix
# In test file
{ pkgs, lib, ... }:
pkgs.runCommand "test-name" {
  meta = {
    description = "Test description";
    broken = true;  # Mark as broken
    timeout = 30;
  };
} ''
  echo "SKIPPED: Test currently broken due to issue #123"
  touch $out
''
```

## Performance Tips

### Parallel Execution
```bash
# Run tests in parallel (automatic with test runners)
nix build '.#checks.x86_64-linux.test1' '.#checks.x86_64-linux.test2' -L

# Limit parallel jobs
nix build '.#checks.x86_64-linux.test-name' -L --max-jobs 2
```

### Caching
```bash
# Use binary cache for faster builds
nix build '.#checks.x86_64-linux.test-name' \
  --extra-substituters https://cache.nixos.org \
  --extra-trusted-public-keys cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

### Selective Testing
```bash
# Test only what changed
# First, check what would be rebuilt
nix build '.#checks.x86_64-linux.test-name' --dry-run

# Skip expensive tests during development
# Run only unit tests
for test in ssh-simple-test sops-simple-test; do
  nix build ".#checks.x86_64-linux.$test" -L
done
```

## Migration from Script-Based Testing

The old script-based testing has been replaced with integrated Nix tests. All functionality is preserved:

| Old Script Command | New Nix Command |
|-------------------|-----------------|
| `./test-configurations.sh` | `nix run .#test-all` |
| Manual evaluation tests | `nix flake check` |
| Config snapshot | `nix run .#snapshot` |
| Individual test | `nix build .#checks.x86_64-linux.TEST_NAME` |

## Feature Coverage Matrix

### Core Modules Coverage

| Module | Unit Tests | Integration Tests | Coverage % | Status |
|--------|------------|-------------------|------------|--------|
| **SSH Public Keys Registry** | ✅ ssh-public-keys-registry | ✅ ssh-management.nix | 95% | ✅ Complete |
| **Bootstrap SSH Keys** | ✅ ssh-simple-test | ✅ ssh-management.nix | 90% | ✅ Complete |
| **SOPS-NiX Integration** | ✅ sops-simple-test, sops-nix | ✅ sops-deployment.nix | 95% | ✅ Complete |
| **Base Module** | ✅ module-base-integration | ✅ All integration tests | 100% | ✅ Complete |
| **WSL Common Module** | ✅ module-wsl-common-integration | ✅ All integration tests | 100% | ✅ Complete |

### Security-Critical Paths

| Security Feature | Test Coverage | Test Type | Status |
|------------------|---------------|-----------|--------|
| SSH Key Format Validation | ✅ Tested | Unit | ✅ Pass |
| Key Storage Permissions | ✅ Tested | Integration | ✅ Pass |
| SOPS Encryption/Decryption | ✅ Tested | Both | ✅ Pass |
| Age Key Management | ✅ Tested | Integration | ✅ Pass |
| Authorized Keys Distribution | ✅ Tested | Integration | ✅ Pass |
| Secret Permissions (0400) | ✅ Tested | Integration | ✅ Pass |
| User/Group Ownership | ✅ Tested | Unit | ✅ Pass |

### Configuration Tests

| Configuration | Evaluation Test | Build Test | Integration Test | Status |
|---------------|-----------------|------------|------------------|--------|
| thinky-nixos | ✅ eval-thinky-nixos | ✅ build-thinky-nixos-dryrun | ✅ All | ✅ Complete |
| potato | ✅ eval-potato | ❌ None | ❌ None | ⚠️ Basic only |
| nixos-wsl-minimal | ✅ eval-nixos-wsl-minimal | ✅ build-nixos-wsl-minimal-dryrun | ✅ Partial | ✅ Good |
| mbp | ✅ eval-mbp | ❌ None | ❌ None | ⚠️ Basic only |

## Summary

The test suite provides comprehensive validation of the NixOS configuration system. Use the test runners for quick validation, and individual test commands for debugging. Integration tests require KVM support but provide the most thorough validation. Always run regression tests before committing changes.

For questions or issues, check the troubleshooting section or examine the test source files in `tests/` and `flake-modules/tests.nix`.