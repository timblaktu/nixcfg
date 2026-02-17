# modules/programs/esp-idf/esp-idf.nix
# ESP-IDF development environment with FHS compatibility [nd]
#
# Provides:
#   flake.modules.homeManager.esp-idf - ESP32 development environment
#
# Features:
#   - FHS environment for ESP-IDF precompiled binaries
#   - esp-idf-install: Install ESP-IDF tools
#   - esp-idf-shell: Enter development shell
#   - esp-idf-export: Export environment variables
#   - idf.py wrapper: Run idf.py in FHS environment
#   - Helper scripts for updating and cleaning tools
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.esp-idf ];
#   espIdf.enable = true;
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.esp-idf = { config, lib, pkgs, ... }:
      let
        cfg = config.espIdf;

        # Create FHS environment for ESP-IDF compatibility
        esp-idf-fhs = pkgs.buildFHSEnv {
          name = "esp-idf-fhs";
          unshareUser = false;

          # Target multilib to handle both 32-bit and 64-bit binaries
          multiPkgs = pkgs: with pkgs; [
            zlib
            libxml2
            libxslt
            libffi
            openssl
            ncurses5
            stdenv.cc.cc.lib
            glibc
            # System libraries for ESP32 tools (multilib)
            udev
            libusb1
            hidapi
            libftdi1
          ];

          targetPkgs = pkgs: with pkgs; [
            # Python and essential tools
            python3
            python3Packages.pip
            python3Packages.virtualenv

            # Build tools that ESP-IDF expects
            gcc
            glibc
            binutils
            cmake
            ninja
            git
            wget
            curl

            # Libraries that ESP-IDF precompiled binaries expect
            zlib
            libxml2
            libxslt
            libffi
            openssl
            ncurses
            ncurses5

            # System libraries for ESP32 tools
            udev # Required by OpenOCD
            libusb1 # USB device access
            hidapi # HID device access
            libftdi1 # FTDI chip support

            # USB/serial tools for ESP32 programming
            dfu-util
            esptool

            # Additional tools for debugging and monitoring
            minicom
            screen

            # Common development utilities
            which
            file
            unzip

            # Libraries for compatibility with precompiled binaries
            stdenv.cc.cc.lib
            glibc.dev
          ];

          # Set up the environment for ESP-IDF
          profile = ''
            export IDF_PATH=${config.home.homeDirectory}/src/dsp/esp-idf
            export PATH="$IDF_PATH/tools:$PATH"
            export FHS_NAME="esp-idf"  # For shell scope detection

            # Set up Python path and tools
            export IDF_PYTHON_ENV_PATH="$HOME/.espressif/python_env/idf5.5_py3.11_env"

            # Create .espressif directory if it doesn't exist
            mkdir -p "$HOME/.espressif"

            echo "ESP-IDF FHS Environment Ready!"
            echo "IDF_PATH: $IDF_PATH"
            echo ""
            echo "Available commands:"
            echo "  esp-idf-install  - Run install.sh in FHS environment"
            echo "  esp-idf-export   - Source export.sh in current shell"
            echo "  idf.py           - ESP-IDF build tool"
            echo "  esptool.py       - ESP32 flashing tool"
            echo ""
            echo "To get started:"
            echo "  1. Run 'esp-idf-install' to install tools"
            echo "  2. Run 'esp-idf-export' to set up environment"
            echo "  3. Navigate to your project and use 'idf.py' commands"
          '';

          # Run command in FHS environment by default
          runScript = "bash";
        };

        # ESP-IDF development scripts
        esp-idf-install = pkgs.writeShellApplication {
          name = "esp-idf-install";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            # Run ESP-IDF install.sh in FHS environment

            echo "Running ESP-IDF install.sh in FHS environment..."

            IDF_PATH="''${IDF_PATH:-$HOME/src/dsp/esp-idf}"
            ESP_IDF_FHS_ENV="''${ESP_IDF_FHS_ENV:-esp-idf-fhs}"

            if [[ -z "$ESP_IDF_FHS_ENV" ]]; then
              echo "Error: ESP-IDF FHS environment not available"
              echo "   This script requires espIdf.enable = true in your home configuration"
              exit 1
            fi

            if [[ ! -f "$IDF_PATH/install.sh" ]]; then
              echo "Error: ESP-IDF not found at $IDF_PATH"
              echo "   Please ensure ESP-IDF is cloned to $IDF_PATH"
              echo "   Run: git clone --recursive https://github.com/espressif/esp-idf.git $IDF_PATH"
              exit 1
            fi

            # Use the FHS environment to run install.sh
            "$ESP_IDF_FHS_ENV" -c "
              export IDF_PATH=$IDF_PATH
              cd \"$IDF_PATH\"
              ./install.sh esp32c5
            "
          '';
        };

        esp-idf-shell = pkgs.writeShellApplication {
          name = "esp-idf-shell";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            # Start ESP-IDF development shell with proper environment

            echo "Starting ESP-IDF development shell..."

            IDF_PATH="''${IDF_PATH:-$HOME/src/dsp/esp-idf}"
            ESP_IDF_FHS_ENV="''${ESP_IDF_FHS_ENV:-esp-idf-fhs}"

            if [[ -z "$ESP_IDF_FHS_ENV" ]]; then
              echo "Error: ESP-IDF FHS environment not available"
              echo "   This script requires espIdf.enable = true in your home configuration"
              exit 1
            fi

            if [[ ! -f "$IDF_PATH/export.sh" ]]; then
              echo "Error: ESP-IDF not found at $IDF_PATH"
              echo "   Please ensure ESP-IDF is cloned to $IDF_PATH"
              echo "   Run: git clone --recursive https://github.com/espressif/esp-idf.git $IDF_PATH"
              exit 1
            fi

            # Enter FHS environment with ESP-IDF activated
            "$ESP_IDF_FHS_ENV" -c "
              export IDF_PATH=$IDF_PATH
              source \"$IDF_PATH/export.sh\"
              echo \"ESP-IDF environment activated!\"
              echo \"ESP-IDF version: \$(idf.py --version 2>/dev/null || echo 'Not installed - run esp-idf-install first')\"
              exec bash
            "
          '';
        };

        esp-idf-export = pkgs.writeShellApplication {
          name = "esp-idf-export";
          runtimeInputs = with pkgs; [ coreutils gnugrep ];
          text = ''
            # Output environment variables for ESP-IDF setup
            # Usage: eval $(esp-idf-export)

            IDF_PATH="''${IDF_PATH:-$HOME/src/dsp/esp-idf}"
            ESP_IDF_FHS_ENV="''${ESP_IDF_FHS_ENV:-esp-idf-fhs}"

            if [[ ! -f "$IDF_PATH/export.sh" ]]; then
              echo "echo 'Error: ESP-IDF not found at $IDF_PATH'" >&2
              exit 1
            fi

            if [[ -z "$ESP_IDF_FHS_ENV" ]]; then
              echo "echo 'Error: ESP-IDF FHS environment not available'" >&2
              exit 1
            fi

            echo "export IDF_PATH=$IDF_PATH"
            "$ESP_IDF_FHS_ENV" -c "
              source $IDF_PATH/export.sh > /dev/null 2>&1
              env | grep -E '^(PATH|IDF_|ESP_)' | sed 's/^/export /'
            "
          '';
        };

        idf-py = pkgs.writeShellApplication {
          name = "idf.py";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            # Wrapper for idf.py that ensures FHS environment

            IDF_PATH="''${IDF_PATH:-$HOME/src/dsp/esp-idf}"
            ESP_IDF_FHS_ENV="''${ESP_IDF_FHS_ENV:-esp-idf-fhs}"

            if [[ -z "$ESP_IDF_FHS_ENV" ]]; then
              echo "Error: ESP-IDF FHS environment not available" >&2
              echo "   This script requires espIdf.enable = true in your home configuration" >&2
              exit 1
            fi

            "$ESP_IDF_FHS_ENV" -c "
              export IDF_PATH=$IDF_PATH
              source \"$IDF_PATH/export.sh\" > /dev/null 2>&1
              exec idf.py \"\$@\"
            " -- "$@"
          '';
        };

      in
      {
        options.espIdf = {
          enable = lib.mkEnableOption "ESP-IDF development environment with FHS compatibility";

          idfPath = lib.mkOption {
            type = lib.types.str;
            default = "${config.home.homeDirectory}/src/dsp/esp-idf";
            description = "Path to ESP-IDF installation";
          };

          targetChips = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "esp32c5" ];
            description = "Target ESP32 chip variants to install tools for";
            example = [ "esp32" "esp32s3" "esp32c5" ];
          };
        };

        config = lib.mkIf cfg.enable {
          # Add ESP-IDF related packages
          home.packages = [
            esp-idf-fhs
            esp-idf-install
            esp-idf-shell
            esp-idf-export
            idf-py

            # Additional tools for ESP32 development
            pkgs.esptool
            pkgs.dfu-util
            pkgs.minicom
            pkgs.screen
            pkgs.tio # Modern serial terminal
          ];

          # Add convenient shell aliases
          programs.bash.shellAliases = {
            esp32c5 = "esp-idf-shell";
            esp-shell = "esp-idf-shell";
            esp-install = "esp-idf-install";
          };

          programs.zsh.shellAliases = {
            esp32c5 = "esp-idf-shell";
            esp-shell = "esp-idf-shell";
            esp-install = "esp-idf-install";
          };

          # Set up environment variables
          home.sessionVariables = {
            IDF_PATH = cfg.idfPath;
            ESP_IDF_FHS_ENV = "${esp-idf-fhs}/bin/esp-idf-fhs";
          };

          # Create useful development scripts in ~/bin
          home.file."bin/esp-update-tools" = {
            text = ''
              #!/usr/bin/env bash
              # Update ESP-IDF tools in FHS environment

              echo "Updating ESP-IDF tools..."
              ${esp-idf-fhs}/bin/esp-idf-fhs -c '
                export IDF_PATH=${cfg.idfPath}
                cd "$IDF_PATH"
                git pull
                ./install.sh ${lib.concatStringsSep " " cfg.targetChips}
              '
            '';
            executable = true;
          };

          home.file."bin/esp-clean-tools" = {
            text = ''
              #!/usr/bin/env bash
              # Clean ESP-IDF tools installation

              echo "This will remove ~/.espressif directory and all installed tools."
              read -p "Are you sure? (y/N) " -n 1 -r
              echo
              if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf ~/.espressif
                echo "ESP-IDF tools cleaned. Run 'esp-idf-install' to reinstall."
              else
                echo "Operation cancelled."
              fi
            '';
            executable = true;
          };
        };
      };
  };
}
