# modules/programs/terminal/terminal.nix
# Terminal configuration, font setup, and verification tools [nd]
#
# Provides:
#   flake.modules.homeManager.terminal - Terminal utilities and WSL verification
#
# Features:
#   - setup-terminal-fonts: Configure terminal fonts
#   - check-terminal-setup: Verify terminal configuration
#   - diagnose-emoji-rendering: Debug emoji display issues
#   - is_terminal_background_light_or_dark: Detect terminal theme
#   - check-windows-terminal: Verify Windows Terminal settings (WSL)
#   - WSL font installation verification
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.terminal ];
#   terminalVerification = {
#     enable = true;  # default
#     terminalFont = "CaskaydiaMono Nerd Font";
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.terminal = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.terminalVerification;

        # Font configuration settings
        fontConfig = {
          terminal = {
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
            emoji = {
              name = "Noto Color Emoji";
              downloadUrl = "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf";
              files = [ "NotoColorEmoji.ttf" ];
              aliases = [ ];
            };
          };
        };

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
              echo "WindowsTerminal"
            else
              echo "Unknown"
            fi
          }

          TERMINAL=$(detect_terminal)

          # Windows Terminal specific verification (WSL only)
          if [[ "$TERMINAL" == "WindowsTerminal" ]] && [[ -n "''${WSL_DISTRO:-}" ]]; then
            WT_SETTINGS=$(powershell.exe -NoProfile -Command "
              try {
                \$settingsPath = @(
                  \"\$env:LOCALAPPDATA\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json\",
                  \"\$env:LOCALAPPDATA\\Packages\\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\\LocalState\\settings.json\"
                ) | Where-Object { Test-Path \$_ } | Select-Object -First 1

                if (\$settingsPath) {
                  \$settings = Get-Content \$settingsPath -Raw | ConvertFrom-Json
                  \$profileName = \"''${WSL_DISTRO_NAME:-NixOS}\"
                  \$profile = \$settings.profiles.list | Where-Object {
                    \$_.name -eq \$profileName -or \$_.source -eq \"Windows.Terminal.Wsl\"
                  } | Select-Object -First 1

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
                echo "Windows Terminal font mismatch: '$CURRENT_FONT' (expected: '${expectedFontFace}')"
              fi
            fi
          fi

          # WSL-specific font checks
          if [[ -n "''${WSL_DISTRO:-}" ]]; then
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

            if [[ "$CASCADIA_CHECK" != "YES" ]]; then
              echo "CaskaydiaMono NFM not found. Download: ${fontConfig.terminal.primary.downloadUrl}"
            fi

            if [[ "$NOTO_CHECK" != "YES" ]]; then
              echo "Noto Color Emoji not found. Install: powershell.exe ~/bin/install-noto-emoji.ps1"
            fi
          fi
        '';

        checkWindowsTerminalScript = pkgs.writeScriptBin "check-windows-terminal" ''
          #!${pkgs.bash}/bin/bash
          ${terminalVerificationScript}
        '';

        wslToolsVerification = ''
          export PATH="$PATH:/mnt/c/Windows/System32:/mnt/c/Windows:/mnt/c/Windows/System32/WindowsPowerShell/v1.0"

          MISSING_TOOLS=""
          for tool in wslpath clip.exe powershell.exe; do
            if ! command -v $tool &>/dev/null; then
              MISSING_TOOLS="$MISSING_TOOLS $tool"
            fi
          done

          if [[ -n "$MISSING_TOOLS" ]]; then
            echo "Missing WSL tools:$MISSING_TOOLS"
          fi
        '';

      in
      {
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

        config = mkMerge [
          # Terminal utilities (always enabled when module is imported)
          {
            home.packages = with pkgs; [
              # Terminal font setup and verification scripts
              (pkgs.writeShellApplication {
                name = "setup-terminal-fonts";
                text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/setup-terminal-fonts");
                runtimeInputs = with pkgs; [ jq coreutils util-linux ];
              })

              (pkgs.writeShellApplication {
                name = "check-terminal-setup";
                text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/check-terminal-setup");
                runtimeInputs = with pkgs; [ jq coreutils ];
              })

              (pkgs.writeShellApplication {
                name = "diagnose-emoji-rendering";
                text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/diagnose-emoji-rendering");
                runtimeInputs = with pkgs; [ xxd coreutils util-linux ];
              })

              (pkgs.writeShellApplication {
                name = "is_terminal_background_light_or_dark";
                text = builtins.readFile (../../.. + "/modules/programs/files [nd]/files/bin/is_terminal_background_light_or_dark.sh");
                runtimeInputs = with pkgs; [ coreutils util-linux ];
              })
            ];
          }

          # Terminal verification (optional, but enabled by default)
          (mkIf cfg.enable {
            fonts.fontconfig.enable = lib.mkDefault true;

            home.packages = with pkgs; [
              nerd-fonts.caskaydia-mono
              fontconfig
              checkWindowsTerminalScript
            ];

            home.activation.terminalVerificationCheck = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              ${terminalVerificationScript}
            '';

            home.activation.wslToolsVerification = mkIf (config.targets.wsl.enable or false) (
              lib.hm.dag.entryAfter [ "writeBoundary" ] wslToolsVerification
            );

            home.sessionVariables = {
              TERMINAL_EXPECTED_FONT = expectedFontFace;
              TERMINAL_FONT_PRIMARY = fontConfig.terminal.primary.name;
              TERMINAL_FONT_EMOJI = fontConfig.terminal.emoji.name;
              WT_EXPECTED_FONT = expectedFontFace;
            };

            programs.zsh.shellAliases = mkIf config.programs.zsh.enable {
              check-terminal = "check-windows-terminal";
              verify-terminal = "check-windows-terminal";
            };

            programs.bash.shellAliases = mkIf config.programs.bash.enable {
              check-terminal = "check-windows-terminal";
              verify-terminal = "check-windows-terminal";
            };
          })
        ];
      };
  };
}
