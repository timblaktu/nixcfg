# TUR Fork Setup Guide

Complete guide to forking TUR (Termux User Repository), adding the claude-wrappers package, and setting up automated builds and publishing.

## Overview

This guide walks through:
1. Forking the TUR repository
2. Adding the claude-wrappers package
3. Setting up GitHub Actions CI/CD
4. Publishing to an APT repository via GitHub Pages
5. Testing installation on Termux

## Prerequisites

- GitHub account
- Git installed locally or on Termux
- (Optional) Docker for local testing

## Phase 1: Fork and Initial Setup

### Step 1: Fork TUR Repository

1. Visit https://github.com/termux-user-repository/tur
2. Click "Fork" button (top right)
3. Choose your account (timblaktu)
4. Wait for fork to complete

### Step 2: Clone Your Fork

```bash
# Clone to local machine or Termux
git clone https://github.com/timblaktu/tur.git
cd tur

# Add upstream remote for syncing
git remote add upstream https://github.com/termux-user-repository/tur.git
```

### Step 3: Add claude-wrappers Package

Copy the package definition from this directory:

```bash
# From nixcfg repository
cd ~/termux-src/nixcfg/tur-package

# Copy to TUR fork
cp -r claude-wrappers ~/path/to/tur/tur/

# Verify structure
ls -la ~/path/to/tur/tur/claude-wrappers
# Should see: build.sh, claudemax, claudepro, claudework, claude-setup-work, README.md
```

### Step 4: Test Package Locally (Optional)

If you have Docker installed:

```bash
cd ~/path/to/tur

# Build using TUR's Docker setup
./scripts/run-docker.sh ./build-package.sh claude-wrappers

# Or build natively on Termux
./build-package.sh claude-wrappers
```

Without Docker (manual build):

```bash
cd tur/claude-wrappers

# Create package directory
PKG_DIR="claude-wrappers_1.0.0-1"
mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/data/data/com.termux/files/usr/bin"
mkdir -p "${PKG_DIR}/data/data/com.termux/files/usr/share/doc/claude-wrappers"

# Generate control file (see build.sh for content)
# ... (create DEBIAN/control, copy files, etc.)

# Build package
dpkg-deb --build "${PKG_DIR}"

# Test install
apt install ./${PKG_DIR}.deb
```

### Step 5: Commit and Push

```bash
cd ~/path/to/tur

# Add package files
git add tur/claude-wrappers/

# Commit
git commit -m "Add claude-wrappers package

Multi-account wrapper scripts for Claude Code on Termux.

Provides:
- claudemax: Claude Max account
- claudepro: Claude Pro account
- claudework: Custom proxy template
- claude-setup-work: Interactive setup helper

Features:
- Separate config directories per account
- Bearer token authentication for work proxy
- Custom model mappings
- Telemetry disabled by default
"

# Push to your fork
git push origin master
```

## Phase 2: GitHub Actions Setup

### Step 1: Copy Workflow File

```bash
cd ~/path/to/tur

# Create .github/workflows if needed
mkdir -p .github/workflows

# Copy workflow from tur-package
cp ~/termux-src/nixcfg/tur-package/.github/workflows/build-claude-wrappers.yml \
   .github/workflows/

# Review and adjust if needed
vim .github/workflows/build-claude-wrappers.yml
```

### Step 2: Enable GitHub Actions

1. Go to your fork on GitHub: https://github.com/timblaktu/tur
2. Click "Actions" tab
3. Click "I understand my workflows, go ahead and enable them"

### Step 3: Enable GitHub Pages

1. Go to Settings → Pages
2. Source: Deploy from a branch
3. Branch: `gh-pages` / `/ (root)`
4. Click Save

GitHub Actions will create the `gh-pages` branch automatically on first deployment.

### Step 4: Commit Workflow and Trigger Build

```bash
cd ~/path/to/tur

# Add workflow
git add .github/workflows/build-claude-wrappers.yml

# Commit
git commit -m "Add GitHub Actions workflow for claude-wrappers

Automated build and publishing:
- Builds .deb package on push
- Publishes to GitHub Pages APT repository
- Creates GitHub releases with package artifacts
"

# Push
git push origin master

# This will trigger the workflow automatically
```

### Step 5: Monitor Build

1. Go to Actions tab on GitHub
2. Watch "Build claude-wrappers" workflow
3. Check logs if build fails

Expected workflow:
- Build job: Creates .deb package, uploads artifact
- Publish job: Updates APT repository on GitHub Pages

## Phase 3: Verify APT Repository

### Step 1: Check GitHub Pages Deployment

1. After workflow completes, visit: https://timblaktu.github.io/tur/
2. Should see APT repository structure:
   ```
   dists/
   └── stable/
       ├── Release
       └── main/
           └── binary-all/
               └── Packages.gz
   ```

### Step 2: Verify Repository Files

```bash
# Download Release file
curl https://timblaktu.github.io/tur/dists/stable/Release

# Download and check Packages
curl https://timblaktu.github.io/tur/dists/stable/main/binary-all/Packages.gz | \
  gunzip | grep -A 10 "^Package: claude-wrappers"
```

## Phase 4: Install on Termux

### Step 1: Add Repository

On your Termux device:

```bash
# Add APT repository
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

# Update package lists
pkg update
```

### Step 2: Install Claude Code (if not already installed)

```bash
pkg install nodejs-lts
npm install -g @anthropic/claude-code
```

### Step 3: Install claude-wrappers

```bash
# Search for package
pkg search claude-wrappers

# Show package info
pkg show claude-wrappers

# Install
pkg install claude-wrappers
```

Should see post-installation message with usage instructions.

### Step 4: Test Wrappers

```bash
# Verify installation
which claudemax claudepro claudework
# Should show: /data/data/com.termux/files/usr/bin/claude*

# Test version
claudemax --version

# Test work account setup
claude-setup-work
# Follow prompts to enter bearer token

# Test work wrapper
claudework --version
```

## Phase 5: Updates and Maintenance

### Making Changes

```bash
cd ~/path/to/tur

# Edit package files
vim tur/claude-wrappers/claudework

# Update version in build.sh
vim tur/claude-wrappers/build.sh
# Change TERMUX_PKG_VERSION or TERMUX_PKG_REVISION

# Commit changes
git add tur/claude-wrappers/
git commit -m "Update claude-wrappers to 1.0.1

- Fix authentication bug
- Update model mappings
"

# Push (triggers automatic build)
git push origin master
```

### Upgrading on Termux

```bash
# Update package lists
pkg update

# Upgrade package
pkg upgrade claude-wrappers

# Or upgrade all
pkg upgrade
```

### Syncing with Upstream TUR

```bash
cd ~/path/to/tur

# Fetch upstream changes
git fetch upstream

# Merge upstream master
git merge upstream/master

# Resolve conflicts if any
git push origin master
```

## Phase 6: Optional Enhancements

### Add to Official TUR

Once stable, consider contributing to upstream:

1. Ensure package follows TUR guidelines
2. Test thoroughly on multiple devices
3. Open PR to https://github.com/termux-user-repository/tur
4. Include:
   - Package description
   - Testing evidence
   - Rationale for inclusion

### Multi-Architecture Support

If you want to build for all architectures (though package is platform-independent):

```yaml
# In .github/workflows/build-claude-wrappers.yml
strategy:
  matrix:
    arch: [aarch64, arm, i686, x86_64]
```

### Automated Version Bumps

Use GitHub Actions to automatically bump versions:

```yaml
# Add to workflow
- name: Auto-bump version
  run: |
    # Logic to increment TERMUX_PKG_REVISION
    # Commit and push
```

## Troubleshooting

### Build Fails in GitHub Actions

- Check Actions tab for detailed logs
- Common issues:
  - Syntax errors in build.sh
  - Missing files
  - Incorrect permissions
  - DEBIAN/control format errors

### APT Repository Not Accessible

- Verify GitHub Pages is enabled
- Check Pages URL in Settings
- Ensure gh-pages branch exists
- Wait 5-10 minutes after first deployment

### Package Installation Fails

```bash
# Check repository is added
cat $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

# Update package lists
pkg update

# Try installing with verbose output
apt install -o Debug::pkgAcquire::Worker=1 claude-wrappers
```

### Wrapper Scripts Don't Work

```bash
# Check permissions
ls -la $PREFIX/bin/claude*

# Should be -rwxr-xr-x (executable)
# If not:
chmod +x $PREFIX/bin/claude{max,pro,work}

# Check Claude Code installation
which claude
claude --version
```

## Directory Structure Reference

```
tur/ (forked repository)
├── tur/
│   └── claude-wrappers/
│       ├── build.sh                 # Package definition
│       ├── claudemax                # Max wrapper script
│       ├── claudepro                # Pro wrapper script
│       ├── claudework               # Work wrapper script
│       ├── claude-setup-work        # Setup helper
│       └── README.md                # Package documentation
├── .github/
│   └── workflows/
│       └── build-claude-wrappers.yml # CI/CD workflow
└── [standard TUR files]

GitHub Pages (gh-pages branch)
├── dists/
│   └── stable/
│       ├── Release
│       └── main/
│           └── binary-all/
│               ├── Packages.gz
│               └── claude-wrappers_1.0.0-1_all.deb
```

## Resources

- **TUR Wiki**: https://github.com/termux-user-repository/tur/wiki
- **Termux Packages Wiki**: https://github.com/termux/termux-packages/wiki
- **Creating Packages**: https://github.com/termux/termux-packages/wiki/Creating-new-package
- **TUR Discussions**: https://github.com/termux-user-repository/tur/discussions
- **Your Fork**: https://github.com/timblaktu/tur
- **APT Repository**: https://timblaktu.github.io/tur

## Next Steps

After completing this setup:

1. **Test thoroughly** on your Termux device
2. **Document any issues** and solutions
3. **Consider Phase 2 integration** with nixcfg (see ../docs/)
4. **Share with others** who might benefit
5. **Contribute upstream** when stable

---

**Status**: This guide reflects the implementation as of 2026-01-19.

**Questions**: Open an issue on https://github.com/timblaktu/tur or consult TUR community.
