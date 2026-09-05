# modules/system/settings/linux-builder-vz/linux-builder-vz.nix
# Portable, declarative enablement of the Apple-Virtualization-framework Linux
# builder (`pkgs.darwin.linux-builder-vz`, backed by `pkgs.vzvm`) for Apple
# Silicon nix-darwin hosts.
#
# STATUS: DESIGN SKETCH (plan 055 PM). SAFE-OFF, adopted by NO host. This module
# only becomes available as `self.modules.darwin.linux-builder-vz`; nothing
# imports it and its `enable` defaults false, so evaluating the flake is
# unaffected. It is intentionally inert until plan 055 P9 makes an explicit
# build-side / test-side decision (reference §7). Do NOT wire it into a host
# before P9 - that would presuppose an unmade §7 choice (reference §0 rule 4).
#
# WHY THIS EXISTS
# ----------------
# Today the team cross-builds `aarch64-linux` from an `x86_64-linux` host with
# QEMU binfmt emulation (`modules/system/settings/dev-team/dev-team.nix`:
# `boot.binfmt.emulatedSystems`), and builds the distributable aarch64 Mac-VM
# qcow2 on a NATIVE aarch64 machine because an x86_64 host cannot (the
# "must build the qcow2 on native aarch64" constraint around
# `modules/hosts/nixos-dev-team-vm [N]/`). On an Apple Silicon laptop there is a
# faster, first-class path: `linux-builder-vz` runs the same NixOS builder guest
# on `Virtualization.framework` (via `vzvm`) instead of QEMU, and can expose
# Rosetta into the aarch64 guest so `x86_64-linux` builds are TRANSLATED rather
# than EMULATED (reference §4: ~2.5x on the author's benchmark; verify per P2).
# `aarch64-linux` builds run natively. This module is the reusable, secret-free
# mechanism that a Mac host (personal `powerbook`, or nixcfg-work's
# `corp-darwin-dev-team`) could opt into with one `enable = true`.
#
# WHAT IT SUPERSEDES (build-side only; NOT test-side)
#   - For a Mac build host: `nix.linux-builder` with the vz backend replaces the
#     x86_64-host `boot.binfmt.emulatedSystems` cross-build path (different
#     machine, so this is a routing choice, not an in-place edit).
#   - The qcow2-on-native-aarch64 workaround: an Apple Silicon host builds
#     aarch64 Linux closures natively, no x86_64 emulation detour.
#   It does NOT move NixOS VM *tests* onto the Mac - that is architecturally
#   constrained and generation-gated (reference §6); `nestedVirtualization`
#   below is the necessary-but-not-sufficient hook, still Mac-only to validate.
#
# HARD PREREQUISITES (host, verified only on hardware - see plan 055 P2/P4)
#   - aarch64-darwin host (`vzvm` runs only there; nixpkgs vz-vm.nix asserts it).
#   - Rosetta installed for x86_64 translation:
#       softwareupdate --install-rosetta --agree-to-license
#     (The builder refuses to start if Rosetta is missing rather than silently
#     dropping x86_64; set `rosetta = false` to run aarch64-only without it.)
#   - `nestedVirtualization` (for `/dev/kvm` inside the guest, i.e. running NixOS
#     VM tests locally) requires macOS 15+ AND an M3+ chip. On M1/M2 it must stay
#     false - the builder still BUILDS both arches, it just cannot host VM tests.
#
# MIGRATION HAZARD (reference §4.6): switching an existing QEMU linux-builder to
# the vz backend needs the stale qcow2 removed first
# (`sudo rm /var/lib/linux-builder/nixos.qcow2`) - the vz builder writes a raw
# image under the same name and refuses to misread a genuine qcow2.
#
# PROVIDES
#   flake.modules.darwin.linux-builder-vz
#
# USAGE (a Mac host, ONLY after plan 055 P9 decides to adopt)
#   imports = [ inputs.self.modules.darwin.linux-builder-vz ];
#   linuxBuilderVz = {
#     enable = true;                       # default false - nothing until set
#     # systems default to both arches; rosetta on; nestedVirtualization OFF.
#     nestedVirtualization = true;         # ONLY on M3+/macOS15+ (for VM tests)
#   };
{ lib, ... }:
let
  cfg' = config: config.linuxBuilderVz;
in
{
  flake.modules.darwin.linux-builder-vz = { config, lib, pkgs, ... }:
    let
      cfg = cfg' config;
    in
    {
      options.linuxBuilderVz = {
        enable = lib.mkEnableOption ''
          the Apple-Virtualization-framework Linux builder (linux-builder-vz /
          vzvm) on this aarch64-darwin host. SAFE-OFF; gated on plan 055 P9'';

        systems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "aarch64-linux" "x86_64-linux" ];
          description = ''
            Linux system types the builder advertises. `aarch64-linux` builds
            run natively; `x86_64-linux` builds are Rosetta-translated (needs
            `rosetta = true`). Drop `x86_64-linux` to run aarch64-only.
          '';
        };

        rosetta = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Expose Rosetta into the guest so x86_64-linux builds are translated
            rather than QEMU-emulated. Maps to the guest's
            `virtualisation.vz.rosetta.enable`. Requires Rosetta installed on the
            host. Set false to run without Rosetta (aarch64-only, no x86_64).
          '';
        };

        nestedVirtualization = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable nested virtualization in the guest (guest `/dev/kvm`), the
            prerequisite for running NixOS VM tests on the builder. Maps to the
            guest's `virtualisation.vz.nestedVirtualization`. REQUIRES macOS 15+
            AND an M3+ chip; leave false on M1/M2 (builds still work; only local
            VM tests are unavailable). Even where supported, whether x86_64 VM
            tests are usable is a separate open question (reference §6.4 / P3).
          '';
        };

        ephemeral = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Wipe the builder guest's filesystem (its Nix store cache) on every
            restart. Maps to `nix.linux-builder.ephemeral`. Default false matches
            upstream nix-darwin: a PERSISTENT builder whose dependency cache stays
            warm across restarts (faster cold builds, lower cache traffic), at the
            risk of stale guest state / config drift. Set true to force a clean
            slate on every restart so config changes always apply with no drift
            (reference §4.5), at the cost of re-populating the guest store on the
            first build after each restart.
          '';
        };

        maxJobs = lib.mkOption {
          type = lib.types.ints.positive;
          default = 4;
          description = "Concurrent build jobs the builder accepts.";
        };

        cores = lib.mkOption {
          type = lib.types.ints.positive;
          default = 6;
          description = "vCPU cores for the builder guest (`virtualisation.cores`).";
        };

        memorySize = lib.mkOption {
          type = lib.types.ints.positive;
          default = 8 * 1024;
          description = "Builder guest RAM in MB. Default 8 GiB (the 3 GiB stock default is too small for real builds).";
        };

        diskSize = lib.mkOption {
          type = lib.types.ints.positive;
          default = 40 * 1024;
          description = "Builder guest disk in MB. Default 40 GiB.";
        };

        trustAdmins = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Add `@admin` to `nix.settings.trusted-users` so admins can use the builder.";
        };
      };

      config = lib.mkIf cfg.enable {
        nix.linux-builder = {
          enable = true;
          package = pkgs.darwin.linux-builder-vz;
          systems = cfg.systems;
          # Builder-disk lifecycle. Default (false) = persistent builder, matching
          # upstream nix-darwin; set `ephemeral = true` for a clean slate on every
          # restart (reference §4.5). Operator's choice, hence an option.
          ephemeral = cfg.ephemeral;
          maxJobs = cfg.maxJobs;
          config = {
            virtualisation = {
              vz.rosetta.enable = cfg.rosetta;
              vz.nestedVirtualization = cfg.nestedVirtualization;
              cores = cfg.cores;
              darwin-builder = {
                memorySize = cfg.memorySize;
                diskSize = cfg.diskSize;
              };
            };
          };
        };

        nix.settings.trusted-users = lib.mkIf cfg.trustAdmins [ "@admin" ];
      };
    };
}
