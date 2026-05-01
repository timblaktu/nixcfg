# modules/system/settings/wsl-home/wsl-home.nix
# WSL Home Manager configuration
#
# Provides:
#   flake.modules.homeManager.wsl-home - WSL user-level configuration
#
# PLATFORM REQUIREMENTS: ANY WSL distribution + Nix + home-manager ✅
# This is a Home Manager module that works on ANY WSL distribution
# where Nix and home-manager are installed (NixOS-WSL, Ubuntu, Debian, Alpine, etc.)
#
# For NixOS-WSL system-level config, see:
#   modules/system/settings/wsl/ - NixOS system module (requires NixOS-WSL)
#
# Features:
#   - User-level WSL tweaks (shell aliases, environment variables)
#   - Windows Terminal settings management (via targets.wsl)
#   - WSL utilities (wslu package)
#   - Windows interop tools (explorer.exe, code.exe aliases)
#   - Wi-Fi priority management via netsh.exe (wifiTools option group)
#
# Usage in host home config:
#   imports = [
#     inputs.self.modules.homeManager.wsl-home
#   ];
#   wsl-home-settings = {
#     enableWindowsAliases = true;
#     distroName = "nixos";
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager WSL Module ===
    homeManager.wsl-home = { config, lib, pkgs, ... }:
      let
        cfg = config.wsl-home-settings;
        wifiCfg = config.wsl-home-settings.wifiTools;

        # Wi-Fi priority management scripts (netsh.exe wrappers)
        mkWifiScripts = defaultIface:
          let
            wslGuard = ''
              if ! command -v netsh.exe >/dev/null 2>&1; then
                echo "Error: netsh.exe not found. This tool requires WSL with Windows interop enabled." >&2
                exit 1
              fi
            '';

            crlfStrip = "tr -d '\\r'";

            elevationError = ''
              echo "" >&2
              echo "This command requires administrator elevation." >&2
              echo "Options:" >&2
              echo "  1. Launch an elevated WSL shell:" >&2
              echo "     powershell.exe -Command \"Start-Process wsl -Verb RunAs\"" >&2
              echo "  2. Re-run from an Administrator terminal" >&2
            '';

            # Awk program to extract SSIDs from netsh profile listing.
            # Parses the "User profiles" section, skipping "Group policy profiles".
            ssidAwk = ''
              /^User profiles/  { in_user=1; next }
              /^Group policy/   { in_user=0; next }
              /^-+/             { next }
              in_user && /All User Profile/ {
                sub(/^[[:space:]]*All User Profile[[:space:]]*: /, "")
                print
              }
            '';

            wifi-priority-list = pkgs.writeShellApplication {
              name = "wifi-priority-list";
              runtimeInputs = with pkgs; [ gawk coreutils ];
              text = ''
                ${wslGuard}
                iface="''${1:-${defaultIface}}"

                echo "Wi-Fi profiles on interface: $iface (priority order)"
                echo "================================================"

                netsh.exe wlan show profiles interface="$iface" 2>&1 | ${crlfStrip} | \
                  awk '
                    ${ssidAwk}
                  ' | awk '{ printf "%3d  %s\n", NR, $0 }'
              '';
            };

            wifi-priority-set = pkgs.writeShellApplication {
              name = "wifi-priority-set";
              runtimeInputs = [ pkgs.gawk pkgs.coreutils pkgs.gnugrep wifi-priority-list ];
              text = ''
                ${wslGuard}
                if [ $# -lt 2 ]; then
                  echo "Usage: wifi-priority-set <SSID> <priority> [interface]" >&2
                  echo "  priority: 1 = highest priority" >&2
                  exit 1
                fi
                ssid="$1"
                priority="$2"
                iface="''${3:-${defaultIface}}"

                echo "=== BEFORE ==="
                wifi-priority-list "$iface"
                echo ""

                echo "Setting '$ssid' to priority $priority on interface '$iface'..."
                output=$(netsh.exe wlan set profileorder name="$ssid" interface="$iface" priority="$priority" 2>&1 | ${crlfStrip}) || true

                if grep -qiE "elevated|access is denied" <<< "$output"; then
                  echo "$output" >&2
                  ${elevationError}
                  exit 1
                fi
                echo "$output"
                echo ""
                echo "=== AFTER ==="
                wifi-priority-list "$iface"
              '';
            };

            wifi-autoswitch-set = pkgs.writeShellApplication {
              name = "wifi-autoswitch-set";
              runtimeInputs = with pkgs; [ coreutils gnugrep ];
              text = ''
                ${wslGuard}
                if [ $# -lt 2 ]; then
                  echo "Usage: wifi-autoswitch-set <SSID> <yes|no> [interface]" >&2
                  exit 1
                fi
                ssid="$1"
                value="$2"
                iface="''${3:-${defaultIface}}"

                if [ "$value" != "yes" ] && [ "$value" != "no" ]; then
                  echo "Error: value must be 'yes' or 'no'" >&2
                  exit 1
                fi

                echo "Setting autoSwitch=$value for '$ssid' on interface '$iface'..."
                output=$(netsh.exe wlan set profileparameter name="$ssid" interface="$iface" autoSwitch="$value" 2>&1 | ${crlfStrip}) || true

                if grep -qiE "elevated|access is denied" <<< "$output"; then
                  echo "$output" >&2
                  ${elevationError}
                  exit 1
                fi
                echo "$output"
              '';
            };

            wifi-priority-show-detail = pkgs.writeShellApplication {
              name = "wifi-priority-show-detail";
              runtimeInputs = with pkgs; [ gawk coreutils ];
              text = ''
                ${wslGuard}
                iface="''${1:-${defaultIface}}"

                # Collect SSIDs in priority order
                mapfile -t ssids < <(
                  netsh.exe wlan show profiles interface="$iface" 2>&1 | ${crlfStrip} | \
                    awk '
                      ${ssidAwk}
                    '
                )

                if [ "''${#ssids[@]}" -eq 0 ]; then
                  echo "No Wi-Fi profiles found on interface '$iface'"
                  exit 0
                fi

                printf "%-4s  %-30s  %-22s  %s\n" "#" "SSID" "Connection Mode" "AutoSwitch"
                printf "%-4s  %-30s  %-22s  %s\n" "---" "------------------------------" "----------------------" "----------"

                n=0
                for ssid in "''${ssids[@]}"; do
                  n=$((n + 1))
                  detail=$(netsh.exe wlan show profile name="$ssid" interface="$iface" 2>&1 | ${crlfStrip})
                  conn_mode=$(awk -F': ' '/Connection mode/ { sub(/^ +/, "", $2); print $2; exit }' <<< "$detail")
                  auto_switch=$(awk -F': ' '/AutoSwitch/ { sub(/^ +/, "", $2); print $2; exit }' <<< "$detail")
                  printf "%-4s  %-30s  %-22s  %s\n" "$n" "$ssid" "''${conn_mode:-N/A}" "''${auto_switch:-N/A}"
                done
              '';
            };
          in
          {
            inherit wifi-priority-list wifi-priority-set wifi-autoswitch-set wifi-priority-show-detail;
          };

        wifiScripts = mkWifiScripts wifiCfg.defaultInterface;
      in
      {
        options.wsl-home-settings = {
          # === Core Settings ===
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable WSL home-manager configuration";
          };

          distroName = lib.mkOption {
            type = lib.types.str;
            default = "nixos";
            description = "WSL distribution name for environment variables";
            example = "Ubuntu";
          };

          editor = lib.mkOption {
            type = lib.types.str;
            default = "nvim";
            description = "Default editor";
          };

          # === Feature Toggles ===
          # NOTE: These options were removed in Task 6.4.9.
          # Features are now enabled by importing dendritic modules directly:
          #   - development-tools module (with developmentTools.enable)
          #   - esp-idf module (with espIdf.enable)
          #   - onedrive module (with oneDriveUtils.enable)
          #   - shell-utils module (always enabled when imported)
          #   - terminal module (always enabled when imported)
          # See host files for import patterns.

          # === Windows Interop ===
          enableWindowsAliases = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Windows tool aliases (explorer, code, etc.)";
          };

          extraShellAliases = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional shell aliases";
            example = {
              pwsh = "powershell.exe";
            };
          };

          # === Environment Variables ===
          extraEnvironmentVariables = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional environment variables";
          };

          # === Windows Terminal ===
          windowsTerminal = {
            enablePowerShell = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable PowerShell integration in Windows Terminal";
            };

            enableCmd = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable cmd.exe integration in Windows Terminal";
            };

            enableWslPath = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable wslpath integration";
            };

            wslPathPath = lib.mkOption {
              type = lib.types.str;
              default = "/bin/wslpath";
              description = "Path to wslpath binary";
            };
          };

          # === Wi-Fi Priority Management ===
          wifiTools = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable Wi-Fi priority management tools (netsh.exe wrappers)";
            };

            defaultInterface = lib.mkOption {
              type = lib.types.str;
              default = "Wi-Fi";
              description = "Default Windows Wi-Fi interface name";
            };
          };
        };

        config = lib.mkIf cfg.enable (lib.mkMerge [
          # === Environment and Aliases ===
          {
            home.sessionVariables = {
              WSL_DISTRO = lib.mkDefault cfg.distroName;
              EDITOR = lib.mkDefault cfg.editor;
            } // cfg.extraEnvironmentVariables;

            programs.bash.shellAliases = lib.mkMerge [
              # Windows aliases
              (lib.mkIf cfg.enableWindowsAliases {
                explorer = lib.mkDefault "explorer.exe .";
                code = lib.mkDefault "code.exe";
                code-insiders = lib.mkDefault "code-insiders.exe";
                esp32c5 = lib.mkDefault "esp-idf-shell";
              })
              cfg.extraShellAliases
            ];

            programs.zsh.shellAliases = lib.mkMerge [
              # Windows aliases
              (lib.mkIf cfg.enableWindowsAliases {
                explorer = lib.mkDefault "explorer.exe .";
                code = lib.mkDefault "code.exe";
                code-insiders = lib.mkDefault "code-insiders.exe";
                esp32c5 = lib.mkDefault "esp-idf-shell";
              })
              cfg.extraShellAliases
            ];
          }

          # === WSL Utilities ===
          {
            home.packages = with pkgs; [
              wslu # WSL utilities (wslview, wslfetch, wslvar, etc.)
            ];

            # xdg-open → wslview wrapper that recovers Windows mounts if needed.
            # wslview relies on /mnt/c (for reg.exe, powershell.exe, etc.) and
            # wslpath (/bin/wslpath), both of which can be unavailable: mounts get
            # unmounted by isar/kas builds, and NixOS doesn't include /bin on PATH.
            home.file.".local/bin/xdg-open" = {
              executable = true;
              text = ''
                #!/bin/sh
                # Recover Windows drive mounts if isar/kas builds unmounted them
                if ! mountpoint -q /mnt/c 2>/dev/null; then
                  wsl-recover-mounts -q -s 2>/dev/null || true
                fi
                # wslpath lives at /bin which NixOS doesn't include on PATH
                export PATH="/bin:$PATH"
                exec "${pkgs.wslu}/bin/wslview" "$@"
              '';
            };
          }

          # === Windows Terminal Target Configuration ===
          {
            targets.wsl = {
              enable = true;
              windowsTools = {
                enablePowerShell = lib.mkDefault cfg.windowsTerminal.enablePowerShell;
                enableCmd = lib.mkDefault cfg.windowsTerminal.enableCmd;
                enableWslPath = lib.mkDefault cfg.windowsTerminal.enableWslPath;
                wslPathPath = lib.mkDefault cfg.windowsTerminal.wslPathPath;
              };
            };
          }

          # === Wi-Fi Priority Management ===
          (lib.mkIf wifiCfg.enable {
            home.packages = with wifiScripts; [
              wifi-priority-list
              wifi-priority-set
              wifi-autoswitch-set
              wifi-priority-show-detail
            ];

            programs.bash.shellAliases = {
              wpl = "wifi-priority-list";
              wps = "wifi-priority-set";
              was = "wifi-autoswitch-set";
              wpd = "wifi-priority-show-detail";
            };

            programs.zsh.shellAliases = {
              wpl = "wifi-priority-list";
              wps = "wifi-priority-set";
              was = "wifi-autoswitch-set";
              wpd = "wifi-priority-show-detail";
            };
          })
        ]);
      };
  };
}
