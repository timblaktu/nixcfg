# Example SSH Public Keys Configuration
# This file demonstrates how to integrate the SSH public keys registry module
# into your host configuration.
{ config, lib, pkgs, ... }:

{
  imports = [ ../../modules/nixos/ssh-public-keys.nix ];
  
  # SSH Public Keys Registry Configuration
  sshPublicKeys = {
    enable = true;  # Set to false to disable the registry
    
    # User SSH public keys organized by username and hostname
    users = {
      tim = {
        # Add actual SSH public keys here
        # Format: "hostname" = "ssh-keytype keydata comment";
        # "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@thinky-nixos";
        # "potato" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@potato";
        # "mbp" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@mbp";
      };
      # Add more users as needed
      # admin = {
      #   "server1" = "ssh-rsa AAAAB3NzaC1yc2E... admin@server1";
      # };
    };
    
    # Host SSH public keys (for known_hosts)
    hosts = {
      # Add host keys here
      # "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... root@thinky-nixos";
      # "potato" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... root@potato";
    };
    
    # Auto-distribution settings
    autoDistribute = true;  # Automatically add keys to authorized_keys
    
    # Optional: Limit which host keys are distributed
    # distributionHosts = [ "thinky-nixos" "potato" ];  # Only these hosts' keys
    
    # Optional: Override auto-distribution for specific users
    # restrictedUsers = {
    #   admin = [ "thinky-nixos" ];  # Admin only gets thinky-nixos key
    #   guest = [ ];                 # Guest gets no keys
    # };
  };
  
  # The module will automatically configure authorized_keys for users
  # based on the registry if autoDistribute is true.
  #
  # You can also manually use the registry functions:
  # config._sshKeyRegistry.getUserKey "tim" "thinky-nixos"
  # config._sshKeyRegistry.getAllUserKeys "tim"
  # config._sshKeyRegistry.getHostKey "thinky-nixos"
}