# ESP32-C5 Development Profile
{ config, lib, pkgs, ... }:

{
  # Import the ESP32 development module
  imports = [
    ../home/modules/esp32-dev.nix
  ];
  
  # Enable ESP32-C5 development environment
  esp32Dev = {
    enable = true;
    repoOwner = "timblaktu"; # Replace with your GitHub username
    branch = "c5";
    additionalPackages = with pkgs; [
      picocom # Serial terminal
      python3 # Often needed for ESP tools
      python3Packages.pyserial
    ];
  };
  
  # Additional packages useful for embedded development
  home.packages = with pkgs; [
    cmake
    ninja
    gdb
    stm32flash # Flash tool for STM32 (complementary to ESP tools)
    platformio # Alternative embedded development platform
  ];
  
  # Create a local shell.nix shortcut in your home directory
  home.file.".local/bin/esp32c5-shell.nix".text = ''
    let
      # Use fetchGit to get your fork
      esp-dev-repo = builtins.fetchGit {
        url = "https://github.com/${config.esp32Dev.repoOwner}/nixpkgs-esp-dev.git";
      };
      
      # Import nixpkgs with the overlay
      pkgs = import <nixpkgs> { 
        overlays = [ (import "''${esp-dev-repo}/overlay.nix") ];
      };
    in
    pkgs.mkShell {
      name = "esp32c5-project";
      
      buildInputs = with pkgs; [
        esp-idf-esp32c5
      ];
      
      # Shell hook for additional environment setup
      shellHook = '''
        echo "ESP32-C5 development environment activated!"
        echo "IDF_PATH: $IDF_PATH"
      ''';
    }
  '';
  
  # Make the shell script executable
  home.file.".local/bin/esp32c5-shell.nix".executable = true;
}
