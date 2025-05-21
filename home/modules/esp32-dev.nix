# ESP32-C5 Development Module
{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.esp32Dev;
in {
  options.esp32Dev = {
    enable = mkEnableOption "ESP32-C5 development environment";
    
    repoOwner = mkOption {
      type = types.str;
      default = "timblaktu"; # Replace with your GitHub username
      description = "GitHub username for the nixpkgs-esp-dev fork";
    };
    
    branch = mkOption {
      type = types.str;
      default = "c5";
      description = "Branch name to use in the nixpkgs-esp-dev repository";
    };
    
    additionalPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional packages for ESP32-C5 development";
    };
  };

  config = mkIf cfg.enable {
    # Add shell alias for easy access
    programs.zsh.shellAliases = {
      esp32c5-shell = "nix develop github:${cfg.repoOwner}/nixpkgs-esp-dev#esp32c5-idf";
    };
    
    programs.bash.shellAliases = {
      esp32c5-shell = "nix develop github:${cfg.repoOwner}/nixpkgs-esp-dev#esp32c5-idf";
    };
    
    # Add useful packages for ESP32 development
    home.packages = with pkgs; [
      screen
      minicom
      usbutils
      # Include any additional packages specific to ESP32 development
    ] ++ cfg.additionalPackages;
  };
}
