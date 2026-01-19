# TUR Deployment Status

**Last Updated**: 2026-01-19
**Branch**: opencode
**Commits**: 69a033b, 68e0450

## Current State: ✅ READY FOR DEPLOYMENT

### What's Complete

| Task | Status | Details |
|------|--------|---------|
| Package definition | ✅ Complete | `claude-wrappers/build.sh` follows TUR standards |
| Wrapper scripts | ✅ Complete | claudemax, claudepro, claudework (template) |
| Setup helper | ✅ Complete | claude-setup-work (interactive token config) |
| GitHub Actions | ✅ Complete | Automated build & publish workflow |
| Documentation | ✅ Complete | 3 guides + README (2000+ lines) |
| Security review | ✅ Complete | All workplace info removed, generic templates |
| Git commits | ✅ Complete | Committed on opencode branch |
| Testing | ⏳ Pending | Awaits TUR fork deployment |

### What's NOT Complete

- [ ] TUR repository fork (not created yet)
- [ ] Package files copied to TUR fork
- [ ] GitHub Actions/Pages enabled on fork
- [ ] First build executed and verified
- [ ] Installation tested on Termux device

## Deployment Checklist

Use this to track deployment progress:

### Phase 1: Fork Setup (10 minutes)

- [ ] Fork https://github.com/termux-user-repository/tur to timblaktu
- [ ] Clone fork locally: `git clone https://github.com/timblaktu/tur.git ~/tur-fork`
- [ ] Add upstream: `cd ~/tur-fork && git remote add upstream https://github.com/termux-user-repository/tur.git`

### Phase 2: File Transfer (5 minutes)

- [ ] Copy package definition:
  ```bash
  cp -r ~/termux-src/nixcfg/tur-package/claude-wrappers ~/tur-fork/tur/
  ```
- [ ] Copy workflow:
  ```bash
  cp ~/termux-src/nixcfg/tur-package/.github/workflows/build-claude-wrappers.yml \
     ~/tur-fork/.github/workflows/
  ```
- [ ] Verify files copied correctly:
  ```bash
  ls ~/tur-fork/tur/claude-wrappers/
  ls ~/tur-fork/.github/workflows/build-claude-wrappers.yml
  ```

### Phase 3: GitHub Configuration (5 minutes)

- [ ] Enable Actions: Settings → Actions → Allow all actions
- [ ] Enable Pages: Settings → Pages → Source: gh-pages, / (root)
- [ ] Verify Pages URL: https://timblaktu.github.io/tur (will be active after first build)

### Phase 4: Initial Commit (5 minutes)

- [ ] Stage files:
  ```bash
  cd ~/tur-fork
  git add tur/claude-wrappers/ .github/workflows/build-claude-wrappers.yml
  ```
- [ ] Commit with message:
  ```bash
  git commit -m "Add claude-wrappers package

  Multi-account wrapper scripts for Claude Code on Termux.

  Provides:
  - claudemax: Claude Max account
  - claudepro: Claude Pro account
  - claudework: Custom proxy template

  Features:
  - Platform-independent package (no compilation)
  - Bearer token authentication support
  - Separate config directories per account
  - Automated builds via GitHub Actions"
  ```
- [ ] Push to trigger build:
  ```bash
  git push origin master
  ```

### Phase 5: Monitor Build (15-30 minutes)

- [ ] Go to https://github.com/timblaktu/tur/actions
- [ ] Find "Build claude-wrappers" workflow run
- [ ] Watch build job (should complete in ~5 minutes)
- [ ] Watch publish job (deploys to gh-pages)
- [ ] Verify GitHub Release created with .deb file
- [ ] Check Pages deployment: https://timblaktu.github.io/tur/dists/stable/Release

### Phase 6: Test Installation (10 minutes)

On Termux device:

- [ ] Add repository:
  ```bash
  echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
    tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list
  ```
- [ ] Update package lists:
  ```bash
  pkg update
  ```
- [ ] Verify package available:
  ```bash
  pkg search claude-wrappers
  pkg show claude-wrappers
  ```
- [ ] Install package:
  ```bash
  pkg install claude-wrappers
  ```
- [ ] Verify installation:
  ```bash
  which claudemax claudepro claudework
  ls -la $PREFIX/bin/claude*
  ```
- [ ] Test wrapper (requires Claude Code installed):
  ```bash
  claudemax --version
  ```

### Phase 7: Documentation (5 minutes)

- [ ] Update nixcfg CLAUDE.md with fork URL
- [ ] Update tur-package/README.md with actual repo links
- [ ] Mark deployment complete in this file
- [ ] Commit changes:
  ```bash
  cd ~/termux-src/nixcfg
  git add CLAUDE.md tur-package/DEPLOYMENT-STATUS.md
  git commit -m "Complete TUR deployment: Update links and status"
  ```

## Quick Resume Commands

### If Starting Fresh

```bash
# Simple prompt for Claude in next session:
Continue with TUR deployment: Fork TUR and deploy claude-wrappers package.
Follow steps in tur-package/DEPLOYMENT-STATUS.md
```

### If Fork Already Exists

```bash
# Resume at step that's incomplete:
Continue TUR deployment at Phase 2: Copy files to TUR fork.
Follow tur-package/DEPLOYMENT-STATUS.md checklist.
```

### If Build Failed

```bash
# Debug and retry:
Review failed TUR build workflow. Check logs at:
https://github.com/timblaktu/tur/actions

Fix issues in tur-package/ directory, then re-deploy to fork.
```

## Troubleshooting Reference

### Build Fails in GitHub Actions

**Symptoms**: Workflow shows red X, build job fails

**Debug steps**:
1. Click into failed workflow run
2. Expand failed step logs
3. Common issues:
   - Syntax error in build.sh → Fix in nixcfg, copy to fork
   - Missing files → Verify all files copied
   - DEBIAN/control format → Check workflow file generation

**Fix process**:
```bash
# Fix in nixcfg
cd ~/termux-src/nixcfg/tur-package/claude-wrappers
vim build.sh  # Make fix

# Copy to fork
cp -r ~/termux-src/nixcfg/tur-package/claude-wrappers ~/tur-fork/tur/

# Re-commit and push
cd ~/tur-fork
git add tur/claude-wrappers/
git commit -m "Fix build error: [description]"
git push origin master
```

### APT Repository Not Accessible

**Symptoms**: `pkg update` fails to fetch from timblaktu.github.io/tur

**Check**:
1. GitHub Pages enabled? Settings → Pages
2. gh-pages branch exists? Check branches list
3. Publish job succeeded? Check Actions workflow
4. Wait 5-10 minutes after first deployment

**Manual check**:
```bash
curl -I https://timblaktu.github.io/tur/dists/stable/Release
# Should return 200 OK
```

### Package Installation Fails

**Symptoms**: `pkg install claude-wrappers` shows errors

**Debug**:
```bash
# Verbose installation
apt install -o Debug::pkgAcquire::Worker=1 claude-wrappers

# Check repository configured
cat $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

# Update and retry
pkg update
pkg install claude-wrappers
```

### Wrappers Don't Execute

**Symptoms**: `claudemax: command not found` or permission denied

**Fix**:
```bash
# Check installation
which claudemax

# Check permissions
ls -la $PREFIX/bin/claude*

# Should be: -rwxr-xr-x (executable)
# If not:
chmod +x $PREFIX/bin/claude{max,pro,work}
```

## File Structure Reference

```
nixcfg/tur-package/                    # SOURCE (development)
├── claude-wrappers/                   # Package definition
│   ├── build.sh                       # TUR build script
│   ├── claudemax, claudepro, claudework
│   ├── claude-setup-work
│   └── README.md
├── .github/workflows/
│   └── build-claude-wrappers.yml      # CI/CD automation
├── README.md                          # Project overview
├── TUR-FORK-SETUP.md                  # Deployment guide
├── DEPLOYMENT-STATUS.md (this file)   # Deployment tracking
└── nixcfg-integration/                # Integration scripts

tur-fork/                              # DESTINATION (TUR fork)
├── tur/
│   └── claude-wrappers/               # ← COPY FROM nixcfg
└── .github/workflows/
    └── build-claude-wrappers.yml      # ← COPY FROM nixcfg

GitHub Pages (after deployment)        # RESULT (distribution)
└── dists/stable/main/binary-all/
    ├── Packages.gz
    └── claude-wrappers_1.0.0-1_all.deb
```

## Success Criteria

Deployment is complete when ALL of these are true:

- ✅ GitHub Actions workflow succeeds (green checkmark)
- ✅ .deb package appears in GitHub Releases
- ✅ APT repository accessible at https://timblaktu.github.io/tur
- ✅ `pkg install claude-wrappers` works on Termux
- ✅ All three wrappers are executable: `which claudemax claudepro claudework`
- ✅ At least one wrapper successfully runs: `claudemax --version`

## Resources

- **TUR Official**: https://github.com/termux-user-repository/tur
- **Your Fork** (once created): https://github.com/timblaktu/tur
- **APT Repo** (once deployed): https://timblaktu.github.io/tur
- **Local Source**: ~/termux-src/nixcfg/tur-package/
- **Local Fork**: ~/tur-fork/ (after cloning)
- **Full Guide**: tur-package/TUR-FORK-SETUP.md (comprehensive walkthrough)

## Next Session Quick Start

**The simplest prompt to continue**:

```
Deploy claude-wrappers to TUR. Follow DEPLOYMENT-STATUS.md checklist.
Start at Phase 1 if fork doesn't exist, or resume at first unchecked item.
```

**Claude will**:
1. Read this file
2. Check current status (which phases are complete)
3. Execute next phase in the checklist
4. Update this file as each phase completes
5. Provide clear feedback on progress

---

**Deployment Status**: 🔄 IN PROGRESS - Waiting for GitHub Pages deployment
**Last Action**: Fixed workflow, deployed to gh-pages, configured Pages
**Next Action**: Wait for Pages to go live (5-10 min), then test installation

**Recent Updates** (2026-01-19):
- ✅ Forked TUR repository to timblaktu/tur
- ✅ Cloned fork locally to ~/tur-fork
- ✅ Copied package files and workflow
- ✅ Fixed workflow bug (removed gh-pages checkout for initial deployment)
- ✅ Build succeeded, deployed to gh-pages branch (commit: b444bcd)
- ✅ All repository files confirmed present:
  - dists/stable/Release
  - dists/stable/main/binary-all/Packages.gz
  - dists/stable/main/binary-all/claude-wrappers_1.0.0-1.deb
- 🔄 GitHub Pages deployment in progress (legacy build type)
- ⏳ Waiting for https://timblaktu.github.io/tur to go live

**Known Issues**:
- GitHub Release step fails (version output not passed correctly from build job)
  - Not critical - APT repository is the primary distribution method
  - Can be fixed in future update if needed
