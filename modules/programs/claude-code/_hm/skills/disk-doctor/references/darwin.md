# disk-doctor - macOS module

macOS-specific reclaim levers. Run `scripts/os/darwin.sh` for a read-only probe. The Nix store levers are OS-agnostic (see SKILL.md). **Authored on Linux; runtime-verify on a real macOS host before trusting the probe output.**

## Purgeable space (why `df` lies on APFS)

APFS reports "free" space that includes **purgeable** space - mostly local Time Machine snapshots and caches macOS will evict under pressure. So `df -h /` can look healthier than it is, and deleting files may not immediately move the number. `diskutil info /` distinguishes container free space. When a Mac is "full" despite little visible usage, purgeable (snapshots) is the usual culprit.

## APFS local Time Machine snapshots (biggest hidden win)

- List: `tmutil listlocalsnapshots /`.
- These are automatic local snapshots (even without a Time Machine destination) and can hold many GB.
- Reclaim (user action): `tmutil thinlocalsnapshots / <bytes-to-free> 4` (urgency 4 = most aggressive). On low disk, macOS also thins them automatically, but you can force it.
- Never hand-delete snapshot files; always go through `tmutil`.

## Developer caches (the big regenerable ones)

- `~/Library/Developer/Xcode/DerivedData` - build intermediates; safe to delete, rebuilds on next Xcode build.
- `~/Library/Developer/CoreSimulator` - simulator devices/caches; can be enormous. `xcrun simctl delete unavailable` removes dead simulators.
- `~/Library/Developer/Xcode/iOS DeviceSupport` - per-iOS-version symbol caches; safe to prune old versions.
- `~/Library/Caches` - general app caches; regenerable, but review before bulk deletion.

## Homebrew

- `brew cleanup -s` removes old versions and cached downloads; `brew autoremove` drops unused dependencies. `brew --cache` shows the download cache location.

## Nix on macOS

- Store/GC-roots levers are identical to Linux (SKILL.md). The scheduled GC under nix-darwin is a **launchd** job, not systemd: `launchctl list | grep nix`. `min-free`/`max-free` still apply - `nix config show`.

## Order of attack (macOS)

1. APFS local snapshots via `tmutil` (usually the largest reclaimable chunk).
2. Nix store GC-roots audit + collect (see SKILL.md; protect fresh outputs first).
3. Xcode DerivedData / CoreSimulator / DeviceSupport.
4. `brew cleanup -s` + `~/Library/Caches`.
