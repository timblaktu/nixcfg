# ESP-IDF development environment module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
  
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
      udev                    # Required by OpenOCD
      libusb1                 # USB device access
      hidapi                  # HID device access
      libftdi1                # FTDI chip support
      
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
  
  # ESP-IDF scripts are now provided by validated-scripts module
  # esp-idf-install, esp-idf-shell, esp-idf-export, and idf.py
  # are available when enableValidatedScripts = true

in {
  config = mkIf cfg.enableEspIdf {
    # Add ESP-IDF related packages
    home.packages = [
      esp-idf-fhs
      # ESP-IDF scripts (esp-idf-install, esp-idf-shell, esp-idf-export, idf.py)
      # are now provided by validated-scripts module
      
      # Additional tools for ESP32 development
      pkgs.esptool
      pkgs.dfu-util
      pkgs.minicom
      pkgs.screen
      pkgs.tio  # Modern serial terminal
    ];
    
    # Add convenient shell aliases
    programs.bash.shellAliases = mkIf cfg.enableEspIdf {
      esp32c5 = "esp-idf-shell";
      esp-shell = "esp-idf-shell";
      esp-install = "esp-idf-install";
    };
    
    programs.zsh.shellAliases = mkIf cfg.enableEspIdf {
      esp32c5 = "esp-idf-shell";
      esp-shell = "esp-idf-shell";
      esp-install = "esp-idf-install";
    };
    
    # Set up environment variables
    home.sessionVariables = mkIf cfg.enableEspIdf {
      IDF_PATH = "${config.home.homeDirectory}/src/dsp/esp-idf";
      ESP_IDF_FHS_ENV = "${esp-idf-fhs}/bin/esp-idf-fhs";
    };
    
    # Create useful development scripts in ~/bin
    home.file."bin/esp-update-tools" = mkIf cfg.enableEspIdf {
      text = ''
        #!/usr/bin/env bash
        # Update ESP-IDF tools in FHS environment
        
        echo "Updating ESP-IDF tools..."
        ${esp-idf-fhs}/bin/esp-idf-fhs -c '
          export IDF_PATH=${config.home.homeDirectory}/src/dsp/esp-idf
          cd "$IDF_PATH"
          git pull
          ./install.sh esp32c5
        '
      '';
      executable = true;
    };
    
    home.file."bin/esp-clean-tools" = mkIf cfg.enableEspIdf {
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
}
