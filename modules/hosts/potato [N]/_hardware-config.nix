# Generated hardware configuration for Potato
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Minimal file system configuration
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_ROOT";
      fsType = "ext4";
    };
  };

  # Boot settings
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  
  # CPU configuration
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  
  # This is a minimal placeholder configuration.
  # On the actual device, you should generate a proper configuration with:
  # nixos-generate-config --root /mnt
}
