# modules/system/settings/proxmox/proxmox.nix
# Proxmox VE image configuration module
#
# Provides:
#   flake.modules.nixos.proxmox-image-config - Deferred module for image.modules.proxmox
#
# Sets sane Proxmox VE defaults: UEFI (ovmf), virtio-scsi-single,
# cloud-init, QEMU guest agent.
#
# This is a deferred module for the image.modules framework (NixOS 25.05+).
# It does NOT import proxmox-image.nix — the framework handles that via
# the built-in imageModules.proxmox registration in nixpkgs' images.nix.
#
# Usage:
#   # In a host module:
#   image.modules.proxmox = {
#     imports = [ inputs.self.modules.nixos.proxmox-image-config ];
#     proxmox.qemuConf.cores = 4;
#     proxmox.qemuConf.memory = 4096;
#     proxmox.qemuConf.name = "my-vm";
#   };
#
# Build VMA:
#   nix build '.#nixosConfigurations.NAME.config.system.build.images.proxmox'
# Import to Proxmox:
#   qmrestore vzdump-qemu-*.vma.zst VMID --storage POOL
#
# KNOWN ISSUE: nixpkgs proxmox-image.nix emits a spurious deprecation warning:
#   "Obsolete option `proxmox.qemuConf.diskSize' is used."
# This is an upstream bug — proxmox-image.nix line 309 iterates ALL qemuConf
# attrs (via cfg.qemuConf // cfg.qemuExtraConf) to build qemu-server.conf,
# which touches the diskSize alias created by mkRenamedOptionModuleWith.
# Our code never sets proxmox.qemuConf.diskSize; the warning is cosmetic.
# Upstream fix: removeAttrs cfg.qemuConf ["diskSize"] // cfg.qemuExtraConf
# TODO: File nixpkgs PR to fix this
_:
{
  flake.modules.nixos.proxmox-image-config = { lib, ... }: {
    # proxmox-image.nix is already registered as imageModules.proxmox
    # in nixpkgs' images.nix framework. We only need to set our configuration
    # defaults here — the builder module import is handled automatically.

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
}
