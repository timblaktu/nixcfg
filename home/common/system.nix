# System bootstrap and administration tools module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
  config = mkIf cfg.enableSystem {
    # System administration packages and utilities
    home.packages = with pkgs; [
      # SOPS secret bootstrap from Bitwarden
      (pkgs.writeShellApplication {
        name = "bootstrap-secrets";
        text = builtins.readFile ../files/bin/bootstrap-secrets.sh;
        runtimeInputs = with pkgs; [ rbw nix coreutils age ];
      })

      # SSH key bootstrap from Bitwarden
      (pkgs.writeShellApplication {
        name = "bootstrap-ssh-keys";
        text = builtins.readFile ../files/bin/bootstrap-ssh-keys.sh;
        runtimeInputs = with pkgs; [ rbw openssh coreutils util-linux ];
      })

      # WSL tarball builder for NixOS configurations
      (pkgs.writeShellApplication {
        name = "build-wsl-tarball";
        text = builtins.readFile ../files/bin/build-wsl-tarball;
        runtimeInputs = with pkgs; [ nix coreutils util-linux ];
      })
    ];
  };
}
