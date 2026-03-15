# Generic x86_64 VM hardware configuration
# Provides minimal hardware config for evaluation and QEMU deployment
{ lib, ... }:

{
  imports = [ ];

  # Standard GRUB boot loader for VM/bare-metal
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  # Root filesystem (generic virtio disk)
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  swapDevices = [ ];

  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
