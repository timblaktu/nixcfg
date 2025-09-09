# Minimal nixvim-only home-manager configuration
# This imports the shared nixvim config and adds only minimal home-manager setup
{ config, lib, pkgs, inputs, ... }:

{
  imports = [ 
    inputs.nixvim.homeModules.nixvim
    ./common/nixvim.nix 
  ];

  home = {
    username = "tim";
    homeDirectory = "/home/tim";
    stateVersion = "24.11";
  };

  # Manage Nix configuration for experimental features
  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

  programs.home-manager.enable = true;
  
  # Disable version check to avoid warnings
  home.enableNixpkgsReleaseCheck = false;

  # Override some settings for minimal preferences
  programs.nixvim.opts = {
    # Prefer 4-space tabs in minimal config
    shiftwidth = lib.mkForce 4;
    tabstop = lib.mkForce 4;
    softtabstop = lib.mkForce 4;
    
    # Disable backups in minimal config  
    backup = lib.mkForce false;
    writebackup = lib.mkForce false;
    backupdir = lib.mkForce null;
    backupcopy = lib.mkForce null;
    
    # Use XDG state directory for undo
    undodir = lib.mkForce "${config.xdg.stateHome}/nvim/undo";
  };
}
