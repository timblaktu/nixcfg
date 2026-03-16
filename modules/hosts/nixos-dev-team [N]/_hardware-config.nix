# Generic x86_64 VM hardware configuration
# Provides minimal hardware config for evaluation and QEMU deployment
{ lib, ... }:

{
  imports = [ ];

  # Standard GRUB boot loader for VM/bare-metal
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  # Root filesystem (generic virtio disk)
  # mkDefault allows image builders (proxmox-image.nix, etc.) to override
  fileSystems."/" = {
    device = lib.mkDefault "/dev/vda1";
    fsType = lib.mkDefault "ext4";
  };

  swapDevices = [ ];

  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
