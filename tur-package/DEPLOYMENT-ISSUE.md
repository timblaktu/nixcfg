# TUR Package Deployment Issue - 2026-01-19/20

## Critical Bug Discovered

**Status**: ⚠️ BLOCKED - Only 1 of 4 packages published

### Problem Summary

All 4 packages (claude-code, claude-wrappers, opencode, opencode-wrappers) build successfully, but only claude-wrappers is currently published to the APT repository. The other packages are being overwritten instead of accumulating.

### Root Cause

**File**: `~/tur-fork/.github/workflows/build-claude-wrappers.yml:178`

```yaml
# WRONG - This wipes all existing packages
- name: Deploy to GitHub Pages
  uses: peaceiris/actions-gh-pages@v3
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./repo
    force_orphan: true  # ← PROBLEM: Creates orphan commit, deletes everything
```

**Correct Configuration** (used in other workflows):

```yaml
# CORRECT - This preserves existing packages
- name: Deploy to GitHub Pages
  uses: peaceiris/actions-gh-pages@v3
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./repo
    keep_files: true  # ← SOLUTION: Keeps existing files
```

### Impact

| Package | Build Status | Published | Issue |
|---------|--------------|-----------|-------|
| claude-code | ✅ SUCCESS | ❌ Overwritten | Wiped by force_orphan |
| claude-wrappers | ✅ SUCCESS | ✅ Published | Uses force_orphan (last to run) |
| opencode | ⚠️ BUILD OK, PUBLISH FAILS | ❌ Never published | Git error + force_orphan |
| opencode-wrappers | ✅ SUCCESS | ❌ Overwritten | Wiped by force_orphan |

### Current Repository State

**Published APT Repository** (https://timblaktu.github.io/tur/dists/stable/main/binary-all/):
- claude-wrappers_1.0.1-1.deb (3.9 KB)

**TUR Fork Commits**:
- master branch: `4215392` (all 4 packages merged)
- gh-pages branch: `e61d93d` (only claude-wrappers present)

### Secondary Issue: opencode Publish Failure

The opencode workflow has an additional issue where the publish step fails with:

```
Error: The process '/usr/bin/git' failed with exit code 1
```

This happens during the "Publish to APT repository" step after the package builds successfully. The artifact is created, but the git push to gh-pages fails. This needs investigation after fixing the force_orphan issue.

### Solution Steps

1. **Fix workflow configuration**:
   ```bash
   cd ~/tur-fork
   git checkout master
   # Edit .github/workflows/build-claude-wrappers.yml line 178
   # Change: force_orphan: true → keep_files: true
   git add .github/workflows/build-claude-wrappers.yml
   git commit -m "Fix: Use keep_files instead of force_orphan to preserve packages"
   git push origin master
   ```

2. **Trigger all builds** (after workflow fix):
   ```bash
   gh workflow run "Build claude-code" --ref master -f force_rebuild=true --repo timblaktu/tur
   gh workflow run "Build claude-wrappers" --ref master -f force_rebuild=true --repo timblaktu/tur
   gh workflow run "Build opencode" --ref master -f force_rebuild=true --repo timblaktu/tur
   gh workflow run "Build opencode-wrappers" --ref master -f force_rebuild=true --repo timblaktu/tur
   ```

3. **Monitor builds**:
   ```bash
   gh run list --repo timblaktu/tur --limit 10
   # Wait for all 4 to complete successfully
   ```

4. **Verify publication**:
   ```bash
   # Check gh-pages branch
   git checkout gh-pages
   git pull origin gh-pages
   ls -lh dists/stable/main/binary-all/*.deb
   # Should see all 4 packages

   # Or check via web
   curl -s https://api.github.com/repos/timblaktu/tur/contents/dists/stable/main/binary-all | jq '.[] | select(.name | endswith(".deb")) | .name'
   ```

5. **Test installation** (on Termux device):
   ```bash
   # Add repository
   echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
     tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

   # Update and install
   pkg update
   pkg install claude-code claude-wrappers opencode opencode-wrappers

   # Verify
   claude --version
   opencode --version
   claudemax --version
   opencodemax --version
   ```

### Debug Commands

**Check workflow runs**:
```bash
gh run list --repo timblaktu/tur --limit 10 --json status,conclusion,name,createdAt
```

**Check published packages**:
```bash
cd ~/tur-fork
git checkout gh-pages
git pull origin gh-pages
ls -lh dists/stable/main/binary-all/
```

**View specific run failure**:
```bash
gh run view RUN_ID --repo timblaktu/tur --log-failed
```

**Manually trigger workflow**:
```bash
gh workflow run "Build PACKAGE_NAME" --ref master -f force_rebuild=true --repo timblaktu/tur
```

### Timeline

- **2026-01-19**: All 4 packages created, merged to master
- **2026-01-19**: Initial builds triggered, appeared successful
- **2026-01-20 00:44-00:50**: Discovered packages overwriting each other
- **2026-01-20 04:08-04:10**: Multiple rebuild attempts, confirmed force_orphan issue
- **2026-01-20 04:11**: Bug documented, awaiting fix

### Related Files

- Workflow: `~/tur-fork/.github/workflows/build-claude-wrappers.yml`
- Published packages: https://timblaktu.github.io/tur/dists/stable/main/binary-all/
- Actions dashboard: https://github.com/timblaktu/tur/actions
- Package definitions: `~/tur-fork/tur/{claude-code,claude-wrappers,opencode,opencode-wrappers}/`
