---
name: disk-doctor
description: Diagnose and reclaim local disk space on Linux, WSL, and macOS - audits the Nix store and GC-roots, caches, temp, and build directories, then proposes a ranked, safe reclaim plan. Use when a disk or filesystem is full or low on space, the Nix store is huge, a build fails for lack of space, or someone asks to free up / clean up / reclaim disk.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/analyze.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/os/*), Read
metadata:
  version: "0.1.0"
  environments: "linux, wsl, darwin"
compatibility: "Full features require Nix on PATH; degrades gracefully to coreutils-only analysis without it."
---

# disk-doctor

Reclaim local disk space safely. The method is identical everywhere; only the discovery/reclaim *levers* differ per operating system, so this skill has a shared core plus one environment module that loads on demand.

## Golden rule

**Analysis is always safe and always first. Deletion is always proposed, never automatic.** Never delete anything the user has not seen in a ranked plan and approved. Hand every `sudo` step to the user as a paste-ready command - do not run `sudo` non-interactively.

## Procedure (every platform)

1. **Triage (read-only).** Run the core analyzer:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/analyze.sh
   ```
   It reports: filesystem usage, largest directories, Nix store size + dead-path count, the **GC-roots audit** (see below), and cache sizes. It writes nothing.

2. **Dispatch to the environment module.** Detect the environment and load its reference, then run its probe:
   - `uname -s` = `Darwin` -> read `references/darwin.md`, run `scripts/os/darwin.sh`
   - `uname -s` = `Linux` and WSL (either `$WSL_DISTRO`/`$WSL_DISTRO_NAME` is set, or `microsoft` appears in `/proc/sys/kernel/osrelease`) -> read `references/wsl.md`, run `scripts/os/wsl.sh`
   - `uname -s` = `Linux` otherwise -> read `references/linux.md`, run `scripts/os/linux.sh`

   The module surfaces the OS-specific levers (temp semantics, snapshots, OS/dev caches, package-manager caches).

3. **Classify** every candidate by **safety x size x age, oldest first.** Prefer targets that are large, old, and regenerable. Separate: (a) always-safe regenerable caches/dead store paths; (b) expensive-to-rebuild artifacts; (c) anything root-owned or needing `sudo`.

4. **Protect before collecting.** If any *fresh or wanted* build output is currently unrooted (and would therefore be collected), pin it with a real GC-root first:
   ```bash
   nix-store --realise <path> --add-root "$HOME/.nix-gcroots-keep/$(basename <path>)" --indirect
   ```
   Only then collect. This is the single most important safety step - see "Nix store" below for why.

5. **Propose a ranked plan.** Present a table (target, size, age, what it is, how it regenerates, safety). Recommend tiers. Wait for approval.

6. **Execute approved tiers**, oldest-first, measuring free space before and after each (`df -h /`). Report the reclaimed amount honestly, including when it is smaller than expected (see the auto-optimise gotcha).

7. **Stop at anything destructive-and-uncertain.** If a target is root-owned, hand the user the exact `sudo rm -rf ...` line. Never kill a running build to free space.

## The Nix store (OS-agnostic - usually the biggest win)

The Nix store is identical on Linux, WSL, and macOS, and is often where the space hides. Key facts the analyzer surfaces:

- **GC-roots audit is the #1 lever.** Most of the store is *live* only because something roots it. `result` symlinks and `nix build --out-link` targets register **indirect GC-roots** under `/nix/var/nix/gcroots/auto/` that pin an entire closure. Stale out-links - especially under `/tmp` - can pin tens of GB of images/AMIs that nothing needs. The audit enumerates each root, resolves its target, flags stale `/tmp` ones, and sizes the closure it pins (`nix path-info -Sh`). Removing a stale out-link symlink makes its closure collectable.
- **Collect dead paths** with `nix-collect-garbage` (keeps all generations) or `nix-collect-garbage -d` (also prunes old generations). Dead = reachable from no root; collecting it is what GC is for.
- **auto-optimise masks per-path reclaim.** If `auto-optimise-store = true`, identical files are hard-linked, so deleting thousands of paths can free surprisingly little. Report this honestly; do not promise a number you cannot verify.
- **The `min-free` emergency GC is a hazard, not a feature, for in-flight work.** When free space drops below `min-free` (query `nix config show | grep -E 'min-free|max-free'`), the daemon auto-deletes *unrooted* store paths mid-build - including `nix-store --add-fixed` FODs. If a session depends on unrooted artifacts, root them (step 4) before doing anything that consumes space.
- Query the live config, never assume: `nix config show` for `min-free`/`max-free`/`auto-optimise-store`; the scheduled GC (e.g. `nix-collect-garbage --delete-older-than Nd`) is run by a service/timer, not by you.

## Cross-cutting gotchas

- A "100% cached"/already-deduped store reclaims little per path - size the *closures*, not the paths.
- `du` on `/nix/store` is slow; prefer `df` for the mount and `nix path-info -S` for closures.
- Regenerable != free: an ISAR/Yocto `sstate` cache or build tree is safe to delete but costs a slow rebuild. Say so in the plan.
- Deleting a build tree does not delete its external shared cache (and vice-versa) - name both if relevant.

## Quiet mode (for hooks)

`${CLAUDE_SKILL_DIR}/scripts/analyze.sh --quiet` prints one line - `FREE=<bytes> PCT=<used%> MOUNT=/` - for a low-disk warning hook. No other output.

## Resources

- `references/linux.md`, `references/wsl.md`, `references/darwin.md` - per-environment levers (load only the one that matches).
- `scripts/analyze.sh` - OS-agnostic read-only triage (store + GC-roots + generic scan).
- `scripts/os/{linux,wsl,darwin}.sh` - per-environment read-only probes; each self-asserts its environment.
- `evals/` - evaluation scenarios (authoring/dev only; not needed at runtime).
