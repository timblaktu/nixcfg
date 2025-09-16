# NixOS Configuration Test Suite

## Overview

This directory contains the comprehensive test suite for the NixOS SSH key management system. The tests validate module functionality, configuration integrity, and system integration using the NixOS testing framework.

## Quick Start

```bash
# Run all tests
nix run '.#apps.x86_64-linux.test-all'

# Run specific test
nix build '.#checks.x86_64-linux.ssh-simple-test' -L

# Run integration tests (requires KVM)
nix run '.#apps.x86_64-linux.test-integration'
```

## Test Structure

```
tests/
├── README.md                    # This file
├── sops-simple.nix             # Basic SOPS functionality tests
├── ssh-auth.nix                # SSH authentication component tests
├── sops-nix.nix               # Advanced SOPS operations tests
└── integration/               # VM-based integration tests
    ├── ssh-management.nix     # Full SSH key management pipeline
    ├── sops-deployment.nix    # SOPS-NiX deployment scenarios
    └── bitwarden-mock.nix     # Mock Bitwarden service for testing
```

## Test Categories

### Unit Tests
Fast, isolated tests that verify individual components:
- **sops-simple.nix**: Basic SOPS encryption/decryption
- **ssh-auth.nix**: SSH key generation and validation
- **sops-nix.nix**: Advanced SOPS-NiX integration

### Integration Tests
Comprehensive VM-based tests that verify full system behavior:
- **ssh-management.nix**: End-to-end SSH key management with Bitwarden mock
- **sops-deployment.nix**: Secret deployment and permissions in real NixOS VMs

### Module Tests (in flake-modules/tests.nix)
Configuration and module interaction tests:
- Configuration evaluation tests
- Cross-module integration tests
- Service configuration validation

## Writing Tests

### Unit Test Template

```nix
# tests/my-test.nix
{ pkgs, lib, ... }:

pkgs.runCommand "my-test" {
  meta = {
    description = "Test description";
    maintainers = [ ];
    timeout = 30;  # seconds
  };
  buildInputs = with pkgs; [ 
    # required packages
  ];
} ''
  echo "Running test..."
  
  # Test logic here
  if [[ condition ]]; then
    echo "✅ Test passed"
  else
    echo "❌ Test failed"
    exit 1
  fi
  
  touch $out
''
```

### Integration Test Template

```nix
# tests/integration/my-integration-test.nix
{ pkgs, lib, ... }:

pkgs.nixosTest {
  name = "my-integration-test";
  
  nodes = {
    machine = { config, pkgs, ... }: {
      # VM configuration
      services.openssh.enable = true;
      virtualisation.memorySize = 1024;
    };
  };
  
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    
    # Python test script
    machine.succeed("command to test")
    
    print("✅ Test completed successfully")
  '';
}
```

## Test Execution

### Prerequisites

For unit tests:
- Nix 2.18+ with flakes enabled
- x86_64-linux system

For integration tests:
- KVM support (check with `ls /dev/kvm`)
- User in `kvm` group
- 2GB+ RAM available

### Running Tests

#### All Tests
```bash
nix run '.#apps.x86_64-linux.test-all'
```

#### Specific Test
```bash
# Build and run
nix build '.#checks.x86_64-linux.test-name' -L

# Just check if it builds
nix build '.#checks.x86_64-linux.test-name' --dry-run
```

#### With Debugging
```bash
# Verbose output
nix build '.#checks.x86_64-linux.test-name' -L --show-trace

# Keep failed build directory
nix build '.#checks.x86_64-linux.test-name' --keep-failed
```

## Test Files

### sops-simple.nix
Tests basic SOPS functionality including:
- Age key generation
- Secret encryption/decryption
- File permissions
- Key format validation

### ssh-auth.nix
Tests SSH authentication components:
- SSH key generation (Ed25519, RSA)
- Key format validation
- Authorized keys formatting
- Public key extraction

### sops-nix.nix
Tests advanced SOPS-NiX integration:
- Multi-user secret access
- Service integration patterns
- Secret rotation
- Permission management

### integration/ssh-management.nix
Full system test including:
- Bitwarden CLI mock
- Cross-host SSH authentication
- Key distribution pipeline
- User management

### integration/sops-deployment.nix
Tests SOPS deployment in VMs:
- Secret file deployment
- Runtime decryption
- Service access patterns
- Permission verification

### integration/bitwarden-mock.nix
Provides mock Bitwarden service:
- Simulates vault operations
- Returns test keys
- No network dependencies

## Test Runners

Located in `flake-modules/tests.nix`:

### test-all
Runs complete test suite with colored output and statistics.

### test-integration  
Runs only VM-based integration tests with detailed logging.

### regression-test
Quick validation that all configurations still evaluate.

### snapshot
Generates configuration snapshots for comparison.

## Coverage

Current test coverage: **~85%**

### Well Tested (>90%)
- Base module configuration
- WSL module integration
- SOPS-NiX operations
- SSH key registry

### Moderately Tested (70-90%)
- Bitwarden integration
- SSH key automation
- Bootstrap operations

### Gaps (<70%)
- Error recovery paths
- Network failure scenarios
- Concurrent operations

## Troubleshooting

### Common Issues

#### KVM not available
```bash
# Enable KVM module
sudo modprobe kvm-intel  # or kvm-amd

# Add user to kvm group
sudo usermod -a -G kvm $USER
```

#### Test timeout
```bash
# Increase timeout in test file
meta = {
  timeout = 120;  # seconds
};
```

#### Out of memory
```bash
# Reduce VM memory in test
virtualisation.memorySize = 512;  # MB
```

### Debug Techniques

1. **Add debug output**:
```nix
echo "DEBUG: variable value = $var" >&2
```

2. **Interactive VM debugging**:
```python
# In testScript
import time
time.sleep(30)  # Pause for inspection
machine.shell_interact()  # Drop to shell
```

3. **Keep test artifacts**:
```bash
nix build '.#checks.x86_64-linux.test-name' --keep-failed
ls /tmp/nix-build-*/
```

## Contributing

### Adding New Tests

1. Create test file in appropriate directory
2. Register in `flake-modules/tests.nix`
3. Run locally to verify
4. Update documentation if needed

### Test Guidelines

- Keep tests fast and deterministic
- Mock external dependencies
- Use descriptive names
- Add timeout limits
- Document what's being tested
- Clean up resources

### Review Checklist

- [ ] Test passes locally
- [ ] No hardcoded paths
- [ ] Appropriate timeout set
- [ ] Clear failure messages
- [ ] Documentation updated
- [ ] No sensitive data

## CI/CD Integration

Tests are designed to run in CI pipelines:

```yaml
# GitHub Actions example
- name: Run tests
  run: nix run '.#apps.x86_64-linux.test-all'
```

See `docs/ci-cd-integration.md` for detailed CI setup.

## Performance

### Execution Times
- Unit tests: <1 second each
- Module tests: ~1 second each
- Integration tests: 2-5 minutes each
- Full suite: ~10 minutes

### Resource Usage
- Unit tests: <100MB RAM
- Integration tests: 1-2GB RAM per VM
- Disk: ~1GB for test artifacts

### Optimization Tips
- Run tests in parallel where possible
- Use `--dry-run` for quick checks
- Cache Nix store between runs
- Skip integration tests during development

## Future Improvements

### Planned
- [ ] Performance benchmarks
- [ ] Stress testing suite
- [ ] Security audit tests
- [ ] Coverage reporting

### Ideas
- Mutation testing
- Property-based testing
- Chaos engineering tests
- Cross-platform testing

## Related Documentation

- [Test Coverage Report](../docs/test-coverage-report.md)
- [Test Execution Guide](../docs/test-execution-guide.md)
- [Test Results Analysis](../docs/test-results-analysis.md)
- [CI/CD Integration](../docs/ci-cd-integration.md)

## Support

For test-related issues:
1. Check troubleshooting section above
2. Review test output carefully
3. Check test source code
4. Search existing issues
5. Ask in NixOS community

---
*Test Suite Version: 1.0 | Framework: NixOS Testing | Last Updated: 2025-09-15*