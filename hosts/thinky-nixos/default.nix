# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

let
  sshKeys = import ../common/ssh-keys.nix;
in
{
  imports = [
    ./hardware-config.nix
    # Dendritic system type - provides system-cli layer (includes default and minimal)
    inputs.self.modules.nixos.system-cli
    # Dendritic WSL configuration
    inputs.self.modules.nixos.wsl
  ];

  # System default layer configuration (required by system types)
  systemDefault.userName = "tim";

  # WSL settings (dendritic module)
  wsl-settings = {
    hostname = "thinky-nixos";
    defaultUser = "tim";
    sshPort = 2223;
    userGroups = [ "wheel" "dialout" ];
    sshAuthorizedKeys = [ sshKeys.timblaktu ];
    usbip.autoAttach = [ "3-1" "3-2" ];
    extraShellAliases = {
      esp32c5 = "esp-idf-shell";
    };
  };

  # USB device management for ESP32 development
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "10-esp32-usb";
      destination = "/etc/udev/rules.d/10-esp32-usb.rules";
      text = ''
        # CP2102N USB to UART Bridge Controller - Device 1
        # Serial: a84d26d0ef5fef1186befc45d9b539e6
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="a84d26d0ef5fef1186befc45d9b539e6", SYMLINK+="ttyESP0", MODE="0666", GROUP="dialout"
        
        # CP2102N USB to UART Bridge Controller - Device 2  
        # Serial: 4095a7a28d1af0119da88250ac170b28
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="4095a7a28d1af0119da88250ac170b28", SYMLINK+="ttyESP1", MODE="0666", GROUP="dialout"
        
        # Generic rule for all CP2102N devices (fallback)
        # This ensures any CP2102N device gets proper permissions even if not explicitly listed
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
        
        # Also handle the usb-serial subsystem
        SUBSYSTEM=="usb-serial", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
      '';
    })
  ];

  # User environment managed by standalone Home Manager
  # Deploy with: home-manager switch --flake '.#tim@thinky-nixos'
}
