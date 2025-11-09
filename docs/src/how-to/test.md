# Testing Guide

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

### Overview
Run the same security checks locally that run in CI to catch issues before pushing.

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

### Prerequisites for GitHub Actions
- **Podman**: `systemctl --user start podman.socket`
- **Act**: Available in development shell
- **GitHub workflows**: Must have `.github/workflows/` directory

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
Fast tests that validate individual components:

```bash
# SOPS encryption/decryption
nix build '.#checks.x86_64-linux.sops-simple-test' -L

# SSH key management
nix build '.#checks.x86_64-linux.ssh-simple-test' -L

# Configuration evaluation
nix build '.#checks.x86_64-linux.eval-thinky-nixos' -L
nix build '.#checks.x86_64-linux.eval-potato' -L
```

### 2. Integration Tests
VM-based tests that validate complete system functionality:

```bash
# SSH service integration
nix build '.#checks.x86_64-linux.ssh-integration-test' -L

# SOPS deployment integration  
nix build '.#checks.x86_64-linux.sops-integration-test' -L

# Run all integration tests
nix run '.#apps.x86_64-linux.test-integration'
```

### 3. Module Tests
Tests for specific NixOS modules:

```bash
# Base module integration
nix build '.#checks.x86_64-linux.module-base-integration' -L

# WSL module integration
nix build '.#checks.x86_64-linux.module-wsl-common-integration' -L

# Cross-module integration
nix build '.#checks.x86_64-linux.cross-module-wsl-base' -L
```

### 4. Security Tests
Validate security configurations and secrets management:

```bash
# GitHub Actions security checks (if enabled)
nix build '.#checks.x86_64-linux.github-actions' -L

# SOPS encryption validation
nix build '.#checks.x86_64-linux.sops-simple-test' -L

# SSH public keys registry
nix build '.#checks.x86_64-linux.ssh-public-keys-registry' -L
```

### 5. Build Tests
Ensure configurations can be built:

```bash
# Dry-run builds (configuration evaluation)
nix build '.#checks.x86_64-linux.build-thinky-nixos-dryrun' -L
nix build '.#checks.x86_64-linux.build-nixos-wsl-minimal-dryrun' -L
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

## Troubleshooting

### Common Issues

#### KVM Permission Denied
```bash
# Add user to kvm group
sudo usermod -a -G kvm $USER
# Log out and back in
```

#### Integration Tests Timeout
```bash
# Increase timeout for slow systems
nix build '.#checks.x86_64-linux.ssh-integration-test' --timeout 600
```

#### GitHub Actions Dependencies Missing
```bash
# Install dependencies
nix shell nixpkgs#act nixpkgs#podman

# Start podman socket
systemctl --user start podman.socket
```

#### Out of Disk Space
```bash
# Clean up test artifacts
nix-collect-garbage -d

# Remove old VM images
rm -rf ~/.cache/nixos-test/
```

### Debug Mode
```bash
# Run tests with detailed output
nix build '.#checks.x86_64-linux.ssh-integration-test' -L --show-trace

# Enable debug logging for VM tests
NIX_DEBUG=1 nix build '.#checks.x86_64-linux.ssh-integration-test' -L
```

### Performance Optimization
```bash
# Parallel testing (faster but more resource intensive)
nix flake check -j 4

# Sequential testing (slower but more stable)
nix flake check -j 1
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