# Personal dotfiles configuration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.customDotfiles;
in {
  imports = [
    ./neovim.nix
    # Add other specific configuration modules here
  ];

  options.customDotfiles = {
    enable = mkEnableOption "Personal dotfiles configuration";
  };
  
  config = mkIf cfg.enable {
    # Start with a few simple dotfiles
    
    # Git configuration (if not using programs.git)
    # home.file.".gitconfig".source = ../../../dotfiles/gitconfig;
    
    # Shell configuration additions
    # home.file.".bashrc.extra".source = ../../../dotfiles/bashrc.extra;
    
    # Custom scripts
    home.file.".local/bin" = {
      source = ../../../dotfiles/bin;
      recursive = true;
      executable = true;
    };
    
    # You can also use text content directly
    home.file.".hushlogin".text = "";
  };
}
