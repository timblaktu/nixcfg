# Potato (ARM) specific configuration
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Hardware configuration
    ./hardware-config.nix
  ];

  # Hostname
  networking = {
    hostName = "potato";
    useNetworkd = true;
    firewall.enable = true;
  };

  # Boot configuration for ARM
  boot = {
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  # ARM-specific optimizations
  nixpkgs.hostPlatform = "aarch64-linux";

  # SSH service
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    htop
    tmux
  ];

  # User configuration
  users.users.tim = {
    isNormalUser = true;
    shell = lib.mkForce pkgs.zsh;
    extraGroups = ["wheel" "networkmanager"];
    openssh.authorizedKeys.keys = [
      # Add your SSH keys here
    ];
  };

  # This is just a placeholder. Hardware configuration should be generated
  # by running `nixos-generate-config` on the actual device.
}
