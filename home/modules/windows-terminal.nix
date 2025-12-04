# Windows Terminal settings management module
# Uses jq for intelligent JSON merging to preserve user customizations
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.windowsTerminal;

  # Build the required settings as a Nix attribute set
  requiredSettings = {
    # Font configuration
    profiles.defaults.font = {
      face = cfg.font.face;
      size = cfg.font.size;
    };

    # Color scheme name
    profiles.defaults.colorScheme = cfg.colorScheme.name;

    # Keybindings array
    keybindings = cfg.keybindings;

    # Color schemes array
    schemes = [ cfg.colorScheme.definition ];
  };

  # Convert to JSON for merging
  requiredSettingsJson = builtins.toJSON requiredSettings;

  # jq script for intelligent merging
  # This handles arrays specially: keybindings by id/keys, schemes by name
  mergeScript = pkgs.writeText "merge-terminal-settings.jq" ''
    # Function to merge keybindings array
    # Updates existing bindings by id or keys, adds new ones
    def merge_keybindings(existing; new):
      (existing // []) as $existing |
      new as $new |

      # Build a map of existing bindings by their id or keys
      ($existing | map({
        key: (if .id then .id else .keys end),
        value: .
      }) | from_entries) as $existing_map |

      # Process each new binding
      ($new | map(
        . as $binding |
        (if .id then .id else .keys end) as $key |
        $binding
      )) as $new_bindings |

      # Merge: update existing and add new
      ($existing_map | to_entries | map(
        .key as $k |
        if ($new_bindings | map(if .id then .id else .keys end) | index($k))
        then ($new_bindings | map(select((if .id then .id else .keys end) == $k)) | .[0])
        else .value
        end
      )) +
      ($new_bindings | map(
        . as $b |
        (if .id then .id else .keys end) as $k |
        if ($existing_map | has($k)) then empty else $b end
      ));

    # Function to merge color schemes array
    # Updates existing schemes by name, adds new ones
    def merge_schemes(existing; new):
      (existing // []) as $existing |
      new as $new |

      # Build map by scheme name
      ($existing | map({key: .name, value: .}) | from_entries) as $existing_map |

      # Merge: update existing and add new
      ($existing_map | to_entries | map(
        .key as $name |
        if ($new | map(.name) | index($name))
        then ($new | map(select(.name == $name)) | .[0])
        else .value
        end
      )) +
      ($new | map(
        . as $scheme |
        if ($existing_map | has($scheme.name)) then empty else $scheme end
      ));

    # Main merge logic
    . as $current |
    $required as $req |

    # Deep merge the settings
    $current * $req |

    # Special handling for arrays
    .keybindings = merge_keybindings($current.keybindings; $req.keybindings) |
    .schemes = merge_schemes($current.schemes; $req.schemes)
  '';

  # Wrapper script that uses jq to merge settings
  mergeSettingsScript = pkgs.writeScriptBin "merge-terminal-settings" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    echo "🔧 Merging Windows Terminal settings..."

    # Find Windows Terminal settings.json
    SETTINGS_PATH=""
    for path in \
      "/mnt/c/Users/$USER/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
      "/mnt/c/Users/$(whoami)/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
      "/mnt/c/Users/blackt1/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"; do
      if [[ -f "$path" ]]; then
        SETTINGS_PATH="$path"
        break
      fi
    done

    if [[ -z "$SETTINGS_PATH" ]]; then
      echo "❌ Windows Terminal settings.json not found"
      exit 1
    fi

    echo "  Found settings at: $SETTINGS_PATH"

    # Create backup
    BACKUP_PATH="$SETTINGS_PATH.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_PATH" "$BACKUP_PATH"
    echo "  📁 Backup created: $BACKUP_PATH"

    # Required settings as JSON
    REQUIRED_JSON='${requiredSettingsJson}'

    # Perform the merge using jq
    echo "  📋 Applying required settings..."

    # Use jq to merge, preserving all existing settings
    ${pkgs.jq}/bin/jq \
      --argjson required "$REQUIRED_JSON" \
      --from-file ${mergeScript} \
      "$SETTINGS_PATH" > "$SETTINGS_PATH.tmp"

    # Check if merge was successful
    if [[ $? -eq 0 ]] && [[ -s "$SETTINGS_PATH.tmp" ]]; then
      # Validate the JSON
      if ${pkgs.jq}/bin/jq empty "$SETTINGS_PATH.tmp" 2>/dev/null; then
        mv "$SETTINGS_PATH.tmp" "$SETTINGS_PATH"
        echo "✅ Settings merged successfully!"

        # Show what was ensured
        echo ""
        echo "Ensured settings:"
        echo "  • Font: ${cfg.font.face} (size ${toString cfg.font.size})"
        echo "  • Color Scheme: ${cfg.colorScheme.name}"
        echo "  • Keybindings: ${toString (length cfg.keybindings)} configured"
        echo ""
        echo "Your other customizations have been preserved."
      else
        echo "❌ Merged JSON is invalid, reverting..."
        rm -f "$SETTINGS_PATH.tmp"
        exit 1
      fi
    else
      echo "❌ Merge failed"
      rm -f "$SETTINGS_PATH.tmp"
      exit 1
    fi
  '';

in
{
  options.windowsTerminal = {
    enable = mkOption {
      type = types.bool;
      default = config.targets.wsl.enable or false;
      description = "Enable Windows Terminal settings management";
    };

    font = {
      face = mkOption {
        type = types.str;
        default = "CaskaydiaMono NFM";
        description = "Font face for Windows Terminal";
      };

      size = mkOption {
        type = types.int;
        default = 11;
        description = "Font size for Windows Terminal";
      };
    };

    colorScheme = {
      name = mkOption {
        type = types.str;
        default = "Solarized Dark (Correct)";
        description = "Color scheme name";
      };

      definition = mkOption {
        type = types.attrs;
        default = {
          name = "Solarized Dark (Correct)";
          background = "#002b36";
          foreground = "#839496";
          black = "#073642";
          red = "#dc322f";
          green = "#859900";
          yellow = "#b58900";
          blue = "#268bd2";
          purple = "#d33682";
          cyan = "#2aa198";
          white = "#eee8d5";
          brightBlack = "#002b36";
          brightRed = "#cb4b16";
          brightGreen = "#586e75";
          brightYellow = "#657b83";
          brightBlue = "#839496";
          brightPurple = "#6c71c4";
          brightCyan = "#93a1a1";
          brightWhite = "#fdf6e3";
          cursorColor = "#FFFFFF";
          selectionBackground = "#FFFFFF";
        };
        description = "Color scheme definition";
      };
    };

    keybindings = mkOption {
      type = types.listOf types.attrs;
      default = [
        { id = "Terminal.CopyToClipboard"; keys = "ctrl+c"; }
        { id = "Terminal.PasteFromClipboard"; keys = "ctrl+v"; }
        { id = "Terminal.DuplicatePaneAuto"; keys = "alt+shift+d"; }
        # Tab navigation with standard keys
        { id = "Terminal.NextTab"; keys = "ctrl+tab"; }
        { id = "Terminal.PrevTab"; keys = "ctrl+shift+tab"; }
        # Vim-style navigation (uncomment if desired)
        # { command = "nextTab"; keys = "alt+l"; }
        # { command = "prevTab"; keys = "alt+h"; }
      ];
      description = "Keybindings to ensure are present";
    };

    additionalSettings = mkOption {
      type = types.attrs;
      default = { };
      description = "Additional settings to merge (advanced)";
    };
  };

  config = mkIf cfg.enable {
    # Ensure jq is available
    home.packages = with pkgs; [
      jq
      mergeSettingsScript
    ];

    # Run merge on activation (non-destructive)
    home.activation.mergeWindowsTerminalSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ -n "''${WSL_DISTRO:-}" ]]; then
        echo "🔧 Checking Windows Terminal settings..."

        # Only run if we're in WSL
        ${mergeSettingsScript}/bin/merge-terminal-settings || {
          echo "⚠️  Failed to merge Windows Terminal settings"
          echo "   You can run 'merge-terminal-settings' manually to retry"
        }
      fi
    '';
  };
}
