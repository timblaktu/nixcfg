# Minimal hardware config for Proxmox VE image
# proxmox-image.nix handles boot, filesystems, disk layout, and kernel modules.
# Only hostPlatform is needed here.
{ lib, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
