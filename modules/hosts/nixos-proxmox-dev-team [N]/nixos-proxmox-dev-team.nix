# modules/hosts/nixos-proxmox-dev-team [N]/nixos-proxmox-dev-team.nix
# Dendritic host composition for nixos-proxmox-dev-team (Proxmox VE image)
#
# Thin composition layer: dev-team + proxmox = VMA image with full dev stack.
#
# Features (via dev-team module):
# - Full CLI dev stack (system-cli -> system-default -> system-minimal)
# - binfmt cross-compilation (aarch64)
# - Podman containers
# - Claude Code enterprise
# - Generic 'dev' user
#
# Features (via proxmox module):
# - UEFI boot (OVMF)
# - Cloud-init for Proxmox provisioning
# - QEMU guest agent
# - VMA image output
#
# Build VMA:
#   nix build '.#nixosConfigurations.nixos-proxmox-dev-team.config.system.build.VMA'
# Import to Proxmox:
#   qmrestore vzdump-qemu-*.vma.zst VMID --storage POOL
{ config, lib, inputs, ... }:
{
  flake.modules.nixos.nixos-proxmox-dev-team = { config, lib, pkgs, ... }: {
    imports = [
      # Hardware configuration (minimal -- proxmox-image.nix handles most hw)
      ./_hardware-config.nix
      # System CLI layer (chains: system-minimal -> system-default -> system-cli)
      inputs.self.modules.nixos.system-cli
      # Shared dev team base (binfmt + Podman + Claude Code + usbutils + kmod)
      inputs.self.modules.nixos.dev-team
      # Proxmox VE image output (UEFI, cloud-init, QEMU guest agent)
      inputs.self.modules.nixos.proxmox
    ];

    config = {
      networking.hostName = "nixos-proxmox-dev-team";

      # Proxmox VM sizing
      proxmox.qemuConf.cores = 4;
      proxmox.qemuConf.memory = 4096;
      proxmox.qemuConf.name = "nixos-dev-team";

      # NOTE: nixpkgs.config.allowUnfree is set at the nixosConfiguration
      # registration level (nixos-configurations.nix), not here.
    };
  };
}
