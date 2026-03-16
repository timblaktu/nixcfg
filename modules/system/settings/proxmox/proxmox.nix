# modules/system/settings/proxmox/proxmox.nix
# Proxmox VE image output settings module [NDnd]
#
# Provides:
#   flake.modules.nixos.proxmox - Proxmox VE (VMA) image generation
#
# Wraps nixpkgs' proxmox-image.nix with sane defaults for team images:
# UEFI (ovmf), virtio-scsi-single, cloud-init, QEMU guest agent.
#
# Does NOT import any system type layer -- consumers must co-import
# a system type (system-cli, dev-team, etc.) alongside this module.
#
# Build VMA: nix build '.#nixosConfigurations.NAME.config.system.build.VMA'
# Import:    qmrestore vzdump-qemu-*.vma.zst VMID --storage POOL
#
# Extensibility: Parallel modules can be created for other formats:
#   - modules/system/settings/qcow2/qcow2.nix (libvirt/QEMU)
#   - modules/system/settings/vmware/vmware.nix (VMDK)
#   - modules/system/settings/iso/iso.nix (bootable ISO)
#
# Usage:
#   # In a host module (must co-import a system type):
#   imports = [
#     inputs.self.modules.nixos.system-cli  # or dev-team, etc.
#     inputs.self.modules.nixos.proxmox
#   ];
{ ... }:
{
  flake.modules.nixos.proxmox = { config, lib, pkgs, inputs, ... }: {
    imports = [
      # nixpkgs native Proxmox VE image builder
      "${inputs.nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
    ];

    config = {
      # === BIOS / Boot ===
      # UEFI via OVMF (modern standard for Proxmox VMs)
      proxmox.qemuConf.bios = lib.mkDefault "ovmf";

      # === Storage ===
      # virtio-scsi-single: best performance for NVMe-backed storage
      proxmox.qemuConf.scsihw = lib.mkDefault "virtio-scsi-single";

      # === Networking ===
      # virtio NIC on vmbr0 with firewall; mac randomized on restore
      proxmox.qemuConf.net0 = lib.mkDefault "virtio=00:00:00:00:00:00,bridge=vmbr0,firewall=1";

      # === Guest Agent ===
      # QEMU guest agent for Proxmox host<->guest communication
      proxmox.qemuConf.agent = lib.mkDefault true;

      # === Cloud-Init ===
      # Accept cloud-init config from Proxmox (hostname, SSH keys, networking)
      proxmox.cloudInit.enable = lib.mkDefault true;

      # === Serial Console ===
      # Serial console for qm terminal access
      proxmox.qemuConf.serial0 = lib.mkDefault "socket";
    };
  };
}
