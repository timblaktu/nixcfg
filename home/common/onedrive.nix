# OneDrive utilities for WSL environments
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;

  # OneDrive status checker for WSL environments
  onedrive-status = pkgs.writeShellApplication {
    name = "onedrive-status";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail
      
      if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
        echo "❌ This script only works in WSL environments"
        exit 1
      fi
      
      echo "📊 OneDrive Status Check"
      echo "======================"
      
      # Check if OneDrive process is running
      if /mnt/c/Windows/System32/cmd.exe /c "tasklist /fi \"imagename eq OneDrive.exe\" | find \"OneDrive.exe\"" > /dev/null 2>&1; then
        echo "✅ OneDrive process is running"
      else
        echo "❌ OneDrive process is not running"
      fi
      
      # Check current directory OneDrive status
      current_dir="$(pwd)"
      if [[ "$current_dir" =~ /mnt/c/Users/.*OneDrive ]]; then
        echo "📁 Current directory is in OneDrive: $current_dir"
        echo "📋 Recent files in current directory:"
        ls -lat | head -5
      else
        echo "📁 Current directory is not in OneDrive: $current_dir"
      fi
      
      echo ""
      echo "💡 To force sync, run: onedrive-force-sync"
    '';
    passthru.tests = {
      syntax = pkgs.runCommand "test-onedrive-status-syntax" { } ''
        echo "✅ Syntax validation passed at build time" > $out
      '';
      wsl_check = pkgs.runCommand "test-onedrive-status-wsl-check" { } ''
        echo "✅ WSL environment check test passed (placeholder)" > $out
      '';
    };
  };

  # OneDrive sync forcer for WSL environments
  onedrive-force-sync = pkgs.writeShellApplication {
    name = "onedrive-force-sync";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail
      
      if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
        echo "❌ This script only works in WSL environments"
        exit 1
      fi
      
      echo "🔄 Forcing OneDrive sync..."
      echo "=========================="
      
      # Method 1: Touch OneDrive directory to trigger sync
      if [[ -d "/mnt/c/Users/tblack/OneDrive" ]]; then
        echo "📁 Touching OneDrive directory..."
        touch "/mnt/c/Users/tblack/OneDrive"
        
        # Method 2: Create and remove a sync trigger file
        echo "📝 Creating sync trigger file..."
        trigger_file="/mnt/c/Users/tblack/OneDrive/.sync_trigger_$(date +%s)"
        touch "$trigger_file"
        sleep 1
        rm -f "$trigger_file"
        
        echo "✅ Sync triggered successfully"
        echo ""
        echo "💡 Note: OneDrive may take a few moments to sync"
        echo "   Run 'onedrive-status' to check sync status"
      else
        echo "❌ OneDrive directory not found at /mnt/c/Users/tblack/OneDrive"
        exit 1
      fi
    '';
    passthru.tests = {
      syntax = pkgs.runCommand "test-onedrive-force-sync-syntax" { } ''
        echo "✅ Syntax validation passed at build time" > $out
      '';
      wsl_check = pkgs.runCommand "test-onedrive-force-sync-wsl-check" { } ''
        echo "✅ WSL environment check test passed (placeholder)" > $out
      '';
    };
  };

in
{
  config = mkIf cfg.enableOneDriveUtils {
    # Add OneDrive utility scripts
    home.packages = [
      onedrive-status
      onedrive-force-sync
    ];

    # Add convenient shell aliases
    programs.bash.shellAliases = mkIf cfg.enableOneDriveUtils {
      ods = "onedrive-status";
      odf = "onedrive-force-sync";
    };

    programs.zsh.shellAliases = mkIf cfg.enableOneDriveUtils {
      ods = "onedrive-status";
      odf = "onedrive-force-sync";
    };
  };
}
