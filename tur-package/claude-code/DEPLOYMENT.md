# claude-code TUR Package - Deployment Guide

**Status**: Ready for deployment (Priority 0 - blocks testing)
**Date**: 2026-01-19

## Overview

This package installs Claude Code binary via npm, providing the `claude` command that `claude-wrappers` depends on.

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
cp -r ~/termux-src/nixcfg/tur-package/claude-code tur/

# 4. Copy the workflow
cp ~/termux-src/nixcfg/tur-package/.github/workflows/build-claude-code.yml \
   .github/workflows/

# 5. Verify files are in place
ls -la tur/claude-code/
ls -la .github/workflows/build-claude-code.yml

# 6. Commit and push
git add tur/claude-code/
git add .github/workflows/build-claude-code.yml
git commit -m "Add claude-code package (Priority 0 - provides claude binary)"
git push origin master

# 7. Watch the build
# Visit: https://github.com/timblaktu/tur/actions
```

### What Happens Next

1. **GitHub Actions triggers**: Workflow detects changes to `tur/claude-code/`
2. **Build process**:
   - Sets up Node.js 20 (LTS)
   - Installs `@anthropic-ai/claude-code` from npm
   - Creates `.deb` package structure
   - Builds `claude-code_0.1.0-1_all.deb`
3. **Publishing** (if on master/main):
   - Updates APT repository on gh-pages branch
   - Regenerates `Packages.gz` (includes both claude-code and claude-wrappers)
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

# 3. Install claude-code
pkg install claude-code

# 4. Verify claude command exists
which claude
claude --version

# 5. Test basic functionality
claude "hello world"

# 6. Install claude-wrappers (NOW TESTABLE!)
pkg install claude-wrappers

# 7. Test wrappers
claudemax --version
claudepro --version
claudework --version  # Should show error about proxy config (expected)

# 8. Verify wrapper functionality
claudemax "test prompt"
```

### Expected Results

✅ **claude-code package**:
- Installs without errors
- `claude` command available at `$PREFIX/bin/claude`
- `claude --version` shows version info
- `claude "prompt"` works

✅ **claude-wrappers package** (after claude-code installed):
- All three wrappers (`claudemax`, `claudepro`, `claudework`) available
- Wrappers successfully invoke `claude` binary
- Config directories created (`~/.claude-max/`, etc.)

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
npm install -g --prefix /tmp/test-npm @anthropic-ai/claude-code
ls -la /tmp/test-npm/lib/node_modules/@anthropic-ai/

# Verify package structure
cd tur/claude-code
bash -x ../../tur-package/.github/workflows/build-claude-code.yml  # Won't work directly, but shows logic
```

### Installation Failures on Termux

**Check**: `apt install -o Debug::pkgAcquire::Worker=1 claude-code`

**Common issues**:
- Repository not added: Re-run repository setup
- Package not in Packages.gz: Check gh-pages branch
- nodejs-lts not installed: `pkg install nodejs-lts` manually

**Manual installation** (bypass repository):
```bash
# Download .deb directly
wget https://github.com/timblaktu/tur/releases/download/claude-code-0.1.0-1/claude-code_0.1.0-1_all.deb

# Install manually
pkg install ./claude-code_0.1.0-1_all.deb
```

### Runtime Errors

**Claude command not found after installation**:
```bash
# Verify symlink
ls -la $PREFIX/bin/claude

# Check node_modules
ls -la $PREFIX/lib/node_modules/@anthropic-ai/claude-code/

# Reinstall
pkg reinstall claude-code
```

**npm errors during installation**:
```bash
# Check Node.js
node --version  # Should be v20.x
npm --version   # Should be 10.x

# Reinstall Node.js
pkg reinstall nodejs-lts
pkg reinstall claude-code
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
  pkg install claude-code
    ↓
  Depends: nodejs-lts (installed automatically)
    ↓
  Installs: @anthropic-ai/claude-code from npm
    ↓
  Provides: /data/data/com.termux/files/usr/bin/claude
    ↓
claude-wrappers (claudemax, claudepro, claudework)
  can now invoke claude binary
```

## Version Management

**Package version**: `0.1.0-1`
- First number (0.1.0): TUR package version
- Second number (1): Package revision

**Claude Code npm version**: Latest from npm (installed dynamically)

**Checking versions**:
```bash
# Package version
dpkg -l claude-code

# Actual Claude Code version
claude --version

# npm upstream version
npm view @anthropic-ai/claude-code version
```

## Next Steps After Deployment

1. ✅ **Deploy claude-code** (this package)
2. ⏳ **Test claude-wrappers**: Verify all three wrappers work
3. ⏳ **Document results**: Update DEPLOYMENT-STATUS.md
4. ⏳ **Plan opencode package**: Similar npm wrapper for opencode binary
5. ⏳ **Plan opencode-wrappers**: Copy/adapt from claude-wrappers

## Files in This Package

```
tur-package/claude-code/
├── build.sh           # TUR package definition
├── README.md          # User documentation
└── DEPLOYMENT.md      # This file (deployment guide)
```

## Related Documentation

- [Main README](../README.md) - Project overview
- [TUR Fork Setup](../TUR-FORK-SETUP.md) - TUR infrastructure setup
- [Integration Guide](../nixcfg-integration/INTEGRATION-GUIDE.md) - Architecture
- [claude-wrappers README](../claude-wrappers/README.md) - Wrapper package docs

## Support

**Issues**:
- TUR packaging: https://github.com/timblaktu/tur/issues
- Package source: https://github.com/timblaktu/nixcfg/issues
- Claude Code itself: https://github.com/anthropics/claude-code/issues

---

**Created**: 2026-01-19
**Status**: Ready for deployment
**Priority**: 0 (blocks testing of claude-wrappers v1.0.1)
