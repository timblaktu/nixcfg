# modules/hosts/nixos-dev-team-vm [N]/nixos-dev-team-vm.nix
# Dendritic host composition for nixos-dev-team-vm (aarch64 Linux VM on a Mac)
#
# This is a DISTRIBUTION configuration for the dev team's generic NixOS image
# packaged as a qcow2 for a Mac laptop hypervisor (UTM / QEMU + Apple
# Hypervisor.framework). It is NOT nix-darwin — the guest is a real aarch64
# NixOS Linux VM. A colleague on an Apple Silicon Mac imports the qcow2 into
# UTM and gets the SAME dev-team environment shipped to Proxmox/EC2/WSL.
#
# It is a thin composition layer -- all real config lives in the shared
# dev-team module (binfmt, Podman, Claude Code, usbutils, kmod), identical to
# the Proxmox variant (nixos-dev-team). Only the platform packaging differs.
#
# Features (via dev-team module):
# - Full CLI dev stack (system-cli -> system-default -> system-minimal)
# - binfmt cross-compilation (aarch64)
# - Podman containers
# - Claude Code enterprise
# - Generic 'dev' user with SSH access
# - No WSL, no CrowdStrike, no Windows Terminal
#
# Image outputs (via image.modules / system.build.images):
# - qcow2 (UEFI): nix build '.#nixosConfigurations.nixos-dev-team-vm.config.system.build.images.qemu-efi'
#   or the convenience alias: nix build '.#image-vm-dev-team'
#   Result contains nixos.qcow2 (systemd-boot / EFI, ext4 root, auto-resize).
#
# Import into UTM (Apple Silicon):
#   1. Copy result/nixos.qcow2 to the Mac.
#   2. UTM -> Create a New Virtual Machine -> Virtualize -> Linux ->
#      "Use existing" and select the qcow2 (Architecture: ARM64, machine virt,
#      boot: UEFI). Give it >=4 cores / 4 GB RAM.
#   3. Boot. Networking is DHCP over UTM's shared/emulated NIC.
#
# See also: nixos-dev-team (x86_64 Proxmox VMA variant, same dev-team base)
{ config, lib, inputs, ... }:
{
  # === NixOS System Module ===
  flake.modules.nixos.nixos-dev-team-vm = { config, lib, pkgs, ... }: {
    imports = [
      # Hardware configuration (generic aarch64 virtio VM)
      ./_hardware-config.nix
      # System CLI layer (chains: system-minimal -> system-default -> system-cli)
      inputs.self.modules.nixos.system-cli
      # Shared dev team base (binfmt + Podman + Claude Code + usbutils + kmod)
      inputs.self.modules.nixos.dev-team
    ];

    config = {
      networking.hostName = "nixos-dev-team-vm";

      # DHCP on all ethernet interfaces via systemd-networkd. UTM hands the
      # guest an address on its shared network; the 99- prefix keeps this at
      # lowest priority so any image/cloud metadata can override it.
      # useDHCP = false disables the legacy dhcpcd path so networkd is the sole
      # interface manager (avoids the dual-management warning / race).
      networking.useDHCP = false;
      systemd.network.enable = true;
      systemd.network.networks."99-ethernet-default-dhcp" = {
        matchConfig.Type = "ether";
        networkConfig.DHCP = "yes";
      };

      # NOTE: nixpkgs.config.allowUnfree is set at the nixosConfiguration
      # registration level (nixos-configurations.nix), not here.

      # === Image Outputs ===
      # image.modules overlays produce format-specific images via
      # system.build.images without polluting this base config.
      # qemu-efi = disk-image.nix with EFI support -> qcow2 + systemd-boot + ESP,
      # which is what UTM/QEMU boot on Apple Silicon.
      image.modules.qemu-efi = { config, lib, pkgs, modulesPath, ... }: {
        image.format = "qcow2";
        # Provisioned virtual disk size (MB). Root auto-resizes on first boot,
        # so users can grow the qcow2 in UTM and the fs follows.
        virtualisation.diskSize = 20480;

        # WORKAROUND (nixpkgs API limitation, verified nixpkgs 26.11 /
        # 331800d): disk-image.nix invokes lib/make-disk-image.nix with the
        # hardcoded default memSize = 1024 (MiB) and exposes NO option to
        # change it. The image is assembled inside a full-system QEMU VM that
        # copies the entire (large) dev-team closure; 1 GiB is tight and can
        # OOM during the copy. Re-invoke make-disk-image with the SAME
        # arguments disk-image.nix uses, only raising memSize for headroom.
        # REMOVE once nixpkgs exposes a builder-memory option for disk-image.
        #
        # NOTE: this MUST be built on NATIVE aarch64 (a Graviton/remote
        # builder). Cross-building on x86_64 via binfmt emulation fails
        # regardless of memSize: the emulated builder VM's virtiofs transport
        # returns ENOMEM on directory reads. See the dev-team-mac-vm project
        # memory for the diagnosis.
        system.build.image = lib.mkForce (import (modulesPath + "/../lib/make-disk-image.nix") {
          inherit lib config pkgs;
          inherit (config.virtualisation) diskSize;
          inherit (config.image) baseName format;
          partitionTableType = "efi";
          memSize = 4096;
        });
      };
    };
  };

  # === Configuration Registration ===
  # Registration is done in flake-parts/nixos-configurations.nix
  # using lib.nixosSystem with self.modules.nixos.nixos-dev-team-vm
  # with system = "aarch64-linux"
  #
  # Home Manager configuration is NOT bundled in this host module.
  # Users apply HM config independently using this flake's feature modules.
}
