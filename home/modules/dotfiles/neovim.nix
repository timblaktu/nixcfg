# Example for a specific tool configuration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.customDotfiles;
in {
  config = mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      
      extraConfig = builtins.readFile ../../../dotfiles/vimrc;
      
      plugins = with pkgs.vimPlugins; [
        vim-nix
        vim-lastplace
        vim-surround
        # Add your plugins here
      ];
    };
  };
}
