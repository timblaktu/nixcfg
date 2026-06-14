# Plan 042: Fix Nixvim nixpkgs.source Warning

## Status: COMPLETE

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

- [x] TASK 1: Research where `programs.nixvim` is configured in the dendritic modules
  - Configured in `modules/programs/neovim/neovim.nix` under `flake.modules.homeManager.neovim`
  - The deferredModule's outer args already expose `inputs`, so Option A applies at module level

- [x] TASK 2: Implement the chosen option (Option A)
  - Added `programs.nixvim.nixpkgs.source = inputs.nixpkgs-unstable;` in `neovim.nix`
  - `nix flake check --no-build` passes; nixvim source warning no longer emitted

- [x] TASK 3: Verify warning is gone
  - `nix run home-manager -- switch --flake '.#tim@pa161878-nixos' --dry-run` succeeds (exit 0)
  - No nixvim / nixpkgs.source / warning lines in output

## Resolution

Chose **Option A**. Set `programs.nixvim.nixpkgs.source = inputs.nixpkgs-unstable;` in
`modules/programs/neovim/neovim.nix`, explicitly acknowledging the `follows` override from
`flake.nix:27`. Single nixpkgs eval preserved, postgres-lsp/other LSP packages still resolve
against nixpkgs-unstable, warning suppressed. Verified via `nix flake check` and home-manager
dry-run on pa161878-nixos.

## Context

- `flake.nix:23-28` — nixvim input with follows
- The comment says `nixpkgs-unstable` is needed for `postgres-lsp` and other LSP packages
- This suggests Option A is preferred (keep follows for package availability, just suppress the warning)
