# Development packages and tools module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in {
  config = mkIf cfg.enableDevelopment {
    # Development-specific packages
    home.packages = with pkgs; [
      cmake
      doxygen
      entr
      gcc
      gnumake
      binutils
      cacert
      nix-prefetch-github
      rust-analyzer
      rustc
      cargo
      rustfmt
      clippy
      nodejs
      yarn
      (python3.withPackages (ps: with ps; [
        ipython
        pip
        setuptools
        pyserial
        cryptography
        pyparsing
      ]))
      flex
      bison
      gperf
      psmisc
      libffi
      openssl
      ncurses
      
      podman
      podman-compose
      kubectl
      k9s
      
      fzf
      bat
      eza  # Modern ls replacement (formerly exa)
      delta  # better git diff
      bottom # system monitoring
      miller # Command-line CSV/TSV/JSON processor
    ];
  };
}
