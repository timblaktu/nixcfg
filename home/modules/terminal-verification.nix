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

  # Expected font configuration for Windows Terminal - simplified
  # Using the Windows-recognized font name (CaskaydiaMono NFM)
  expectedFontFace = "CaskaydiaMono NFM";

  # Terminal verification script for activation
  terminalVerificationScript = ''
    # Terminal Font Verification Script
    # This script runs during home-manager activation to verify terminal configuration
    
    echo "🔍 Verifying terminal configuration..."
    
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
    echo "  Terminal: $TERMINAL"
    
    # Windows Terminal specific verification (WSL only)
    if [[ "$TERMINAL" == "WindowsTerminal" ]] && [[ -n "''${WSL_DISTRO:-}" ]]; then
      echo "  Checking Windows Terminal settings..."
      
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
        echo "  Current Font: $CURRENT_FONT"
        
        if [[ "$CURRENT_FONT" != "${expectedFontFace}" ]]; then
          echo ""
          echo "⚠️  Windows Terminal configuration needs update:"
          echo "  Expected Font: ${expectedFontFace}"
          echo ""
          echo "  To fix this, update Windows Terminal:"
          echo "  1. Open Windows Terminal Settings (Ctrl+,)"
          echo "  2. Navigate to Profiles → ''${WSL_DISTRO_NAME:-NixOS}"
          echo "  3. Go to Appearance → Font face"
          echo "  4. Set to: ${expectedFontFace}"
          echo ""
        else
          echo "  ✅ Font configuration correct"
        fi
      else
        echo "  ⚠️  Could not read Windows Terminal settings"
      fi
    fi
    
    # Check for Nerd Font installation
    echo ""
    echo "🔍 Checking font availability..."
    
    # Function to check if font is available
    check_font() {
      local font_name="$1"
      # Use fontconfig from the Nix store if fc-list isn't in PATH yet
      if command -v fc-list &>/dev/null; then
        fc-list | grep -qi "$font_name"
      elif [[ -x "${pkgs.fontconfig}/bin/fc-list" ]]; then
        "${pkgs.fontconfig}/bin/fc-list" | grep -qi "$font_name"
      else
        # Fallback: assume font is not available if we can't check
        return 1
      fi
    }
    
    # Check each configured font
    for font_alias in ${concatMapStringsSep " " (x: ''"${x}"'') fontConfig.terminal.primary.aliases}; do
      if check_font "$font_alias"; then
        echo "  ✅ Primary font available: $font_alias"
        break
      fi
    done
    
    # Primary font already has Nerd Font icons, no need for separate check
    
    # WSL-specific font checks
    if [[ -n "''${WSL_DISTRO:-}" ]]; then
      echo ""
      echo "🔍 Checking Windows font installation..."
      
      # Check for fonts in Windows using PowerShell
      WINDOWS_FONTS=$(powershell.exe -NoProfile -Command "
        \$fonts = @()
        
        # Check for CaskaydiaMono Nerd Font
        \$cascadiaCheck = [System.Drawing.Text.InstalledFontCollection]::new()
        \$cascadiaFonts = \$cascadiaCheck.Families | Where-Object { 
          \$_.Name -like '*Cascadia*' -or \$_.Name -like '*Caskaydia*'
        }
        
        if (\$cascadiaFonts) {
          \$fonts += 'CASCADIA:YES'
        } else {
          \$fonts += 'CASCADIA:NO'
        }
        
        # Check for Noto Color Emoji
        \$notoCheck = \$cascadiaCheck.Families | Where-Object { 
          \$_.Name -like '*Noto*Color*Emoji*'
        }
        
        if (\$notoCheck) {
          \$fonts += 'NOTO:YES'
        } else {
          \$fonts += 'NOTO:NO'
        }
        
        \$fonts -join '|'
      " 2>/dev/null | tr -d '\r')
      
      # Parse results
      if [[ "$WINDOWS_FONTS" == *"CASCADIA:YES"* ]]; then
        echo "  ✅ Cascadia/CaskaydiaMono fonts installed in Windows"
      else
        echo "  ⚠️  CaskaydiaMono Nerd Font not found in Windows"
        echo "     Download from: ${fontConfig.terminal.primary.downloadUrl}"
      fi
      
      if [[ "$WINDOWS_FONTS" == *"NOTO:YES"* ]]; then
        echo "  ✅ Noto Color Emoji installed in Windows"
      else
        echo "  ⚠️  Noto Color Emoji not found in Windows"
        echo "     Install via: winget install Google.NotoEmoji"
      fi
    fi
    
    echo ""
    echo "✨ Terminal verification complete"
    echo ""
  '';

  # Script to check Windows Terminal settings
  checkWindowsTerminalScript = pkgs.writeScriptBin "check-windows-terminal" ''
    #!${pkgs.bash}/bin/bash
    ${terminalVerificationScript}
  '';

  wslToolsVerification = mkIf (config.targets.wsl.enable or false) ''
    # WSL tools verification  
    echo "🔧 Checking WSL tools availability..."
    
    # Ensure Windows paths are in PATH for this check
    export PATH="$PATH:/mnt/c/Windows/System32:/mnt/c/Windows:/mnt/c/Windows/System32/WindowsPowerShell/v1.0"
    
    # Check for wslpath
    if command -v wslpath &>/dev/null; then
      echo "  ✅ wslpath: available"
    else
      echo "  ⚠️  wslpath: not found"
      # Check common locations
      for path in /usr/bin/wslpath /bin/wslpath; do
        if [[ -x "$path" ]]; then
          echo "     Found at: $path (not in PATH)"
          break
        fi
      done
    fi
    
    # Check for Windows utilities
    if command -v clip.exe &>/dev/null; then
      echo "  ✅ clip.exe: available"
    else
      echo "  ⚠️  clip.exe: not found"
      # Check if it exists but not in PATH
      if [[ -x "/mnt/c/Windows/System32/clip.exe" ]]; then
        echo "     Found at: /mnt/c/Windows/System32/clip.exe (not in PATH)"
      fi
    fi
    
    # Check for other common Windows tools
    for tool in powershell.exe cmd.exe explorer.exe code.exe; do
      if command -v $tool &>/dev/null; then
        echo "  ✅ $tool: available"
      fi
    done
    
    echo ""
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
