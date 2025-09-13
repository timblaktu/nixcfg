# Example module showing how to use SOPS secrets with NetworkManager WiFi
# This is an example - adapt for your actual needs
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.wifiSecrets;
in
{
  options.wifiSecrets = {
    enable = mkEnableOption "WiFi configuration from SOPS secrets";
    
    secretsFile = mkOption {
      type = types.path;
      description = "Path to SOPS file containing WiFi credentials";
      example = "/etc/nixos/secrets/common/wifi.yaml";
    };
  };

  config = mkIf cfg.enable {
    # Define the secrets we need from SOPS
    sops.secrets = {
      "wirelessNetworks.home.ssid" = {
        sopsFile = cfg.secretsFile;
      };
      "wirelessNetworks.home.psk" = {
        sopsFile = cfg.secretsFile;
        mode = "0400";
      };
      "wirelessNetworks.work.ssid" = {
        sopsFile = cfg.secretsFile;
      };
      "wirelessNetworks.work.psk" = {
        sopsFile = cfg.secretsFile;
        mode = "0400";
      };
    };

    # NetworkManager configuration using the decrypted secrets
    # Note: This is an example approach. In practice, you might need
    # to use a systemd service to configure NetworkManager after secrets are available
    
    # Example systemd service to configure WiFi after boot
    systemd.services.configure-wifi = {
      description = "Configure WiFi networks from SOPS secrets";
      after = [ "sops-nix.service" "NetworkManager.service" ];
      wants = [ "sops-nix.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        # Read the decrypted secrets
        HOME_SSID=$(cat ${config.sops.secrets."wirelessNetworks.home.ssid".path})
        HOME_PSK=$(cat ${config.sops.secrets."wirelessNetworks.home.psk".path})
        WORK_SSID=$(cat ${config.sops.secrets."wirelessNetworks.work.ssid".path})
        WORK_PSK=$(cat ${config.sops.secrets."wirelessNetworks.work.psk".path})
        
        # Configure NetworkManager connections
        # Check if connection exists, if not create it
        if ! ${pkgs.networkmanager}/bin/nmcli connection show "$HOME_SSID" &>/dev/null; then
          ${pkgs.networkmanager}/bin/nmcli connection add \
            type wifi \
            con-name "$HOME_SSID" \
            ifname wlan0 \
            ssid "$HOME_SSID" \
            wifi-sec.key-mgmt wpa-psk \
            wifi-sec.psk "$HOME_PSK"
        fi
        
        if ! ${pkgs.networkmanager}/bin/nmcli connection show "$WORK_SSID" &>/dev/null; then
          ${pkgs.networkmanager}/bin/nmcli connection add \
            type wifi \
            con-name "$WORK_SSID" \
            ifname wlan0 \
            ssid "$WORK_SSID" \
            wifi-sec.key-mgmt wpa-psk \
            wifi-sec.psk "$WORK_PSK"
        fi
      '';
    };
  };
}