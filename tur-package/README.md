# Termux Package Building - TUR Integration

Complete implementation of Claude Code multi-account wrappers as Termux `.deb` packages distributed via a personal TUR (Termux User Repository) fork.

## Executive Summary

**Status**: ✅ All 4 Packages Deployed - Ready for Testing

**What we built**:
- ✅ Production-ready Termux packages for Claude Code and OpenCode
- ✅ Multi-account wrappers for both: `claudemax`, `claudepro`, `claudework`, `opencodemax`, `opencodepro`, `opencodework`
- ✅ GitHub Actions CI/CD for automated builds and publishing (4 workflows)
- ✅ APT repository setup via GitHub Pages
- ✅ Setup scripts and comprehensive documentation
- ✅ Workflow bug fixed (force_orphan → keep_files)

**Architecture**: Producer-Consumer pattern
- **TUR Fork** (timblaktu/tur): Produces and distributes `.deb` packages
- **nixcfg Repo**: Documents usage and provides setup scripts

**Package Status** (2026-01-20):
- `claude-code`: ✅ v0.1.0-1 deployed (22 MB npm wrapper)
- `claude-wrappers`: ✅ v1.0.1-1 deployed (3.9 KB)
- `opencode`: ✅ v0.1.0-1 deployed (44 KB npm wrapper)
- `opencode-wrappers`: ✅ v1.0.0-1 deployed (3.9 KB)

**Deployment Complete**: All packages published at https://timblaktu.github.io/tur/dists/stable/main/binary-all/

## Quick Start

### For End Users (Termux Device)

```bash
# Option 1: One-command setup (recommended)
curl -sSL https://raw.githubusercontent.com/timblaktu/nixcfg/main/tur-package/nixcfg-integration/setup-termux-repos.sh | bash

# Option 2: Manual installation
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list
pkg update
pkg install claude-wrappers
```

### For Maintainers (Setting Up TUR Fork)

See [TUR-FORK-SETUP.md](TUR-FORK-SETUP.md) for complete guide.

**Quick overview**:
1. Fork https://github.com/termux-user-repository/tur
2. Copy `claude-wrappers/` to `tur/` directory in fork
3. Copy `.github/workflows/build-claude-wrappers.yml` to fork
4. Enable GitHub Actions and Pages
5. Push changes - CI/CD builds and publishes automatically

## Project Structure

```
tur-package/
├── README.md (this file)             # Overview
├── TUR-FORK-SETUP.md                 # Complete TUR setup guide
├── DEPLOYMENT-STATUS.md              # Deployment tracking
│
├── claude-code/                      # ✅ Ready to deploy
│   ├── build.sh                      # Package definition (npm wrapper)
│   ├── README.md                     # Package documentation
│   └── DEPLOYMENT.md                 # Deployment guide
│
├── claude-wrappers/                  # ✅ Deployed v1.0.1
│   ├── build.sh                      # Package definition
│   ├── claudemax                     # Max account wrapper
│   ├── claudepro                     # Pro account wrapper
│   ├── claudework                    # Work account wrapper
│   ├── claude-setup-work             # Setup helper
│   └── README.md                     # Package documentation
│
├── opencode/                         # ✅ Ready to deploy
│   ├── build.sh                      # Package definition (npm wrapper)
│   ├── README.md                     # Package documentation
│   └── DEPLOYMENT.md                 # Deployment guide
│
├── opencode-wrappers/                # ✅ Ready to deploy
│   ├── build.sh                      # Package definition
│   ├── opencodemax                   # Max account wrapper
│   ├── opencodepro                   # Pro account wrapper
│   ├── opencodework                  # Work account wrapper
│   ├── opencode-setup-work           # Setup helper
│   └── README.md                     # Package documentation
│
├── .github/
│   └── workflows/
│       ├── build-claude-code.yml     # ✅ CI/CD for claude-code
│       ├── build-claude-wrappers.yml # ✅ CI/CD for claude-wrappers
│       ├── build-opencode.yml        # ✅ CI/CD for opencode
│       └── build-opencode-wrappers.yml # ✅ CI/CD for opencode-wrappers
│
└── nixcfg-integration/               # For nixcfg users
    ├── INTEGRATION-GUIDE.md          # Integration architecture
    └── setup-termux-repos.sh         # Termux setup script
```

## What's Included

### 1. Package Definition (`claude-wrappers/`)

**Files**:
- `build.sh` - Termux package build script following TUR conventions
- `claudemax`, `claudepro`, `claudework` - Wrapper scripts
- `claude-setup-work` - Interactive setup for work account
- `README.md` - Package documentation

**Features**:
- Platform-independent (no compilation needed)
- Separate config directories per account
- Bearer token authentication for proxy
- Telemetry disabled by default
- Helpful error messages
- Post-installation instructions

### 2. CI/CD Workflow (`.github/workflows/`)

**Automation**:
- Triggers on push to `tur/claude-wrappers/`
- Builds `.deb` package
- Publishes to GitHub Pages APT repository
- Creates GitHub Releases with package files
- Multi-architecture matrix (though package is arch-independent)

**GitHub Actions jobs**:
1. **Build**: Creates `.deb`, uploads artifact
2. **Publish**: Updates APT repo, deploys to Pages, creates release

### 3. Documentation

- **TUR-FORK-SETUP.md**: Complete guide for forking TUR and setting up packages
- **nixcfg-integration/INTEGRATION-GUIDE.md**: Architecture and integration options
- **nixcfg-integration/setup-termux-repos.sh**: One-command setup for users
- **claude-wrappers/README.md**: End-user package documentation

## Implementation Highlights

### Follows TUR Best Practices

✅ Uses TUR package structure and conventions
✅ Compatible with termux-packages build system
✅ Platform-independent package (SKIP_SRC_EXTRACT)
✅ Proper DEBIAN control file format
✅ Post-installation messages
✅ Suggests dependencies without enforcing

### Production Quality

✅ Comprehensive error handling
✅ Security-conscious (chmod 600 for tokens)
✅ Interactive setup helpers
✅ Clear user feedback
✅ Follows XDG conventions
✅ Extensive documentation

### CI/CD Ready

✅ GitHub Actions workflow
✅ Automated building
✅ APT repository generation
✅ GitHub Pages deployment
✅ Release automation

## Usage Examples

### Basic Usage

```bash
# Use different accounts
claudemax "help with bash"
claudepro "review this code"
claudework "analyze code"  # After configuring proxy

# Check configuration
claudemax env | grep CLAUDE
claudework env | grep ANTHROPIC

# Get help
claudemax --help
```

### Work Account Setup

```bash
# Interactive setup
claude-setup-work

# Manual setup
mkdir -p ~/.secrets
echo 'bearer-token-here' > ~/.secrets/claude-work-token
chmod 600 ~/.secrets/claude-work-token

# Test
claudework --version
```

### Configuration

Each account uses separate directory:
- `~/.claude-max/` - Max account config
- `~/.claude-pro/` - Pro account config
- `~/.claude-work/` - Work account config

## Deployment Workflow

### One-Time Setup

1. **Fork TUR**:
   ```bash
   # On GitHub: Fork https://github.com/termux-user-repository/tur
   git clone https://github.com/timblaktu/tur.git
   ```

2. **Copy Package**:
   ```bash
   cp -r ~/termux-src/nixcfg/tur-package/claude-wrappers ~/path/to/tur/tur/
   cp ~/termux-src/nixcfg/tur-package/.github/workflows/build-claude-wrappers.yml \
      ~/path/to/tur/.github/workflows/
   ```

3. **Configure GitHub**:
   - Enable Actions
   - Enable Pages (gh-pages branch)
   - Push changes

### Update Workflow

```bash
# 1. Edit in nixcfg (easier to work with)
cd ~/termux-src/nixcfg/tur-package/claude-wrappers
vim claudework

# 2. Copy to TUR fork
cp -r ~/termux-src/nixcfg/tur-package/claude-wrappers ~/path/to/tur/tur/

# 3. Commit and push
cd ~/path/to/tur
git add tur/claude-wrappers/
git commit -m "Update claude-wrappers to 1.0.1"
git push origin master

# 4. GitHub Actions builds automatically
# 5. Users upgrade: pkg upgrade claude-wrappers
```

## Testing on Termux

**Comprehensive Testing Guide**: See [TERMUX-TESTING.md](TERMUX-TESTING.md) for detailed testing instructions.

### Quick Testing Steps

1. **Install packages**:
   ```bash
   echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
     tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list
   pkg update
   pkg install claude-code claude-wrappers opencode opencode-wrappers
   ```

2. **Verify installation**:
   ```bash
   claude --version && opencode --version
   which claudemax claudepro claudework
   which opencodemax opencodepro opencodework
   ```

3. **Test wrappers**:
   ```bash
   claudemax --help
   opencodemax --help
   ```

### Testing Checklist Summary

✅ **Deployment Complete** (2026-01-20):
- [x] All 4 packages published to APT repository
- [x] GitHub Actions workflows executing successfully
- [x] Workflow bug fixed (force_orphan → keep_files)
- [x] All packages accessible via HTTPS

⏳ **On-Device Testing Required**:
- [ ] Installation on Termux device
- [ ] Binary functionality (claude, opencode)
- [ ] Wrapper functionality (all 6 wrappers)
- [ ] Configuration directory creation
- [ ] Telemetry disabling verification
- [ ] Multiple account switching

See [TERMUX-TESTING.md](TERMUX-TESTING.md) for complete testing procedures and troubleshooting.

## Troubleshooting

### Build Failures

**Check**: GitHub Actions logs for detailed errors

**Common issues**:
- Syntax errors in build.sh
- Missing files
- Incorrect paths
- DEBIAN/control format issues

**Fix**: Review package definition, test locally with Docker

### APT Repository Issues

**Check**: GitHub Pages URL: https://timblaktu.github.io/tur

**Common issues**:
- Pages not enabled
- gh-pages branch missing
- Packages.gz not generated
- Release file malformed

**Fix**: Verify Pages settings, check workflow publish job

### Installation Failures

**Check**: `apt install -o Debug::pkgAcquire::Worker=1 claude-wrappers`

**Common issues**:
- Repository not added
- Package lists not updated
- Network connectivity
- Permission issues

**Fix**: Re-run setup-termux-repos.sh, check repository configuration

## Advantages Over Previous Approach

| Feature | Shell Scripts | Termux Packages |
|---------|---------------|-----------------|
| Installation | Manual copy | `pkg install` |
| Updates | Manual | `pkg upgrade` |
| Versioning | None | Proper versions |
| Discovery | Hidden | `pkg search` |
| Removal | Manual | `pkg remove` |
| Dependencies | Manual | Tracked |
| Integration | None | Full Termux ecosystem |

## Future Enhancements

### Possible Improvements

1. **Additional Packages**
   - ✅ OpenCode wrappers (COMPLETED - opencode + opencode-wrappers)
   - MCP server packages
   - Configuration templates

2. **Automation**
   - Auto-sync from nixcfg to TUR fork
   - Version bump scripts
   - Release notes generation

3. **Testing**
   - Automated package testing
   - Integration tests
   - Installation verification

4. **Upstream Contribution**
   - Submit to official TUR
   - Benefit wider Termux community

## Resources

### Documentation
- [TUR Fork Setup Guide](TUR-FORK-SETUP.md) - Complete setup walkthrough
- [Integration Guide](nixcfg-integration/INTEGRATION-GUIDE.md) - Architecture details
- [Package README](claude-wrappers/README.md) - User documentation

### External Resources
- [TUR Repository](https://github.com/termux-user-repository/tur)
- [Termux Packages Wiki](https://github.com/termux/termux-packages/wiki)
- [Creating Termux Packages](https://github.com/termux/termux-packages/wiki/Creating-new-package)

### Your Resources
- **TUR Fork**: https://github.com/timblaktu/tur (to be created)
- **APT Repository**: https://timblaktu.github.io/tur (after setup)
- **nixcfg Source**: https://github.com/timblaktu/nixcfg

## Support

Questions or issues:
1. Check [TUR-FORK-SETUP.md](TUR-FORK-SETUP.md) troubleshooting section
2. Review [TUR discussions](https://github.com/termux-user-repository/tur/discussions)
3. Open issue on your fork

## License

MIT (consistent with nixcfg repository)

---

**Implementation Date**: 2026-01-19
**Status**: Ready for deployment
**Next Step**: Fork TUR and deploy (see TUR-FORK-SETUP.md)
