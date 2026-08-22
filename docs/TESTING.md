# NixOS Configuration Testing

## Overview

This repository uses Nix-native testing integrated directly into the flake configuration. All tests are defined as flake checks and can be run using standard Nix commands.

> **Faster integration tests:** most VM-based integration tests can run on the **systemd-nspawn
> container backend** (NixOS 26.05) instead of QEMU — ~5-7× faster boot, far less RAM. See
> [TESTING-NSPAWN.md](TESTING-NSPAWN.md) for when to use it, the host prerequisites, and how to
> write or migrate a container test (with the real VM-vs-container caveats).

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
# Tier-0 eval-regression gate (fast, no boot)
nix build '.#checks.x86_64-linux.regression-test' -L

# A fast behavioral VMTest (nspawn; no KVM)
nix build '.#checks.x86_64-linux.vm-nspawn-smoke' -L

# A QEMU behavioral VMTest (requires KVM)
nix build '.#checks.x86_64-linux.vm-boot-minimal' -L
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
│   └── test-secrets/         - SOPS fixtures (behavioral VM tests: modules/flake-parts/vm-tests.nix)
│
└── modules/flake-parts/tests.nix   - Test orchestration & runners
```

### Test Categories

> The suite was redesigned into two tiers in plan 054. The authoritative live
> list is `nix eval '.#checks.x86_64-linux' --apply builtins.attrNames`.

#### Tier 0 - Eval-regression gates (fast, no boot)
- **Purpose**: Force host/HM/module configs to evaluate; catch syntax errors,
  missing modules, undefined options, stateVersion/username drift.
- **Checks**: `regression-test` (consolidated host + HM gate), `eval-hm-modules`
  (all HM modules), `eval-nixos-modules` (all NixOS layers),
  `eval-wsl-settings-ssh-port`, and the `eval-*-toplevel` / `eval-*-tarball` /
  `eval-images-*` forcers.

```bash
nix build '.#checks.x86_64-linux.regression-test' -L
nix build '.#checks.x86_64-linux.eval-hm-modules' -L
nix build '.#checks.x86_64-linux.eval-nixos-modules' -L
nix build '.#checks.x86_64-linux.eval-thinky-nixos-toplevel' -L
```

#### Lint
```bash
nix build '.#checks.x86_64-linux.lint-formatting' -L
nix build '.#checks.x86_64-linux.lint-statix' -L
nix build '.#checks.x86_64-linux.lint-deadnix' -L
```

#### Module / integration / security checks
- **Checks**: `module-base-integration`, `module-binfmt-integration`,
  `files-module-test`, `user-configured`, `wsl-dev-team-setup-username-user`,
  `tmux-picker-syntax`, `opencode-json-syntax`, `opencode-mcp-structure`, and the
  `skill-injection-*` prompt-injection guards.

```bash
nix build '.#checks.x86_64-linux.module-base-integration' -L
nix build '.#checks.x86_64-linux.user-configured' -L
nix build '.#checks.x86_64-linux.skill-injection-awscli' -L
```

#### Tier 1 - Behavioral VMTests
Real machine tests. Boot-independent ones run on the fast systemd-nspawn
container backend (no KVM; x86_64 AND aarch64); boot/kernel/graphics/real-network
ones stay on QEMU (x86_64 KVM). See [TESTING-NSPAWN.md](TESTING-NSPAWN.md).

```bash
# nspawn (fast, ~10-20s)
nix build '.#checks.x86_64-linux.vm-nspawn-smoke' -L
nix build '.#checks.x86_64-linux.vm-hm-activation' -L
nix build '.#checks.x86_64-linux.vm-sops-secrets' -L

# QEMU (requires KVM)
nix build '.#checks.x86_64-linux.vm-boot-minimal' -L
nix build '.#checks.x86_64-linux.vm-compose-stack' -L
```

#### Package / activation builds
```bash
nix build '.#checks.x86_64-linux.activate-hm-nixvim-minimal' -L
nix build '.#checks.x86_64-linux.build-docling' -L
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
nix build '.#checks.x86_64-linux.vm-ssh-service' --keep-failed

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
# Run only the fast Tier-0 + nspawn checks
for test in regression-test vm-nspawn-smoke vm-hm-activation; do
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

> **Superseded by plan 054.** The pre-054 coverage matrix that lived here
> referenced checks and integration files (`ssh-management.nix`,
> `sops-deployment.nix`, `eval-thinky-nixos`, `build-*-dryrun`, …) that have since
> been deleted, renamed, or consolidated. For the current, authoritative
> feature/code-coverage map see **[`VMTEST-AUDIT.md`](VMTEST-AUDIT.md)** (per-module
> covering tests + depth) and the target design in
> **[`VMTEST-TARGET-DESIGN.md`](VMTEST-TARGET-DESIGN.md)**. The live check set is:
>
> ```bash
> nix eval '.#checks.x86_64-linux' --apply builtins.attrNames
> ```

## Windows-Side WSL Import Testing

The Nix-native tests validate configuration evaluation and builds on Linux. However,
the actual **import into WSL** can only be tested on a real Windows machine. The
`Test-WslImport.ps1` script fills this gap.

### Prerequisites

- Windows 10/11 with WSL installed (`wsl --status` succeeds)
- A WSL distro with Nix installed (for building tarballs)
- Passwordless `sudo` in the build distro (tarball builder requires root)
- Windows Terminal (optional, for fragment GUID validation)

### Test Scenarios

#### Full Pipeline (Build + Import + Validate + Cleanup)

```powershell
.\Test-WslImport.ps1
```

Builds the `nixos-wsl-dev-team` tarball in your Nix-enabled WSL distro, imports it
as `test-nixos-wsl-dev-team`, runs all validation checks, and cleans up.

#### Pre-Built Tarball (Import + Validate + Cleanup)

```powershell
.\Test-WslImport.ps1 -TarballPath .\nixcfg-wsl-dev-team-0.1.0.wsl -SkipBuild
```

Skips the build phase. Use this to validate a downloaded release artifact or CI
build artifact.

#### Matrix Mode (All WSL Configs)

```powershell
.\Test-WslImport.ps1 -All
```

Discovers all `nixosConfigurations` with `wsl.enable = true` and tests each one
sequentially. Produces a summary matrix at the end.

#### Debug Mode (Keep Test Distro)

```powershell
.\Test-WslImport.ps1 -SkipCleanup
```

Leaves the test distro registered so you can inspect it manually:
```powershell
wsl -d test-nixos-wsl-dev-team
# When done:
wsl --unregister test-nixos-wsl-dev-team
```

### Interpreting Results

Each check is reported with a phase tag, name, status, and optional detail:

```
[VALIDATE] user-matches             PASS  (expected: dev, got: dev)
[VALIDATE] systemd-state            PASS  (running)
[TERMINAL] tier2-guid-matches       FAIL  (fragment={abc...} expected={def...})
```

- **PASS**: Check succeeded
- **FAIL**: Check failed (detail explains why)
- **SKIP**: Check was skipped (e.g., terminal not installed, `-SkipTerminalValidation`)

Exit code 0 means all non-skipped checks passed. Exit code 1 means at least one
check failed. Exit code 2 means a fatal error prevented testing (WSL missing,
build failed, import failed).

### CI Limitations

This test requires a real Windows machine with WSL -- it cannot run in GitHub
Actions (no WSL in Linux runners). Run it manually as part of the release
validation workflow:

1. CI builds the tarball and uploads as artifact
2. Download artifact to a Windows machine
3. Run `.\Test-WslImport.ps1 -TarballPath <artifact> -SkipBuild`
4. Verify all checks pass before publishing the release

Source: `docs/tools/Test-WslImport.ps1`

## Summary

The test suite provides comprehensive validation of the NixOS configuration system. Use the test runners for quick validation, and individual test commands for debugging. Integration tests require KVM support but provide the most thorough validation. Always run regression tests before committing changes.

For questions or issues, check the troubleshooting section or examine the test source files in `tests/` and `flake-modules/tests.nix`.