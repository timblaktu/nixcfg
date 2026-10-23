# disk-doctor - Linux module

Linux-specific reclaim levers, in rough priority order. Run `scripts/os/linux.sh` for a read-only probe. The Nix store levers (usually the biggest win) are in SKILL.md, not here, because they are OS-agnostic.

## `/tmp` semantics and aging

- `/tmp` may be `tmpfs` (RAM-backed, cleared on reboot) or on-disk (part of `/`, survives reboots). `findmnt /tmp` tells you which. On-disk `/tmp` that is rarely rebooted accumulates indefinitely.
- systemd ages `/tmp` via a `tmpfiles.d` rule, typically `q /tmp 1777 root root 10d` (delete entries untouched for 10 days; `/var/tmp` usually 30d), run by `systemd-tmpfiles-clean.timer`. Aging is by atime/mtime/ctime, so busy subtrees persist past the nominal window.
- **Interaction with Nix:** a Nix out-link left in `/tmp` is an indirect GC-root. It pins its whole closure until the `/tmp` aging rule removes the symlink - which can be weeks, or never if its timestamps keep refreshing. This is the usual cause of a bloated store on a long-lived Linux/WSL box. The GC-roots audit in `analyze.sh` surfaces these.

## Filesystem snapshots

- **ZFS:** `zfs list -t snapshot -o name,used,creation`. Old automatic snapshots (zfs-auto-snapshot, sanoid) can dominate a pool. Destroy with `sudo zfs destroy pool/dataset@snap` (irreversible - confirm with the user).
- **btrfs:** `sudo btrfs subvolume list /` and `sudo btrfs filesystem usage /`. Snapshots and unbalanced metadata both consume space.

## Caches and package managers

- XDG caches under `~/.cache`: common heavy hitters are `go-build`, `nix`, `uv`, browser/puppeteer caches - all regenerable.
- apt: `/var/cache/apt/archives` (`sudo apt-get clean`); an `apt-cacher-ng` proxy cache under `~/.cache` can be large.
- Yocto/ISAR: `~/.cache/yocto/sstate` (shared state) and per-worktree `backends/*/build/` trees are large and **regenerable but slow to rebuild** - deleting sstate forces full rebuilds. The build trees are frequently **root-owned** (container user-namespaces), so a normal `rm` fails; hand the user a `sudo rm -rf ...` line.

## Order of attack (Linux)

1. Nix store: GC-roots audit -> remove stale out-links -> `nix-collect-garbage` (see SKILL.md; protect fresh outputs first).
2. Regenerable dev caches (`~/.cache/*`).
3. Snapshots, if ZFS/btrfs and the user confirms.
4. Yocto/ISAR sstate and build trees (note the rebuild cost; hand over `sudo` for root-owned trees).
