# Plan 042: Fix Nixvim nixpkgs.source Warning

## Status: PENDING

## Problem

Every `home-manager switch` and `nix flake check` emits this warning:

```
trace: warning: The `programs.nixvim.nixpkgs.source` default value has been affected by your flake input `follows`.
Nixvim's inputs pin Nixpkgs to `4df1b885d76a54e1aa1a318f8d16fd6005b6401f`. Actual Nixpkgs is following `cbb5cf358f50aa6acc9efd6113b7bcfbc352cd73`.
Please remove your `inputs.nixvim.inputs.nixpkgs.follows` or explicitly define `programs.nixvim.nixpkgs.source` to suppress this warning.
```

## Root Cause

In `flake.nix:23-28`, the nixvim input uses `inputs.nixpkgs.follows = "nixpkgs-unstable"`. Nixvim now warns when its pinned nixpkgs is overridden via `follows`, because some LSP server definitions may depend on packages only available in their pinned nixpkgs.

## Options

### Option A: Set `programs.nixvim.nixpkgs.source` explicitly
- Add `programs.nixvim.nixpkgs.source = inputs.nixpkgs-unstable;` (or whichever nixpkgs you want nixvim to use) in the home-manager config
- Keeps the `follows` but suppresses the warning by explicitly acknowledging the override
- **Pros**: Explicit, keeps single nixpkgs eval, no extra download
- **Cons**: Need to find where nixvim is configured in the dendritic modules

### Option B: Remove the `follows` entirely
- Let nixvim use its own pinned nixpkgs
- **Pros**: Simplest, nixvim uses versions it's tested against
- **Cons**: Two separate nixpkgs evaluations (more memory, longer eval), potential package version mismatches

### Option C: Remove `follows` and set `inputs.nixvim.inputs.nixpkgs.url` to match ours
- Pin nixvim's nixpkgs to the same rev as our `nixpkgs-unstable`
- **Pros**: Same packages, no warning
- **Cons**: Must update manually, fragile

## Tasks

- [ ] TASK 1: Research where `programs.nixvim` is configured in the dendritic modules
  - Check `modules/programs/` for nixvim module
  - Identify which hosts import it
  - Determine if Option A can be applied at the module level

- [ ] TASK 2: Implement the chosen option
  - If Option A: add `programs.nixvim.nixpkgs.source` in the nixvim module
  - If Option B: remove the `follows` line from `flake.nix:27`
  - Test with `nix flake check --no-build`

- [ ] TASK 3: Verify warning is gone
  - Run `home-manager switch --flake '.#tim@$(hostname)' --dry-run`
  - Confirm no nixvim source warning in output

## Context

- `flake.nix:23-28` — nixvim input with follows
- The comment says `nixpkgs-unstable` is needed for `postgres-lsp` and other LSP packages
- This suggests Option A is preferred (keep follows for package availability, just suppress the warning)
