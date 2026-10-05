# disk-doctor - WSL module

WSL is Linux, so **everything in `references/linux.md` applies** - read it too, and run both `scripts/os/linux.sh` and `scripts/os/wsl.sh`. This file covers only the WSL-specific concerns.

## The `.vhdx` sparse-growth trap (most important)

WSL2 stores the distro's filesystem in a virtual disk (`.vhdx`) on the Windows host. The `.vhdx` **grows** as you consume space but does **not** automatically **shrink** when you delete files. Consequences:

- Reclaiming space *inside* WSL frees the Linux filesystem immediately, but the Windows-side `.vhdx` stays at its high-water mark, so Windows still shows the disk as full.
- To actually return the space to Windows, after freeing it inside WSL (user action, Windows-side):
  1. `wsl --shutdown` (PowerShell/cmd).
  2. Compact the disk: `Optimize-VHD -Path <distro.vhdx> -Mode Full` (Hyper-V available), or `diskpart` -> `select vdisk file="<distro.vhdx>"` -> `compact vdisk`.
- The `.vhdx` lives under `%LOCALAPPDATA%\Packages\<DistroPackage>\LocalState\` on Windows.

## `/tmp` on WSL

`/tmp` is on-disk here (not tmpfs) and the box is rarely rebooted, so stale Nix out-links under `/tmp` accumulate aggressively - this is the dominant store-bloat cause on this host. Prioritize the GC-roots audit.

## Windows temp visible via `/mnt/c`

`/mnt/c/Users/*/AppData/Local/Temp` can be large but is **Windows-owned** - clean it from Windows (Disk Cleanup / Storage Sense), never with `rm` from WSL (permissions and semantics differ, and it won't shrink the Linux `.vhdx` anyway).

## 9p / drvfs mounts

`/mnt/*` drives are 9p/drvfs bridges to Windows, not reclaimable from WSL. Noted only so you don't mistake their apparent size for Linux usage. (Unrelated gotcha: 9p mounts can make `sync()` block - relevant to builds, not to disk reclaim.)

## Order of attack (WSL)

1. Free space inside WSL using the Linux order (`references/linux.md`), starting with the Nix GC-roots audit.
2. Then, if Windows still reports the disk full, hand the user the `wsl --shutdown` + `.vhdx` compact steps above.
