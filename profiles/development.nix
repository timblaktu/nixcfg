# Development profile for home manager
{ config, lib, pkgs, ... }:

{
  # Development-specific packages
  home.packages = with pkgs; [
    # Development tools
    gcc
    gnumake
    rust-analyzer
    rustc
    cargo
    nodejs
    yarn
    python3
    python3Packages.pip
    python3Packages.ipython
    vscode
    
    # DevOps tools
    docker-compose
    kubectl
    k9s
    
    # Additional utilities
    fzf
    bat
    eza  # Modern ls replacement (formerly exa)
    delta  # better git diff
    bottom # system monitoring
  ];
  
  # VS Code configuration
  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      vscodevim.vim
      ms-python.python
      rust-lang.rust-analyzer
      jnoortheen.nix-ide
    ];
  };
}
