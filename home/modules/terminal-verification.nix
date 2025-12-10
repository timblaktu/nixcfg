# WSL Microsoft Terminal alignment verification module
# Ensures Windows Terminal and WSL NixOS configurations are properly aligned
# This module can be extended to check other cross-environment dependencies
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.terminalVerification;

  # Font configuration settings - Configurable terminal font
  fontConfig = {
    terminal = {
      # Primary terminal font - configurable through option
      primary = {
        name = cfg.terminalFont;
        downloadUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip";
        files = [
          "CaskaydiaMonoNerdFontMono-Regular.ttf"
          "CaskaydiaMonoNerdFontMono-Bold.ttf"
          "CaskaydiaMonoNerdFontMono-Italic.ttf"
          "CaskaydiaMonoNerdFontMono-BoldItalic.ttf"
        ];
        aliases = [
          "CaskaydiaMono NFM"
          "CaskaydiaMonoNerdFontMono"
        ];
      };
      # Emoji support - Noto Color Emoji
      emoji = {
        name = "Noto Color Emoji";
        downloadUrl = "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf";
        files = [ "NotoColorEmoji.ttf" ];
        aliases = [ ];
      };
    };
  };

  # Nerd Fonts to install
  nerdFonts = [
    "CascadiaMono" # For terminal (includes CaskaydiaMono Nerd Font Mono)
  ];

  # Expected font configuration for Windows Terminal
  # Noto Color Emoji provides better emoji rendering than fallback
  expectedFontFace = "CaskaydiaMono NFM, Noto Color Emoji";

  # Terminal verification script for activation
  terminalVerificationScript = ''
    # Terminal Font Verification Script
    # This script runs during home-manager activation to verify terminal configuration

    # Function to check terminal emulator
    detect_terminal() {
      if [[ -n "''${WT_SESSION:-}" ]]; then
        echo "WindowsTerminal"
      elif [[ -n "''${TERM_PROGRAM:-}" ]]; then
        echo "$TERM_PROGRAM"
      elif [[ -n "''${ALACRITTY_SOCKET:-}" ]]; then
        echo "Alacritty"
      elif [[ -n "''${KITTY_WINDOW_ID:-}" ]]; then
        echo "Kitty"
      elif [[ "''${TERM:-}" == "xterm-256color" ]] && [[ -n "''${WSL_DISTRO:-}" ]]; then
        # Likely Windows Terminal in WSL
        echo "WindowsTerminal"
      else
        echo "Unknown"
      fi
    }

    TERMINAL=$(detect_terminal)
    
    # Windows Terminal specific verification (WSL only)
    if [[ "$TERMINAL" == "WindowsTerminal" ]] && [[ -n "''${WSL_DISTRO:-}" ]]; then
      # Read Windows Terminal settings using PowerShell
      WT_SETTINGS=$(powershell.exe -NoProfile -Command "
        try {
          # Try both possible settings locations
          \$settingsPath = @(
            \"\$env:LOCALAPPDATA\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json\",
            \"\$env:LOCALAPPDATA\\Packages\\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\\LocalState\\settings.json\"
          ) | Where-Object { Test-Path \$_ } | Select-Object -First 1

          if (\$settingsPath) {
            \$settings = Get-Content \$settingsPath -Raw | ConvertFrom-Json

            # Find the profile for this WSL distro
            \$profileName = \"''${WSL_DISTRO_NAME:-NixOS}\"
            \$profile = \$settings.profiles.list | Where-Object {
              \$_.name -eq \$profileName -or \$_.source -eq \"Windows.Terminal.Wsl\"
            } | Select-Object -First 1

            # Get font face (check profile first, then defaults)
            \$fontFace = if (\$profile.font.face) {
              \$profile.font.face
            } elseif (\$settings.profiles.defaults.font.face) {
              \$settings.profiles.defaults.font.face
            } else {
              \"Cascadia Mono\"
            }

            Write-Output \"FONT:\$fontFace\"
          }
        } catch {
          Write-Output \"ERROR:Could not read settings\"
        }
      " 2>/dev/null | tr -d '\r' | grep -E '^(FONT|ERROR):')

      if [[ "$WT_SETTINGS" == FONT:* ]]; then
        CURRENT_FONT="''${WT_SETTINGS#FONT:}"

        if [[ "$CURRENT_FONT" != "${expectedFontFace}" ]]; then
          echo "⚠️  Windows Terminal font mismatch: '$CURRENT_FONT' (expected: '${expectedFontFace}')"
        fi
      fi
    fi
    
    
    # WSL-specific font checks - Check registry instead of System.Drawing
    if [[ -n "''${WSL_DISTRO:-}" ]]; then
      # Check for fonts in Windows registry (more reliable than System.Drawing)
      CASCADIA_CHECK=$(powershell.exe -NoProfile -Command "
        \$fonts = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue
        if (\$fonts -and (\$fonts.PSObject.Properties | Where-Object { \$_.Name -like '*CaskaydiaMono NFM*' })) {
          'YES'
        } else {
          'NO'
        }
      " 2>/dev/null | tr -d '\r\n ')

      NOTO_CHECK=$(powershell.exe -NoProfile -Command "
        \$fonts = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue
        if (\$fonts -and (\$fonts.PSObject.Properties | Where-Object { \$_.Name -like '*Noto Color Emoji*' })) {
          'YES'
        } else {
          'NO'
        }
      " 2>/dev/null | tr -d '\r\n ')

      # Only show warnings if fonts are missing
      if [[ "$CASCADIA_CHECK" != "YES" ]]; then
        echo "⚠️  CaskaydiaMono NFM not found. Download: ${fontConfig.terminal.primary.downloadUrl}"
      fi

      if [[ "$NOTO_CHECK" != "YES" ]]; then
        echo "⚠️  Noto Color Emoji not found. Install:"
        echo "    powershell.exe ~/bin/install-noto-emoji.ps1"
      fi
    fi
  '';

  # Script to check Windows Terminal settings
  checkWindowsTerminalScript = pkgs.writeScriptBin "check-windows-terminal" ''
    #!${pkgs.bash}/bin/bash
    ${terminalVerificationScript}
  '';

  wslToolsVerification = mkIf (config.targets.wsl.enable or false) ''
    # WSL tools verification - only show errors
    # Ensure Windows paths are in PATH for this check
    export PATH="$PATH:/mnt/c/Windows/System32:/mnt/c/Windows:/mnt/c/Windows/System32/WindowsPowerShell/v1.0"

    # Check for critical tools and only report if missing
    MISSING_TOOLS=""
    for tool in wslpath clip.exe powershell.exe; do
      if ! command -v $tool &>/dev/null; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
      fi
    done

    if [[ -n "$MISSING_TOOLS" ]]; then
      echo "⚠️  Missing WSL tools:$MISSING_TOOLS"
    fi
  '';
in
{
  # Define options for this module
  options.terminalVerification = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable terminal verification and font installation";
    };

    verbose = mkOption {
      type = types.bool;
      default = false;
      description = "Show verbose output during verification";
    };

    warnOnMisconfiguration = mkOption {
      type = types.bool;
      default = true;
      description = "Show warnings when terminal configuration doesn't match expectations";
    };

    terminalFont = mkOption {
      type = types.str;
      default = "CaskaydiaMono Nerd Font";
      description = "Primary terminal font to use in Windows Terminal";
      example = "JetBrainsMono Nerd Font";
    };
  };

  # Configuration based on options
  config = mkIf cfg.enable {
    # Install Nerd Fonts (provides a selection of programming fonts with icons)
    fonts.fontconfig.enable = lib.mkDefault true;

    home.packages = with pkgs; [
      # Install only the Nerd Font we actually use
      nerd-fonts.caskaydia-mono # CaskaydiaMono Nerd Font Mono

      # Font management utilities
      fontconfig # Provides fc-list, fc-cache, etc.

      # Terminal verification script
      checkWindowsTerminalScript
    ];

    # Activation script to verify terminal configuration
    home.activation.terminalVerificationCheck = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${terminalVerificationScript}
    '';

    # WSL-specific tools check
    home.activation.wslToolsVerification = mkIf (config.targets.wsl.enable or false) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] wslToolsVerification
    );

    # Set environment variables for terminal verification
    home.sessionVariables = {
      TERMINAL_EXPECTED_FONT = expectedFontFace;
      TERMINAL_FONT_PRIMARY = fontConfig.terminal.primary.name;
      TERMINAL_FONT_EMOJI = fontConfig.terminal.emoji.name;
      # Also set WT_ prefixed variables for compatibility with scripts
      WT_EXPECTED_FONT = expectedFontFace;
      # WT_SETTINGS_PATH will be detected dynamically by scripts
    };

    # Convenience alias for checking terminal configuration
    programs.zsh.shellAliases = mkIf config.programs.zsh.enable {
      check-terminal = "check-windows-terminal";
      verify-terminal = "check-windows-terminal";
    };

    programs.bash.shellAliases = mkIf config.programs.bash.enable {
      check-terminal = "check-windows-terminal";
      verify-terminal = "check-windows-terminal";
    };
  };
}
