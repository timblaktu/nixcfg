# Potato (ARM) specific configuration
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Hardware configuration
    ./hardware-config.nix
    ../../modules/base.nix
    inputs.sops-nix.nixosModules.sops
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = lib.mkDefault true;

  # Base module configuration
  base = {
    userGroups = lib.mkDefault [ "wheel" "networkmanager" "gpio" ];
  };

  # Hostname
  networking = {
    hostName = "potato";
    useNetworkd = lib.mkDefault true;
    firewall.enable = lib.mkDefault true;
  };

  # Boot configuration for ARM
  boot = {
    loader = {
      grub.enable = lib.mkDefault false;
      generic-extlinux-compatible.enable = lib.mkDefault true;
    };
  };

  # ARM-specific optimizations
  nixpkgs.hostPlatform = "aarch64-linux";

  # SSH service
  services.openssh = {
    enable = lib.mkDefault true;
    ports = lib.mkDefault [ 22 ];
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
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
    isNormalUser = lib.mkDefault true;
    extraGroups = lib.mkDefault ["wheel" "networkmanager" "gpio"];
    openssh.authorizedKeys.keys = lib.mkDefault [
      # Add your SSH keys here
    ];
  };

  # System state version
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
