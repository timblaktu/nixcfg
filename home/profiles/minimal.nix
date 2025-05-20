# Minimal profile for servers
{ config, lib, pkgs, ... }:

{
  # Very basic packages suitable for servers
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    htop
    curl
    wget
    unzip
    git
    tmux
    tree
  ];
  
  # Simplified shell configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
      ];
      theme = "robbyrussell";
    };
    
    shellAliases = {
      ll = "ls -la";
      la = "ls -a";
    };
  };
  
  # Basic vim configuration
  programs.vim = {
    enable = true;
    defaultEditor = true;
    extraConfig = ''
      set number
      set expandtab
      set shiftwidth=2
      set tabstop=2
      set incsearch
      set hlsearch
      syntax on
      set mouse=a
    '';
  };
}
