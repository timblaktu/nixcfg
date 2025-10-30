# Development packages and tools module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
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
      eza # Modern ls replacement (formerly exa)
      delta # better git diff
      bottom # system monitoring
      miller # Command-line CSV/TSV/JSON processor

      # Claude development workflow scripts
      (pkgs.writeShellApplication {
        name = "claudevloop";
        text = builtins.readFile ../files/bin/claudevloop;
        runtimeInputs = with pkgs; [ neovim ];
      })

      (pkgs.writeShellApplication {
        name = "restart_claude";
        text = builtins.readFile ../files/bin/restart_claude;
        runtimeInputs = with pkgs; [ jq findutils coreutils ];
      })

      (pkgs.writeShellApplication {
        name = "mkclaude_desktop_config";
        text = builtins.readFile ../files/bin/mkclaude_desktop_config;
        runtimeInputs = with pkgs; [ jq coreutils ];
      })
    ];
  };
}
