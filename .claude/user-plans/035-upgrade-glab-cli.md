# Plan 035: Upgrade glab CLI to Fix --live Signal Handling

**Status**: COMPLETE  
**Created**: 2026-04-15  
**Updated**: 2026-04-28  
**Priority**: LOW (quality-of-life improvement)  
**Repo**: `~/src/nixcfg`

---

## Context

**Issue**: `glab ci status --live` does not respond to Ctrl+C, Esc, or q key presses due to missing signal handling in the main loop. The command only exits when:
1. Pipeline completes (status changes from running/pending to success/failed)
2. Terminal is not a TTY
3. User sends SIGTERM/SIGKILL from another terminal

**Previous version**: glab 1.82.0 (from nixpkgs 25.11 stable)  
**Upgraded to**: glab 1.92.1 (from nixpkgs-unstable, via overlay)  
**Latest upstream**: glab 1.93.0 (GitLab, 2026)  
**Navigator crash fix**: Applied as local patch (unfixed upstream through v1.93.0)  
**Upstream MR**: Pending — fix at `~/src/gitlab-cli` branch `fix/ci-view-navigator-reset`

**Discovered during**: Plan 125 (PaaS VTE deployment) while monitoring CI pipeline with `glab ci status --live --branch feat/CONVSW-1694-basic-paas-package-test`

**Source code analysis**: The `--live` mode implementation in `commands/ci/status/status.go` (glab 1.82.0) has an infinite loop that polls the GitLab API but does not check for interrupt signals or provide an escape mechanism while the pipeline is still running.

---

## Validation Strategy

**Problem**: Cannot reliably test signal handling without a long-running pipeline to interrupt.

**Solution**: Create a synthetic test case using GitLab API triggers or manual pipeline runs:

1. **Trigger a test pipeline** (any branch with slow jobs):
   ```bash
   glab ci trigger -b main
   ```

2. **Start monitoring with --live**:
   ```bash
   glab ci status --live -b main
   ```

3. **Attempt to interrupt** within 10 seconds:
   - Ctrl+C (should exit immediately)
   - q key (if TUI is active)
   - Esc key (if TUI is active)

4. **Success criteria**:
   - Command exits within 1 second of interrupt signal
   - No orphaned processes left running
   - No need to send SIGTERM/SIGKILL from another terminal

**Alternative validation** (if no pipelines available):
- Read the glab 1.91.0 source code at `gitlab-org/cli` to verify signal handling was added
- Check GitLab CLI issue tracker for related bug fixes between 1.82.0 and 1.91.0

---

## Implementation

### Option 1: Upgrade via nixpkgs-unstable (Recommended)

**File**: `modules/programs/gitlab-auth/gitlab-auth.nix`

**Change**: Use unstable glab for all `pkgs.glab` references

```nix
# At the top of the module, add unstable input resolution
{ config, lib, pkgs, inputs, ... }:
let
  # Use unstable glab for bug fixes (signal handling in --live mode)
  glab = inputs.nixpkgs-unstable.legacyPackages.${pkgs.system}.glab;
in
{
  # ... rest of module ...
  
  # Update all pkgs.glab references:
  # Line 40, 51, 67, etc:
  - ${pkgs.glab}/bin/glab
  + ${glab}/bin/glab
}
```

**Requires**: Ensure `nixpkgs-unstable` is available in flake inputs (already present in most configs)

### Option 2: Package Override in Host Configuration

**File**: Host-specific configuration (e.g., `hosts/wsl-debian/default.nix`)

```nix
nixpkgs.config.packageOverrides = pkgs: {
  glab = pkgs.unstable.glab;  # 1.91.0
};
```

### Option 3: Global nixpkgs Overlay

**File**: `flake.nix` or `overlays/default.nix`

```nix
overlays = [
  (final: prev: {
    glab = final.unstable.glab;
  })
];
```

---

## Rollback Plan

If glab 1.91.0 introduces regressions:

```nix
# Revert to stable
glab = pkgs.glab;  # 1.82.0 from nixos-25.11
```

No state files or configs need cleanup - glab is stateless CLI tool with config in `~/.config/glab-cli/config.yml` (unchanged between versions).

---

## Testing Steps

1. **Verify current version**:
   ```bash
   glab --version  # Should show 1.82.0
   ```

2. **Test unstable version in isolation**:
   ```bash
   nix shell nixpkgs/nixos-unstable#glab -c glab --version  # Should show 1.91.0
   ```

3. **Apply upgrade** (choose Option 1, 2, or 3 above)

4. **Rebuild and switch**:
   ```bash
   cd ~/src/nixcfg
   sudo nixos-rebuild switch --flake .#$(hostname)
   ```

5. **Verify upgrade**:
   ```bash
   glab --version  # Should show 1.91.0
   ```

6. **Test signal handling** (see Validation Strategy above)

---

## Related Issues

- **Upstream bug report**: Search https://gitlab.com/gitlab-org/cli/-/issues for "live signal interrupt" or "ctrl+c"
- **Workaround**: Use `glab ci view` (interactive TUI, properly handles Ctrl+Q) instead of `glab ci status --live`
- **Alternative monitoring**: `watch -n 5 glab ci status` (manual refresh, no live mode)

---

## Notes

- **Priority is LOW** because workarounds exist (glab ci view, manual SIGTERM)
- **No breaking changes expected** - glab CLI API is stable between minor versions
- **Commit convention**: If implementing, use `feat(cli): upgrade glab to 1.91.0 for signal handling fixes`
- **Testing window**: Wait until a long-running CI pipeline is available in n3x-infra or another project to validate interrupt behavior

---

## References

- Current usage: `~/src/nixcfg/modules/programs/gitlab-auth/gitlab-auth.nix`
- Source analysis: https://github.com/profclems/glab/blob/trunk/commands/ci/status/status.go (archived fork)
- Official repo: https://gitlab.com/gitlab-org/cli (requires authentication to view raw source)
- nixpkgs package: https://search.nixos.org/packages?query=glab
