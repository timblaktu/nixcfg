# NixOS Configuration Testing Strategy

## Overview

This repository uses Nix-native testing integrated directly into the flake configuration. All tests are defined as flake checks and can be run using standard Nix commands.

## Benefits Over Script-Based Testing

1. **No External Dependencies**: Tests run in pure Nix environments
2. **Cached Results**: Nix caches test results, only re-running when inputs change
3. **Parallel Execution**: Tests run in parallel automatically
4. **CI/CD Integration**: Works seamlessly with GitHub Actions, Hydra, etc.
5. **Type Safety**: Nix evaluation catches errors at build time
6. **Reproducibility**: Tests are deterministic and reproducible

## Running Tests

### Quick Commands

```bash
# Run all tests (regression testing)
nix flake check

# Run all tests and continue even if some fail
nix flake check --keep-going

# Run a specific test
nix build .#checks.x86_64-linux.eval-thinky-nixos

# Run interactive test suite with colored output
nix run .#test-all

# Generate configuration snapshot
nix run .#snapshot

# Quick regression test before changes
nix run .#regression-test
```

## Test Categories

### 1. Configuration Evaluation Tests
- **Purpose**: Ensure all host configurations can be evaluated without errors
- **Tests**: `eval-thinky-nixos`, `eval-potato`, `eval-nixos-wsl-minimal`
- **What they catch**: Syntax errors, missing modules, undefined options

### 2. Module Integration Tests
- **Purpose**: Verify that custom modules integrate correctly
- **Tests**: `module-base-integration`, `module-wsl-common-integration`
- **What they catch**: Module conflicts, option collisions, dependency issues

### 3. Service Configuration Tests
- **Purpose**: Ensure critical services are properly configured
- **Tests**: `ssh-service-configured`, `user-tim-configured`
- **What they catch**: Service misconfigurations, missing users/groups

### 4. Build Tests (Dry Run)
- **Purpose**: Verify configurations can be built without actually building
- **Tests**: `build-thinky-nixos-dryrun`, `build-nixos-wsl-minimal-dryrun`
- **What they catch**: Build-time errors, missing packages, evaluation problems

### 5. Configuration Snapshots
- **Purpose**: Capture current configuration state for comparison
- **Test**: `config-snapshot`
- **Use case**: Compare configurations before/after refactoring

## Writing New Tests

Add new tests to `flake-modules/tests.nix`:

```nix
checks = {
  my-new-test = pkgs.runCommand "my-new-test" {} ''
    echo "Running my test..."
    ${pkgs.nix}/bin/nix eval \
      --impure \
      --expr 'assertion expression here'
    touch $out
  '';
};
```

## CI/CD Integration

In GitHub Actions or other CI systems:

```yaml
- name: Run NixOS Configuration Tests
  run: nix flake check --keep-going
```

## Best Practices

1. **Run Before Commits**: Always run `nix flake check` before committing
2. **Test After Module Changes**: Run integration tests after modifying modules
3. **Snapshot Before Refactoring**: Generate snapshots before major changes
4. **Use --keep-going**: When debugging multiple failures
5. **Cache Wisely**: Tests are cached; use `--recreate-lock-file` if needed

## Troubleshooting

### Test Failures
- Run individual test: `nix build .#checks.x86_64-linux.test-name --show-trace`
- Check evaluation: `nix eval .#nixosConfigurations.hostname.config --show-trace`

### Performance
- Tests run in parallel automatically
- Use `--max-jobs N` to control parallelism
- Cached results make subsequent runs fast

### Debugging
- Add `--show-trace` for detailed error traces
- Use `--print-build-logs` to see test output
- Check `nix log .#checks.x86_64-linux.test-name`

## Migration from Script-Based Testing

The old `test-configurations.sh` script has been replaced with integrated Nix tests. All functionality is preserved:

| Old Script Command | New Nix Command |
|-------------------|-----------------|
| `./test-configurations.sh` | `nix run .#test-all` |
| Manual evaluation tests | `nix flake check` |
| Config snapshot | `nix run .#snapshot` |
| Individual test | `nix build .#checks.x86_64-linux.TEST_NAME` |

## Continuous Testing

For continuous testing during development:

```bash
# Watch for changes and re-run tests
while true; do
  inotifywait -r -e modify,create,delete *.nix modules/ hosts/
  nix flake check
done
```