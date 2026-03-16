# Generic x86_64 VM hardware configuration
# Provides minimal hardware config for evaluation and QEMU deployment
{ lib, ... }:

{
  imports = [ ];

  # GRUB bootloader — mkDefault so image builders (proxmox-image.nix for
  # EFI, amazon-image.nix, etc.) can override with their own boot config
  boot.loader.grub.enable = lib.mkDefault true;
  boot.loader.grub.device = lib.mkDefault "nodev";
  boot.loader.grub.efiSupport = lib.mkDefault true;
  boot.loader.grub.efiInstallAsRemovable = lib.mkDefault true;

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
