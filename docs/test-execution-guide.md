# Test Execution Guide

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

## Test Categories

### 1. Unit Tests
Fast, isolated tests for individual components.

```bash
# SSH authentication tests
nix build '.#checks.x86_64-linux.ssh-simple-test' -L

# SOPS functionality tests  
nix build '.#checks.x86_64-linux.sops-simple-test' -L

# Module integration tests
nix build '.#checks.x86_64-linux.module-base-integration' -L
nix build '.#checks.x86_64-linux.module-wsl-common-integration' -L
```

**Expected Output**:
```
=== Simple SSH Test ===
✓ ssh-keygen is available
✓ Successfully generated test SSH key

=== Test Completed ===
```

### 2. Configuration Evaluation Tests
Verify that NixOS configurations can be evaluated without errors.

```bash
# Test individual host configurations
nix build '.#checks.x86_64-linux.eval-thinky-nixos' -L
nix build '.#checks.x86_64-linux.eval-potato' -L
nix build '.#checks.x86_64-linux.eval-nixos-wsl-minimal' -L
nix build '.#checks.x86_64-linux.eval-mbp' -L
```

**Expected Output**:
```
Testing thinky-nixos configuration evaluation...
Configuration state version: 24.11
✅ thinky-nixos evaluation passed
```

### 3. Integration Tests (VM-Based)
Comprehensive tests using full NixOS VMs.

```bash
# SSH key management pipeline test
nix build '.#checks.x86_64-linux.ssh-integration-test' -L

# SOPS deployment test
nix build '.#checks.x86_64-linux.sops-integration-test' -L

# Run all integration tests
nix run '.#apps.x86_64-linux.test-integration'
```

**Expected Output**:
```
🔬 Running Integration Test Suite (VM-based)
============================================
Note: These tests require KVM/virtualization support

Starting ssh-integration-test...
[VM output and test results]
✅ ssh-integration-test PASSED

Starting sops-integration-test...
[VM output and test results]
✅ sops-integration-test PASSED
```

### 4. Cross-Module Tests
Verify module interactions and dependencies.

```bash
# WSL and base module interaction
nix build '.#checks.x86_64-linux.cross-module-wsl-base' -L

# SOPS and base module integration
nix build '.#checks.x86_64-linux.cross-module-sops-base' -L

# Home Manager integration
nix build '.#checks.x86_64-linux.cross-module-home-manager' -L
```

## Test Runners

### test-all
Comprehensive test suite runner with colored output.

```bash
nix run '.#apps.x86_64-linux.test-all'
```

**Features**:
- Runs all test categories
- Colored pass/fail indicators
- Summary statistics
- Exit code indicates overall success

### test-integration
Focused runner for VM-based integration tests.

```bash
nix run '.#apps.x86_64-linux.test-integration'
```

**Features**:
- Only runs VM tests
- Detailed output with `-L` flag
- KVM requirement checking
- Progress indicators

### regression-test
Quick check that all configurations still evaluate.

```bash
nix run '.#apps.x86_64-linux.regression-test'
```

**Features**:
- Fast evaluation checks
- Continues on failure (`--keep-going`)
- Useful before commits
- Minimal output

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

# Run interactively (requires modification of test script)
# Add `interactive()` in the test script where you want to debug
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

#### Issue: "error: flake check failure in fcitx5"
**Solution**: Known unrelated issue, use targeted tests
```bash
# Instead of 'nix flake check', run specific tests
nix run '.#apps.x86_64-linux.test-all'
```

## Adding New Tests

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

## Test Output Locations

### Build Results
```bash
# Test outputs are symlinked to result
./result

# View test output
cat result

# Clean up result symlinks
rm result*
```

### Log Files
```bash
# Nix build logs
~/.cache/nix/log/

# Find specific test log
nix log '.#checks.x86_64-linux.test-name'
```

### Coverage Reports
```bash
# Generate snapshot for analysis
nix run '.#apps.x86_64-linux.snapshot'

# View snapshots
ls -la config-snapshots/
cat config-snapshots/snapshot-*/
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

## Continuous Integration

### GitHub Actions Example
```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: cachix/install-nix-action@v22
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes
      - name: Run tests
        run: |
          nix run '.#apps.x86_64-linux.test-all'
```

### Pre-commit Hook
```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit

echo "Running regression tests..."
nix run '.#apps.x86_64-linux.regression-test' || {
  echo "Tests failed! Commit aborted."
  exit 1
}
```

## Test Maintenance

### Updating Test Baselines
When intentionally changing configuration:

```bash
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

## Comprehensive Troubleshooting Guide

### Test Failure Patterns

#### Pattern: Configuration Evaluation Failures
**Symptoms**: 
- `error: attribute 'xxx' missing`
- `error: infinite recursion encountered`
- `error: assertion failed`

**Common Causes & Solutions**:

1. **Missing module import**
   ```nix
   # Check hosts/*/default.nix for missing imports
   imports = [
     ../../modules/nixos/base.nix  # Add missing module
   ];
   ```

2. **Circular dependencies**
   ```bash
   # Trace the dependency chain
   nix build '.#nixosConfigurations.host' --show-trace 2>&1 | grep -A5 "infinite recursion"
   ```

3. **Assertion failures**
   ```bash
   # Find the assertion
   nix eval '.#nixosConfigurations.host.config.assertions' --json | jq
   ```

#### Pattern: VM Test Failures
**Symptoms**:
- `error: virtual machine didn't start`
- `timeout waiting for unit`
- `command failed with exit code`

**Solutions**:

1. **Increase timeout**
   ```python
   # In testScript
   machine.wait_for_unit("service", timeout=120)
   ```

2. **Debug VM state**
   ```python
   # Add to testScript
   print(machine.execute("systemctl status service")[1])
   print(machine.execute("journalctl -u service")[1])
   ```

3. **Interactive debugging**
   ```python
   # Drop to interactive shell
   machine.shell_interact()
   ```

#### Pattern: Resource Exhaustion
**Symptoms**:
- `error: out of memory`
- `No space left on device`
- Test hangs indefinitely

**Solutions**:

1. **Memory issues**
   ```nix
   # Reduce VM memory
   virtualisation.memorySize = 512;  # was 1024
   
   # Or increase system resources
   ulimit -v unlimited
   ```

2. **Disk space**
   ```bash
   # Clean Nix store
   nix-collect-garbage -d
   
   # Remove old test results
   rm -rf result* /tmp/nix-build-*
   ```

3. **CPU limits**
   ```bash
   # Limit parallel builds
   nix build '.#checks.x86_64-linux.test' --max-jobs 2
   ```

### Module-Specific Issues

#### SSH Module Tests
**Issue**: Key generation fails
```bash
# Debug
nix build '.#checks.x86_64-linux.ssh-simple-test' -L 2>&1 | grep -i error

# Fix: Ensure openssh is available
buildInputs = with pkgs; [ openssh ];
```

**Issue**: Key validation fails
```bash
# Check key format
echo "$test_key" | ssh-keygen -l -f -

# Fix: Update validation regex
if [[ "$key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
```

#### SOPS Module Tests
**Issue**: Age key not found
```bash
# Check age key generation
age-keygen -o test.key

# Fix: Ensure age is in buildInputs
buildInputs = with pkgs; [ age sops ];
```

**Issue**: Decryption fails
```bash
# Debug SOPS
SOPS_AGE_KEY_FILE=key.txt sops -d secret.yaml

# Fix: Check key permissions
chmod 600 key.txt
```

#### Integration Test Issues
**Issue**: Bitwarden mock not working
```python
# Debug in testScript
print(machine.succeed("rbw list"))

# Fix: Ensure mock script is executable
chmod +x ${mockBitwarden}/bin/rbw
```

### Environment-Specific Problems

#### WSL Environment
**Issue**: Tests fail in WSL
```bash
# Check WSL version
wsl --version

# Solutions:
# 1. Enable systemd in WSL2
echo -e "[boot]\nsystemd=true" | sudo tee /etc/wsl.conf

# 2. Use WSL2 (not WSL1)
wsl --set-version <distro> 2
```

#### Darwin/macOS
**Issue**: Linux-specific tests fail on macOS
```nix
# Skip on Darwin
meta = {
  platforms = lib.platforms.linux;
};

# Or add Darwin-specific logic
if pkgs.stdenv.isDarwin then
  # macOS-specific test
else
  # Linux test
```

### Performance Optimization

#### Slow Test Execution
```bash
# Profile test execution
time nix build '.#checks.x86_64-linux.test' -L

# Solutions:
# 1. Use binary cache
nix build '.#checks.x86_64-linux.test' \
  --option substituters "https://cache.nixos.org" \
  --option trusted-public-keys "cache.nixos.org-1:..."

# 2. Parallel execution
nix build '.#checks.x86_64-linux.test1' '.#checks.x86_64-linux.test2'

# 3. Reduce VM resources
virtualisation.memorySize = 256;  # Minimum viable
```

### Advanced Debugging Techniques

#### Trace Nix Evaluation
```bash
# Full trace
NIX_SHOW_TRACE=1 nix build '.#checks.x86_64-linux.test'

# Specific attribute
nix eval '.#checks.x86_64-linux.test' --show-trace
```

#### Inspect Test Derivation
```bash
# Show derivation
nix show-derivation '.#checks.x86_64-linux.test'

# Inspect build script
nix develop '.#checks.x86_64-linux.test' -c bash -c 'cat $stdenv/setup'
```

#### Debug VM Network
```python
# In testScript
print(machine.succeed("ip addr"))
print(machine.succeed("ss -tulpn"))
print(machine.succeed("ping -c 1 8.8.8.8"))
```

#### Analyze Test Logs
```bash
# Find test logs
find ~/.cache/nix/log -name "*.drv" -mtime -1

# View specific log
nix log '.#checks.x86_64-linux.test'

# Parse structured output
nix build '.#checks.x86_64-linux.test' -L --json | jq
```

### Recovery Procedures

#### Reset Test Environment
```bash
# Clean everything
rm -rf result* /tmp/nix-build-*
nix-collect-garbage -d
nix-store --verify --check-contents

# Rebuild from scratch
nix build '.#checks.x86_64-linux.test' --rebuild
```

#### Fix Corrupted Store
```bash
# Verify and repair
nix-store --verify --check-contents --repair

# Nuclear option: clear and rebuild
sudo rm -rf /nix/store/.links
nix-store --gc
nix-store --optimise
```

## Summary

The test suite provides comprehensive validation of the SSH key management system. Use the test runners for quick validation, and individual test commands for debugging. Integration tests require KVM support but provide the most thorough validation. Always run regression tests before committing changes.

For questions or issues, check the troubleshooting section or examine the test source files in `tests/` and `flake-modules/tests.nix`.