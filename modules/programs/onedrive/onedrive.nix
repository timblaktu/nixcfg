# modules/programs/onedrive/onedrive.nix
# OneDrive utilities for WSL environments [nd]
#
# Provides:
#   flake.modules.homeManager.onedrive - OneDrive sync utilities for WSL
#
# Features:
#   - onedrive-status: Check OneDrive sync status
#   - onedrive-force-sync: Force OneDrive sync
#   - Shell aliases: ods, odf, od-sync, od-status
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.onedrive ];
#   oneDriveUtils.enable = true;  # Only for WSL hosts
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.onedrive = { config, lib, pkgs, ... }:
      let
        cfg = config.oneDriveUtils;

        # OneDrive status checker for WSL environments
        onedrive-status = pkgs.writeShellApplication {
          name = "onedrive-status";
          runtimeInputs = with pkgs; [ coreutils findutils ];
          text = ''
            set -euo pipefail

            if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
              echo "This script only works in WSL environments"
              exit 1
            fi

            echo "OneDrive Status Check"
            echo "======================"

            # Check if OneDrive process is running
            if /mnt/c/Windows/System32/cmd.exe /c "tasklist /fi \"imagename eq OneDrive.exe\" | find \"OneDrive.exe\"" > /dev/null 2>&1; then
              echo "OneDrive process is running"
            else
              echo "OneDrive process is not running"
            fi

            # Check current directory OneDrive status
            current_dir="$(pwd)"
            if [[ "$current_dir" =~ /mnt/c/Users/.*OneDrive ]]; then
              echo "Current directory is in OneDrive: $current_dir"
              echo "Recent files in current directory:"
              find . -maxdepth 1 -type f -printf '%T@ %p\n' | sort -nr | head -5 | cut -d' ' -f2-
            else
              echo "Current directory is not in OneDrive: $current_dir"
            fi

            echo ""
            echo "To force sync, run: onedrive-force-sync"
          '';
        };

        # OneDrive sync forcer for WSL environments
        onedrive-force-sync = pkgs.writeShellApplication {
          name = "onedrive-force-sync";
          runtimeInputs = with pkgs; [ coreutils findutils ];
          text = ''
            set -euo pipefail

            if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
              echo "This script only works in WSL environments"
              exit 1
            fi

            echo "Forcing OneDrive sync..."
            echo "=========================="

            # Dynamically find OneDrive directory (works across Windows usernames and OneDrive variants)
            ONEDRIVE_DIR=$(find /mnt/c/Users/*/OneDrive* -maxdepth 0 -type d 2>/dev/null | head -1)

            if [[ -n "$ONEDRIVE_DIR" && -d "$ONEDRIVE_DIR" ]]; then
              echo "Found OneDrive at: $ONEDRIVE_DIR"
              echo "Touching OneDrive directory..."
              touch "$ONEDRIVE_DIR"

              # Method 2: Create and remove a sync trigger file
              echo "Creating sync trigger file..."
              trigger_file="$ONEDRIVE_DIR/.sync_trigger_$(date +%s)"
              touch "$trigger_file"
              sleep 1
              rm -f "$trigger_file"

              echo "Sync triggered successfully"
              echo ""
              echo "Note: OneDrive may take a few moments to sync"
              echo "   Run 'onedrive-status' to check sync status"
            else
              echo "OneDrive directory not found in /mnt/c/Users/*/OneDrive*"
              exit 1
            fi
          '';
        };

      in
      {
        options.oneDriveUtils = {
          enable = lib.mkEnableOption "OneDrive utilities for WSL environments";
        };

        config = lib.mkIf cfg.enable {
          # Add OneDrive utility scripts
          home.packages = [
            onedrive-status
            onedrive-force-sync
          ];

          # Add convenient shell aliases
          programs.bash.shellAliases = {
            ods = "onedrive-status";
            odf = "onedrive-force-sync";
            "od-sync" = "onedrive-force-sync";
            "od-status" = "onedrive-status";
            "force-onedrive" = "onedrive-force-sync";
          };

          programs.zsh.shellAliases = {
            ods = "onedrive-status";
            odf = "onedrive-force-sync";
            "od-sync" = "onedrive-force-sync";
            "od-status" = "onedrive-status";
            "force-onedrive" = "onedrive-force-sync";
          };
        };
      };
  };
}
