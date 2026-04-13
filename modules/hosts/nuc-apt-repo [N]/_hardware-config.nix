# Intel NUC hardware configuration with disko ZFS layout
#
# Hardware: Intel NUC, dual NICs (enp1s0/enp2s0), WiFi (wlp3s0), ~953G NVMe SSD
# Disk layout: ESP + root ext4 + ZFS pool (cache) for /nix
#
# Deployment: nixos-anywhere --flake ~/src/nixcfg#nuc-apt-repo root@<ip>
{ lib, pkgs, ... }:

{
  imports = [ ];

  # Intel NUC hardware
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.enableRedistributableFirmware = true;

  # Large console font for physical access
  console = {
    packages = [ pkgs.terminus_font ];
    font = "ter-v32b";
  };
  boot.kernelParams = [ "video=1280x720" ];

  # Bootloader: systemd-boot (NUC has EFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS support
  boot.supportedFilesystems.zfs = true;
  boot.zfs.forceImportRoot = false;
  networking.hostId = "57d03bc8";

  # Disko: single NVMe with ESP + root ext4 + ZFS
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "50G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "cache";
            };
          };
        };
      };
    };

    zpool.cache = {
      type = "zpool";
      options = {
        ashift = "12";
        autotrim = "on";
        cachefile = "none";
      };
      rootFsOptions = {
        compression = "zstd";
        atime = "off";
        "com.sun:auto-snapshot" = "false";
        canmount = "off";
        mountpoint = "none";
        xattr = "sa";
        acltype = "posixacl";
        dnodesize = "auto";
      };
      datasets = {
        "nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options = {
            mountpoint = "legacy";
            recordsize = "128K";
          };
        };
        "reserved" = {
          type = "zfs_fs";
          options = {
            mountpoint = "none";
            canmount = "off";
            refreservation = "10G";
          };
        };
      };
    };
  };

  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
