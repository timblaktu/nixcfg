# Plan 055 PM — Portable `linux-builder-vz` module: design note

Status: DESIGN SKETCH (eval-gated). SAFE-OFF, adopted by no host. Gated on plan 055 **P9**.
Companion to `055-rosetta-multiarch.md` (task PM) and `055-rosetta-multiarch-reference.md` (§4.5/§6.5).
Author date: 2026-08-31.

This note satisfies PM's "design + eval-gate only - NO adoption" contract. It deliberately does
**not** choose a reference-§7 option (A/B/C/D); it provides the reusable mechanism that whichever
option P9 picks would consume, and proves that mechanism *evaluates* on a darwin config.

## 1. What was built

A single dendritic darwin feature module:

- File: `modules/system/settings/linux-builder-vz/linux-builder-vz.nix`
- Provides: `flake.modules.darwin.linux-builder-vz` (auto-loaded by `import-tree`; available as
  `self.modules.darwin.linux-builder-vz`).
- Option namespace: `linuxBuilderVz.*`, `enable` defaults **false**.
- Imported by **no host**. Because it is available-only and default-off, the whole flake evaluates
  exactly as before (the eval-gate below confirms this).

It follows the existing cross-platform-feature idiom in the repo (mirrors
`modules/system/networking/mss-clamp/mss-clamp.nix`: heavy WHY docs, `mkEnableOption`, SAFE-off,
`config = lib.mkIf cfg.enable {...}`).

## 2. Option surface

| Option | Default | Maps to (when `enable`) | Notes |
|---|---|---|---|
| `enable` | `false` | (gates everything) | No host adopts until P9. |
| `systems` | `["aarch64-linux" "x86_64-linux"]` | `nix.linux-builder.systems` | aarch64 native; x86_64 Rosetta-translated. |
| `rosetta` | `true` | guest `virtualisation.vz.rosetta.enable` | Needs host Rosetta; false ⇒ aarch64-only. |
| `nestedVirtualization` | `false` | guest `virtualisation.vz.nestedVirtualization` | **M3+/macOS15+ only**; the VM-test hook. |
| `ephemeral` | `false` | `nix.linux-builder.ephemeral` | Matches upstream (persistent builder, warm cache). `true` = wipe guest FS each restart (clean config, slower cold builds; reference §4.5). |
| `maxJobs` | `4` | `nix.linux-builder.maxJobs` | |
| `cores` | `6` | guest `virtualisation.cores` | |
| `memorySize` | `8192` (MB) | guest `virtualisation.darwin-builder.memorySize` | 3 GiB stock default is too small. |
| `diskSize` | `40960` (MB) | guest `virtualisation.darwin-builder.diskSize` | |
| `trustAdmins` | `true` | `nix.settings.trusted-users = ["@admin"]` | |

Attribute paths verified against our pinned nixpkgs source (P1): `nix.linux-builder.*` (nix-darwin),
`virtualisation.vz.{rosetta.enable,nestedVirtualization}` (`nixos/modules/virtualisation/vz-vm.nix`:81,100),
`virtualisation.darwin-builder.{memorySize,diskSize}` + `virtualisation.cores`.

## 3. What it supersedes - and what it deliberately does not

**Build-side (this module's job).** For an Apple Silicon *build host* it replaces two current
workarounds:
- the x86_64-host QEMU binfmt cross-build path
  (`modules/system/settings/dev-team/dev-team.nix`: `boot.binfmt.emulatedSystems`) - on a Mac,
  x86_64-linux is Rosetta-translated instead of QEMU-emulated (reference §4: ~2.5x on the author's
  benchmark; **our** number is P2's job to measure);
- the "must build the aarch64 Mac-VM qcow2 on native aarch64" constraint around
  `modules/hosts/nixos-dev-team-vm [N]/` - an Apple Silicon host builds aarch64 Linux closures
  natively, no emulation detour.

This is a **routing choice between machines**, not an in-place edit of the NixOS modules: the binfmt
path stays correct for x86_64 Linux hosts; this module is what a Mac host would use instead.

**Test-side (explicitly NOT solved here).** Moving NixOS VM *tests* onto the Mac is architecturally
constrained and generation-gated (reference §6). `nestedVirtualization` is the necessary hook for
guest `/dev/kvm`, but:
- aarch64 VM tests locally need M3+/macOS15+ (benchmark = P4);
- x86_64 VM tests hit the two-stacked-translations pathology (reference §6.4) and may not run at all
  (the empirical P3 experiment, Mac-only).
The module exposes the hook and documents the constraint; it does not presuppose that any test moves.

## 4. Eval-gate (the DoD's "proves it evaluates on a darwin config")

Two independent proofs, both host-independent (run on this x86_64-linux dev host):

**(a) Enabled option surface on a throwaway aarch64-darwin config.** Instantiate a bare
`darwinSystem` importing the module with `enable = true; nestedVirtualization = true;` and read the
host-side leaves:

```
$ nix eval --impure --json --expr '
    let f = builtins.getFlake (toString ./.);
        sys = f.inputs.darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [ f.modules.darwin.linux-builder-vz
                      { linuxBuilderVz.enable = true; linuxBuilderVz.nestedVirtualization = true; }
                      { system.stateVersion = 5; } ];
          specialArgs = { inherit (f) inputs; };
        };
        lb = sys.config.nix.linux-builder;
    in { enable = lb.enable; systems = lb.systems;
         packageName = lb.package.name or "?";
         trustedUsersHasAdmin = builtins.elem "@admin" sys.config.nix.settings.trusted-users; }'
{"enable":true,"ephemeral":false,"packageName":"create-builder","systems":["aarch64-linux","x86_64-linux"],"trustedUsersHasAdmin":true}
```

(`ephemeral:false` is the option's default — matches upstream nix-darwin; see §2.)
`packageName = "create-builder"` confirms `pkgs.darwin.linux-builder-vz` resolved from our pinned
nixpkgs. This proves the darwin-host option surface is well-formed and wires to the vz backend.

**(b) Whole-flake green.** `nix flake check --no-build` stays green with the module file present
(imported nowhere, default-off). VERIFIED 2026-09-04 on this x86_64-linux dev host: exit 0, zero
`error:` lines (only the standard "omitted incompatible systems: aarch64-linux" note and a
pre-existing, unrelated `proxmox.qemuConf.diskSize` obsolete-option warning). Re-verified at 13:15 PDT
after the review-driven change (promoting `ephemeral` from a hardcoded `true` to an option defaulting
to `false`, matching upstream) — still exit 0, zero errors; proof (a) re-run returned the quoted JSON
(now including `"ephemeral":false`).

**Boundary (honest scope of the gate).** The gate proves the *darwin-host* option surface evaluates.
It does **not** force-evaluate the builder guest's full NixOS toplevel, so it does not, by itself,
re-prove that `virtualisation.vz.nestedVirtualization` is a live option inside the guest - that comes
from P1's reading of `vz-vm.nix` in nixpkgs, and is fully validated only by actually standing up the
builder on a Mac (P2/P4). A design sketch proving the host wiring is the right altitude here.

## 5. Adoption path (NOT taken now - for P9)

When P9 decides to adopt build-side, a Mac host (personal `powerbook`, or nixcfg-work
`corp-darwin-dev-team`) adds:

```nix
imports = [ inputs.self.modules.darwin.linux-builder-vz ];
linuxBuilderVz.enable = true;
# linuxBuilderVz.nestedVirtualization = true;   # ONLY on M3+/macOS15+, for local VM tests
```

Prerequisites the host operator must satisfy (reference §4.5/§4.6, verified only on hardware):
`softwareupdate --install-rosetta --agree-to-license`; and when migrating an existing QEMU builder,
`sudo rm /var/lib/linux-builder/nixos.qcow2` first (vz writes a raw image under the same name).

nixcfg-work reuses this module verbatim (public, secret-free) and layers its corp decision on top -
consistent with plan 055's public/private split.

## 6. Open items handed forward

- **P2** (Mac): measure our real x86_64-linux build speedup vs the binfmt path; confirm/refute 2.5x.
- **P3** (Mac): does a Rosetta-translated `qemu-system-x86_64` TCG run at all? (test-side blocker).
- **P4** (M3+): aarch64 VM test wall-clock under `nestedVirtualization` vs a native aarch64 runner.
- **P9** (decision): adopt build-side and test-side separately; only then does a host set `enable`.
