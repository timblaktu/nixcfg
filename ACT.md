# Act Tool Analysis & Implementation Plan for nixcfg Security Workflows

## Overview

**Act** is a powerful local GitHub Actions runner that executes workflows in Docker containers, providing near-identical environment to GitHub's hosted runners. This analysis covers act's capabilities for testing our nixcfg security workflows locally, reducing development time and GitHub Actions costs.

## Tool Capabilities

### Core Features
- **Local workflow execution**: Run complete `.github/workflows/*.yml` files locally
- **Individual job testing**: Target specific jobs with `-j <job-id>` 
- **Event simulation**: Support for push, pull_request, schedule, and custom events
- **Container management**: Three image sizes (Micro <200MB, Medium ~500MB, Large ~17GB)
- **Development features**: Dry run, watch mode, bind mounts, artifact/cache servers

### Architecture
- **Language**: Go-based CLI tool
- **Version**: 0.2.82 (source), 0.2.81 (nixpkgs)
- **Dependencies**: Docker daemon required
- **Execution model**: Uses Docker API for container orchestration

## Installation Options

### Option 1: Nix Package (Recommended)
```bash
# System install via nixpkgs
nix-env -iA nixpkgs.act

# Or add to configuration.nix/home.nix
environment.systemPackages = [ pkgs.act ];
```

### Option 2: Source Build (Current Setup)
```bash
cd /home/tim/src/act
make build
# Binary at: ./dist/local/act
```

### Option 3: Install Script
```bash
cd /home/tim/src/act
./install.sh -b ~/.local/bin
```

## nixcfg Security Workflow Analysis

### Current Workflow Jobs
Our `security.yml` workflow contains 5 jobs suitable for local testing:

| Job | Purpose | Act Compatibility | Local Test Value |
|-----|---------|------------------|------------------|
| `gitleaks` | Secret scanning | ✅ **Excellent** | High - Fast feedback on commits |
| `trufflehog` | Additional secret detection | ✅ **Excellent** | High - Comprehensive coverage |
| `semgrep` | Security analysis | ⚠️ **Good** | Medium - May need auth tokens |
| `verify-sops` | SOPS encryption validation | ✅ **Perfect** | Very High - Pure shell, instant |
| `audit-permissions` | File permission checks | ✅ **Perfect** | Very High - Pure shell, instant |

### Testing Commands

#### Individual Job Testing (Recommended Start)
```bash
# Fast jobs for immediate feedback
act -j verify-sops            # SOPS validation (~5 seconds)
act -j audit-permissions      # File permissions (~3 seconds)

# Medium complexity jobs  
act -j gitleaks              # Secret scanning (~30 seconds + download)
act -j trufflehog            # Additional secrets (~45 seconds)

# Complex jobs requiring setup
act -j semgrep --secret SEMGREP_APP_TOKEN=<PLACEHOLDER_TOKEN_IMPOSSIBLE>
```

#### Full Workflow Testing
```bash
# Test complete security workflow
act push                     # Simulates push event
act pull_request            # Simulates PR event

# Dry run validation (no containers)
act --dryrun push           # Validate workflow syntax only
```

#### Development Workflow
```bash
# Watch mode for active development
act -j verify-sops --watch  # Re-run on file changes

# Bind mount for live editing
act -j gitleaks --bind      # Mount working directory vs copy
```

## Git Hook Integration

### Pre-commit Hook (Fast Security Checks)
```bash
#!/bin/sh
# .git/hooks/pre-commit
echo "🔒 Running fast security checks..."
act -j verify-sops -j audit-permissions --quiet
if [ $? -ne 0 ]; then
    echo "❌ Security checks failed. Fix issues before committing."
    exit 1
fi
echo "✅ Security checks passed"
```

### Pre-push Hook (Comprehensive Security Scan)
```bash
#!/bin/sh
# .git/hooks/pre-push
echo "🔍 Running comprehensive security scan..."
act -j gitleaks -j trufflehog --quiet
if [ $? -ne 0 ]; then
    echo "❌ Security scan failed. Fix issues before pushing."
    exit 1
fi
echo "✅ Security scan passed"
```

### Benefits of Git Hook Integration
- **Fast feedback**: Catch issues before GitHub CI (save ~2-5 minutes per cycle)
- **Cost savings**: Reduce GitHub Actions minutes consumption
- **Offline capability**: Security validation without internet
- **Developer experience**: Immediate validation in familiar environment

## Implementation Plan

### Phase 1: Setup & Basic Validation (Day 1)
```bash
# 1. Install act via Nix (preferred for system integration)
nix-env -iA nixpkgs.act

# 2. Configure act for medium image (good balance)
mkdir -p ~/.config/act
echo '-P ubuntu-latest=catthehacker/ubuntu:act-latest' > ~/.config/act/actrc

# 3. Test workflow parsing
act -l  # List all workflows and jobs

# 4. Validate fastest jobs
act -j audit-permissions --dryrun
act -j verify-sops --dryrun
```

### Phase 2: Individual Job Testing (Day 1-2)
```bash
# Test each job individually for baseline performance
act -j audit-permissions      # Expected: ~3 seconds
act -j verify-sops            # Expected: ~5 seconds  
act -j gitleaks              # Expected: ~30 seconds first run, ~10 seconds cached
act -j trufflehog            # Expected: ~45 seconds first run, ~15 seconds cached
act -j semgrep               # Expected: Variable, may need token setup
```

### Phase 3: Workflow Integration Testing (Day 2-3)
```bash
# Test complete workflow
act push                     # Full security workflow

# Test with environment simulation
act --env GITHUB_TOKEN=dummy push

# Test event-specific triggers
act pull_request            # PR-specific security checks
```

### Phase 4: Git Hook Implementation (Day 3-4)
```bash
# Implement progressive git hooks
# Start with pre-commit (fast checks only)
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
echo "🔒 Running fast security checks..."
act -j verify-sops -j audit-permissions --quiet
EOF
chmod +x .git/hooks/pre-commit

# Add pre-push after team validation
cat > .git/hooks/pre-push << 'EOF'  
#!/bin/sh
echo "🔍 Running security scan..."
act -j gitleaks --quiet
EOF
chmod +x .git/hooks/pre-push
```

### Phase 5: Team Adoption & Documentation (Day 5+)
- Document successful patterns in team knowledge base
- Create team-wide act configuration recommendations
- Establish best practices for local security testing
- Consider CI/CD optimization based on local testing insights

## Expected Benefits

### Quantified Improvements
- **Development cycle time**: Reduce from 3-5 minutes (GitHub CI) to 5-30 seconds (local)
- **GitHub Actions cost**: Reduce security workflow runs by ~70% (local pre-validation)
- **Security feedback speed**: Immediate vs delayed (push → wait → review → fix cycle)
- **Offline capability**: Full security workflow validation without internet

### Quality Improvements
- **Earlier issue detection**: Catch problems before they reach CI
- **Faster iteration**: Quick testing of security workflow changes
- **Improved developer experience**: Familiar local environment for debugging
- **Consistent environment**: Same containers as production CI

## Limitations & Considerations

### Technical Limitations
- **Docker dependency**: Requires Docker daemon running (already available)
- **Resource usage**: Medium image ~500MB disk, containers use ~200-400MB RAM
- **Secret simulation**: Some jobs may need mock secrets/tokens for full testing
- **GitHub-specific features**: Some marketplace actions may behave differently locally

### Team Considerations
- **Learning curve**: Team needs to adopt local testing workflow
- **Git hook enforcement**: Consider making hooks mandatory vs optional
- **CI/CD coordination**: Balance local testing with comprehensive CI validation
- **Tool maintenance**: Keep act version updated with nixpkgs updates

## Configuration Files

### Act Configuration (~/.config/act/actrc)
```bash
# Use medium-sized container images (good balance of features vs size)
-P ubuntu-latest=catthehacker/ubuntu:act-latest

# Enable artifact server for testing upload/download workflows
--artifact-server-path /tmp/act-artifacts

# Default to quiet mode for git hooks
--quiet
```

### Recommended .actrc for nixcfg
```bash
# Optimized for security workflow testing
-P ubuntu-latest=catthehacker/ubuntu:act-latest
--container-cap-add SYS_PTRACE  # For security tools
--quiet                         # Less verbose for git hooks
--rm                           # Auto-cleanup containers
```

## Success Metrics

### Developer Experience
- [ ] Security workflow changes can be tested locally in <30 seconds
- [ ] Git hooks provide immediate feedback on security issues
- [ ] Team adopts local testing for >80% of security-related changes

### Cost & Performance  
- [ ] Reduce GitHub Actions security workflow runs by 50-70%
- [ ] Decrease average time from change to validated security fix
- [ ] Achieve <5% false positive rate in local vs CI testing

### Quality Metrics
- [ ] Reduce security issues reaching CI by 80%
- [ ] Improve security workflow reliability through local iteration
- [ ] Enable rapid prototyping of new security checks

## Next Steps

1. **Install act via Nix** for system integration
2. **Test individual jobs** starting with fastest (verify-sops, audit-permissions)
3. **Implement progressive git hooks** (pre-commit first, pre-push after validation)
4. **Document successful patterns** for team adoption
5. **Iterate on configuration** based on real-world usage patterns

This implementation plan should provide immediate value while building toward comprehensive local security testing capability that enhances our existing security scanning infrastructure.