# CI/CD Integration Guide

## Overview

This guide provides templates and strategies for integrating the NixOS test suite into continuous integration and deployment pipelines. Due to the VM-based nature of integration tests requiring KVM, we recommend a hybrid approach with unit tests in CI and integration tests run locally.

## CI Platform Support

### Platform Compatibility Matrix

| Platform | Unit Tests | Integration Tests | Recommendation |
|----------|------------|------------------|----------------|
| GitHub Actions | ✅ Full | ⚠️ Limited* | Use for unit tests |
| GitLab CI | ✅ Full | ✅ With runner | Self-hosted runner |
| Jenkins | ✅ Full | ✅ Full | Full support |
| CircleCI | ✅ Full | ⚠️ Machine executor | Premium features needed |
| Local | ✅ Full | ✅ Full | Pre-commit hooks |

*Integration tests require KVM, which needs nested virtualization or self-hosted runners

## GitHub Actions

### Basic Unit Test Workflow

```yaml
# .github/workflows/tests.yml
name: NixOS Configuration Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 2 * * 1'  # Weekly on Monday at 2 AM

jobs:
  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    timeout-minutes: 30
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for git-based tests
      
      - name: Install Nix
        uses: cachix/install-nix-action@v24
        with:
          nix_path: nixpkgs=channel:nixos-unstable
          extra_nix_config: |
            experimental-features = nix-command flakes
            accept-flake-config = true
            max-jobs = auto
            cores = 0
            
      - name: Setup Nix cache
        uses: cachix/cachix-action@v12
        with:
          name: nixos-ssh-keys
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
          
      - name: Check flake
        run: |
          nix flake show
          nix flake metadata
          
      - name: Run unit tests
        run: |
          # Run individual unit tests
          nix build '.#checks.x86_64-linux.ssh-simple-test' -L
          nix build '.#checks.x86_64-linux.sops-simple-test' -L
          nix build '.#checks.x86_64-linux.module-base-integration' -L
          nix build '.#checks.x86_64-linux.module-wsl-common-integration' -L
          
      - name: Run configuration tests
        run: |
          # Test configuration evaluation
          nix build '.#checks.x86_64-linux.eval-thinky-nixos' -L
          nix build '.#checks.x86_64-linux.eval-nixos-wsl-minimal' -L
          
      - name: Generate test report
        if: always()
        run: |
          echo "## Test Results" >> $GITHUB_STEP_SUMMARY
          echo "| Test | Status |" >> $GITHUB_STEP_SUMMARY
          echo "|------|--------|" >> $GITHUB_STEP_SUMMARY
          for test in ssh-simple-test sops-simple-test module-base-integration; do
            if nix build ".#checks.x86_64-linux.$test" 2>/dev/null; then
              echo "| $test | ✅ Pass |" >> $GITHUB_STEP_SUMMARY
            else
              echo "| $test | ❌ Fail |" >> $GITHUB_STEP_SUMMARY
            fi
          done
```

### Advanced Workflow with Matrix Strategy

```yaml
# .github/workflows/matrix-tests.yml
name: Matrix Testing

on: [push, pull_request]

jobs:
  test-matrix:
    name: Test ${{ matrix.host }}
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        host:
          - thinky-nixos
          - nixos-wsl-minimal
          - potato
          - mbp
    
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes
            
      - name: Evaluate ${{ matrix.host }}
        run: |
          nix build '.#checks.x86_64-linux.eval-${{ matrix.host }}' -L
          
      - name: Build configuration
        run: |
          nix build '.#nixosConfigurations.${{ matrix.host }}.config.system.build.toplevel' --dry-run
```

### Self-Hosted Runner for Integration Tests

```yaml
# .github/workflows/integration-tests.yml
name: Integration Tests (Self-Hosted)

on:
  push:
    branches: [ main ]
  workflow_dispatch:  # Manual trigger

jobs:
  integration:
    name: VM Integration Tests
    runs-on: [self-hosted, linux, kvm]  # Requires KVM-enabled runner
    timeout-minutes: 60
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Verify KVM support
        run: |
          if [[ ! -e /dev/kvm ]]; then
            echo "::error::KVM not available on runner"
            exit 1
          fi
          
      - name: Run integration tests
        run: |
          nix run '.#apps.x86_64-linux.test-integration'
          
      - name: Upload test logs
        if: failure()
        uses: actions/upload-artifact@v3
        with:
          name: integration-test-logs
          path: |
            /tmp/nix-build-*/
            result/
```

## GitLab CI

### .gitlab-ci.yml

```yaml
stages:
  - validate
  - test
  - integration
  - deploy

variables:
  NIX_PATH: "nixpkgs=channel:nixos-unstable"

before_script:
  - nix-env --version
  - nix --experimental-features 'nix-command flakes' flake show

validate:flake:
  stage: validate
  script:
    - nix flake check --no-build
  only:
    - merge_requests
    - main

test:unit:
  stage: test
  script:
    - |
      for test in ssh-simple-test sops-simple-test module-base-integration; do
        echo "Running $test..."
        nix build ".#checks.x86_64-linux.$test" -L || exit 1
      done
  artifacts:
    reports:
      junit: test-results.xml
    when: always

test:integration:
  stage: integration
  tags:
    - kvm  # Runner with KVM support
  script:
    - nix run '.#apps.x86_64-linux.test-integration'
  only:
    - main
    - tags
```

## Jenkins Pipeline

### Jenkinsfile

```groovy
pipeline {
    agent { label 'nixos' }
    
    environment {
        NIX_REMOTE = 'daemon'
        NIX_PATH = 'nixpkgs=channel:nixos-unstable'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Validate') {
            steps {
                sh 'nix --experimental-features "nix-command flakes" flake show'
                sh 'nix --experimental-features "nix-command flakes" flake metadata'
            }
        }
        
        stage('Unit Tests') {
            parallel {
                stage('SSH Tests') {
                    steps {
                        sh 'nix build .#checks.x86_64-linux.ssh-simple-test -L'
                    }
                }
                stage('SOPS Tests') {
                    steps {
                        sh 'nix build .#checks.x86_64-linux.sops-simple-test -L'
                    }
                }
                stage('Module Tests') {
                    steps {
                        sh 'nix build .#checks.x86_64-linux.module-base-integration -L'
                    }
                }
            }
        }
        
        stage('Integration Tests') {
            when {
                branch 'main'
            }
            steps {
                sh 'nix run .#apps.x86_64-linux.test-integration'
            }
        }
        
        stage('Deploy') {
            when {
                branch 'main'
                expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
            }
            steps {
                echo 'Deployment logic here'
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'result/**', allowEmptyArchive: true
            cleanWs()
        }
    }
}
```

## Local CI with Git Hooks

### Pre-commit Hook

```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit

set -e

echo "Running pre-commit tests..."

# Quick evaluation tests
HOSTS="thinky-nixos nixos-wsl-minimal"
for host in $HOSTS; do
    echo "Checking $host configuration..."
    if ! nix build ".#nixosConfigurations.$host.config.system.build.toplevel" --dry-run 2>/dev/null; then
        echo "❌ Configuration $host failed evaluation"
        exit 1
    fi
done

# Run fast unit tests
echo "Running unit tests..."
if ! nix build '.#checks.x86_64-linux.ssh-simple-test' 2>/dev/null; then
    echo "❌ Unit tests failed"
    exit 1
fi

echo "✅ All pre-commit checks passed"
```

### Pre-push Hook

```bash
#!/usr/bin/env bash
# .git/hooks/pre-push

set -e

echo "Running pre-push validation..."

# Run regression test
if ! nix run '.#apps.x86_64-linux.regression-test'; then
    echo "❌ Regression tests failed"
    echo "Fix issues before pushing"
    exit 1
fi

# Check for secrets
if git diff --cached --name-only | xargs grep -l "BEGIN PRIVATE KEY\|password\|secret" 2>/dev/null; then
    echo "⚠️  Warning: Potential secrets detected in commit"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "✅ Pre-push checks passed"
```

## Continuous Deployment

### Automated Deployment Script

```bash
#!/usr/bin/env bash
# scripts/deploy.sh

set -euo pipefail

ENVIRONMENT=${1:-staging}
HOST=${2:-$(hostname)}

echo "🚀 Deploying to $HOST ($ENVIRONMENT)"

# Run tests first
echo "📋 Running tests..."
nix run '.#apps.x86_64-linux.test-all' || {
    echo "❌ Tests failed, aborting deployment"
    exit 1
}

# Build configuration
echo "🔨 Building configuration..."
nix build ".#nixosConfigurations.$HOST.config.system.build.toplevel" -o result

# Deploy based on environment
case $ENVIRONMENT in
    staging)
        echo "🔄 Deploying to staging..."
        sudo nix-env -p /nix/var/nix/profiles/staging -i ./result
        sudo /nix/var/nix/profiles/staging/bin/switch-to-configuration test
        ;;
    production)
        echo "⚡ Deploying to production..."
        sudo nixos-rebuild switch --flake ".#$HOST"
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT"
        exit 1
        ;;
esac

echo "✅ Deployment complete"
```

### Rollback Strategy

```yaml
# .github/workflows/rollback.yml
name: Rollback Deployment

on:
  workflow_dispatch:
    inputs:
      profile:
        description: 'Profile to rollback'
        required: true
        default: 'system'
      generations:
        description: 'Number of generations to rollback'
        required: true
        default: '1'

jobs:
  rollback:
    runs-on: [self-hosted, production]
    steps:
      - name: List generations
        run: |
          sudo nix-env --list-generations -p /nix/var/nix/profiles/${{ inputs.profile }}
          
      - name: Rollback
        run: |
          sudo nix-env --rollback -p /nix/var/nix/profiles/${{ inputs.profile }}
          sudo /nix/var/nix/profiles/${{ inputs.profile }}/bin/switch-to-configuration switch
```

## Monitoring & Notifications

### Test Status Badge

```markdown
![Tests](https://github.com/USER/REPO/workflows/tests/badge.svg)
```

### Slack Notifications

```yaml
- name: Notify Slack
  if: failure()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    text: 'NixOS tests failed on ${{ github.ref }}'
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

### Email Notifications

```yaml
- name: Send email
  if: failure()
  uses: dawidd6/action-send-mail@v3
  with:
    server_address: smtp.gmail.com
    server_port: 465
    username: ${{ secrets.EMAIL_USERNAME }}
    password: ${{ secrets.EMAIL_PASSWORD }}
    subject: Test Failure - ${{ github.repository }}
    body: Tests failed on commit ${{ github.sha }}
    to: ops-team@example.com
```

## Best Practices

### 1. Test Parallelization
- Run independent tests concurrently
- Use matrix strategies for multiple configurations
- Separate fast and slow test suites

### 2. Caching Strategy
```yaml
- uses: cachix/cachix-action@v12
  with:
    name: your-cache-name
    authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
    pushFilter: "(-source$|\.tar\.gz$|\.iso$)"
```

### 3. Resource Management
- Set appropriate timeouts
- Use resource limits for VM tests
- Clean up artifacts and old builds

### 4. Security
- Never commit secrets
- Use GitHub Secrets or similar
- Scan for exposed credentials
- Limit runner permissions

### 5. Monitoring
- Track test execution times
- Monitor flaky tests
- Set up alerts for failures
- Regular dependency updates

## Troubleshooting CI Issues

### Common Problems

#### Nix not found
```yaml
- name: Install Nix
  uses: cachix/install-nix-action@v24
  with:
    install_url: https://releases.nixos.org/nix/nix-2.19.2/install
```

#### Flake not enabled
```yaml
extra_nix_config: |
  experimental-features = nix-command flakes
```

#### Out of disk space
```yaml
- name: Free disk space
  run: |
    sudo rm -rf /usr/share/dotnet
    sudo rm -rf /opt/ghc
    df -h
```

#### KVM not available
Use self-hosted runners or skip integration tests in CI:
```bash
if [[ -e /dev/kvm ]]; then
    nix run '.#apps.x86_64-linux.test-integration'
else
    echo "::warning::Skipping integration tests (no KVM)"
fi
```

## Summary

The CI/CD integration focuses on running unit tests in cloud CI platforms while reserving integration tests for environments with KVM support. Use the provided templates as starting points and adapt them to your specific needs. Remember to:

1. Start with unit tests in CI
2. Add integration tests with self-hosted runners if needed
3. Implement proper caching for faster builds
4. Set up monitoring and notifications
5. Follow security best practices

For questions about specific CI platforms or advanced configurations, consult the platform's documentation and the Nix community resources.