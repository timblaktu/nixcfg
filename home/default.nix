# This is the main entry point for Home Manager
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Common configurations
    ./common/shell.nix
    ./common/git.nix
    ./common/neovim.nix
    ./common/tmux.nix
    
    # Profiles 
    # Import based on hostname or parameter to determine appropriate profile
    (if (builtins.getEnv "WSL_DISTRO_NAME" != "") 
     then ./profiles/wsl.nix
     else ./profiles/development.nix)
  ];

  # Home Manager needs a bit of information about you and the paths it should manage
  home = {
    username = "tim";
    homeDirectory = "/home/tim";
    
    # Basic packages that should be available everywhere
    packages = with pkgs; [
      ripgrep
      fd
      jq
      htop
      curl
      wget
      unzip
      tree
    ];
    
    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    stateVersion = "24.11";
  };

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;
}
