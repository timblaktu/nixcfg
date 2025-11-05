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

      # USB device restart utilities  
      (pkgs.writeShellApplication {
        name = "restart-usb";
        text = builtins.readFile ../files/bin/restart-usb;
        runtimeInputs = with pkgs; [ coreutils util-linux usbutils ];
      })

      (pkgs.writeShellApplication {
        name = "restart-usb-improved";
        text = builtins.readFile ../files/bin/restart-usb-improved;
        runtimeInputs = with pkgs; [ coreutils util-linux usbutils ];
      })
    ];

    # Windows-specific PowerShell scripts (documentation only)
    # These are provided as reference files for Windows/WSL environments
    home.file = {
      ".local/share/docs/windows-scripts/fix-terminal-fonts.ps1".source = ../files/bin/fix-terminal-fonts.ps1;
      ".local/share/docs/windows-scripts/font-detection-functions.ps1".source = ../files/bin/font-detection-functions.ps1;
      ".local/share/docs/windows-scripts/install-terminal-fonts.ps1".source = ../files/bin/install-terminal-fonts.ps1;
      ".local/share/docs/windows-scripts/restart-usb-v4.ps1".source = ../files/bin/restart-usb-v4.ps1;
    };
  };
}
