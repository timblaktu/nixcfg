# Plan 036: Reduce Overlay Peak Memory via overrideAttrs

**Branch**: `refactor/private-overlay`
**Created**: 2026-04-15

## Scope

Replace 3 `builtins.fetchTarball` nixpkgs imports in `overlays/default.nix` with `overrideAttrs` calls against the flake's existing nixpkgs. Additionally, make the pre-commit hook skip `nix flake check` when no Nix files are staged.

**Files modified**: 2 (`overlays/default.nix`, `modules/programs/git/git.nix`)
**Files added**: 1 (`overlays/claude-code-package-lock.json` — version-specific, required by buildNpmPackage)
**Files removed**: 0
**Conventions changed**: 0 — no new patterns introduced; `overrideAttrs` is standard Nix overlay practice

## Why This Will Work

### The memory problem

Each `import (builtins.fetchTarball <nixpkgs-rev>) { system = ...; }` forces the Nix evaluator to instantiate a complete nixpkgs attribute set (~30K expressions). Even though Nix is lazy at the attribute level, the `import nixpkgs {}` call itself runs `config.nix`, `overlays`, `stdenv` bootstrapping, and `lib` — costing ~1.5-2 GB per import regardless of how many packages are accessed. With 3 fetchTarball imports + 1 main nixpkgs + 1 flake input (docling), peak memory hits ~7.8 GB during `nix flake check --no-build`.

### The fix: overrideAttrs eliminates extra imports

`prev.glab.overrideAttrs { version = "1.91.0"; ... }` modifies the existing package from the flake's nixpkgs — no additional nixpkgs import needed. The `finalAttrs` pattern used by all three packages (glab, claude-code, opencode) means changing `version` automatically propagates to `src.url`/`src.tag`. Only version, source hash, and build hash change between versions.

**Expected result**: 3 fewer nixpkgs evaluations = ~5 GB less peak memory. From ~7.8 GB → ~2.5 GB.

### What doesn't change

- **Dendritic pattern**: Untouched. The overlay is still applied in `perSystem` via `flake.nix:98-100`, exported via `modules/flake-parts/overlays.nix`. All modules still access packages via `pkgs.*`.
- **`pkgs/` directory**: Remains for truly custom packages only. No vendored nixpkgs files added there.
- **Package references**: Every module that uses `pkgs.claude-code`, `pkgs.opencode`, or `pkgs.glab` works unchanged — the overlay still provides these attributes.
- **flake.nix inputs**: No new inputs added. No inputs removed.
- **Build outputs**: Identical derivations (same version, same source, same hashes).

### Risks and mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| `overrideAttrs` doesn't propagate correctly for `buildGoModule`'s `vendorHash` | Low — `vendorHash` is a top-level attr, overrideAttrs handles it | Test with `nix eval` before committing |
| claude-code's `package-lock.json` differs between versions | Certain — must vendor the 2.1.97 lockfile | Single file in `overlays/`, clearly documented |
| opencode's nested `node_modules` derivation complicates override | Medium — it uses `finalAttrs.version` internally | If override fails, fall back to vendored package.nix for opencode only |

## Tasks

### T1: Measure baseline memory (`TASK:COMPLETE`)

Run `nix flake check --no-build` under GNU time, record peak RSS. 3 runs for consistency.

**DoD**: Baseline peak RSS documented.

### T2: Convert glab from fetchTarball to overrideAttrs (`TASK:COMPLETE`)

In `overlays/default.nix`, replace:
```nix
pkgsGlab = import (builtins.fetchTarball { ... }) { ... };
# ...
inherit (pkgsGlab) glab;
```
With:
```nix
glab = prev.glab.overrideAttrs (old: {
  version = "1.91.0";
  src = old.src.override {
    tag = "v1.91.0";
    hash = "<hash from pinned rev>";
  };
  vendorHash = "<hash from pinned rev>";
});
```

**DoD**: `nix eval '.#legacyPackages.x86_64-linux.glab.version'` returns `1.91.0`. `nix flake check --no-build` passes.

### T3: Convert claude-code from fetchTarball to overrideAttrs (`TASK:COMPLETE`)

Replace fetchTarball with overrideAttrs. Vendor `package-lock.json` for 2.1.97 at `overlays/claude-code-package-lock.json` (referenced via `postPatch` override).

**DoD**: `pkgs.claude-code` resolves to 2.1.97. `nix flake check --no-build` passes.

### T4: Convert opencode to callPackage vendored package.nix (`TASK:COMPLETE`)

Override version, src hash, and `node_modules` outputHash. The nested `node_modules` derivation uses `finalAttrs.version` and `finalAttrs.src`, so overriding the top-level attrs should propagate.

**Fallback**: If the nested derivation override fails, vendor opencode's `package.nix` as `pkgs/opencode-pinned/package.nix` and callPackage it.

**DoD**: `pkgs.opencode` resolves to 1.4.3. `nix flake check --no-build` passes.

### T5: Make pre-commit hook incremental (`TASK:COMPLETE`)

In `modules/programs/git/git.nix:141-152`, guard the flake check:
```bash
if git diff --cached --name-only | grep -qE '\.(nix)$|^flake\.lock$'; then
  echo "🔍 Running flake check..."
  nix flake check --no-build ...
else
  echo "ℹ️  No .nix files staged, skipping flake check"
fi
```

**DoD**: Non-Nix commits skip flake check. Nix commits still run it.

### T6: Final measurement and cgroup/oomd tuning (`TASK:COMPLETE`)

Re-run memory measurement, diagnose actual memory needs, tune cgroup limits.

**Measurements** (3 runs, unguarded `NIX_NO_GUARD=1`):

| Run | Peak RSS | Wall clock |
|-----|----------|------------|
| 1 | 16.7 GB | 4:55 |
| 2 | 16.5 GB | — |
| 3 | 16.7 GB | 2:45 |

Mean: **16.6 GB** peak RSS (unguarded).

**Key finding**: T1 baseline of "8.6 GB" was RSS-under-cgroup (MemoryHigh=8.2G capped
the resident set; actual working set was ~17G with excess swapped). The refactor DID
eliminate 3 fetchTarball imports, but the true working set was never ~8G — it was always
much larger, just hidden by cgroup throttling.

**Remaining memory contributors**: pkgsDocling (1 full nixpkgs import), pythonPackagesExtensions
+ python3{11,12}Packages.override (watchfiles fix), 80+ checks across 2 systems, 9 NixOS
configs, 7 home configs.

**Cgroup tuning** (27.4G RAM, 7G swap):

| Setting | Old | New | Rationale |
|---------|-----|-----|-----------|
| Per-scope MemoryHigh | 30% (8.2G) | 65% (17.8G) | Above 16.6G peak |
| Per-scope MemoryMax | 35% (9.6G) | 75% (20.5G) | Hard kill for runaway |
| Slice MemoryHigh | 60% (16.4G) | 80% (21.9G) | Single eval headroom |
| Slice MemoryMax | 75% (20.5G) | 90% (24.7G) | Kill at aggregate |
| oomd PressureDuration | 30s | 60s | Tolerate brief spikes |

**Validation**: Guarded eval completed successfully (exit 0, 16.7G RSS, no oomd kills).

## Sequencing

```
T1 → T2 → T3 → T4 → T6
T5 (independent, any time)
```

## Verification

After each task:
- `nix flake check --no-build`
- `nix eval '.#legacyPackages.x86_64-linux.<pkg>.version'` returns expected version
- `home-manager switch --flake ".#${USER}@$(hostname)" --dry-run`

## Critical Files

- `overlays/default.nix` — all overlay changes (T2-T4)
- `overlays/claude-code-package-lock.json` — NEW, version-specific lockfile (T3)
- `modules/programs/git/git.nix:141-152` — pre-commit hook (T5)
