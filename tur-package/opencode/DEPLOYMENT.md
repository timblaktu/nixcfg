# opencode TUR Package - Deployment Guide

**Status**: Ready for deployment (Priority 1 - parallel with claude-code)
**Date**: 2026-01-19

## Overview

This package installs OpenCode binary via npm, providing the `opencode` command that `opencode-wrappers` depends on.

## Deployment to TUR Fork

### Prerequisites

- TUR fork created: https://github.com/timblaktu/tur
- GitHub Actions enabled
- GitHub Pages enabled (gh-pages branch)

### Deployment Steps

```bash
# 1. Ensure you're in the nixcfg repo
cd ~/termux-src/nixcfg

# 2. Navigate to your TUR fork (or clone it)
cd ~/path/to/tur  # Adjust path as needed
# OR clone if not yet cloned:
# git clone https://github.com/timblaktu/tur.git && cd tur

# 3. Copy the package definition
cp -r ~/termux-src/nixcfg/tur-package/opencode tur/

# 4. Copy the workflow
cp ~/termux-src/nixcfg/tur-package/.github/workflows/build-opencode.yml \
   .github/workflows/

# 5. Verify files are in place
ls -la tur/opencode/
ls -la .github/workflows/build-opencode.yml

# 6. Commit and push
git add tur/opencode/
git add .github/workflows/build-opencode.yml
git commit -m "Add opencode package (Priority 1 - provides opencode binary)"
git push origin master

# 7. Watch the build
# Visit: https://github.com/timblaktu/tur/actions
```

### What Happens Next

1. **GitHub Actions triggers**: Workflow detects changes to `tur/opencode/`
2. **Build process**:
   - Sets up Node.js 20 (LTS)
   - Installs `@opencode-ai/sdk` from npm
   - Creates `.deb` package structure
   - Builds `opencode_0.1.0-1_all.deb`
3. **Publishing** (if on master/main):
   - Updates APT repository on gh-pages branch
   - Regenerates `Packages.gz` (includes all packages)
   - Creates GitHub Release with downloadable `.deb`
4. **Repository accessible**: https://timblaktu.github.io/tur

## Testing After Deployment

### On Termux Device

```bash
# 1. Ensure repository is configured
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

# 2. Update package lists
pkg update

# 3. Install opencode
pkg install opencode

# 4. Verify opencode command exists
which opencode
opencode --version

# 5. Test basic functionality
opencode "hello world"

# 6. Install opencode-wrappers (NOW TESTABLE!)
pkg install opencode-wrappers

# 7. Test wrappers
opencodemax --version
opencodepro --version
opencodework --version  # Should show error about proxy config (expected)

# 8. Verify wrapper functionality
opencodemax "test prompt"
```

### Expected Results

✅ **opencode package**:
- Installs without errors
- `opencode` command available at `$PREFIX/bin/opencode`
- `opencode --version` shows version info
- `opencode "prompt"` works

✅ **opencode-wrappers package** (after opencode installed):
- All three wrappers (`opencodemax`, `opencodepro`, `opencodework`) available
- Wrappers successfully invoke `opencode` binary
- Config directories created (`~/.opencode-max/`, etc.)

## Troubleshooting

### Build Failures

**Check**: GitHub Actions logs at https://github.com/timblaktu/tur/actions

**Common issues**:
- npm installation timeout: Increase timeout in workflow
- Node.js version mismatch: Workflow uses Node 20 LTS
- Permission errors: Verify file permissions in package structure

**Debug locally**:
```bash
# Test npm installation
npm install -g --prefix /tmp/test-npm @opencode-ai/sdk
ls -la /tmp/test-npm/lib/node_modules/@opencode-ai/

# Verify package structure
cd tur/opencode
bash -x ../../tur-package/.github/workflows/build-opencode.yml  # Won't work directly, but shows logic
```

### Installation Failures on Termux

**Check**: `apt install -o Debug::pkgAcquire::Worker=1 opencode`

**Common issues**:
- Repository not added: Re-run repository setup
- Package not in Packages.gz: Check gh-pages branch
- nodejs-lts not installed: `pkg install nodejs-lts` manually

**Manual installation** (bypass repository):
```bash
# Download .deb directly
wget https://github.com/timblaktu/tur/releases/download/opencode-0.1.0-1/opencode_0.1.0-1_all.deb

# Install manually
pkg install ./opencode_0.1.0-1_all.deb
```

### Runtime Errors

**OpenCode command not found after installation**:
```bash
# Verify symlink
ls -la $PREFIX/bin/opencode

# Check node_modules
ls -la $PREFIX/lib/node_modules/@opencode-ai/sdk/

# Reinstall
pkg reinstall opencode
```

**npm errors during installation**:
```bash
# Check Node.js
node --version  # Should be v20.x
npm --version   # Should be 10.x

# Reinstall Node.js
pkg reinstall nodejs-lts
pkg reinstall opencode
```

## Package Architecture

### npm Wrapper Approach

This package wraps npm installation rather than vendoring the binary:

**Advantages**:
1. **Size**: No large binary in git repo
2. **Updates**: Automatic upstream tracking
3. **Maintenance**: Simpler, less to maintain
4. **Compatibility**: npm handles platform details

**Trade-offs**:
- Requires network during installation
- Requires nodejs-lts dependency (~50MB)
- Version in package name may lag behind npm version

### Package Relationships

```
User installs:
  pkg install opencode
    ↓
  Depends: nodejs-lts (installed automatically)
    ↓
  Installs: @opencode-ai/sdk from npm
    ↓
  Provides: /data/data/com.termux/files/usr/bin/opencode
    ↓
opencode-wrappers (opencodemax, opencodepro, opencodework)
  can now invoke opencode binary
```

## Version Management

**Package version**: `0.1.0-1`
- First number (0.1.0): TUR package version
- Second number (1): Package revision

**OpenCode npm version**: Latest from npm (installed dynamically)

**Checking versions**:
```bash
# Package version
dpkg -l opencode

# Actual OpenCode version
opencode --version

# npm upstream version
npm view @opencode-ai/sdk version
```

## Next Steps After Deployment

1. ✅ **Deploy opencode** (this package)
2. ⏳ **Test opencode-wrappers**: Verify all three wrappers work
3. ⏳ **Document results**: Update DEPLOYMENT-STATUS.md
4. ⏳ **Batch deploy**: Deploy all 4 packages together

## Files in This Package

```
tur-package/opencode/
├── build.sh           # TUR package definition
├── README.md          # User documentation
└── DEPLOYMENT.md      # This file (deployment guide)
```

## Related Documentation

- [Main README](../README.md) - Project overview
- [TUR Fork Setup](../TUR-FORK-SETUP.md) - TUR infrastructure setup
- [Integration Guide](../nixcfg-integration/INTEGRATION-GUIDE.md) - Architecture
- [opencode-wrappers README](../opencode-wrappers/README.md) - Wrapper package docs

## Support

**Issues**:
- TUR packaging: https://github.com/timblaktu/tur/issues
- Package source: https://github.com/timblaktu/nixcfg/issues
- OpenCode itself: https://github.com/anomalyco/opencode/issues

---

**Created**: 2026-01-19
**Status**: Ready for deployment
**Priority**: 1 (parallel with claude-code)
