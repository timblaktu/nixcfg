# Development profile
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ../common/shell.nix
    ../common/git.nix
    ../common/neovim.nix
    ../common/tmux.nix
  ];
  
  # Development packages
  home.packages = with pkgs; [
    # Version control
    git
    git-lfs
    
    # Build tools
    gnumake
    cmake
    ninja
    
    # Compilers and dev platforms
    gcc
    clang
    rustup
    go
    nodejs
    yarn
    python3
    python3Packages.pip
    python3Packages.pipx
    jdk
    
    # Container tools
    docker
    docker-compose
    kubectl
    k9s
    
    # Cloud tools
    awscli2
    google-cloud-sdk
    terraform
    
    # Database tools
    postgresql
    sqlite
    dbeaver
    
    # Network tools
    httpie
    curl
    wget
    nmap
    
    # Text processing
    jq
    yq
    ripgrep
    fd
    
    # Documentation
    man-pages
    tldr
    
    # Utilities
    zip
    unzip
    tree
    htop
    bat
    exa
    fzf
    
    # Terminal tools
    ranger
    
    # Nix tools
    nixpkgs-fmt
    nil # Nix LSP
    nix-index
    
    # Useful for scripting
    shellcheck
    shfmt
    
    # Language servers (also used by Neovim)
    nodePackages.typescript-language-server
    nodePackages.vscode-langservers-extracted
    rust-analyzer
    gopls
    pyright
  ];
  
  # Direnv for per-directory environment variables
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  
  # Modern terminal utilities
  programs.bat.enable = true;   # Better cat
  programs.exa.enable = true;   # Better ls
  programs.fzf.enable = true;   # Fuzzy finder
  
  # Add bat aliases
  programs.bash.shellAliases = {
    cat = "bat";
    ls = "exa";
    ll = "exa -la";
    la = "exa -a";
    tree = "exa --tree";
    
    # Docker aliases
    d = "docker";
    dc = "docker-compose";
  };
  programs.zsh.shellAliases = {
    cat = "bat";
    ls = "exa";
    ll = "exa -la";
    la = "exa -a";
    tree = "exa --tree";
    
    # Docker aliases
    d = "docker";
    dc = "docker-compose";
  };
  
  # Python development
  home.file.".config/pip/pip.conf".text = ''
    [global]
    timeout = 60
    index-url = https://pypi.org/simple
  '';
  
  # Node.js development
  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';
  
  # Rust configuration
  home.sessionVariables = {
    RUSTUP_HOME = "${config.home.homeDirectory}/.rustup";
    CARGO_HOME = "${config.home.homeDirectory}/.cargo";
    PATH = "$PATH:${config.home.homeDirectory}/.cargo/bin:${config.home.homeDirectory}/.npm-global/bin";
  };
  
  # Create directories
  home.activation = {
    createDevelopmentDirectories = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p ${config.home.homeDirectory}/.npm-global/bin
      mkdir -p ${config.home.homeDirectory}/.cargo/bin
      mkdir -p ${config.home.homeDirectory}/.rustup
    '';
  };
}
