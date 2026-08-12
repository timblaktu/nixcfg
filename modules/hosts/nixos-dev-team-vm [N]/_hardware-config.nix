# Generic aarch64 VM hardware configuration (Apple Silicon Mac guest)
# Provides minimal hardware config so the base config evaluates; the
# qemu-efi image builder (disk-image.nix) overrides bootloader + filesystems
# for the actual qcow2 output.
{ lib, ... }:

{
  imports = [ ];

  # UEFI boot via systemd-boot. aarch64 has no legacy BIOS path — UTM/QEMU
  # boot the guest through EDK2 UEFI, so systemd-boot is the right loader.
  # mkDefault lets disk-image.nix (image.modules.qemu-efi) keep control.
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault false;

  # virtio + USB-HID modules for QEMU/UTM guests
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "usbhid"
    "xhci_pci"
  ];

  # Root filesystem (generic virtio disk).
  # mkDefault so disk-image.nix can override with its by-label/nixos device.
  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/nixos";
    fsType = lib.mkDefault "ext4";
    autoResize = true;
  };

  swapDevices = [ ];

  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
