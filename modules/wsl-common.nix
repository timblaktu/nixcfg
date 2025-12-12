# Common WSL configuration module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.wslCommon;
in
{
  options.wslCommon = {
    enable = mkEnableOption "WSL common configuration";

    hostname = mkOption {
      type = types.str;
      description = "System hostname";
      example = "thinky-nixos";
    };

    defaultUser = mkOption {
      type = types.str;
      default = "tim";
      description = "Default WSL user";
    };

    interopRegister = mkOption {
      type = types.bool;
      default = true;
      description = "Enable WSL interop registration";
    };

    interopIncludePath = mkOption {
      type = types.bool;
      default = true;
      description = "Enable integration with Windows paths";
    };

    appendWindowsPath = mkOption {
      type = types.bool;
      default = true;
      description = "Ensure Win32 support works by appending Windows PATH";
    };

    automountRoot = mkOption {
      type = types.str;
      default = "/mnt";
      description = "WSL automount root directory";
    };

    enableWindowsTools = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Windows tool aliases (explorer, code, etc.)";
    };

    sshPort = mkOption {
      type = types.int;
      default = 22;
      description = "SSH port for this WSL instance";
    };

    userGroups = mkOption {
      type = types.listOf types.str;
      default = [ "wheel" ];
      description = "Additional user groups";
    };

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "SSH authorized keys for the default user";
    };

    enableDnsTunneling = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable WSL2 DNS tunneling support. When enabled, provides a helper script
        to configure the Windows-side .wslconfig file with dnsTunneling=true.
        This prevents DNS resolution failures during nixos-rebuild by using
        WSL2's built-in DNS tunneling instead of the unreliable /mnt/wsl/resolv.conf.

        After enabling this option, run 'wsl-enable-dns-tunneling' and restart WSL.
      '';
    };

    windowsUsername = mkOption {
      type = types.str;
      default = "tblack";
      description = "Windows username for accessing .wslconfig file";
    };
  };

  config = mkIf cfg.enable
    {
      # Runtime assertions for WSL configuration validation
      assertions = [
        {
          assertion = cfg.hostname != "";
          message = "wslCommon.hostname must not be empty";
        }
        {
          assertion = cfg.defaultUser != "";
          message = "wslCommon.defaultUser must not be empty";
        }
        {
          assertion = cfg.sshPort > 0 && cfg.sshPort < 65536;
          message = "wslCommon.sshPort must be a valid port number (1-65535)";
        }
        {
          assertion = cfg.automountRoot != "";
          message = "wslCommon.automountRoot must not be empty";
        }
        {
          assertion = builtins.elem "wheel" cfg.userGroups;
          message = "wslCommon.userGroups should include 'wheel' for sudo access";
        }
      ];
      # WSL configuration
      wsl = {
        enable = true;
        defaultUser = cfg.defaultUser;
        interop.includePath = cfg.interopIncludePath;
        interop.register = cfg.interopRegister;
        wslConf.automount.root = cfg.automountRoot;
        wslConf.interop.appendWindowsPath = cfg.appendWindowsPath;
      };

      # Set hostname
      networking.hostName = cfg.hostname;

      # Configure the default user
      users.users.${cfg.defaultUser} = {
        isNormalUser = lib.mkDefault true;
        extraGroups = lib.mkDefault cfg.userGroups;
        # Shell is set by base.nix userShell option
        hashedPassword = lib.mkDefault ""; # No password needed in WSL
        openssh.authorizedKeys.keys = lib.mkDefault cfg.authorizedKeys;
      };

      # SSH configuration
      services.openssh = {
        enable = lib.mkDefault true;
        ports = [ cfg.sshPort ];
      };

      # WSL-specific packages
      environment.systemPackages = with pkgs; [
        wslu # WSL utilities
      ];

      # Windows tool aliases (conditional)
      environment.shellAliases = mkIf cfg.enableWindowsTools {
        explorer = "explorer.exe .";
        code = "code.exe";
        code-insiders = "code-insiders.exe";
      };

      # Disable services that don't make sense in WSL
      services.xserver.enable = false;
      services.printing.enable = false;
    }

  # DNS Tunneling configuration (conditional)
  // (mkIf cfg.enableDnsTunneling {
    # Helper script to configure Windows .wslconfig
    environment.systemPackages = with pkgs; [
      (writeScriptBin "wsl-enable-dns-tunneling" ''
                #!${pkgs.bash}/bin/bash
                set -euo pipefail

                WINDOWS_USER="${cfg.windowsUsername}"
                WSLCONFIG_PATH="/mnt/c/Users/$WINDOWS_USER/.wslconfig"

                echo "================================"
                echo "WSL2 DNS Tunneling Configuration"
                echo "================================"
                echo ""

                # Check if C drive is mounted
                if [ ! -d "/mnt/c/Users/$WINDOWS_USER" ]; then
                  echo "ERROR: Cannot access Windows user directory at /mnt/c/Users/$WINDOWS_USER"
                  echo ""
                  echo "This could mean:"
                  echo "  1. The C drive is not mounted (try: sudo mount -a)"
                  echo "  2. The Windows username is incorrect (current: $WINDOWS_USER)"
                  echo "  3. WSL interop is disabled"
                  echo ""
                  echo "To fix, check your wslCommon.windowsUsername setting in configuration.nix"
                  exit 1
                fi

                # Check current .wslconfig
                if [ -f "$WSLCONFIG_PATH" ]; then
                  echo "Found existing .wslconfig:"
                  echo "---"
                  cat "$WSLCONFIG_PATH"
                  echo "---"
                  echo ""

                  if grep -q "dnsTunneling.*true" "$WSLCONFIG_PATH"; then
                    echo "✓ DNS tunneling is already enabled in .wslconfig"
                    echo ""
                    echo "If DNS issues persist, restart WSL:"
                    echo "  1. Exit all WSL sessions"
                    echo "  2. Run in PowerShell: wsl --shutdown"
                    echo "  3. Start a new WSL session"
                    exit 0
                  fi
                fi

                echo "Creating/updating .wslconfig with DNS tunneling..."

                # Backup existing config
                if [ -f "$WSLCONFIG_PATH" ]; then
                  cp "$WSLCONFIG_PATH" "$WSLCONFIG_PATH.backup.$(date +%Y%m%d_%H%M%S)"
                  echo "✓ Backed up existing .wslconfig"
                fi

                # Create or update .wslconfig
                if [ -f "$WSLCONFIG_PATH" ] && grep -q "^\[wsl2\]" "$WSLCONFIG_PATH"; then
                  # Add to existing [wsl2] section
                  if grep -q "^\[wsl2\]" "$WSLCONFIG_PATH"; then
                    sed -i '/^\[wsl2\]/a dnsTunneling=true' "$WSLCONFIG_PATH"
                  fi
                else
                  # Create new [wsl2] section
                  cat >> "$WSLCONFIG_PATH" << 'EOF'

        [wsl2]
        dnsTunneling=true
        EOF
                fi

                echo "✓ Updated .wslconfig"
                echo ""
                echo "New .wslconfig contents:"
                echo "---"
                cat "$WSLCONFIG_PATH"
                echo "---"
                echo ""
                echo "⚠ IMPORTANT: You must restart WSL for changes to take effect:"
                echo ""
                echo "  1. Exit all WSL sessions (close all terminals)"
                echo "  2. Open PowerShell and run: wsl --shutdown"
                echo "  3. Start a new WSL session"
                echo ""
                echo "After restart, DNS will use WSL2's tunneling mechanism instead of"
                echo "/mnt/wsl/resolv.conf, preventing DNS failures during nixos-rebuild."
      '')

      (writeScriptBin "wsl-check-dns-tunneling" ''
        #!${pkgs.bash}/bin/bash

        WINDOWS_USER="${cfg.windowsUsername}"
        WSLCONFIG_PATH="/mnt/c/Users/$WINDOWS_USER/.wslconfig"

        echo "Checking DNS tunneling configuration..."
        echo ""

        if [ ! -f "$WSLCONFIG_PATH" ]; then
          echo "✗ No .wslconfig file found"
          echo "  Run 'wsl-enable-dns-tunneling' to configure DNS tunneling"
          exit 1
        fi

        if grep -q "dnsTunneling.*true" "$WSLCONFIG_PATH"; then
          echo "✓ DNS tunneling is enabled in .wslconfig"
          echo ""
          echo "Current resolv.conf:"
          cat /etc/resolv.conf
        else
          echo "✗ DNS tunneling is NOT enabled in .wslconfig"
          echo "  Run 'wsl-enable-dns-tunneling' to enable it"
          exit 1
        fi
      '')
    ];

    # Warning if DNS tunneling is enabled but .wslconfig isn't configured
    warnings =
      let
        wslconfigPath = "/mnt/c/Users/${cfg.windowsUsername}/.wslconfig";
        wslconfigExists = builtins.pathExists wslconfigPath;
      in
      [
        (mkIf (!wslconfigExists) ''
          WSL DNS tunneling is enabled in NixOS config, but .wslconfig may not be configured yet.
          Run 'wsl-enable-dns-tunneling' to set up Windows-side configuration.
        '')
      ];
  });
}
