# WSL2 doesn't have traditional hardware configuration
# This file provides the minimal required configuration for WSL2
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];

  # WSL2 kernel is provided by Windows
  boot.loader.grub.enable = false;

  # WSL2 handles its own networking
  networking.useDHCP = false;

  # Virtual filesystem for WSL2
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # WSL2 memory is dynamic
  swapDevices = [ ];

  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
