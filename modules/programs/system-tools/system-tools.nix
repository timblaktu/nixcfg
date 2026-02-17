# modules/programs/system-tools/system-tools.nix
# System bootstrap and administration tools [nd]
#
# Provides:
#   flake.modules.homeManager.system-tools - System admin and bootstrap utilities
#
# Features:
#   - bootstrap-secrets: SOPS secret bootstrap from Bitwarden
#   - bootstrap-ssh-keys: SSH key bootstrap from Bitwarden
#   - build-wsl-tarball: WSL tarball builder for NixOS configs
#   - restart-usb: USB device restart utilities
#   - PowerShell reference scripts for Windows/WSL environments
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.system-tools ];
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.system-tools = { config, lib, pkgs, ... }:
      {
        # System tools are always enabled when this module is imported
        home.packages = with pkgs; [
          # SOPS secret bootstrap from Bitwarden
          (pkgs.writeShellApplication {
            name = "bootstrap-secrets";
            text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/bootstrap-secrets.sh");
            runtimeInputs = with pkgs; [ rbw nix coreutils age ];
          })

          # SSH key bootstrap from Bitwarden
          (pkgs.writeShellApplication {
            name = "bootstrap-ssh-keys";
            text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/bootstrap-ssh-keys.sh");
            runtimeInputs = with pkgs; [ rbw openssh coreutils util-linux ];
          })

          # WSL tarball builder for NixOS configurations
          (pkgs.writeShellApplication {
            name = "build-wsl-tarball";
            text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/build-wsl-tarball");
            runtimeInputs = with pkgs; [ nix coreutils util-linux ];
          })

          # USB device restart utilities
          (pkgs.writeShellApplication {
            name = "restart-usb";
            text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/restart-usb");
            runtimeInputs = with pkgs; [ coreutils util-linux usbutils ];
          })

          (pkgs.writeShellApplication {
            name = "restart-usb-improved";
            text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/restart-usb-improved");
            runtimeInputs = with pkgs; [ coreutils util-linux usbutils ];
          })
        ];

        # Windows-specific PowerShell scripts (documentation only)
        # These are provided as reference files for Windows/WSL environments
        home.file = {
          ".local/share/docs/windows-scripts/fix-terminal-fonts.ps1".source =
            ../../.. + "/modules/programs/files [nd]/files/bin/fix-terminal-fonts.ps1";
          ".local/share/docs/windows-scripts/font-detection-functions.ps1".source =
            ../../.. + "/modules/programs/files [nd]/files/bin/font-detection-functions.ps1";
          ".local/share/docs/windows-scripts/install-terminal-fonts.ps1".source =
            ../../.. + "/modules/programs/files [nd]/files/bin/install-terminal-fonts.ps1";
          ".local/share/docs/windows-scripts/restart-usb-v4.ps1".source =
            ../../.. + "/modules/programs/files [nd]/files/bin/restart-usb-v4.ps1";
        };
      };
  };
}
